CREATE OR REPLACE FUNCTION public.invite_new_member_to_future_sessions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.session_participants (session_id, user_id, check_in_state)
  SELECT s.id, NEW.user_id, 'invited'
  FROM public.sessions s
  WHERE s.group_id = NEW.group_id
    AND s.state = 'scheduled'
    AND s.scheduled_for > now()
  ON CONFLICT (session_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER invite_new_member_to_future_sessions
  AFTER INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.invite_new_member_to_future_sessions();
