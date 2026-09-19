-- D5 (review-data.md F1): sessions.venue_id is written by claim_session_venue only.
--
-- The sessions UPDATE policy admits the organizer and every participant with no column
-- list, and private.session_round_guard covered round / round_started_at / stations /
-- style only, so a participant could PATCH venue_id directly and skip the presence check
-- (a venue check-in within 12 hours) that claim_session_venue exists to enforce.
--
-- The guard now refuses a client write of a non-NULL venue_id. Clearing to NULL stays
-- legal on purpose: venues ON DELETE SET NULL arrives here as an UPDATE, and a cleared
-- venue can only be re-claimed through the presence check.
--
-- claim_session_venue adopts the engine idiom (gymsync.engine on around its write, ''
-- after) and, for a caller with no recent check-in, returns the venue the session already
-- has (NULL when it has none) instead of always NULL.

-- APPLIED: 2026-09-18 19:34:41 UTC (schema_migrations version
-- 20260918193441). Verified live: the guard refuses a client write of a
-- non-NULL venue_id; claim_session_venue sets gymsync.engine around its
-- write and returns the session's existing venue for a caller with no
-- recent check-in; anon cannot execute it.

CREATE OR REPLACE FUNCTION private.session_round_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.round            IS DISTINCT FROM OLD.round
     OR NEW.round_started_at IS DISTINCT FROM OLD.round_started_at
     OR NEW.stations         IS DISTINCT FROM OLD.stations THEN
    RAISE EXCEPTION 'round, round_started_at and stations are engine-owned'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.style IS DISTINCT FROM OLD.style AND OLD.lifting_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'the style is fixed once lifting has started'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.venue_id IS NOT NULL AND NEW.venue_id IS DISTINCT FROM OLD.venue_id THEN
    RAISE EXCEPTION 'venue_id is claimed through claim_session_venue'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_session_venue(p_session_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_venue uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;
  SELECT venue_id INTO v_venue
    FROM public.venue_checkins
   WHERE user_id = auth.uid() AND created_at > now() - interval '12 hours'
   ORDER BY created_at DESC LIMIT 1;
  IF v_venue IS NOT NULL THEN
    PERFORM set_config('gymsync.engine', 'on', true);
    UPDATE public.sessions SET venue_id = v_venue
     WHERE id = p_session_id AND venue_id IS NULL;
    PERFORM set_config('gymsync.engine', '', true);
  END IF;
  SELECT venue_id INTO v_venue FROM public.sessions WHERE id = p_session_id;
  RETURN v_venue;
END;
$function$;
