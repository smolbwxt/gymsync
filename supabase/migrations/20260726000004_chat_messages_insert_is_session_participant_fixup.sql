-- ============================================================
-- Phase O / Task 1, fix-wave 2 fix-forward: chat_messages INSERT policy
-- missed by 20260726000001_is_session_participant_dual_schema.sql.
-- ============================================================
-- BUG: 20260726000001's own inventory (its header, "Dependent POLICIES...
-- (13)") listed chat_messages SELECT ("group members read messages") but
-- missed chat_messages INSERT. That INSERT policy was renamed from "members
-- send text or image as themselves" (20260711000002_storage_buckets.sql,
-- the name grepped when compiling that inventory) to "members send client
-- messages as themselves" by 20260719000010_session_chat_subthreads.sql
-- (adding session-scoped support + an is_session_participant leg for the
-- session_id IS NOT NULL branch) and evolved further by 20260719000011 and
-- 20260725000002 (which repointed only its is_group_member leg to private,
-- explicitly leaving the is_session_participant leg as the then-still-
-- public function — correct at the time, since 20260726000001 hadn't run
-- yet). The static grep this task's inventory process relied on
-- (`grep -rn "is_session_participant(" supabase/migrations/`) DID surface
-- this exact line (20260725000002:100), but it was misread as a duplicate
-- of the SELECT policy at line 83 in the same file rather than a distinct
-- INSERT policy — a real inventory miss, not a tooling gap. Caught here via
-- a live `pg_policies` query (`qual ILIKE '%is_session_participant%' OR
-- with_check ILIKE '%is_session_participant%'`) run against production
-- immediately after 20260726000001 was pushed, as part of investigating an
-- unexpected pgTAP regression (see task-1-report.md for the full
-- diagnostic trail) — the query is the authoritative source of truth this
-- fix was verified against, not another static grep.
--
-- IMPACT (empirically confirmed, not assumed): because Postgres checks
-- EXECUTE privilege on every function OID appearing in a compiled WITH
-- CHECK expression at ACL-check time — not lazily, gated by which AND/OR
-- branch would actually be reached at runtime for a given row — EVERY
-- chat_messages INSERT via this policy failed with `42501 permission
-- denied for function is_session_participant` after 20260726000001 was
-- applied, including plain GROUP-LEVEL sends (session_id IS NULL) where
-- the is_session_participant branch is logically unreachable. This is a
-- stronger form of the same doctrine 20260722000001's header already
-- documents (EXECUTE is checked per-call, not just per schema-USAGE
-- resolution) — worth recording explicitly here since "the branch never
-- runs for this row" turned out NOT to be a safe assumption for whether a
-- REVOKE is felt by that row's WITH CHECK evaluation.
--
-- FIX: identical DROP+CREATE POLICY idiom as everywhere else in this
-- sweep — full WITH CHECK text transplanted verbatim from the current live
-- version (confirmed via the same pg_policies query), changing only the
-- bare `is_session_participant(...)` call to `private.is_session_participant(...)`.
-- ============================================================

DROP POLICY "members send client messages as themselves" ON public.chat_messages;
CREATE POLICY "members send client messages as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND (kind NOT IN ('image', 'audio') OR storage_path IS NOT NULL)
    AND (kind <> 'soundboard_echo' OR payload IS NOT NULL)
    AND (
      (chat_messages.session_id IS NULL
       AND private.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND private.is_session_participant(chat_messages.session_id, auth.uid())
          AND chat_messages.group_id IS NOT DISTINCT FROM (
                SELECT s.group_id FROM public.sessions s
                WHERE s.id = chat_messages.session_id))
    )
  );
