-- 20260728000008_open_publishing_and_stars.sql
-- Redesign round (2026-07-24, user decision): publishing opens to EVERYONE;
-- the FEATURED spotlight becomes the curator-managed thing; popularity gets
-- an organic signal via GitHub-style stars.
--
-- Before: routines INSERT/UPDATE WITH CHECK gated `visibility='public'` on
-- profiles.is_curator — only curators could publish at all. After: any owner
-- may publish public (searchable in Discover); only curators may set
-- is_featured=true (the Library spotlight shelf). Append-only.

-- 1. Re-gate publishing: public for everyone, FEATURED for curators.
DROP POLICY IF EXISTS "users can insert their own routines" ON public.routines;
CREATE POLICY "users can insert their own routines" ON public.routines
  FOR INSERT
  WITH CHECK (
    auth.uid() = owner_id
    AND (NOT coalesce(is_featured, false)
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "users can update their own routines" ON public.routines;
CREATE POLICY "users can update their own routines" ON public.routines
  FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (
    auth.uid() = owner_id
    AND (NOT coalesce(is_featured, false)
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );

-- 2. Stars — one row per (routine, user); counts are the popularity signal.
CREATE TABLE IF NOT EXISTS public.routine_stars (
  routine_id uuid NOT NULL REFERENCES public.routines(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (routine_id, user_id)
);
CREATE INDEX IF NOT EXISTS routine_stars_routine_idx ON public.routine_stars (routine_id);

ALTER TABLE public.routine_stars ENABLE ROW LEVEL SECURITY;

-- Counts are public data (like profiles' public fields): any authenticated
-- user can read who-starred-what for public routines they can see anyway.
CREATE POLICY "stars are readable" ON public.routine_stars
  FOR SELECT USING (auth.role() = 'authenticated');

-- Star as yourself, and only PUBLIC routines (starring someone's private
-- routine would leak its existence).
CREATE POLICY "star public routines as self" ON public.routine_stars
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.routines r
                WHERE r.id = routine_id AND r.visibility = 'public')
  );

CREATE POLICY "unstar own" ON public.routine_stars
  FOR DELETE USING (auth.uid() = user_id);
