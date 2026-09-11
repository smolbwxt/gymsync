-- 20260907000001_block_goals.sql
--
-- Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md §8.
-- Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md, A1.
--
-- ONE PRIMARY GOAL PER BLOCK (owner decision 2) — enforced by
-- `unique (enrollment_id)`, not by client logic. A block that has no goal is a
-- block that predates this feature; a block with two is impossible.
--
-- `target` AND `block_goal_rungs.target` CARRY CAMELCASE KEYS, exactly as
-- `weekly_goals.params` does (`20260906000001_weekly_goals.sql:35-40`): the app
-- sets no `keyEncodingStrategy` anywhere, so `GoalTarget`'s synthesized encoder
-- writes its Swift property names, and those names ARE the wire contract.
--
-- RUNGS ARE PERSISTED, NOT ONLY COMPUTED (spec §8), for two reasons the design
-- states: a missed or overridden week must stay visible after re-laddering, and
-- the ledger has to be able to show the climb after the block is over.
-- Re-laddering rewrites only rows whose status is 'ahead' or 'current'.

CREATE TABLE public.block_goals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  enrollment_id uuid NOT NULL REFERENCES public.program_enrollments(id) ON DELETE CASCADE,
  metric        text NOT NULL,
  target        jsonb NOT NULL DEFAULT '{}'::jsonb,
  by_date       date,
  preset        text,
  source        text NOT NULL DEFAULT 'coach' CHECK (source IN ('coach','user')),
  outcome       text CHECK (outcome IN ('met','missed','partial')),
  outcome_value jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (enrollment_id)
);

-- NO CHECK ON `metric` OR `preset`, and that is deliberate rather than lax.
-- The registry is OPEN by owner decision 5: phases 2 and 3 add `zone2`,
-- `vo2_max`, `skill_reps` and `pattern_load_percent`, and a CHECK here would
-- make every one of those a migration on a table that did not otherwise change,
-- applied to the live project before the client that writes the value ships.
-- `GoalMetric(rawValue:)` is the gate on the read side — a row this build
-- cannot spell decodes to nil and the page renders empty, which is the same
-- forward-compatibility posture `WeeklyGoalRow.model` already takes
-- (`WeeklyGoalLiveRepository.swift:55-71`). `source` and `outcome` DO carry
-- CHECKs: those two vocabularies are closed by their own rulings.

ALTER TABLE public.block_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own block goal"
  ON public.block_goals FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "owner inserts own block goal"
  ON public.block_goals FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner updates own block goal"
  ON public.block_goals FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner deletes own block goal"
  ON public.block_goals FOR DELETE TO authenticated
  USING (user_id = auth.uid());

CREATE TABLE public.block_goal_rungs (
  goal_id     uuid NOT NULL REFERENCES public.block_goals(id) ON DELETE CASCADE,
  week_index  int  NOT NULL CHECK (week_index >= 0),
  week_start  date NOT NULL,
  target      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status      text NOT NULL DEFAULT 'ahead'
              CHECK (status IN ('ahead','current','met','missed','overridden')),
  derived_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (goal_id, week_index)
);

ALTER TABLE public.block_goal_rungs ENABLE ROW LEVEL SECURITY;

-- Rungs have no `user_id` of their own — they belong to a goal, and the goal
-- belongs to a user. Every policy therefore reaches through `block_goals`, and
-- that subquery is safe under INVOKER RLS here (unlike `friends_live`'s
-- sessions/participants cycle, `20260906000002_friends_live.sql:12-18`):
-- `block_goals`' own policies read only `auth.uid()` and never re-enter this
-- table, so there is no cycle to break and no reason for SECURITY DEFINER.
CREATE POLICY "owner reads own rungs"
  ON public.block_goal_rungs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner inserts own rungs"
  ON public.block_goal_rungs FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.block_goals g
                      WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner updates own rungs"
  ON public.block_goal_rungs FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.block_goals g
                      WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner deletes own rungs"
  ON public.block_goal_rungs FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()));

-- `updated_at` is `BlockGoal.updatedAt`, which the ladder page reads as "when
-- this milestone was last set". `DEFAULT now()` fires on INSERT only and the
-- client write path is an upsert whose row omits the column — the never-bumps
-- bug this repo has fixed three times now
-- (`20260726000005`, `20260726000006`, `20260906000001`).
--
-- clock_timestamp(), not now(): now() is frozen at transaction start, so a
-- transaction that creates and then updates the same row would stamp both
-- identically — which is also what lets A3's pgTAP compare GREATER rather than
-- equal. In `private`, not `public`, so it mints no PostgREST RPC endpoint
-- (`20260722000001_is_blocked_private_schema.sql`'s schema-purpose COMMENT).
CREATE OR REPLACE FUNCTION private.touch_block_goals_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER block_goals_touch_updated_at
  BEFORE UPDATE ON public.block_goals
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_block_goals_updated_at();
