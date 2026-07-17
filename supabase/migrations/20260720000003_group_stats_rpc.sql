-- ============================================================
-- Phase F / Task 5 — Group Stats sub-tab aggregate RPCs
-- ============================================================
-- Spec: docs/superpowers/specs/2026-06-28-gymsync-design.md Flow 5
-- (~798-805, "Stats — collective metrics (total sessions, PRs, volume),
-- per-member leaderboards") + phase spec §3 (2026-07-16-social-finishers-
-- design.md ~17-18, "One aggregate RPC in the established DEFINER/LATERAL
-- idiom if client-side aggregation would N+1").
--
-- Shape decision (plan Task 5 offered two options — judged here):
-- TWO functions, not one RETURNS TABLE with scalars repeated per row
-- (clumsy) and not a single rows-function with client-side summation
-- (the alternative the plan floated as "simplest honest"). Reasons:
--   1. `session_count` cannot be derived from the per-member rows at all
--      (a session has multiple members; summing member rows double/
--      triple-counts it) — the plan's own text flags this ("session count
--      needs its own cheap scalar"). Once a session-count scalar function
--      is required anyway, folding volume/PRs into the SAME scalar
--      function is strictly simpler for the client than: rows function +
--      a second scalar function + client-side reduce() for volume/PRs.
--   2. Server-computed totals are more honest than client-derived ones —
--      the client isn't trusted to correctly re-implement the aggregation
--      (or to keep doing so if the row shape changes later).
-- Two functions: `group_stats` (scalars: session_count, total_volume,
-- total_prs) + `group_member_stats` (rows: user_id, username, volume,
-- pr_count — the leaderboard). Named exactly as the plan's first-choice
-- option.
--
-- Membership scope consistency (deliberate, so the two functions' numbers
-- reconcile): BOTH functions scope volume/PR contributions to CURRENT
-- group members only (joined through group_members), not to whoever
-- historically participated in a session (group_burpee_ledger's shape).
-- A departed member's historical sets/PRs stop counting toward the crew's
-- collective total the moment they leave — "collective metrics" reads as
-- a live snapshot of the current roster, and "per-member leaderboard"
-- literally means "the members" (current ones). This makes
-- SUM(group_member_stats.volume) = group_stats.total_volume and
-- SUM(group_member_stats.pr_count) = group_stats.total_prs a real
-- invariant, checked in group_stats_rpc_test.sql. `session_count` has no
-- such membership scoping — it counts every completed session that ever
-- belonged to the group, current-roster-independent, since a session
-- itself isn't "owned" by any one member.
--
-- Session scope: `s.state = 'completed'` (sessions.state CHECK,
-- 20260709000006_create_sessions.sql:5-7) — matches activity_feed's
-- "collective metrics" reasoning (in-progress/scheduled sessions haven't
-- produced final volume/PR totals yet).
--
-- Volume formula + exclusions: `reps * weight`, excluding is_penalty and
-- is_failed rows — verbatim the same rule as increment_lifetime_volume()
-- (20260709000008_lifetime_volume_trigger.sql:4) and activity_feed's
-- per-session volume LATERAL (20260719000002_activity_feed_rpc.sql:65,
-- 69-70). NULL reps/weight coalesced to 0 (same as activity_feed).
--
-- No-fan-out aggregation: group_member_stats joins group_members ->
-- profiles (one row per current member, no multiplication risk) then
-- LEFT JOIN LATERAL for volume and LATERAL for pr_count independently —
-- same pattern as activity_feed's per-session set_logs/personal_records
-- LATERALs and group_burpee_ledger_paid's owed/paid LATERAL split: a
-- member's set_logs count and personal_records count are unrelated
-- cardinalities, so joining both directly into one GROUP BY would
-- multiply one aggregate by the other's row count. group_stats has no
-- fan-out risk at all — each of its three columns is an independent
-- scalar subquery, not a join.
CREATE OR REPLACE FUNCTION public.group_stats(p_group_id uuid)
RETURNS TABLE (
  session_count int,
  total_volume  numeric,
  total_prs     int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  -- Gate FIRST, same idiom as group_burpee_ledger / session_pr_counts:
  -- reject before any row is touched.
  IF NOT public.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*)::int
       FROM public.sessions s
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS session_count,
    (SELECT COALESCE(SUM(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)), 0)
       FROM public.set_logs sl
       JOIN public.sessions s ON s.id = sl.session_id
       JOIN public.group_members gm
         ON gm.group_id = p_group_id AND gm.user_id = sl.user_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed'
        AND NOT sl.is_penalty
        AND NOT sl.is_failed) AS total_volume,
    (SELECT count(*)::int
       FROM public.personal_records pr
       JOIN public.sessions s ON s.id = pr.session_id
       JOIN public.group_members gm
         ON gm.group_id = p_group_id AND gm.user_id = pr.user_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS total_prs;
END;
$$;

-- Self-gated by the is_group_member check above (same revoke-then-grant
-- idiom as group_burpee_ledger / session_pr_counts / register_push_device).
-- Newly created functions get PUBLIC EXECUTE by default, which anon
-- inherits, so REVOKE FROM PUBLIC, anon and GRANT back explicitly TO
-- authenticated. Do NOT include authenticated in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.group_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_stats(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.group_member_stats(p_group_id uuid)
RETURNS TABLE (
  user_id   uuid,
  username  text,
  volume    numeric,
  pr_count  int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT public.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT gm.user_id,
         p.username,
         COALESCE(vol_agg.volume, 0) AS volume,
         COALESCE(pr_agg.pr_count, 0)::int AS pr_count
    FROM public.group_members gm
    JOIN public.profiles p ON p.id = gm.user_id
    LEFT JOIN LATERAL (
      SELECT SUM(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)) AS volume
        FROM public.set_logs sl
        JOIN public.sessions s ON s.id = sl.session_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND sl.user_id = gm.user_id
         AND NOT sl.is_penalty
         AND NOT sl.is_failed
    ) vol_agg ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS pr_count
        FROM public.personal_records pr
        JOIN public.sessions s ON s.id = pr.session_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND pr.user_id = gm.user_id
    ) pr_agg ON true
   WHERE gm.group_id = p_group_id
   ORDER BY volume DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.group_member_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_member_stats(uuid) TO authenticated;
