-- D7 (review-data.md F9): the INSERT door of the same hole D5 closed on UPDATE.
--
-- private.session_round_guard is BEFORE UPDATE only, and neither sessions INSERT policy
-- has a column list, so an organizer (or a trainer booking for a client) could create a
-- session with venue_id already set -- no presence check, the same bypass by another
-- door. A BEFORE INSERT guard refuses a non-NULL venue_id unless the engine GUC is on.
-- Every existing insert path leaves the column NULL (it is a day old), so nothing that
-- ships today changes behaviour. BEFORE ROW triggers run before the RLS WITH CHECK, so
-- the caller sees this P0001 rather than a policy violation.
--
-- Not covered here, on purpose: round / round_started_at / stations are equally
-- unguarded on INSERT. The QA seed and fixtures write them at insert time; docketed.
--
-- APPLIED: live 2026-09-18 as `session_venue_insert_guard`, version 20260918195107
-- (controller, Supabase MCP; verified: trigger present BEFORE INSERT on public.sessions).

CREATE OR REPLACE FUNCTION private.session_venue_insert_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.venue_id IS NOT NULL THEN
    RAISE EXCEPTION 'venue_id is claimed through claim_session_venue'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS session_venue_insert_guard ON public.sessions;
CREATE TRIGGER session_venue_insert_guard
  BEFORE INSERT ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION private.session_venue_insert_guard();
