-- D5 (Phase C1; review-data.md, blocking): the INSERT door of the swap layer.
--
-- private.session_round_guard is BEFORE UPDATE only, and the sessions INSERT
-- policy (organizer_id = auth.uid()) has no column list, so an organizer could
-- create a session with squad_swaps already set -- skipping every check
-- apply_squad_swap makes (a real slot of the session's routine, a known
-- replacement). The controller first ruled this door harmless ("an organizer
-- could equally choose another routine"); the review's answer is the right one:
-- the door bypasses VALIDATION, not authority, and it is the same hole
-- 20260918000204 closed for venue_id a day earlier. One more clause on that
-- same insert guard. Nothing that ships writes squad_swaps at insert.
--
-- Also corrects the self_swaps column comment, which said it is read "ahead of
-- squad_swaps": RoutineLayering.apply layers squad_swaps FIRST and the lifter's
-- own self_swaps OVERRIDES it, then todays_scale.
--
-- Not changed, on purpose (docketed): the organizer-side UPDATE policy on
-- session_participants has no column list, so an organizer can overwrite a
-- lifter's self_swaps -- as they already can energy and todays_scale.
--
-- APPLIED: live 2026-09-19 as `session_swap_layer_insert_guard`, version 20260919004851
-- (controller, Supabase MCP; verified: the insert guard carries the venue AND the squad_swaps clauses).

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

  IF NEW.squad_swaps IS NOT NULL THEN
    RAISE EXCEPTION 'squad_swaps is written through apply_squad_swap'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON COLUMN public.session_participants.self_swaps IS
  'My own quiet exercise swaps for this session (decision 2, Phase C1 D1). Shape {"<routine_exercise_id>": "<replacement_exercise_id>", ...}, keyed by the routine_exercises row id (the SLOT), not the exercise id -- a routine may name one lift twice. An absent key means no swap for that slot; NULL means no layer at all -- readers must treat NULL and {} identically. Written by a direct own-row UPDATE through the existing "participant updates own check-in" policy -- no new policy. Layer order in RoutineLayering.apply(): squad_swaps first, then self_swaps OVERRIDES it for this lifter, then todays_scale.';
