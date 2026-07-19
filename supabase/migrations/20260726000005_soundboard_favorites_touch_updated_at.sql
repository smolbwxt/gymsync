-- 20260726000005_soundboard_favorites_touch_updated_at.sql
--
-- Task 6 item 8 (reliability/debt roll-up, docs/superpowers/specs/
-- 2026-07-18-reliability-debt-design.md §6; ledger origin:
-- .superpowers/sdd/progress.md:344 "favorites updated_at never bumps").
--
-- soundboard_favorites.updated_at (20260717000003_curation.sql:22) has
-- `DEFAULT now()`, but a DEFAULT only fires on INSERT. The client write
-- path (SoundboardFavoritesRepository.set(), GymSyncApp/GymSync/Models/
-- Soundboard.swift) upserts a Row that encodes only {user_id, slugs} —
-- confirmed by reading the Codable struct, it has no updated_at field at
-- all — so the ON CONFLICT (user_id) DO UPDATE path Supabase's upsert()
-- generates only ever touches `slugs`, never `updated_at`. Every favorites
-- change after the first ever save leaves `updated_at` frozen at row-
-- creation time forever.
--
-- Fixed at the DB level (trigger), not by adding the field to the client
-- struct: a client-side fix only protects THIS write path — the same class
-- of bug already exists identically on user_settings.updated_at
-- (UserSettingsUpsert, UserSettings.swift, out of this item's scope but
-- confirmed by reading it) precisely because "remember to set updated_at
-- on every call site" doesn't hold up. A BEFORE UPDATE trigger fixes this
-- table for every future write path, present and future, with no client
-- coordination required — same reasoning `private` schema helpers exist
-- for RLS (this repo already prefers "enforce it in the DB, once" over
-- "trust every call site").
--
-- Lives in `private` (not `public`) purely to avoid minting a needless
-- PostgREST RPC endpoint for a function nothing should ever call directly
-- (see 20260722000001_is_blocked_private_schema.sql's schema-purpose
-- COMMENT — this isn't an RLS helper, but the same "don't expose what
-- doesn't need exposing" reasoning applies to any function landing in a
-- schema PostgREST introspects).

-- clock_timestamp() (real wall-clock time), not now()/transaction_timestamp()
-- (frozen at transaction start) — a multi-statement transaction that both
-- creates and later updates a row in the same transaction would otherwise
-- stamp both with the identical time, which is also what makes `now()`
-- unusable for the pgTAP before/after proof below.
CREATE OR REPLACE FUNCTION private.touch_soundboard_favorites_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER soundboard_favorites_touch_updated_at
  BEFORE UPDATE ON public.soundboard_favorites
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_soundboard_favorites_updated_at();
