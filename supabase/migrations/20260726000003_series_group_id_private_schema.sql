-- ============================================================
-- Phase O / Task 1, fix-wave 2 (Part 2 of 2): relocate series_group_id() to
-- `private` — flagged in fix-wave 1 but not queued
-- (task-1-report.md, "Concerns for the controller" #3: "series_group_id(...)
-- ... is a group_id oracle in the same shape as the now-relocated
-- message_group_id ... also not in this task's queue, also flagged rather
-- than touched").
-- ============================================================
-- CLASSIFICATION: public.series_group_id(p_series_id uuid) is SECURITY
-- DEFINER STABLE, lives in the exposed `public` schema
-- (20260713000001_session_series.sql:29-32, never redefined), no
-- REVOKE/GRANT EXECUTE anywhere (default PUBLIC EXECUTE) — auto-minted as
-- POST /rest/v1/rpc/series_group_id, callable with any arbitrary series_id
-- by any authenticated caller. Same oracle SHAPE as message_group_id before
-- its own relocation (20260725000003_chat_message_access_private_schema.
-- sql): given a series_id the caller may not otherwise have read access to
-- (session_series' own SELECT policy is group-membership-gated), this RPC
-- reveals that series' group_id directly — a group_id oracle that bypasses
-- session_series' RLS the same way message_group_id bypassed
-- chat_messages'. DECISION: same exposure class — relocate.
--
-- RPC-caller check: grepped supabase/functions/**/*.ts for `.rpc(` (two
-- hits total in the whole tree, both already accounted for elsewhere in
-- this fix wave: livekit-token's is_session_participant, push-dispatcher's
-- claim_push_batch) and separately for the literal string
-- `series_group_id` across supabase/functions/ and GymSyncApp/**/*.swift:
-- zero hits. No SQL-function-body callers either (grep-confirmed: every
-- non-comment occurrence of `series_group_id(` outside its own CREATE
-- FUNCTION resolves to one of the 4 policy dependents below). Clean
-- relocation, no dual-function treatment needed.
--
-- Live POLICY dependents — all four on session_series_days, all last
-- redefined in 20260725000002_is_group_member_private_schema.sql (which
-- repointed each policy's is_group_member call to private.is_group_member
-- but deliberately left series_group_id as `public.series_group_id`, per
-- that migration's own header: "series_group_id() stays public — not in
-- this sweep's queue — only its caller (is_group_member) is repointed").
-- This migration is that deferred follow-up: only the
-- `public.series_group_id(...)` argument expression changes to
-- `private.series_group_id(...)` in all four; `private.is_group_member`
-- and (on the write policies) `public.is_series_organizer` are untouched —
-- is_series_organizer was never flagged by this sweep and stays public.
--   1. SELECT ("group members read series days")
--   2. INSERT ("organizer writes series days")
--   3. UPDATE ("organizer updates series days")
--   4. DELETE ("organizer deletes series days")
-- ============================================================

-- ── 1. private.series_group_id() — same contract, unreachable schema.
--    `private` already exists — not recreated here. No REVOKE/GRANT
--    EXECUTE lines: the source function never had any (default PUBLIC
--    EXECUTE), so the relocated copy keeps the exact same grant posture.
CREATE FUNCTION private.series_group_id(p_series_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT group_id FROM public.session_series WHERE id = p_series_id;
$$;

-- ── 2. Repoint the four dependent policies ───────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE. Full
-- USING/WITH CHECK text transplanted verbatim from the current live version
-- (20260725000002), changing only public.series_group_id ->
-- private.series_group_id.

DROP POLICY "group members read series days" ON public.session_series_days;
CREATE POLICY "group members read series days"
  ON public.session_series_days FOR SELECT TO authenticated
  USING (private.is_group_member(
           private.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer writes series days" ON public.session_series_days;
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    private.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer updates series days" ON public.session_series_days;
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               private.series_group_id(session_series_days.series_id), auth.uid()))
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    private.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer deletes series days" ON public.session_series_days;
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               private.series_group_id(session_series_days.series_id), auth.uid()));

-- ── 3. Drop the oracle ────────────────────────────────────────────────────
-- Must run AFTER all four policies above stop referencing
-- public.series_group_id: a policy dependency on the function would
-- otherwise block this DROP. Confirmed no other consumer exists (see
-- RPC-caller check above).
DROP FUNCTION public.series_group_id(uuid);
