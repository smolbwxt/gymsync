-- ============================================================
-- Fix-forward for 20260720000003_group_stats_rpc.sql (already applied to the
-- live DB — applied migrations are append-only in this repo, so this ships
-- as a NEW migration that CREATE OR REPLACEs group_stats rather than editing
-- 20260720000003 in place).
-- ============================================================
--
-- ── Reviewer finding: group_stats was internally inconsistent ──────────────
-- 20260720000003 scoped `total_volume`/`total_prs` to CURRENT group members
-- only (joined through group_members), while `session_count` was already
-- all-time (every completed session that ever belonged to the group,
-- current-roster-independent — see that migration's own header, "session_count
-- has no such membership scoping"). One RPC, two different scoping rules on
-- its own three columns. After roster turnover this reads to a user as "12
-- sessions, 0 lbs" — a group with a long, real history whose volume/PR
-- totals silently collapse toward zero the moment the members who logged
-- them leave, even though the sessions themselves (and the session count)
-- still show the group was active.
--
-- This also reversed the scoping philosophy `group_burpee_ledger` already
-- established and documented for group-wide aggregates
-- (20260717000002_burpee_ledger_rpc.sql: "sums across every
-- session_participants row for the group regardless of who was or wasn't
-- invited to which session" — gated on CURRENT membership to READ the
-- aggregate, but the aggregate itself counts everyone who ever participated,
-- not just today's roster). `group_burpee_ledger_paid`
-- (20260719000005_burpee_ledger_paid.sql) follows the same precedent for
-- `paid`. group_stats's member-scoped volume/PRs were the outlier, not the
-- ledger.
--
-- ── Decision ─────────────────────────────────────────────────────────────
-- `total_volume`/`total_prs` become ALL-TIME: every set_logs/personal_records
-- row belonging to one of the group's completed sessions counts, regardless
-- of whether that row's user_id is a current group_members row today. This
-- matches `session_count`'s existing scoping (no membership join at all) and
-- aligns with the group_burpee_ledger precedent above — a group's collective
-- history is "everyone who ever showed up," not "whoever is still here."
-- `is_penalty`/`is_failed` exclusions are unchanged (same rule as
-- increment_lifetime_volume() and activity_feed's per-session LATERAL).
--
-- `group_member_stats` (the per-member LEADERBOARD rows) is DELIBERATELY
-- left untouched — current-roster scoping is still correct there. A
-- leaderboard is "the current crew's standings"; ranking someone who left
-- the group above people who are still training together reads as wrong in
-- a way that an aggregate history total does not. This is a genuine split:
-- the scalar total answers "how much has this group ever lifted," the
-- leaderboard answers "who's on top right now."
--
-- ── Invariant dropped, on purpose ────────────────────────────────────────
-- 20260720000003 documented and pgTAP-checked SUM(group_member_stats.volume)
-- = group_stats.total_volume (and the pr_count equivalent) as "a real
-- invariant." That equality only held BECAUSE both functions shared the same
-- (inconsistent) current-members-only scoping — it was a side effect of the
-- bug, not a property worth preserving. With this fix, group_stats.
-- total_volume >= SUM(group_member_stats.volume) is the true relationship
-- (strict `>` whenever any departed member's historical rows exist for the
-- group; equal only when every contributing user is still a current
-- member). group_stats_rpc_test.sql is updated to assert the inequality
-- (with exact fixture numbers) instead of the old equality, with a comment
-- explaining why the equality was never a real invariant.
--
-- Future option, not taken here: if a future review instead wants
-- `group_member_stats` to ALSO include departed members (rows for everyone
-- who ever contributed, not just the current roster) so the two functions'
-- totals reconcile again by symmetry, that is a one-function follow-up
-- (drop the group_members join, add a LEFT JOIN to profiles for the
-- username) — flagged here as a live option, not decided.
-- ============================================================

CREATE OR REPLACE FUNCTION public.group_stats(p_group_id uuid)
RETURNS TABLE (
  session_count int,
  total_volume  numeric,
  total_prs     int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  -- Gate unchanged: caller must be a CURRENT member of the group. This
  -- controls who may READ the aggregate, not what the aggregate counts —
  -- same distinction group_burpee_ledger's gate already draws.
  IF NOT public.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*)::int
       FROM public.sessions s
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS session_count,
    -- All-time: no group_members join. Any set_logs row belonging to one of
    -- this group's completed sessions counts, whoever logged it, current
    -- member or not — matches session_count's scoping and the
    -- group_burpee_ledger precedent (see header above).
    (SELECT COALESCE(SUM(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)), 0)
       FROM public.set_logs sl
       JOIN public.sessions s ON s.id = sl.session_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed'
        AND NOT sl.is_penalty
        AND NOT sl.is_failed) AS total_volume,
    -- All-time, same reasoning: no group_members join.
    (SELECT count(*)::int
       FROM public.personal_records pr
       JOIN public.sessions s ON s.id = pr.session_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS total_prs;
END;
$$;

-- No REVOKE re-run needed: CREATE OR REPLACE preserves the function's
-- existing REVOKE EXECUTE / GRANT EXECUTE set in 20260720000003 (same idiom
-- already used by 20260719000004's mark_no_shows fix-forward and
-- 20260719000007's streak fix-forward) — signature and return type are both
-- unchanged here, only the body.

-- group_member_stats is NOT redefined by this migration — its current-roster
-- scoping is intentionally kept as-is (see header above).
