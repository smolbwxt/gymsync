CREATE TABLE public.profiles (
  id                     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username               text UNIQUE NOT NULL CHECK (length(username) >= 3),
  display_name           text,
  avatar_url             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  show_solo_workouts     boolean NOT NULL DEFAULT false,
  lifetime_volume_lifted numeric(14,2) NOT NULL DEFAULT 0
);

CREATE INDEX profiles_username_lower_idx ON public.profiles (lower(username));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles are readable by any authenticated user"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
