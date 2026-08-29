-- O1 (first-run resume, review-critical): onboarding completion becomes a
-- DURABLE fact instead of process memory. The coordinator's isNewSignup
-- was @State - kill the app after the username row existed and relaunch
-- routed straight to the main app, permanently skipping home gym, lift
-- anchors, push priming, the welcome screen, and the Coach offer (whose
-- only setter is the welcome screen).
--
-- NULL = this signup never finished the onboarding arc; the app resumes
-- it. Backfilled to created_at for every existing profile so nobody who
-- is already using the app re-onboards.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS onboarded_at timestamptz;
UPDATE public.profiles SET onboarded_at = created_at WHERE onboarded_at IS NULL;
