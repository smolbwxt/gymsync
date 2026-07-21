-- 20260728000007_user_settings_accent_and_onyx.sql
-- Redesign foundation: add a user-selectable accent, add the Onyx palette as
-- the new default look, and migrate existing rows onto it. Append-only.
-- Dated after the latest applied migration (20260728000006) so it applies in
-- order — today's calendar date (2026-07-20) is behind the repo's migration
-- timestamps, so a today-dated file would be rejected as out-of-order.

-- 1. Accent column. Free-form text: a preset id ('sky'|'violet'|'amber'|'lime'
--    |'coral'|'rose'|'mono') OR a custom '#rrggbb' hex. No CHECK — the client
--    (GSAccents.accent(for:)) is total and falls back to sky for anything it
--    doesn't recognise, so an odd value degrades to the default, never errors.
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS accent text NOT NULL DEFAULT 'sky';

-- 2. Allow 'onyx' in the palette CHECK. The original constraint
--    (20260717000001_user_settings.sql) restricts palette to the four canvas
--    palettes; drop and re-add including onyx. MUST run before the UPDATE below,
--    or setting palette='onyx' would violate the old constraint.
ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS user_settings_palette_check;
ALTER TABLE public.user_settings
  ADD CONSTRAINT user_settings_palette_check
  CHECK (palette IN ('onyx','midnight','arena','ink','modernist'));

-- 3. Onyx is the new default, and the redesign replaces the old look for
--    everyone (pre-GA, no real users to disrupt), so migrate existing rows.
ALTER TABLE public.user_settings ALTER COLUMN palette SET DEFAULT 'onyx';
UPDATE public.user_settings SET palette = 'onyx' WHERE palette <> 'onyx';
