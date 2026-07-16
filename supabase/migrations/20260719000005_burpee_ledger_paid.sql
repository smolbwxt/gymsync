-- ============================================================
-- Phase S Task 2 — Burpee settlement, derived from penalty logs
-- ============================================================
-- Decision (docs/superpowers/specs/2026-07-16-streaks-design.md #2):
-- settled burpees are DERIVED, not stored. `paid` = Sum of reps of a
-- member's is_penalty = true set_logs rows within the group's sessions —
-- the exact same session scope group_burpee_ledger already uses for
-- `owed` (session_participants JOIN sessions WHERE sessions.group_id =
-- p_group). `settled` = paid >= total_owed. No new columns anywhere:
-- no counter to drift against the append-only set_logs history it
-- summarizes.
--
-- Burpee-identification finding (discovery, not a re-decision): set_logs
-- has no column or constraint tying an is_penalty row to a specific
-- "burpee" exercise identity.
--   - groups/sessions.late_penalty is `{"exercise": "burpee", "per_minute":
--     N}` (20260712000001_sessions_phase3_columns.sql,
--     20260713000001_session_series.sql) — "exercise" is a free-text
--     label, group-configurable, never validated against exercises.slug.
--   - The client's penalty-logging sheet
--     (GroupSessionLiveView.swift:1346-1349) best-effort matches
--     `allExercises.first(where: name contains "burpee")`, falling back to
--     `allExercises.first` (i.e. ANY exercise) when no such row exists.
--   - 20260709000003_seed_exercises.sql never seeds a "burpee" exercise at
--     all, so that fallback is the common case today — penalty sets are
--     routinely logged against whatever exercise happens to be first in
--     the list, NOT a dedicated burpee row.
--   - `owed` itself (session_participants.burpees_owed) is a unitless
--     penalty-minutes counter with no exercise_id of its own.
-- Since neither side of the ledger (owed or the exercise catalog) ties
-- penalty debt to one canonical exercise row, filtering `paid` by
-- exercise identity would be unenforceable and inconsistent with how
-- `owed` is computed. Simplest faithful rule, matching frame 25's "paid
-- off 20": every is_penalty = true set_logs row by that user, in that
-- group's sessions, counts as paid — regardless of exercise_id.
--
-- No-fan-out aggregation: `owed`'s per-user sums come from a GROUP BY
-- over session_participants JOIN sessions (one row per participant-
-- session). Joining set_logs directly into that same GROUP BY would
-- multiply session_participants rows by however many set_logs rows exist
-- for that user/session, corrupting SUM(burpees_owed) and the late/
-- no_show counts. Fixed the same way activity_feed
-- (20260719000002_activity_feed_rpc.sql) avoids fan-out for its per-
-- session set_logs/personal_records aggregates: the owed aggregation
-- runs first as its own GROUP BY (unchanged), then a LATERAL subquery
-- computes `paid` independently per user_id row — no join multiplies
-- either aggregate.
-- Postgres cannot CREATE OR REPLACE a function that changes its OUT-parameter
-- row type (RETURNS TABLE column list) — adding `paid`/`settled` hits
-- "cannot change return type of existing function" (42P13). Drop first;
-- the REVOKE/GRANT below re-applies the exact same grants immediately after.
DROP FUNCTION IF EXISTS public.group_burpee_ledger(uuid);

CREATE FUNCTION public.group_burpee_ledger(p_group uuid)
RETURNS TABLE (
  user_id       uuid,
  total_owed    int,
  paid          int,
  settled       boolean,
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
  SELECT owed.user_id,
         owed.total_owed,
         COALESCE(paid_agg.paid, 0)::int AS paid,
         COALESCE(paid_agg.paid, 0) >= owed.total_owed AS settled,
         owed.late_count,
         owed.no_show_count,
         owed.last_late_at
    FROM (
      SELECT sp.user_id,
             SUM(sp.burpees_owed)::int AS total_owed,
             COUNT(*) FILTER (WHERE sp.check_in_state = 'late')::int AS late_count,
             COUNT(*) FILTER (WHERE sp.check_in_state = 'no_show')::int AS no_show_count,
             MAX(COALESCE(s.scheduled_for, s.started_at))
               FILTER (WHERE sp.burpees_owed > 0) AS last_late_at
        FROM public.session_participants sp
        JOIN public.sessions s ON s.id = sp.session_id
       WHERE s.group_id = p_group
       GROUP BY sp.user_id
    ) owed
    LEFT JOIN LATERAL (
      SELECT SUM(COALESCE(sl.reps, 0))::int AS paid
        FROM public.set_logs sl
        JOIN public.sessions ps ON ps.id = sl.session_id
       WHERE ps.group_id = p_group
         AND sl.user_id = owed.user_id
         AND sl.is_penalty
    ) paid_agg ON true;
END;
$$;

-- Self-gated by the is_group_member check above (same revoke-then-grant
-- idiom as register_push_device, 20260716000007_register_push_device.sql).
-- The DROP above wipes prior grants, and a freshly CREATEd function gets
-- PUBLIC EXECUTE by default (which anon inherits), so this REVOKE FROM
-- PUBLIC, anon + GRANT TO authenticated must be restated here.
REVOKE EXECUTE ON FUNCTION public.group_burpee_ledger(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_burpee_ledger(uuid) TO authenticated;
