-- Sets belong to LIVE sessions. Field bug 2026-07-30/31: a Home-CTA
-- NavigationLink re-resolved its computed session mid-workout, so a live
-- view carrying one session's @State wrote 14 sets into the NEXT
-- SCHEDULED series occurrence — a session that had never started. The
-- client now pins view identity to the session id and guards on state;
-- this trigger is the backstop that makes the damage class impossible at
-- the source, whatever surface regresses next.
--
-- Deny-list of PRE-LIVE states (not an allow-list): completed/abandoned
-- sessions must keep accepting inserts — the offline set-log queue
-- legitimately replays after a session ends (697 completed-state sets in
-- production are that flow's history).
CREATE OR REPLACE FUNCTION public.set_logs_reject_prelive_session()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_state text;
BEGIN
  SELECT state INTO v_state FROM public.sessions WHERE id = NEW.session_id;
  IF v_state IN ('scheduled', 'lobby_open', 'editing', 'voting', 'locked') THEN
    RAISE EXCEPTION 'session has not started' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_logs_reject_prelive ON public.set_logs;
CREATE TRIGGER set_logs_reject_prelive
  BEFORE INSERT ON public.set_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.set_logs_reject_prelive_session();
