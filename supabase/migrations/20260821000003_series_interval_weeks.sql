-- 20260821000003_series_interval_weeks.sql
--
-- Every-other-week scheduling (field report #9). interval_weeks = 1 keeps
-- every existing series weekly; 2 = biweekly. anchor_date pins WHICH weeks
-- fire: occurrence expansion keeps weeks where the whole-week distance
-- from the anchor is divisible by the interval, so an edit-forward
-- mid-cycle can never flip the parity. Old rows have NULL anchor_date and
-- interval 1 - the expansion never consults the anchor at interval 1.
ALTER TABLE public.session_series
  ADD COLUMN IF NOT EXISTS interval_weeks int NOT NULL DEFAULT 1
    CHECK (interval_weeks BETWEEN 1 AND 4),
  ADD COLUMN IF NOT EXISTS anchor_date date;
