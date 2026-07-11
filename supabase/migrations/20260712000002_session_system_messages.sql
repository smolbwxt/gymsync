CREATE OR REPLACE FUNCTION public.announce_session_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_username text;
  v_routine  text;
  v_body     text;
BEGIN
  IF NEW.group_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_username FROM public.profiles WHERE id = NEW.organizer_id;
  SELECT name INTO v_routine FROM public.routines WHERE id = NEW.routine_id;

  v_body := CASE
    WHEN TG_OP = 'INSERT' AND NEW.state = 'scheduled' THEN
      '📅 ' || COALESCE(v_routine, 'Workout') || ' scheduled for '
           || to_char(NEW.scheduled_for AT TIME ZONE 'UTC', 'Dy Mon DD, HH24:MI')
           || ' UTC by ' || v_username
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'in_progress' THEN
      '🏁 ' || COALESCE(v_routine, 'Session') || ' started'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'completed' THEN
      '✅ ' || COALESCE(v_routine, 'Session') || ' complete'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'abandoned' THEN
      '🌫️ ' || COALESCE(v_routine, 'Session') || ' abandoned'
    ELSE NULL
  END;

  IF v_body IS NOT NULL THEN
    INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
    VALUES (NEW.group_id, NULL, 'system_session', v_body,
            jsonb_build_object('session_id', NEW.id, 'state', NEW.state,
                               'scheduled_for', NEW.scheduled_for));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER session_lifecycle_announce
  AFTER INSERT OR UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.announce_session_lifecycle();
