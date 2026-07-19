-- ============================================================
-- Debt-zero sprint / Task 1, item 3 of 3: relocate proposal_session_id()
-- to `private`.
-- ============================================================
-- CLASSIFICATION (live-state, not repo grep): public.proposal_session_id
-- (p_proposal_id uuid) is SECURITY DEFINER STABLE, lives in the exposed
-- `public` schema (defined once,
-- 20260712000003_routine_proposals.sql, never redefined), and per live
-- information_schema.routine_privileges carries EXECUTE for
-- PUBLIC/anon/authenticated/service_role/postgres — the Supabase platform
-- default, never narrowed. Auto-minted as
-- POST /rest/v1/rpc/proposal_session_id, callable by any authenticated (or
-- anon) caller with an arbitrary proposal_id, returning that proposal's
-- session_id directly — a session_id oracle, same SHAPE as
-- message_group_id/series_group_id before their own relocations (both
-- this sweep): given an id the caller may not otherwise have read access
-- to (routine_proposals' own SELECT policy is session-participant-gated),
-- this RPC reveals the linked session_id, which a caller could then feed
-- into other session-scoped oracles/queries. DECISION: same exposure
-- class — relocate.
--
-- Live POLICY dependents — verified via
-- `SELECT ... FROM pg_policies WHERE qual ILIKE '%proposal_session_id%'
-- OR with_check ILIKE '%proposal_session_id%'` against the live database
-- (2 rows) and cross-checked against pg_depend (refobjid = this
-- function's oid, refclassid = 'pg_proc'::regclass) for an
-- object-type-agnostic dependency scan (2 rows, same policy oids) — the
-- two independent methods converge, both on routine_proposal_votes, both
-- last redefined in
-- 20260726000001_is_session_participant_dual_schema.sql (which repointed
-- the outer private.is_session_participant(...) wrapper but explicitly
-- left the inner argument as `public.proposal_session_id(...)`, per that
-- migration's own header: "that helper itself does not call
-- is_session_participant and is out of this task's scope, left
-- untouched" — this migration is that deferred follow-up):
--   1. SELECT ("session participants read votes")
--   2. INSERT ("session participants vote as themselves")
-- Both wrap the call as
-- private.is_session_participant(proposal_session_id(proposal_id), auth.uid()).
--
-- No SQL-function-body callers: pg_depend scan above returned zero
-- non-pg_policy dependents. A first-pass exact-substring scan for
-- `proposal_session_id(` across pg_proc.prosrc did surface
-- resolve_proposal / resolve_proposal_debug / resolve_proposal_debug2 /
-- resolve_proposal_debug3 under an ILIKE '%proposal_session_id%' pattern —
-- but ILIKE/LIKE treat a bare `_` as a single-character wildcard, so that
-- pattern also matches unrelated text like the record-field access
-- `v_proposal.session_id` (proposal + any-char + session + any-char + id).
-- Re-checked with `position('proposal_session_id(' in prosrc) > 0` (an
-- exact literal substring, not a wildcard pattern) run over the entire
-- public schema: zero matches outside this function's own definition —
-- confirming those four hits were false positives from the wildcard, not
-- real callers. (resolve_proposal is a trigger function on
-- routine_proposal_votes that reads NEW.proposal_id and
-- v_proposal.session_id directly; the three resolve_proposal_debug*
-- variants appear to be ad-hoc functions present only in live pg_proc —
-- not defined by any migration file, not referenced by any grep of the
-- repo — and are unrelated to proposal_session_id specifically. Flagged
-- as dead/undocumented live objects for the controller; out of this
-- task's scope to remove.)
--
-- No Edge Function callers: `grep -rn "\.rpc(" supabase/functions/` finds
-- exactly two RPC call sites in the whole tree (livekit-token's
-- is_session_participant, push-dispatcher's claim_push_batch) — neither is
-- this helper. A direct grep for the literal name across
-- supabase/functions/ and GymSyncApp/**/*.swift returns nothing beyond
-- migration files. Clean relocation, no dual-function treatment needed.
-- ============================================================

-- `private` schema already exists — not recreated here.

-- ── 1. private.proposal_session_id() — same contract, unreachable
--    schema. No REVOKE/GRANT EXECUTE lines: the source function never
--    had any (default PUBLIC EXECUTE), so the relocated copy keeps the
--    exact same grant posture. ─────────────────────────────────────────
CREATE FUNCTION private.proposal_session_id(p_proposal_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT session_id FROM public.routine_proposals WHERE id = p_proposal_id;
$$;

-- ── 2. Repoint the two dependent policies ────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE. Full
-- USING/WITH CHECK text transplanted verbatim from the current live
-- version (20260726000001), changing only public.proposal_session_id ->
-- private.proposal_session_id; the outer
-- private.is_session_participant(...) wrapper is untouched (already
-- private).

DROP POLICY "session participants read votes" ON public.routine_proposal_votes;
CREATE POLICY "session participants read votes"
  ON public.routine_proposal_votes FOR SELECT TO authenticated
  USING (private.is_session_participant(
           private.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

DROP POLICY "session participants vote as themselves" ON public.routine_proposal_votes;
CREATE POLICY "session participants vote as themselves"
  ON public.routine_proposal_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND private.is_session_participant(
                    private.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

-- ── 3. Drop the oracle ────────────────────────────────────────────────
-- Must run AFTER both policies above stop referencing
-- public.proposal_session_id: a policy dependency on the function would
-- otherwise block this DROP. Confirmed no other consumer exists (pg_depend
-- scan above).
DROP FUNCTION public.proposal_session_id(uuid);
