-- 20260726000006_user_settings_touch_updated_at.sql
--
-- Task 7 item 5 (pre-GA ledger bonus, docs/superpowers/specs/
-- 2026-07-18-reliability-debt-design.md §7; carried forward from Task 6's
-- own report: .superpowers/sdd/task-6-report.md:154 — "user_settings.
-- updated_at has the IDENTICAL never-bumps bug as item 8's
-- soundboard_favorites ... Flagged, not fixed — candidate for a follow-up
-- debt item").
--
-- user_settings.updated_at (20260717000001_user_settings.sql:17) has
-- `DEFAULT now()`, but a DEFAULT only fires on INSERT. The client write path
-- (`UserSettingsRepository.upsert()`, GymSyncApp/GymSync/Models/
-- UserSettings.swift:81-97) upserts a `UserSettingsUpsert` Row that encodes
-- only `{user_id, default_rest_seconds, palette}` — confirmed by reading the
-- struct (UserSettings.swift:41-51), it has no `updated_at` field at all —
-- so the `ON CONFLICT (user_id) DO UPDATE` path Supabase's `upsert()`
-- generates only ever touches `default_rest_seconds`/`palette`, never
-- `updated_at`. Every settings change (rest-timer duration, palette) after
-- the first ever save leaves `updated_at` frozen at row-creation time
-- forever — byte-for-byte the same bug class as soundboard_favorites, on a
-- different table.
--
-- Fixed at the DB level (trigger), not by adding the field to the client
-- struct, for the exact same reason `20260726000005_soundboard_favorites_
-- touch_updated_at.sql`'s own header gives (quoted there almost verbatim):
-- a client-side fix only protects THIS write path, and this table has
-- exactly one client write path today but that's not a property worth
-- depending on going forward. A BEFORE UPDATE trigger fixes this table for
-- every future write path, present and future, with no client coordination
-- required.
--
-- Lives in `private` (not `public`), same reasoning as the soundboard
-- trigger: avoids minting a needless PostgREST RPC endpoint for a function
-- nothing should ever call directly (20260722000001_is_blocked_private_
-- schema.sql's schema-purpose COMMENT).

-- clock_timestamp() (real wall-clock time), not now()/transaction_timestamp()
-- (frozen at transaction start) — same reasoning as the soundboard trigger's
-- own comment: a multi-statement transaction that both creates and later
-- updates a row in the same transaction would otherwise stamp both with the
-- identical time, which is also what makes `now()` unusable for the pgTAP
-- before/after proof below (the soundboard migration's own history: the
-- first live push used `now()`, the pgTAP proof caught the equal-not-greater
-- bug before commit, and it was corrected to `clock_timestamp()` —
-- `.superpowers/sdd/task-6-report.md:94` — applying that lesson directly
-- here instead of repeating the mistake).
CREATE OR REPLACE FUNCTION private.touch_user_settings_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_settings_touch_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_user_settings_updated_at();
