-- 20260907000002_weekly_goals_block_link.sql
--
-- Spec §4: the shipped weekly goal BECOMES the materialised current rung.
-- Two additive columns so a row knows the ladder it belongs to, and four
-- additive `kind` values so a rung of any phase-1 metric has a row shape.
--
-- ADDITIVE IN BOTH DIRECTIONS. `goal_id` is nullable with ON DELETE SET NULL:
-- "a row with goal_id = null is a standalone weekly goal exactly as today"
-- (spec §4), and deleting a block must not delete the weeks it happened to
-- describe — the athlete trained those weeks.

ALTER TABLE public.weekly_goals
  ADD COLUMN goal_id    uuid REFERENCES public.block_goals(id) ON DELETE SET NULL,
  ADD COLUMN rung_index int CHECK (rung_index IS NULL OR rung_index >= 0);

-- The CHECK is REPLACED rather than added to: a column may carry only one
-- constraint of this name, and Postgres has no "extend a CHECK". The five
-- shipped values are repeated verbatim so the diff shows exactly four
-- additions and no removals.
--
-- The constraint's real name on the live project was CONFIRMED before this
-- migration was written, exactly as the plan's step 2 requires
-- (`SELECT conname FROM pg_constraint WHERE conrelid = 'public.weekly_goals'
-- ::regclass AND contype = 'c'`): `weekly_goals_kind_check`, Postgres's own
-- default for the inline CHECK in `20260906000001`. A DROP CONSTRAINT on a
-- name that does not exist would fail the whole migration.
ALTER TABLE public.weekly_goals DROP CONSTRAINT weekly_goals_kind_check;
ALTER TABLE public.weekly_goals ADD CONSTRAINT weekly_goals_kind_check
  CHECK (kind IN ('muscle_sets','distance','sessions_of_type','days','lift',
                  'recovery','body_weight','volume','benchmark'));

-- `goal_id` is written in BOTH the column and `params.goalID`, and that is not
-- an accident: the COLUMN is what the foreign key and the ON DELETE SET NULL
-- need, and the PARAM is what survives into `WeeklyGoal` — a struct that is
-- deliberately not Codable and has no field per column
-- (`WeeklyGoalLiveRepository.swift:9-13`). One value, written twice by one
-- function (`LiveWeeklyGoalRepository`'s row DTO, task A11); pgTAP asserts they
-- agree (task A4).
COMMENT ON COLUMN public.weekly_goals.goal_id IS
  'The block_goals row whose ladder materialised this week. NULL = a standalone weekly goal. Mirrored into params.goalID for the client model.';
COMMENT ON COLUMN public.weekly_goals.rung_index IS
  '0-based week index within that ladder, matching block_goal_rungs.week_index.';
