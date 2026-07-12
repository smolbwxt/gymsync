-- ============================================================
-- Phase 3b Task 2: Live plumbing (set_logs publication + no-show rejoin)
-- ============================================================

-- ── 1. Add set_logs to realtime publication ────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.set_logs;


-- ── 2. Fix-forward: join_session_by_code ──────────────────────────────────────
--    Copy of 20260712000005 with improved ON CONFLICT clause:
--    no_show participants re-joining by code get a clean slate (online, no check-in fields).
--    other states (ready, online, late) are untouched via WHERE clause.
CREATE OR REPLACE FUNCTION public.join_session_by_code(p_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT id INTO v_session_id
    FROM public.sessions
   WHERE room_code = p_code
     AND state IN ('scheduled', 'lobby_open');

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'invalid room code' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.session_participants (session_id, user_id, check_in_state)
  VALUES (v_session_id, auth.uid(), 'online')
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET check_in_state = 'online', check_in_at = NULL, check_in_method = NULL
    WHERE session_participants.check_in_state = 'no_show';

  RETURN v_session_id;
END;
$$;


-- ── 3. Fix-forward: advance_turn with liveness guard ────────────────────────────
--    Copy of 20260714000001 with added validation:
--    after the wrap-around query, raise if no active participants remain.
CREATE OR REPLACE FUNCTION public.advance_turn(p_session_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id    uuid;
  v_state           text;
  v_current_user    uuid;
  v_current_order   integer;
  v_max_order       integer;
  v_next_user       uuid;
  v_next_order      integer;
BEGIN
  -- Lock the session row to serialize concurrent advances.
  SELECT organizer_id, state, current_turn_user_id
    INTO v_organizer_id, v_state, v_current_user
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

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

  SELECT MAX(turn_order) INTO v_max_order
    FROM public.session_participants
   WHERE session_id = p_session_id;

  -- Find the next active (non-no_show) participant wrapping around.
  -- Try orders higher than current first, then wrap from 1.
  SELECT user_id, turn_order
    INTO v_next_user, v_next_order
    FROM public.session_participants
   WHERE session_id = p_session_id
     AND check_in_state <> 'no_show'
     AND turn_order > v_current_order
   ORDER BY turn_order ASC
   LIMIT 1;

  -- Wrap if nothing found after current.
  IF v_next_user IS NULL THEN
    SELECT user_id, turn_order
      INTO v_next_user, v_next_order
      FROM public.session_participants
     WHERE session_id = p_session_id
       AND check_in_state <> 'no_show'
       AND turn_order <= v_current_order
     ORDER BY turn_order ASC
     LIMIT 1;
  END IF;

  -- Liveness guard: ensure at least one active participant remains.
  IF v_next_user IS NULL THEN
    RAISE EXCEPTION 'no active participants remain' USING ERRCODE = 'P0001';
  END IF;

  -- Update session's current turn.
  UPDATE public.sessions
  SET current_turn_user_id    = v_next_user,
      current_turn_started_at = now()
  WHERE id = p_session_id;

  RETURN v_next_user;
END;
$$;
