-- ============================================================
-- Device QA Round 1 — Bug 2 (20-minute check-in window, server-side)
-- ============================================================
-- The client (LobbyView) already disables "Check In" until
-- scheduled_for - 20 minutes, but SessionRepository.checkIn does a bare
-- UPDATE with no time predicate — nothing on the server enforces the
-- window, so it's spoofable by any authenticated client hitting the
-- session_participants table directly. Add a BEFORE UPDATE trigger scoped
-- to the check-in transition (NEW.check_in_state = 'ready'), matching the
-- existing engine_guard trigger's style
-- (20260714000001_session_engine_rpcs.sql).

CREATE OR REPLACE FUNCTION public.checkin_window_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_scheduled_for timestamptz;
BEGIN
  -- Only guard the check-in transition itself (NEW.check_in_state = 'ready').
  -- Other transitions (online, late, no_show, etc. — e.g. join_session_by_code,
  -- evaluate_lateness) are untouched.
  IF NEW.check_in_state IS DISTINCT FROM 'ready' THEN
    RETURN NEW;
  END IF;

  -- Engine bypass — mirrors engine_guard's escape hatch so server-side engine
  -- flows can never be blocked by this guard.
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  SELECT scheduled_for INTO v_scheduled_for
    FROM public.sessions
   WHERE id = NEW.session_id;

  -- No scheduled_for (shouldn't happen for a lobby check-in) — fail open
  -- rather than permanently blocking check-in on unexpected data.
  IF v_scheduled_for IS NOT NULL
     AND now() < v_scheduled_for - interval '20 minutes' THEN
    RAISE EXCEPTION 'check-in opens 20 minutes before the scheduled start'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS checkin_window_guard ON public.session_participants;
CREATE TRIGGER checkin_window_guard
  BEFORE UPDATE ON public.session_participants
  FOR EACH ROW EXECUTE FUNCTION public.checkin_window_guard();
