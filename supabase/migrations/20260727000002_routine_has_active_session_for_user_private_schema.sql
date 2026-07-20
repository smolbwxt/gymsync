-- ============================================================
-- Debt-zero sprint / Task 1, item 1 of 3: relocate
-- routine_has_active_session_for_user() to `private` — FIRST in queue
-- because its routine_id input is publicly discoverable via Discover
-- (public.routines rows with visibility = 'public'), which turns this
-- oracle into a live "is this user working out on this routine right now"
-- probe reachable with zero prior relationship to the target.
-- ============================================================
-- CLASSIFICATION (live-state, not repo grep — per the Phase O incident
-- doctrine: dependency/exposure inventory comes from LIVE pg_policies +
-- pg_proc, never repo grep alone):
-- public.routine_has_active_session_for_user(p_routine_id uuid,
-- p_user_id uuid) is SECURITY DEFINER STABLE, lives in the exposed
-- `public` schema (defined once, 20260712000004_routine_exercises_session_
-- read.sql, never redefined), and per live information_schema.
-- routine_privileges carries EXECUTE for PUBLIC/anon/authenticated/
-- service_role/postgres — the Supabase platform default, never narrowed.
-- Same oracle SHAPE as every other helper in this sweep: a DEFINER
-- function, auto-minted as POST /rest/v1/rpc/routine_has_active_session_
-- for_user, callable by any authenticated caller (or anon, per the same
-- default grant) with two arbitrary uuids, answering a relationship
-- question the tables' own RLS does not otherwise expose to that caller.
--
-- NOTE for the record (observed, not changed here — out of this task's
-- scope, which is relocation only): despite the name, the function body
-- does not filter on session state at all — it answers "does ANY session
-- (any state: scheduled/in_progress/completed/abandoned) tied to this
-- routine have this user as a session_participants row," not specifically
-- an in-progress one. Flagged as a naming/behavior mismatch for a future
-- task, not touched here — the relocation preserves the body verbatim.
--
-- Live POLICY dependents — verified via
-- `SELECT ... FROM pg_policies WHERE qual ILIKE '%routine_has_active_
-- session_for_user%' OR with_check ILIKE '%...%'` against the live
-- database (1 row) and cross-checked against pg_depend
-- (refobjid = this function's oid, refclassid = 'pg_proc'::regclass) for
-- an object-type-agnostic dependency scan (also 1 row, same policy oid) —
-- the two independent methods converge:
--   1. routine_exercises SELECT ("session participants read session
--      routine exercises") — 20260712000004, never redefined.
--
-- No SQL-function-body callers: pg_depend scan above returned zero
-- non-pg_policy dependents (no functions, triggers, or views reference
-- this function's OID at all — not merely "none found by text search").
-- Exact-substring scan of every function's prosrc for the literal call
-- text `routine_has_active_session_for_user(` (not a wildcard ILIKE
-- pattern — see the "underscores are LIKE/ILIKE single-char wildcards"
-- caution in the task report) also returned zero rows outside this
-- function's own definition.
--
-- No Edge Function callers: `grep -rn "\.rpc(" supabase/functions/` finds
-- exactly two RPC call sites in the whole tree (livekit-token's
-- is_session_participant, push-dispatcher's claim_push_batch) — neither is
-- this helper. A direct grep for the literal name across
-- supabase/functions/ and GymSyncApp/**/*.swift returns nothing beyond
-- this function's own migration file. Clean relocation, no dual-function
-- treatment needed.
-- ============================================================

-- `private` schema already exists (CREATE SCHEMA IF NOT EXISTS + REVOKE
-- ALL FROM PUBLIC, 20260722000001_is_blocked_private_schema.sql) — not
-- recreated here.

-- ── 1. private.routine_has_active_session_for_user() — same contract,
--    unreachable schema. No REVOKE/GRANT EXECUTE lines: the source
--    function never had any (default PUBLIC EXECUTE), so the relocated
--    copy keeps the exact same grant posture. ─────────────────────────
CREATE FUNCTION private.routine_has_active_session_for_user(
  p_routine_id uuid, p_user_id uuid
)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sessions s
    JOIN public.session_participants sp ON sp.session_id = s.id
    WHERE s.routine_id = p_routine_id
      AND sp.user_id = p_user_id
  );
$$;

-- ── 2. Repoint the one dependent policy ──────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE, this
-- repo's established idiom throughout the sweep. Full USING text
-- transplanted verbatim from the current live version
-- (20260712000004_routine_exercises_session_read.sql), changing only
-- public.routine_has_active_session_for_user ->
-- private.routine_has_active_session_for_user.
DROP POLICY "session participants read session routine exercises" ON public.routine_exercises;
CREATE POLICY "session participants read session routine exercises"
  ON public.routine_exercises FOR SELECT TO authenticated
  USING (
    private.routine_has_active_session_for_user(routine_exercises.routine_id, auth.uid())
  );

-- ── 3. Drop the oracle ────────────────────────────────────────────────
-- Must run AFTER the policy above stops referencing
-- public.routine_has_active_session_for_user: a policy dependency on the
-- function would otherwise block this DROP. Confirmed no other consumer
-- exists (pg_depend scan above).
DROP FUNCTION public.routine_has_active_session_for_user(uuid, uuid);
