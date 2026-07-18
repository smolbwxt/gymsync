-- ============================================================
-- Phase O / Task 1: DEFINER-helper sweep, item 1 of 6 — is_friend()
-- (worst exposure in the queue: a relationship oracle, same shape as
-- is_blocked before 20260722000001, which is the pattern this migration
-- replicates exactly)
-- ============================================================
-- public.is_friend(p_user_id uuid, p_viewer_id uuid) — defined once,
-- 20260719000006_streaks.sql:127-136, never redefined since. SECURITY
-- DEFINER STABLE, search_path pinned to public, default PUBLIC EXECUTE
-- grant (no REVOKE/GRANT statements anywhere for it — confirmed by grep of
-- every migration referencing is_friend).
--
-- Exposure: answers "are p_user_id and p_viewer_id accepted friends
-- (either direction)?" for ANY two arbitrary uuids. Public schema +
-- PostgREST-exposed (supabase/config.toml [api] schemas = ["public",
-- "graphql_public"]) means POST /rest/v1/rpc/is_friend is auto-minted and
-- callable by any authenticated caller with two arbitrary uuids — the
-- exact oracle shape is_blocked had (20260722000001's header), and flagged
-- as such by its own downstream callers: 20260722000002_solo_workout_
-- privacy.sql ("`is_friend` carries the same shape of oracle risk in
-- principle... a decision already made and shipped in Phase S, not
-- something this migration re-litigates") and 20260722000003_block_severs_
-- friendship.sql (same helper, unchanged posture). This migration is that
-- deferred fix.
--
-- Grep confirms exactly two live dependent policies and zero other SQL
-- function bodies or non-SQL (edge function / app) callers:
--   1. "owner and friends can read user streaks" ON public.user_streaks
--      (20260719000006, never redefined)
--   2. "set_logs read: owner, participant, or opted-in friend" ON
--      public.set_logs (last redefined 20260722000003_block_severs_
--      friendship.sql — verbatim transplant below, changing only
--      public.is_friend -> private.is_friend; the is_session_participant,
--      is_solo_session, and private.is_blocked references are untouched)
--
-- Grep of supabase/functions/**/*.ts and the whole repo for direct
-- `.rpc("is_friend", ...)` calls: none found (the only such direct-RPC
-- caller in this entire sweep is is_session_participant, from
-- livekit-token/index.ts — reported separately as this task's one
-- blocker, not relocated).
-- ============================================================

-- ── 1. private.is_friend() — same contract, unreachable schema ──────────
-- Body/SECURITY DEFINER/STABLE/search_path identical to public.is_friend.
-- `private` schema already exists (CREATE SCHEMA IF NOT EXISTS + REVOKE ALL
-- FROM PUBLIC, 20260722000001_is_blocked_private_schema.sql) — not
-- recreated here. No REVOKE/GRANT EXECUTE lines: the source function never
-- had any (default PUBLIC EXECUTE), so the relocated one keeps the exact
-- same grant posture, unlike is_blocked's relocation (which had a narrowed
-- authenticated-only grant on the public version to preserve). RLS policy
-- evaluation still resolves it under the same asymmetry is_blocked's own
-- migration documents: SCHEMA USAGE (revoked from anon/authenticated) is
-- checked at query-parse time for a role composing its own SQL; a policy's
-- USING/WITH CHECK qual already carries the resolved function OID from
-- CREATE POLICY time and is never re-parsed per call.
CREATE FUNCTION private.is_friend(p_user_id uuid, p_viewer_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships
    WHERE status = 'accepted'
      AND ((user_id = p_user_id AND friend_id = p_viewer_id)
        OR (user_id = p_viewer_id AND friend_id = p_user_id))
  );
$$;

-- ── 2. Repoint the two dependent policies ────────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE, same idiom
-- used throughout this repo's history for every policy edit.

DROP POLICY "owner and friends can read user streaks" ON public.user_streaks;
CREATE POLICY "owner and friends can read user streaks"
  ON public.user_streaks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR private.is_friend(user_streaks.user_id, auth.uid())
  );

-- Full USING text transplanted verbatim from 20260722000003_block_severs_
-- friendship.sql (the current live version), changing only
-- public.is_friend -> private.is_friend.
DROP POLICY "set_logs read: owner, participant, or opted-in friend" ON public.set_logs;
CREATE POLICY "set_logs read: owner, participant, or opted-in friend"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_session_participant(set_logs.session_id, auth.uid())
    OR (
      public.is_solo_session(set_logs.session_id)
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
-- Must run AFTER both policies above stop referencing public.is_friend: a
-- policy dependency on the function would otherwise block this DROP.
DROP FUNCTION public.is_friend(uuid, uuid);
