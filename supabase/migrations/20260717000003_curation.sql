-- 20260717000003_curation.sql
-- Curation phase: catalog metadata, per-user soundboard favorites,
-- curator-gated routine publishing.

-- ── 1. Catalog metadata (designer frames use emoji icons + 3 categories) ──
ALTER TABLE public.soundboard_sounds
  ADD COLUMN icon text,
  ADD COLUMN category text CHECK (category IN ('hype','funny','fx'));

UPDATE public.soundboard_sounds SET icon = '📯', category = 'hype'  WHERE slug = 'airhorn';
UPDATE public.soundboard_sounds SET icon = '🔥', category = 'hype'  WHERE slug = 'lets-go';
UPDATE public.soundboard_sounds SET icon = '🔔', category = 'fx'    WHERE slug = 'ding';
UPDATE public.soundboard_sounds SET icon = '📣', category = 'funny' WHERE slug = 'boo';

-- ── 2. Per-user favorites — DELIBERATELY its own table, not a user_settings
--       column: user_settings is written via full-row upserts from multiple
--       cached views (see the Canvas-Completion B1 fix); a favorites column
--       there would be clobbered by every rest-timer/palette save. ──
CREATE TABLE public.soundboard_favorites (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  slugs      text[] NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.soundboard_favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own soundboard favorites"
  ON public.soundboard_favorites FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "users insert own soundboard favorites"
  ON public.soundboard_favorites FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "users update own soundboard favorites"
  ON public.soundboard_favorites FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ── 3. Curator flag — readable by all (profiles SELECT already public to
--       authenticated), writable by NOBODY client-side (column privilege
--       revoked; service role/superuser only). ──
ALTER TABLE public.profiles
  ADD COLUMN is_curator boolean NOT NULL DEFAULT false;
REVOKE UPDATE (is_curator) ON public.profiles FROM authenticated, anon;

-- NOTE: the column-level REVOKE above is intent documentation only — it is
-- NOT sufficient in this project (authenticated/anon hold table-wide UPDATE;
-- Postgres ORs table- and column-level ACLs, so the REVOKE is a no-op).
-- The real enforcement is the guard trigger in 20260717000004 — kept as a
-- separate migration so this file matches exactly what was applied under
-- this version (append-only provenance).

-- ── 4. Curator-gated publishing: replace routines INSERT/UPDATE policies so
--       visibility='public' requires is_curator. 'private'/'shared' behavior
--       unchanged. ──
DROP POLICY "users can insert their own routines" ON public.routines;
CREATE POLICY "users can insert their own routines"
  ON public.routines FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = owner_id
    AND (visibility <> 'public'
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );

DROP POLICY "users can update their own routines" ON public.routines;
CREATE POLICY "users can update their own routines"
  ON public.routines FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id)
  WITH CHECK (
    auth.uid() = owner_id
    AND (visibility <> 'public'
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );
