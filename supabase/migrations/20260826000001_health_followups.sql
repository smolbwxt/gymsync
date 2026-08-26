-- PAR-Q+ Step 2 (2026-08-26).
--
-- Step 1 is a ROUTER, not a verdict. Its own decision rule: all seven NO
-- means cleared; any YES routes to the FOLLOW-UP condition pages or a
-- clinician conversation. We shipped only the second branch, so a single
-- YES refused to program someone permanently — every asthmatic, every
-- statin user, every person on levothyroxine treated identically to
-- unstable angina.
--
-- follow_ups holds Step-2 answers as {question_id: option_id}. Open shape
-- for the same reason `answers` is: the instrument gets revised and the
-- schema should not have to. The app's HealthTriage is the only thing that
-- interprets it.
--
-- Note what is NOT stored: which symptom, which condition, which
-- medication. We refer either way, and recording those would edge toward
-- holding clinical data — outside what a training app has any business
-- keeping, and outside the scope NSCA draws for a trainer.
ALTER TABLE public.health_screenings
  ADD COLUMN IF NOT EXISTS follow_ups jsonb NOT NULL DEFAULT '{}'::jsonb;
