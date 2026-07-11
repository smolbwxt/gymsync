-- RPC: join_session_by_code
-- Lets any authenticated user join a session by its room code.
-- SECURITY DEFINER so the RLS session-readable-only-to-participants restriction
-- is bypassed during the lookup; once the caller is inserted as a participant
-- they gain full RLS access through the existing participant-read policy.
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
  ON CONFLICT (session_id, user_id) DO NOTHING;

  RETURN v_session_id;
END;
$$;
