-- ============================================================
-- Exercise media: YouTube demo video IDs.
-- ============================================================
-- Design: docs/superpowers/specs/2026-07-26-lifting-quality-design.md,
-- Phase M. Stores the VIDEO ID, not a URL — the client builds the
-- youtube-nocookie embed URL itself, so a future player change is a client
-- change, and a stored URL can't smuggle in a non-embed form.
--
-- Population is a content operation (service-role SQL from the verified
-- research CSV), not a client write — exercises is global catalog content
-- with no client write policy, and that stays true.
--
-- The pre-existing demo_video_url column stays for now (every row is NULL;
-- ExerciseDetailView's GSDemoView reads it) — dropping it is a separate
-- cleanup once the YouTube path fully replaces that surface.

ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS demo_youtube_id text
    CHECK (demo_youtube_id IS NULL OR demo_youtube_id ~ '^[A-Za-z0-9_-]{5,20}$');

COMMENT ON COLUMN public.exercises.demo_youtube_id IS
  'YouTube video ID (not URL) for the form demo, embedded via youtube-nocookie. Verified against oEmbed before insertion.';
