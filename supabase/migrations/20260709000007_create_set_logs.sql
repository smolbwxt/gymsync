CREATE TABLE public.set_logs (
  id          uuid PRIMARY KEY,  -- client-generated for idempotent retry
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id  uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES public.exercises(id),
  set_index   integer NOT NULL CHECK (set_index >= 1),
  reps        integer CHECK (reps IS NULL OR reps >= 0),
  weight      numeric(7,2) CHECK (weight IS NULL OR weight >= 0),
  rpe         numeric(3,1) CHECK (rpe IS NULL OR (rpe >= 1 AND rpe <= 10)),
  is_failed   boolean NOT NULL DEFAULT false,
  is_penalty  boolean NOT NULL DEFAULT false,
  note        text,
  logged_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX set_logs_user_exercise_time_idx
  ON public.set_logs(user_id, exercise_id, logged_at DESC);
CREATE INDEX set_logs_user_time_idx
  ON public.set_logs(user_id, logged_at DESC);
CREATE INDEX set_logs_session_idx
  ON public.set_logs(session_id, set_index);

ALTER TABLE public.set_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select their own set logs OR shared session logs"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_session_participant(set_logs.session_id, auth.uid())
  );

CREATE POLICY "users can insert their own set logs"
  ON public.set_logs FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users can update their own set logs"
  ON public.set_logs FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
