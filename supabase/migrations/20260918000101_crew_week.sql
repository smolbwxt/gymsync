-- 20260918000101_crew_week.sql
--
-- APPLIED LIVE 2026-09-18 18:45:31 UTC (schema_migrations version
-- 20260918184531).
--
-- Spec §6 and owner decision 21 (Phase B2 brief, decisions 1-2). The crew's
-- weekly consistency strip needs one cross-member read: per participant of
-- a session, this week's goal and how many sessions they have completed.
--
-- WHY THE WEEK IS A PARAMETER, NOT COMPUTED HERE. Spec §6 writes
-- `crew_week(session_id)` — one argument short in practice. The strip's own
-- maths is Monday-first (`CrewWeek.doneByDay`), while the client's week
-- start is the device calendar's (`WeekMath.startOfWeek` uses
-- `calendar.dateInterval(of: .weekOfYear:)`, which is Sunday in a US
-- locale) — and Postgres's `date_trunc('week', …)` is Monday, in the
-- server's timezone. A server that picked its own week would print counts
-- for a week the athlete's own app does not agree with, under a kicker
-- that says "this week". So the client sends its own week start and this
-- function counts the half-open window
-- `[p_week_start, p_week_start + interval '7 days')` — one definition of
-- "this week" in the app, and pgTAP can pin it with a literal.
--
-- WHY `p_week_start` IS `timestamptz`, NOT `date` (R-B2-16). The first cut
-- of this function took `p_week_start date` and cast it with
-- `p_week_start::timestamptz` — which resolves a bare date at the SERVER's
-- timezone (UTC on this project), not the caller's. For a lifter at UTC−7
-- that shifted the counted window to `[Sat 17:00 local, next Sat 17:00
-- local)` — exactly the "counts for a week the athlete's own app does not
-- agree with" disagreement this function's whole parameter exists to
-- prevent, reintroduced one cast down. Taking `timestamptz` instead means
-- the client sends the actual ISO-8601 instant of its local week start,
-- offset included, and the server does no date arithmetic at all: every
-- comparison in this function is `timestamptz` to `timestamptz`, with the
-- caller's offset baked into the value before it ever reaches Postgres.
--
-- WHY THE GOAL COMES FROM profiles.weekly_session_goal, NOT weekly_goals.
-- `weekly_goals` (20260906000001) is the Home-v3 per-goal store, an
-- entirely different shape (multiple named goals per user, not a single
-- per-week session count). `profiles.weekly_session_goal`
-- (20260811000003, NOT NULL DEFAULT 3) is the one column the crew's own
-- goal has always lived in.
--
-- WHY `goal` IS NOT weekly_session_goal RAW (R-B2-14). Decision 2's text
-- rules out the wrong TABLE (weekly_goals) but never considered the
-- anti-goalpost COLUMNS a later migration added to the right one
-- (20260812000001_weekly_goal_next_week.sql): a goal edit made mid-week
-- must not take effect until next week, "so people can't move the
-- goalposts in order not to lose their streak." `weekly_session_goal` is
-- always the STANDING goal (in effect from next week on);
-- `weekly_session_goal_prev` + `weekly_session_goal_changed_at` are the
-- snapshot that governs the week the edit happened in.
-- `Profile.effectiveWeeklyGoal` (GymSyncApp/GymSync/Models/Profile.swift
-- :85-95) is the one place the app resolves this today, and it is the
-- documented single source of truth every other "sessions this week vs.
-- goal" comparison draws from (WeeklyGoalProgressMath.swift:312-318,
-- BlockGoalLiveRepository.swift:1280, HomeView.swift:718). This function
-- mirrors that same CASE in SQL — changed_at inside the window being
-- asked about, and prev not null, means prev governs that window;
-- otherwise the standing goal does — evaluated against `p_week_start`
-- rather than `.now`, because `crew_week` (unlike the Swift call site) is
-- asked about an arbitrary week, not only the current one (D2's own
-- pgTAP moves `p_week_start` back a week to prove the parameter, not the
-- clock, decides `done`; `goal` must be equally parameter-driven or the
-- same inconsistency the rule exists to prevent reappears one column
-- over). Without this, a member who lowers their goal mid-week to
-- protect a streak — the exact scenario the rule exists for — would be
-- shown to crewmates with the new goal immediately, while their own
-- Home/Ladder screens still show the old one until next week: the same
-- fact, two contradictory numbers, depending on which screen you're on.
--
-- WHY A ZERO-SESSION MEMBER IS A ROW HERE, AN ABSENCE IN
-- group_consistency_honor (20260911000001). The honor RPC drops a member
-- with zero sessions because a crown decays — no honor to show is the
-- correct empty state. A crew's week is different: it has to show the
-- lifter who has not trained yet, or the strip lies about the crew's size.
-- So every participant of the session is a row, done = 0 included.
--
-- THE SHAPE IS group_consistency_honor's, deliberately: gate FIRST with
-- private.is_session_participant, LEFT JOIN LATERAL per member so two
-- cardinalities cannot multiply, REVOKE then GRANT. Two departures from
-- that sibling, both named above: the window is a parameter rather than
-- `now() - interval '30 days'`, and a zero-session member is a row, not an
-- absence.
CREATE OR REPLACE FUNCTION public.crew_week(p_session_id uuid, p_week_start timestamptz)
RETURNS TABLE (user_id uuid, username text, goal int, done int)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT sp.user_id,
         p.username,
         -- Anti-goalpost rule (20260812000001), mirroring
         -- Profile.effectiveWeeklyGoal but relative to p_week_start rather
         -- than now(): a change stamped inside the window being asked
         -- about is still governed by the snapshot it took.
         (CASE
            WHEN p.weekly_session_goal_changed_at IS NOT NULL
             AND p.weekly_session_goal_prev IS NOT NULL
             AND p.weekly_session_goal_changed_at >= p_week_start
             AND p.weekly_session_goal_changed_at <  p_week_start + interval '7 days'
            THEN p.weekly_session_goal_prev
            ELSE p.weekly_session_goal
          END)::int                                AS goal,
         COALESCE(agg.session_count, 0)::int       AS done
    FROM public.session_participants sp
    JOIN public.profiles p ON p.id = sp.user_id
    LEFT JOIN LATERAL (
      SELECT count(DISTINCT s.id) AS session_count
        FROM public.sessions s
        JOIN public.session_participants sp2
          ON sp2.session_id = s.id AND sp2.user_id = sp.user_id
       WHERE s.state = 'completed'
         AND s.completed_at >= p_week_start
         AND s.completed_at <  p_week_start + interval '7 days'
    ) agg ON true
   WHERE sp.session_id = p_session_id
   ORDER BY p.username;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.crew_week(uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crew_week(uuid, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.crew_week(uuid, timestamptz) IS
  'Spec §6, owner decision 21 (R-B2-14, R-B2-16). Per participant of '
  'p_session_id: user_id, username, goal, done. p_week_start is the '
  'ISO-8601 INSTANT of the caller''s local week start, offset included '
  '(not a bare date) — R-B2-16: a date cast at the server''s timezone '
  'shifts the window by the caller''s UTC offset, exactly the '
  '"disagrees with the athlete''s own app" failure this parameter exists '
  'to prevent. done = DISTINCT completed sessions attended, via '
  'session_participants, with completed_at in the half-open window '
  '[p_week_start, p_week_start + interval ''7 days''), compared as '
  'timestamptz to timestamptz throughout — no date casts anywhere in this '
  'function. goal mirrors Profile.effectiveWeeklyGoal''s anti-goalpost '
  'CASE (20260812000001) over weekly_session_goal / '
  'weekly_session_goal_prev / weekly_session_goal_changed_at, evaluated '
  'against the same p_week_start window rather than now(): a goal change '
  'stamped inside the window asked about is still governed by the prev '
  'snapshot it took, so a member cannot dodge a crewmate''s view of their '
  'goal by editing it mid-week. A member with zero sessions this window '
  'is still a row (contrast group_consistency_honor, which drops them). '
  'SECURITY DEFINER gated by private.is_session_participant so any '
  'participant may read every other participant''s count.';
