-- 1) Members of a session can read its ROUTINE (field 2026-07-31: the
--    organizer's PRIVATE routine never reached the crew — every member's
--    lobby said "No routine yet" and their live session had no exercises.
--    routine_exercises already had exactly this policy
--    (`routine_has_active_session_for_user`, 20260719-era) but the PARENT
--    routines table did not, so `RoutineRepository.fetch` died at the
--    routine row before the exercises policy ever mattered). The helper is
--    session-state-agnostic, so the lobby (pre-start) sees it too.
CREATE POLICY "session participants read the session routine"
  ON public.routines FOR SELECT
  USING (private.routine_has_active_session_for_user(id, auth.uid()));

-- 2) 'left' check-in state (user 2026-07-31: leaving a live session must
--    not end it for everyone). Outside the presence trio, so advance_turn
--    skips leavers; walking back in (left → online) rides the late-joiner
--    trigger to the rotation's end like any other re-arrival.
ALTER TABLE public.session_participants
  DROP CONSTRAINT session_participants_check_in_state_check;
ALTER TABLE public.session_participants
  ADD CONSTRAINT session_participants_check_in_state_check
  CHECK (check_in_state = ANY (ARRAY[
    'invited'::text, 'online'::text, 'ready'::text,
    'late'::text, 'no_show'::text, 'left'::text
  ]));
