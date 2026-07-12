-- Task 2: personal_records — immutable log of PR-detection events.
-- Written client-side (best-effort) at the two priorMax detection sites
-- (WorkoutSessionView, GroupSessionLiveView). Backs the Home PR card,
-- Stats "Recent PRs" table, and solo recap PR card (later tasks).

CREATE TABLE public.personal_records (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  exercise_id    uuid NOT NULL REFERENCES public.exercises(id),
  weight         numeric(7,2) NOT NULL CHECK (weight >= 0),
  reps           integer NOT NULL CHECK (reps >= 0),
  previous_best  numeric(7,2) NOT NULL DEFAULT 0 CHECK (previous_best >= 0),
  session_id     uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  achieved_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX personal_records_user_achieved_idx
  ON public.personal_records(user_id, achieved_at DESC);

ALTER TABLE public.personal_records ENABLE ROW LEVEL SECURITY;

-- Records are immutable once written — no UPDATE/DELETE policies.
CREATE POLICY "users can select their own personal records"
  ON public.personal_records FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "users can insert their own personal records"
  ON public.personal_records FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
