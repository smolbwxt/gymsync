CREATE TABLE public.gyms (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name           text NOT NULL,
  latitude       double precision NOT NULL,
  longitude      double precision NOT NULL,
  radius_meters  integer NOT NULL DEFAULT 200 CHECK (radius_meters > 0),
  is_primary     boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX gyms_user_id_idx ON public.gyms(user_id);

-- Enforce single primary per user
CREATE UNIQUE INDEX gyms_one_primary_per_user_idx
  ON public.gyms(user_id)
  WHERE is_primary = true;

ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select their own gyms"
  ON public.gyms FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "users can insert their own gyms"
  ON public.gyms FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users can update their own gyms"
  ON public.gyms FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users can delete their own gyms"
  ON public.gyms FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
