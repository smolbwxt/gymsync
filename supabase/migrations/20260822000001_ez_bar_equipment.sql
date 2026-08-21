-- 20260822000001_ez_bar_equipment.sql
--
-- Equipment subclass unlock (docket): the app has keyed bar weight on
-- equipment = 'ez-bar' since 20260821000002 (per-user ez_bar_weight_lbs),
-- but the seven EZ-bar catalog rows still said 'barbell', so every one
-- of them loaded the straight bar's 45 lb. The held catalog corrections
-- land now. Name-matched exactly; no CHECK constraint exists on the
-- equipment column.
UPDATE public.exercises SET equipment = 'ez-bar'
WHERE name IN (
  'Close-Grip EZ Bar Curl',
  'Close-Grip EZ-Bar Curl with Band',
  'Close-Grip EZ-Bar Press',
  'Decline EZ Bar Triceps Extension',
  'EZ-Bar Curl',
  'EZ-Bar Preacher Curl',
  'EZ-Bar Skullcrusher'
);
