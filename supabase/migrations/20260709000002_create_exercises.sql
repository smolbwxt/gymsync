CREATE TABLE public.exercises (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL,
  slug              text UNIQUE NOT NULL,
  category          text NOT NULL CHECK (category IN ('compound','isolation','cardio','mobility')),
  primary_muscle    text NOT NULL,
  secondary_muscles text[] NOT NULL DEFAULT '{}',
  equipment         text NOT NULL,
  default_unit      text NOT NULL DEFAULT 'lbs',
  demo_video_url    text,
  is_user_defined   boolean NOT NULL DEFAULT false
);

CREATE INDEX exercises_slug_idx ON public.exercises(slug);
CREATE INDEX exercises_primary_muscle_idx ON public.exercises(primary_muscle);

ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercises are globally readable"
  ON public.exercises FOR SELECT
  TO authenticated
  USING (true);

-- No INSERT/UPDATE/DELETE policies — writes only via service_role (seed migrations).
