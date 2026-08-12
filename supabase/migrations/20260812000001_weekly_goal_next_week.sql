-- Weekly-goal anti-goalpost rule (owner 2026-08-12): editing the weekly
-- days goal must only affect NEXT week — "don't want people moving the
-- goal posts in order not to lose their streak."
--
-- Mechanism (no rollover job needed): `weekly_session_goal` stays the
-- STANDING goal (what the user last set — the goal from next week on).
-- On the FIRST edit within a calendar week the client snapshots the
-- in-effect goal into `_prev` and stamps `_changed_at`; later edits in the
-- same week keep the original snapshot. Readers compute the week's
-- effective goal as: `_changed_at` within the current week -> `_prev`,
-- otherwise -> `weekly_session_goal`. Once the week rolls over the stamp
-- falls out of "current week" and the standing goal takes effect with no
-- write ever needed.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS weekly_session_goal_prev int,
  ADD COLUMN IF NOT EXISTS weekly_session_goal_changed_at timestamptz;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_weekly_session_goal_prev_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_weekly_session_goal_prev_check
  CHECK (weekly_session_goal_prev IS NULL
         OR weekly_session_goal_prev BETWEEN 1 AND 14);
