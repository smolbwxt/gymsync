-- ============================================================
-- Block enforcement symmetry: chat_messages SELECT becomes mutual.
-- ============================================================
-- Source: docs/FUNCTIONAL-AUDIT-2026-07-20.md, D4 — the audit's single
-- actionable backend finding, re-verified live on 2026-07-25 (the policy
-- below still carried only the one-directional clause).
--
-- `private.is_blocked(p_blocker, p_blocked)` is strictly DIRECTIONAL: one
-- `blocked_users` row expresses one direction. The pre-existing
-- chat_messages SELECT policy checked only
--   NOT private.is_blocked(auth.uid(), author_id)
-- i.e. "I don't see people I blocked". The reverse was never checked, so
-- if A blocks B: A stops seeing B's messages, but B KEEPS SEEING ALL OF
-- A's — B's own read evaluates is_blocked(B, A), which is false.
--
-- The intended semantic is mutual, and the codebase already states it
-- elsewhere: the `set_logs` read policy
-- (20260721000001_moderation_block_report.sql) checks BOTH directions.
-- Two policies over the same concept disagreeing is the signal; this
-- migration makes chat match set_logs.
--
-- Scope is deliberately the SELECT policy only. INSERT is untouched: a
-- blocked user writing into a group they're still a member of is a
-- membership question, not a block question, and silently dropping their
-- writes would be a behavior change the audit never called for. Blocking
-- governs what YOU see; both parties now stop seeing each other.
--
-- Recreated (not ALTERed) because Postgres has no ALTER POLICY ... USING
-- append; the rest of the qual is reproduced verbatim from the live
-- definition (pg_policies, 2026-07-25) — group-vs-session branch
-- unchanged.
DROP POLICY IF EXISTS "group members read messages" ON public.chat_messages;

CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (
      ((session_id IS NULL) AND private.is_group_member(group_id, auth.uid()))
      OR
      ((session_id IS NOT NULL) AND private.is_session_participant(session_id, auth.uid()))
    )
    AND (NOT private.is_blocked(auth.uid(), author_id))
    AND (NOT private.is_blocked(author_id, auth.uid()))
  );
