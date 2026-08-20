-- TrainingProfile storage (Phase 2, owner arc 2026-08-20).
--
-- One row per athlete: the profile IS the truth the generator reads
-- (personality = prior, conversation = delta, generator = the only thing
-- that prescribes). The payload is jsonb because the schema's field set
-- is versioned in code (TrainingProfile.swift, Codable) and evolves with
-- generator capability; `version` lets a future migration rewrite old
-- payloads knowingly rather than guessing.
--
-- Visible and editable by its owner — a black-box profile is worse than
-- a dial (design spec 2026-08-20 section 2).

CREATE TABLE IF NOT EXISTS public.training_profiles (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  payload    jsonb NOT NULL DEFAULT '{}'::jsonb,
  version    integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.training_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own profile read"
  ON public.training_profiles FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "own profile insert"
  ON public.training_profiles FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "own profile update"
  ON public.training_profiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
