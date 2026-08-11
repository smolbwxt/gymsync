-- Personal weekly session goal (owner decision 2026-08-11): feeds the Home
-- streak widget's intraweek count + slot column — your sessions this week
-- against the goal you set. Client-writable on the own-row UPDATE policy
-- like display_name/show_solo_workouts.

ALTER TABLE public.profiles
  ADD COLUMN weekly_session_goal int NOT NULL DEFAULT 3
  CHECK (weekly_session_goal BETWEEN 1 AND 14);
