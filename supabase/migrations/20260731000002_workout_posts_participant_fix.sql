-- Pump Check P1 fixup: the INSERT policy called
-- public.is_session_participant, whose EXECUTE was revoked from
-- `authenticated` in the dual-schema hardening (20260726000001:429 — it is
-- service-role-only now; the 13 repointed policies all call
-- private.is_session_participant). Evaluated as an authenticated client,
-- the policy's function call fails and EVERY post INSERT is denied —
-- caught by workout_posts_test.sql test 1 before any client shipped.
-- Same contract, unreachable schema.

DROP POLICY "author posts own finished session" ON public.workout_posts;
CREATE POLICY "author posts own finished session"
  ON public.workout_posts FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND private.is_session_participant(workout_posts.session_id, auth.uid())
  );
