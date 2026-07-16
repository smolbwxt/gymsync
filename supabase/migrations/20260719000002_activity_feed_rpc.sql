-- ============================================================
-- Canvas frame 45 (Task 3 prep) — Activity Feed aggregate RPC
-- ============================================================
-- Powers the Activity Feed screen: month-grouped rows of the calling user's
-- completed sessions with duration/volume/sets meta and a PR count chip.
--
-- SECURITY DEFINER, same reasoning as group_burpee_ledger
-- (20260717000002_burpee_ledger_rpc.sql) but adapted for a USER-SCOPED
-- aggregate rather than a group-wide one:
--
-- This RPC only ever returns rows for auth.uid() — every filter below is
-- hardwired to the caller's own id, so (unlike group_burpee_ledger's
-- p_group parameter) there is no OTHER entity to authorize against and
-- therefore no IF/RAISE EXCEPTION gate is needed. The caller's own identity
-- IS the gate.
--
-- DEFINER is still required, not for gating but to avoid a display-name
-- regression under RLS drift between "participated" (permanent, historical)
-- and "currently visible" (RLS's present-tense notion):
--   - groups: "members and creator can read group" requires CURRENT
--     is_group_member(). A user who later leaves a group must still see
--     that group's name on sessions they completed while a member —
--     INVOKER would silently NULL the join and the row would fall back to
--     'Workout' instead of the true group name.
--   - routines: "users can select routines they own OR public routines"
--     requires ownership or public visibility. A session organizer can add
--     ANY user as a participant (participants insertable only by session
--     organizer, not gated on group/friendship), so a participant who used
--     the organizer's private routine has no RLS path to that routine's
--     name under INVOKER — same silent-NULL-to-'Workout' regression.
-- session_participants / set_logs / personal_records all have "own row"
-- policies that pass trivially here since every predicate is user_id =
-- auth.uid(), so DEFINER changes nothing for those three, but is applied
-- uniformly since the function body is one query.
CREATE OR REPLACE FUNCTION public.activity_feed(p_limit int DEFAULT 50)
RETURNS TABLE (
  session_id    uuid,
  started_at    timestamptz,
  completed_at  timestamptz,
  is_group      boolean,
  display_name  text,
  set_count     int,
  volume        numeric,
  pr_count      int
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT
    s.id,
    s.started_at,
    s.completed_at,
    (s.group_id IS NOT NULL) AS is_group,
    CASE WHEN s.group_id IS NOT NULL
         THEN g.name
         ELSE COALESCE(r.name, 'Workout')
    END AS display_name,
    COALESCE(sl_agg.set_count, 0)::int AS set_count,
    COALESCE(sl_agg.volume, 0)::numeric AS volume,
    COALESCE(pr_agg.pr_count, 0)::int AS pr_count
  FROM public.sessions s
  JOIN public.session_participants sp
    ON sp.session_id = s.id AND sp.user_id = auth.uid()
  LEFT JOIN public.groups g ON g.id = s.group_id
  LEFT JOIN public.routines r ON r.id = s.routine_id
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS set_count,
           sum(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)) AS volume
      FROM public.set_logs sl
     WHERE sl.session_id = s.id
       AND sl.user_id = auth.uid()
       AND NOT sl.is_penalty
       AND NOT sl.is_failed
  ) sl_agg ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS pr_count
      FROM public.personal_records pr
     WHERE pr.session_id = s.id
       AND pr.user_id = auth.uid()
  ) pr_agg ON true
  WHERE s.state = 'completed'
  ORDER BY s.completed_at DESC NULLS LAST
  LIMIT p_limit;
$$;

-- Self-gated by auth.uid() throughout the query body above — same
-- revoke-then-grant idiom as group_burpee_ledger / register_push_device.
-- Newly created functions get PUBLIC EXECUTE by default, which anon
-- inherits, so REVOKE FROM PUBLIC, anon and GRANT back explicitly TO
-- authenticated. Do NOT include authenticated in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.activity_feed(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activity_feed(int) TO authenticated;
