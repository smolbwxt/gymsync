CREATE TABLE public.routines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name              text NOT NULL,
  description       text,
  visibility        text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','shared','public')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX routines_owner_id_idx ON public.routines(owner_id);

CREATE TABLE public.routine_exercises (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id     uuid NOT NULL REFERENCES public.routines(id) ON DELETE CASCADE,
  exercise_id    uuid NOT NULL REFERENCES public.exercises(id),
  position       integer NOT NULL CHECK (position >= 1),
  target_sets    integer CHECK (target_sets >= 1),
  target_reps    text,
  target_weight  text,
  rest_seconds   integer CHECK (rest_seconds >= 0),
  notes          text,
  UNIQUE (routine_id, position)
);

CREATE INDEX routine_exercises_routine_id_idx ON public.routine_exercises(routine_id);

ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select routines they own OR public routines"
  ON public.routines FOR SELECT TO authenticated
  USING (auth.uid() = owner_id OR visibility = 'public');

CREATE POLICY "users can insert their own routines"
  ON public.routines FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "users can update their own routines"
  ON public.routines FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "users can delete their own routines"
  ON public.routines FOR DELETE TO authenticated
  USING (auth.uid() = owner_id);

-- routine_exercises inherit parent visibility
CREATE POLICY "routine_exercises follow parent routine visibility"
  ON public.routine_exercises FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id
      AND (r.owner_id = auth.uid() OR r.visibility = 'public')
  ));

CREATE POLICY "routine_exercises writable by parent owner"
  ON public.routine_exercises FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id AND r.owner_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id AND r.owner_id = auth.uid()
  ));
