-- Safety-class label corrections (20-athlete audit, owner 2026-08-20).
--
-- Complexity and joint labels are SAFETY labels: the cost of a wrongly-
-- easy complexity is a hurt novice, so the review bar is deliberately
-- lower than the 2-channel bar effectiveness scores required — these are
-- judged corrections from the audit's read, not statistical consensus.

-- The Pendlay finding: a dead-stop row demanding a rigid horizontal
-- torso every rep was labeled complexity 3 — identical to a basic
-- barbell row — and the novice gate waved it through to a day-one
-- 50-year-old (the axial boost then promoted it as the most spinally
-- loaded row in the catalog).
UPDATE public.exercises SET complexity = 4 WHERE name = 'Pendlay Row';

-- A machine-assisted pistol is easier than a free one, but complexity 1
-- put a single-leg squat below a leg press.
UPDATE public.exercises SET complexity = 3
WHERE name = 'Smith Machine Pistol Squat';

-- Mislabel: a hip raise is a glute bridge, not core — it was winning the
-- ab-slot pick in six of twenty audited programs.
UPDATE public.exercises SET primary_muscle = 'glutes'
WHERE name = 'Smith Machine Hip Raise' AND primary_muscle != 'glutes';
