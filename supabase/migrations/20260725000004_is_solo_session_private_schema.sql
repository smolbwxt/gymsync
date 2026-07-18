-- ============================================================
-- Phase O / Task 1: DEFINER-helper sweep, item 6 of 6 — is_solo_session()
-- ============================================================
-- public.is_solo_session(p_session_id uuid) — defined once,
-- 20260722000002_solo_workout_privacy.sql:110-117, never redefined.
-- SECURITY DEFINER STABLE, search_path pinned, default PUBLIC EXECUTE (no
-- REVOKE/GRANT).
--
-- Exposure: given ANY session_id, returns whether that session currently
-- has exactly one participant. Lower sensitivity than the other five
-- helpers in this queue (20260722000002's own header judged it "carries no
-- identity or relationship information for an arbitrary caller to
-- harvest" and deliberately left it in `public`) — but it is still a
-- SECURITY DEFINER function in the exposed `public` schema, callable via
-- POST /rest/v1/rpc/is_solo_session with an arbitrary session_id, i.e. the
-- same oracle SHAPE as the others even though the specific fact it leaks
-- is low-value. Relocated for consistency with the rest of the sweep and
-- because the task brief's queue names it explicitly — not because a new
-- concrete exploit was found.
--
-- Live dependents (grep-confirmed): exactly one — set_logs SELECT
-- ("set_logs read: owner, participant, or opted-in friend"), current live
-- version last defined in 20260725000001_is_friend_private_schema.sql
-- (this sweep's own migration 1, which already repointed the is_friend
-- call in this same policy to private.is_friend; the is_solo_session call
-- was left as public.is_solo_session at that point, per queue order).
-- Transplanted verbatim below, changing only public.is_solo_session ->
-- private.is_solo_session. No SQL-function-body callers, no non-SQL
-- callers (grepped supabase/functions/**/*.ts and the whole repo).
-- ============================================================

-- ── 1. private.is_solo_session() — same contract, unreachable schema ────
CREATE FUNCTION private.is_solo_session(p_session_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT (
    SELECT count(*) FROM public.session_participants
    WHERE session_id = p_session_id
  ) = 1;
$$;

-- ── 2. Repoint the one dependent policy ──────────────────────────────────
DROP POLICY "set_logs read: owner, participant, or opted-in friend" ON public.set_logs;
CREATE POLICY "set_logs read: owner, participant, or opted-in friend"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_session_participant(set_logs.session_id, auth.uid())
    OR (
      private.is_solo_session(set_logs.session_id)
      AND private.is_friend(set_logs.user_id, auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = set_logs.user_id AND p.show_solo_workouts = true
      )
      AND NOT private.is_blocked(set_logs.user_id, auth.uid())
      AND NOT private.is_blocked(auth.uid(), set_logs.user_id)
    )
  );

-- ── 3. Drop the oracle ────────────────────────────────────────────────────
DROP FUNCTION public.is_solo_session(uuid);
