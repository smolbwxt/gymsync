-- For Phase 1, PR detection returns a boolean the client can use to render
-- a celebration on the newly-inserted log. Phase 4 will replace this with a
-- system_pr chat message when Groups + Chat exist.

CREATE OR REPLACE FUNCTION public.is_pr(p_user_id uuid, p_exercise_id uuid, p_weight numeric)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.set_logs
    WHERE user_id = p_user_id
      AND exercise_id = p_exercise_id
      AND is_failed = false
      AND is_penalty = false
      AND weight >= p_weight
  );
$$;

COMMENT ON FUNCTION public.is_pr IS
  'Returns true when the given weight strictly exceeds all prior non-failed non-penalty logs for the user+exercise. Callable from clients to render PR celebrations.';
