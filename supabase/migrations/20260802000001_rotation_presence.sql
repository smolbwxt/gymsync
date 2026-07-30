-- Rotation presence (2026-07-30 user direction): "if the workout starts
-- without someone checked in, they should not be in the queue for the
-- rotation. If they join late, add them in at the end of the rotation —
-- but we should not be waiting on someone who's not checked in for me to
-- have my turn again."
--
-- THE DEFECT: advance_turn's next-picker excluded only 'no_show'. The
-- check-in state machine is invited → online/ready/late → no_show, so a
-- participant who never opened the session ('invited', or NULL) was a full
-- member of the rotation — the turn could land on a ghost and the whole
-- room waited. Observed on device 2026-07-30 (a never-checked-in test
-- account sat in a live session's queue).
--
-- THE FIX, two parts:
--   1. advance_turn only hands the turn to PRESENT participants —
--      check_in_state IN ('online','ready','late'), the exact presence
--      trio the push logic already defines (20260716000001_push_schema
--      .sql:192-206). One definition of "here", now used by both.
--   2. A late joiner (first transition into the presence trio AFTER the
--      session is in progress) moves to the END of the rotation:
--      turn_order = max(turn_order)+1. Their original slot was assigned
--      when the session started without them; joining mid-rotation must
--      not let them cut the line — or worse, be skipped forever because
--      the wrap already passed their number.

-- ── 1. advance_turn: present-only next-picker ────────────────────────────
-- Full replacement of 20260801000001's function; the idempotency guard,
-- authorization, locking and version bump are byte-identical — only the
-- two next-picker WHERE clauses change.
CREATE OR REPLACE FUNCTION public.advance_turn(
  p_session_id       uuid,
  p_expected_version integer DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id    uuid;
  v_state           text;
  v_current_user    uuid;
  v_turn_version    integer;
  v_current_order   integer;
  v_next_user       uuid;
  v_next_order      integer;
BEGIN
  -- Lock the session row to serialize concurrent advances.
  SELECT organizer_id, state, current_turn_user_id, turn_version
    INTO v_organizer_id, v_state, v_current_user, v_turn_version
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

  -- Idempotency guard — see 20260801000001 for the full rationale.
  IF p_expected_version IS NOT NULL AND p_expected_version <> v_turn_version THEN
    RETURN v_current_user;
  END IF;

  -- Authorization: must be current lifter OR organizer.
  IF auth.uid() IS DISTINCT FROM v_current_user AND
     auth.uid() IS DISTINCT FROM v_organizer_id THEN
    RAISE EXCEPTION 'not your turn' USING ERRCODE = 'P0001';
  END IF;

  IF v_state <> 'in_progress' THEN
    RAISE EXCEPTION 'session is not in progress' USING ERRCODE = 'P0001';
  END IF;

  -- Resolve current turn_order.
  SELECT turn_order INTO v_current_order
    FROM public.session_participants
   WHERE session_id = p_session_id AND user_id = v_current_user;

  -- Next PRESENT participant, wrapping. 'invited' and NULL are not present:
  -- the rotation never waits on someone who hasn't checked in.
  SELECT user_id, turn_order
    INTO v_next_user, v_next_order
    FROM public.session_participants
   WHERE session_id = p_session_id
     AND check_in_state IN ('online', 'ready', 'late')
     AND turn_order > v_current_order
   ORDER BY turn_order ASC
   LIMIT 1;

  IF v_next_user IS NULL THEN
    SELECT user_id, turn_order
      INTO v_next_user, v_next_order
      FROM public.session_participants
     WHERE session_id = p_session_id
       AND check_in_state IN ('online', 'ready', 'late')
       AND turn_order <= v_current_order
     ORDER BY turn_order ASC
     LIMIT 1;
  END IF;

  IF v_next_user IS NULL THEN
    RAISE EXCEPTION 'no active participants remain' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.sessions
  SET current_turn_user_id    = v_next_user,
      current_turn_started_at = now(),
      turn_version            = turn_version + 1
  WHERE id = p_session_id;

  RETURN v_next_user;
END;
$$;

-- ── 2. Late joiners append to the rotation's end ─────────────────────────
-- Fires on the FIRST transition into presence while the session is already
-- in progress. Pre-start check-ins keep their assigned order (the normal
-- flow); re-transitions (late → ready etc.) don't reshuffle — only the
-- arrival itself moves you, and only once.
CREATE OR REPLACE FUNCTION public.session_late_joiner_to_rotation_end()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_state text;
BEGIN
  -- Only the not-present → present edge.
  IF NEW.check_in_state NOT IN ('online', 'ready', 'late') THEN
    RETURN NEW;
  END IF;
  IF COALESCE(OLD.check_in_state, 'invited') IN ('online', 'ready', 'late') THEN
    RETURN NEW;
  END IF;

  SELECT state INTO v_state FROM public.sessions WHERE id = NEW.session_id;
  IF v_state IS DISTINCT FROM 'in_progress' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(MAX(turn_order), 0) + 1
    INTO NEW.turn_order
    FROM public.session_participants
   WHERE session_id = NEW.session_id
     AND user_id <> NEW.user_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS late_joiner_to_rotation_end ON public.session_participants;
CREATE TRIGGER late_joiner_to_rotation_end
  BEFORE UPDATE OF check_in_state ON public.session_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.session_late_joiner_to_rotation_end();
