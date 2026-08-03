-- Solo workouts count toward your streak (owner report 2026-08-02:
-- "completed solo workouts don't contribute toward your streak").
--
-- Diagnosis: `startSolo` DOES create a `session_participants` row with
-- check_in_state='ready', so the readiness predicate was never the problem.
-- The blanket `IF NEW.scheduled_for IS NULL THEN RETURN NEW` guard was: a
-- solo workout is unscheduled by construction, so the trigger returned
-- before reaching either bump.
--
-- That guard was written to stop an ad-hoc "Quick Workout" tap from minting
-- streak credit for nothing, which is still a rule worth keeping. So rather
-- than deleting it, this migration replaces "was it scheduled?" with the
-- question the guard was actually reaching for: DID YOU DO THE WORK?
--
--   • Scheduled sessions: behavior COMPLETELY unchanged — same readiness
--     predicates ('ready'/'late'), same group rule, same abandonment breaks.
--   • Unscheduled + completed: bumps the INDIVIDUAL streak only for
--     participants who logged at least one non-penalty set in that session.
--     Opening a solo session and closing it still earns nothing; finishing
--     actual sets earns the day.
--   • Unscheduled + abandoned: still returns early. Bailing out of an ad-hoc
--     workout must not BREAK a streak — the punishment path stays reserved
--     for sessions someone committed to on a schedule.
--   • Group streaks stay scheduled-only. A crew streak is about showing up
--     to a planned session together; nothing here changes that.
--
-- Penalty sets are excluded from the "did work" test on purpose: paying off
-- burpee debt is not a workout.

CREATE OR REPLACE FUNCTION public.streak_on_session_state_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec           RECORD;
  v_all_ready   boolean;
  v_unscheduled boolean;
BEGIN
  IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
    RETURN NEW;
  END IF;
  IF NEW.state NOT IN ('completed', 'abandoned') THEN
    RETURN NEW;
  END IF;

  v_unscheduled := NEW.scheduled_for IS NULL;

  -- Unscheduled sessions reach the 'completed' branch (gated on logged work
  -- below); everything else about them is still ignored, including the
  -- abandonment break.
  IF v_unscheduled AND NEW.state <> 'completed' THEN
    RETURN NEW;
  END IF;

  IF NEW.state = 'completed' THEN
    -- Lock this session's participant rows BEFORE evaluating readiness, so
    -- this transaction serializes against a concurrent mark_no_shows() tick
    -- touching the same rows (Finding 1(a), 20260719000007 — unchanged).
    PERFORM 1 FROM public.session_participants
      WHERE session_id = NEW.id
      FOR UPDATE;

    -- Individual: every participant whose OWN row is 'ready' OR 'late' at
    -- completion increments, independent of everyone else's state (the
    -- 2026-07-16 late-credit widening, unchanged).
    --
    -- The trailing clause is the 2026-08-02 addition and applies ONLY to
    -- unscheduled sessions: they must carry real logged work by that
    -- specific user. `NOT v_unscheduled` short-circuits it away entirely for
    -- scheduled sessions, so their behavior is bit-for-bit what it was.
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id
        AND sp.check_in_state IN ('ready', 'late')
        AND (
          NOT v_unscheduled
          OR EXISTS (
            SELECT 1 FROM public.set_logs sl
            WHERE sl.session_id = NEW.id
              AND sl.user_id = sp.user_id
              AND COALESCE(sl.is_penalty, false) = false
          )
        )
    LOOP
      PERFORM public.streak_bump_user(rec.user_id, NEW.id);
    END LOOP;

    -- Group: only if EVERY invited participant is ready OR late — and only
    -- for scheduled sessions. A crew streak measures showing up to something
    -- you planned together.
    IF NOT v_unscheduled AND NEW.group_id IS NOT NULL THEN
      SELECT NOT EXISTS (
        SELECT 1 FROM public.session_participants sp
        WHERE sp.session_id = NEW.id
          AND COALESCE(sp.check_in_state, 'invited') NOT IN ('ready', 'late')
      ) INTO v_all_ready;

      IF v_all_ready THEN
        PERFORM public.streak_bump_group(NEW.group_id, NEW.id);
      END IF;
    END IF;

  ELSIF NEW.state = 'abandoned' THEN
    -- Untouched. Breaks every invited participant who never checked in at
    -- all. Absence predicate per the mark_no_shows Finding-1 lesson
    -- (20260719000004): check_in_at IS NULL, never a state-label guess.
    -- Unreachable for unscheduled sessions (early return above).
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_at IS NULL
    LOOP
      PERFORM public.streak_break_user(rec.user_id, NEW.id);
    END LOOP;

    -- Defensive group break, same absence-predicate discipline. Unconditional
    -- re-apply is a documented no-op (streak_break_group's own header).
    IF NEW.group_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_at IS NULL
    ) THEN
      PERFORM public.streak_break_group(NEW.group_id, NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
