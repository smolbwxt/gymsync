-- Getting-started lift anchors (owner 2026-08-12): during onboarding the
-- lifter states confident 5-rep weights for the primary barbell compounds
-- (slugs: back-squat, bench-press, deadlift, ohp). These seed starting-
-- weight suggestions for those lifts AND ratio-derived auxiliaries until
-- real logged sets exist (WorkingWeight's `.seeded` rung fires only below
-- `.lastSet` — any real training outranks a seed).
--
-- Stored as jsonb {slug: pounds} — CANONICAL POUNDS like every stored
-- weight (Units.swift converts at display/parse edges only). NULL = never
-- captured (the step is skippable). Seeds are suggestions only: they never
-- enter set_logs, PR math, or volume.
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS lift_anchors jsonb;
