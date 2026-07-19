-- ============================================================
-- Debt-zero sprint / Task 1, item 2 of 3: relocate is_series_organizer()
-- to `private`.
-- ============================================================
-- CLASSIFICATION (live-state, not repo grep): public.is_series_organizer
-- (p_series_id uuid, p_user_id uuid) is SECURITY DEFINER STABLE, lives in
-- the exposed `public` schema (defined once,
-- 20260713000001_session_series.sql, never redefined), and per live
-- information_schema.routine_privileges carries EXECUTE for
-- PUBLIC/anon/authenticated/service_role/postgres — the Supabase platform
-- default, never narrowed. Auto-minted as
-- POST /rest/v1/rpc/is_series_organizer, callable by any authenticated (or
-- anon) caller with two arbitrary uuids, answering "is p_user_id the
-- organizer of p_series_id?" — the same relationship-oracle shape as
-- is_session_organizer before its own relocation
-- (20260725000005_is_session_organizer_private_schema.sql), for the
-- session_series table instead of sessions. DECISION: same exposure
-- class — relocate.
--
-- Live POLICY dependents — verified via
-- `SELECT ... FROM pg_policies WHERE qual ILIKE '%is_series_organizer%'
-- OR with_check ILIKE '%is_series_organizer%'` against the live database
-- (3 rows) and cross-checked against pg_depend (refobjid = this
-- function's oid, refclassid = 'pg_proc'::regclass) for an
-- object-type-agnostic dependency scan (3 distinct policy oids, one of
-- which carries both a USING and a WITH CHECK reference and so appears
-- twice in the raw pg_depend rows) — the two independent methods
-- converge, all three on session_series_days, all last redefined in
-- 20260726000003_series_group_id_private_schema.sql (which repointed each
-- policy's series_group_id call to private.series_group_id but explicitly
-- left is_series_organizer as `public.is_series_organizer`, per that
-- migration's own header: "is_series_organizer was never flagged by this
-- sweep and stays public" — this migration is that deferred follow-up):
--   1. INSERT ("organizer writes series days")
--   2. UPDATE ("organizer updates series days")
--   3. DELETE ("organizer deletes series days")
-- (The fourth session_series_days policy, SELECT "group members read
-- series days", does not reference is_series_organizer at all — it is
-- group-membership-gated only — and is correctly absent from both scans.)
--
-- No SQL-function-body callers: pg_depend scan above returned zero
-- non-pg_policy dependents. Exact-substring scan of every function's
-- prosrc for the literal call text `is_series_organizer(` (not a wildcard
-- ILIKE pattern — see the task report's note on underscores as
-- LIKE/ILIKE single-char wildcards, which produced a false-positive
-- caller set for a different helper in this same sweep and was caught by
-- this exact-match re-check) also returned zero rows outside this
-- function's own definition.
--
-- No Edge Function callers: `grep -rn "\.rpc(" supabase/functions/` finds
-- exactly two RPC call sites in the whole tree (livekit-token's
-- is_session_participant, push-dispatcher's claim_push_batch) — neither is
-- this helper. A direct grep for the literal name across
-- supabase/functions/ and GymSyncApp/**/*.swift returns nothing beyond
-- migration files. Clean relocation, no dual-function treatment needed.
-- ============================================================

-- `private` schema already exists — not recreated here.

-- ── 1. private.is_series_organizer() — same contract, unreachable
--    schema. No REVOKE/GRANT EXECUTE lines: the source function never
--    had any (default PUBLIC EXECUTE), so the relocated copy keeps the
--    exact same grant posture. ─────────────────────────────────────────
CREATE FUNCTION private.is_series_organizer(p_series_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.session_series
                 WHERE id = p_series_id AND organizer_id = p_user_id);
$$;

-- ── 2. Repoint the three dependent policies ──────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE. Full
-- USING/WITH CHECK text transplanted verbatim from the current live
-- version (20260726000003), changing only public.is_series_organizer ->
-- private.is_series_organizer; private.series_group_id and
-- private.is_group_member calls are untouched (already private).

DROP POLICY "organizer writes series days" ON public.session_series_days;
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (private.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    private.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer updates series days" ON public.session_series_days;
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (private.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               private.series_group_id(session_series_days.series_id), auth.uid()))
  WITH CHECK (private.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    private.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer deletes series days" ON public.session_series_days;
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (private.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               private.series_group_id(session_series_days.series_id), auth.uid()));

-- ── 3. Drop the oracle ────────────────────────────────────────────────
-- Must run AFTER all three policies above stop referencing
-- public.is_series_organizer: a policy dependency on the function would
-- otherwise block this DROP. Confirmed no other consumer exists (pg_depend
-- scan above).
DROP FUNCTION public.is_series_organizer(uuid, uuid);
