-- ============================================================
-- Lifting quality: unit system + barbell/plate inventory.
-- ============================================================
-- Design: docs/superpowers/specs/2026-07-26-lifting-quality-design.md
--
-- THE LOAD-BEARING DECISION, restated here because every future query
-- depends on it: stored weights stay in POUNDS, everywhere, forever.
-- `set_logs.weight`, `personal_records.weight`, `body_weight_logs.weight`
-- and program baselines are all canonical lbs. `unit_system` is a DISPLAY
-- and ENTRY preference only — converted at the UI edge, never in the
-- database.
--
-- That is what makes this safe to ship: there is no data migration, so
-- there is no window in which some rows are kg and some are lbs, and no
-- possibility of a partially-converted dataset. Aggregates
-- (venue_month_leaderboard, group_stats, campaign volume) keep summing a
-- single unit and need no changes at all.

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS unit_system text NOT NULL DEFAULT 'lbs'
    CHECK (unit_system IN ('lbs', 'kg')),

  -- Bar weight is stored in LBS like every other weight (see above), even
  -- when the user works in kg — the UI converts for display. Range covers
  -- a 15 kg trainer (33 lb) through a 55 lb safety-squat bar; anything
  -- outside that is a typo, not a bar.
  ADD COLUMN IF NOT EXISTS bar_weight_lbs numeric(5,2) NOT NULL DEFAULT 45
    CHECK (bar_weight_lbs BETWEEN 15 AND 100),

  -- The denominations this user's gym actually has, as a JSON array of
  -- numbers in the user's OWN unit (e.g. [45,35,25,10,5,2.5] lbs or
  -- [25,20,15,10,5,2.5,1.25] kg). NULL means "the standard set for my
  -- unit" — a null here is meaningfully different from an empty array
  -- ("I have no plates"), so the column stays nullable rather than
  -- defaulting to a guess.
  ADD COLUMN IF NOT EXISTS plate_inventory jsonb;

COMMENT ON COLUMN public.user_settings.unit_system IS
  'Display/entry unit only. All stored weights are canonical POUNDS.';
COMMENT ON COLUMN public.user_settings.bar_weight_lbs IS
  'Always lbs regardless of unit_system, like every other stored weight.';
COMMENT ON COLUMN public.user_settings.plate_inventory IS
  'Plate denominations in the user''s own unit. NULL = standard set for that unit.';
