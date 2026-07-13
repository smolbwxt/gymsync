-- ============================================================
-- Fix round 1 (Canvas Completion Task 3) — membership-gated ledger aggregate
-- ============================================================
-- Bug: SessionRepository.burpeeLedger(groupID:) queried session_participants
-- directly under RLS ("participants readable by other participants" ->
-- is_session_participant(session_id, auth.uid())). A member who joins a
-- group AFTER some of its sessions have already run was never invited to
-- those earlier sessions (see late_joiner_test.sql: new members are only
-- invited to FUTURE scheduled sessions), so they have no
-- session_participants row for them at all -> is_session_participant is
-- false for every pre-membership session -> RLS silently drops those rows
-- from THIS caller's query -> BurpeeLedgerMath.crewDebts undercounts every
-- crew member's total (not just the late joiner's own), because the whole
-- aggregate is computed client-side from whatever rows this one caller's
-- RLS-filtered fetch happened to return. The task-3-report.md previously
-- called this "correct behavior (RLS-consistent with 'you weren't there')"
-- — that was wrong: RLS is scoping which SESSIONS a member can act on, not
-- which pre-existing GROUP-WIDE debts they may read.
--
-- Fix: SECURITY DEFINER aggregate, gated on CURRENT group membership (not
-- session participation), that sums across every session_participants row
-- for the group regardless of who was or wasn't invited to which session.
--
-- Fields mirror BurpeeLedgerMath.crewDebts(rows:)'s per-user aggregation
-- exactly (total_owed = SUM(burpees_owed), late_count/no_show_count =
-- COUNT(check_in_state)), plus last_late_at: the effective date
-- (scheduled_for, falling back to started_at — same fallback as
-- BurpeeLedgerRow.SessionInfo.effectiveDate) of the most recent session
-- that actually contributed debt (burpees_owed > 0) — the group-wide
-- generalization of youOweSummary(rows:userID:)'s self-only
-- "most recent contributing session" pick.
CREATE OR REPLACE FUNCTION public.group_burpee_ledger(p_group uuid)
RETURNS TABLE (
  user_id       uuid,
  total_owed    int,
  late_count    int,
  no_show_count int,
  last_late_at  timestamptz
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  -- Gate: caller must be a CURRENT member of the group. Deliberately NOT
  -- is_session_participant — that's exactly the check whose absence (for
  -- pre-membership sessions) caused the undercount this RPC fixes.
  IF NOT public.is_group_member(p_group, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT sp.user_id,
         SUM(sp.burpees_owed)::int AS total_owed,
         COUNT(*) FILTER (WHERE sp.check_in_state = 'late')::int AS late_count,
         COUNT(*) FILTER (WHERE sp.check_in_state = 'no_show')::int AS no_show_count,
         MAX(COALESCE(s.scheduled_for, s.started_at))
           FILTER (WHERE sp.burpees_owed > 0) AS last_late_at
    FROM public.session_participants sp
    JOIN public.sessions s ON s.id = sp.session_id
   WHERE s.group_id = p_group
   GROUP BY sp.user_id;
END;
$$;

-- Self-gated by the is_group_member check above (same revoke-then-grant
-- idiom as register_push_device, 20260716000007_register_push_device.sql) —
-- newly created functions get PUBLIC EXECUTE by default, which anon
-- inherits, so REVOKE FROM PUBLIC, anon and GRANT back explicitly TO
-- authenticated. Do NOT include authenticated in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.group_burpee_ledger(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_burpee_ledger(uuid) TO authenticated;
