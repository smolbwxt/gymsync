-- Session participants need read access to exercises in the session's routine.
-- The trigger in 20260712000003 can INSERT into routine_exercises (SECURITY DEFINER
-- bypasses the owner-only write policy), but participants who are not the routine
-- owner could not SELECT the resulting rows. This policy grants read-only access
-- so participants can observe the current exercise list during the editing lobby.
CREATE OR REPLACE FUNCTION public.routine_has_active_session_for_user(
  p_routine_id uuid, p_user_id uuid
)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sessions s
    JOIN public.session_participants sp ON sp.session_id = s.id
    WHERE s.routine_id = p_routine_id
      AND sp.user_id = p_user_id
  );
$$;

CREATE POLICY "session participants read session routine exercises"
  ON public.routine_exercises FOR SELECT TO authenticated
  USING (
    public.routine_has_active_session_for_user(routine_exercises.routine_id, auth.uid())
  );
