-- Field 2026-08-24: "Deleting a workout doesn't affect the streak."
-- streak_bump_user fires on completion; nothing ever reversed it, so a
-- deleted workout kept its credit forever.
--
-- Fix: BEFORE DELETE on sessions (row still readable, participants not
-- yet cascaded) recomputes each credited participant's CURRENT streak
-- from the sessions that remain, excluding the dying row, under the
-- same credit predicates streak_on_session_state_change uses: state
-- completed, own check-in ready/late, and unscheduled sessions must
-- carry real non-penalty logged work.
--
-- Two honest limitations, both deliberate:
--   • The recompute counts qualifying sessions since the last recorded
--     break (broken_at). Sessions that predate solo-streak credit
--     (20260803000005) would over-count, so the result is clamped with
--     LEAST(recomputed, current) — deletion can only lower or hold a
--     streak, never inflate it.
--   • longest_streak keeps its history: past eras cannot be
--     reconstructed from a single broken_at, and retro-shrinking a
--     record the athlete already saw is worse than letting a deleted
--     session's contribution stand in the all-time number.

CREATE OR REPLACE FUNCTION public.streak_recompute_user_after_delete(
  p_user_id uuid, p_exclude uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_current  integer;
  v_broken   timestamptz;
  v_count    integer;
  v_last_id  uuid;
BEGIN
  SELECT current_streak, broken_at INTO v_current, v_broken
    FROM public.user_streaks WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT count(*) INTO v_count
  FROM public.sessions s
  JOIN public.session_participants sp
    ON sp.session_id = s.id AND sp.user_id = p_user_id
  WHERE s.id <> p_exclude
    AND s.state = 'completed'
    AND sp.check_in_state IN ('ready', 'late')
    AND (v_broken IS NULL OR s.completed_at > v_broken)
    AND (
      s.scheduled_for IS NOT NULL
      OR EXISTS (
        SELECT 1 FROM public.set_logs sl
        WHERE sl.session_id = s.id
          AND sl.user_id = p_user_id
          AND COALESCE(sl.is_penalty, false) = false
      )
    );

  -- Clamp: recompute may over-count pre-solo-credit history; a delete
  -- can only lower or hold the streak.
  v_count := LEAST(COALESCE(v_count, 0), COALESCE(v_current, 0));

  -- last_streak_session_id: latest remaining credited session.
  SELECT s.id INTO v_last_id
  FROM public.sessions s
  JOIN public.session_participants sp
    ON sp.session_id = s.id AND sp.user_id = p_user_id
  WHERE s.id <> p_exclude
    AND s.state = 'completed'
    AND sp.check_in_state IN ('ready', 'late')
  ORDER BY s.completed_at DESC NULLS LAST
  LIMIT 1;

  UPDATE public.user_streaks
  SET current_streak = v_count,
      last_streak_session_id = v_last_id
  WHERE user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.streak_on_session_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec RECORD;
BEGIN
  IF OLD.state <> 'completed' THEN
    RETURN OLD;
  END IF;
  FOR rec IN
    SELECT sp.user_id FROM public.session_participants sp
    WHERE sp.session_id = OLD.id
      AND sp.check_in_state IN ('ready', 'late')
  LOOP
    PERFORM public.streak_recompute_user_after_delete(rec.user_id, OLD.id);
  END LOOP;
  RETURN OLD;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.streak_recompute_user_after_delete(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS streak_on_session_delete ON public.sessions;
CREATE TRIGGER streak_on_session_delete
  BEFORE DELETE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.streak_on_session_delete();
