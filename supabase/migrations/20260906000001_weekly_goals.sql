-- 20260906000001_weekly_goals.sql
--
-- Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
-- -goal-design.md §B ("The weekly goal"). Plan:
-- docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, Stream A
-- task A1.
--
-- One goal per user per week. The week is the DEVICE calendar's week, not
-- ISO — `WeekMath` (GymSyncApp/GymSync/Models/WeeklyGoal.swift:86) records
-- why, and it is the client that computes `week_start`, so this column only
-- ever receives a `yyyy-MM-dd` string the client already agreed on with the
-- streak tile. The column is `date` so the PK dedupes a week regardless of
-- how the string was spelled.
--
-- THE OWNER RULING THIS TABLE ENCODES ("propose only", design §B owner
-- answer 3): Coach may write a row whose `source = 'coach'` freely, and may
-- NEVER overwrite one whose `source = 'user'`. That rule is enforced on the
-- WRITE PATH (task A11's `WeeklyGoalWriteRule.shouldOverwrite`), not in a
-- trigger, for one reason: Coach does not have a server identity here. Every
-- Coach write in this app runs through the app's own Supabase client on the
-- user's own JWT (`WeekBooker`, `ProgramBuilder`), so a trigger could not
-- tell a Coach-originated UPDATE from a user-originated one — both arrive as
-- `auth.uid()`. The distinction lives in the `source` column and in the code
-- that consults it before writing. When Coach wants to change a `user` row it
-- PROPOSES: a line in the existing coach-line/debrief path, never a write.
--
-- No `set_at` column: `WeeklyGoal.setAt` maps to `updated_at` (see the
-- trigger at the foot of this file), which is what "when this goal was last
-- set" actually means for a row that gets re-saved when the user edits it.

CREATE TABLE public.weekly_goals (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  week_start date NOT NULL,
  kind       text NOT NULL CHECK (kind IN ('muscle_sets','distance','sessions_of_type','days','lift')),
  -- The per-kind payload. Keys are the Swift property names of
  -- `WeeklyGoalParams` in camelCase (`muscleTargets`, `targetSource`,
  -- `distanceTarget`, `sessionType`, `exerciseID`, `targetWeightLbs`,
  -- `byDate`) — the app sets no `keyEncodingStrategy` anywhere, so the
  -- synthesized encoder's names are the wire names. Absent, not null, for
  -- the fields a kind does not use.
  params     jsonb NOT NULL DEFAULT '{}'::jsonb,
  source     text NOT NULL DEFAULT 'coach' CHECK (source IN ('coach','user')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_start)
);

ALTER TABLE public.weekly_goals ENABLE ROW LEVEL SECURITY;

-- Own rows, all four verbs. Written as four named policies rather than one
-- FOR ALL, following `20260710000001_create_friendships.sql`'s shape, so a
-- future change to one verb (say, a service role that may insert coach rows)
-- is a one-policy edit and reads as such in the diff.
CREATE POLICY "owner reads own weekly goal"
  ON public.weekly_goals FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "owner inserts own weekly goal"
  ON public.weekly_goals FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "owner updates own weekly goal"
  ON public.weekly_goals FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "owner deletes own weekly goal"
  ON public.weekly_goals FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- `updated_at` is `WeeklyGoal.setAt`, so it has to be true after an edit and
-- not only after a create. `DEFAULT now()` fires on INSERT only, and the
-- client write path is an upsert whose Row does not carry the column — the
-- identical never-bumps bug this repo has already fixed twice
-- (`20260726000005_soundboard_favorites_touch_updated_at.sql`,
-- `20260726000006_user_settings_touch_updated_at.sql`). Fixing it here at
-- the table rather than in the client, for the reason those two headers
-- give: a client-side fix protects only today's single write path.
--
-- clock_timestamp(), not now()/transaction_timestamp() (frozen at
-- transaction start) — the lesson `20260726000006`'s header records: a
-- transaction that creates and then updates the same row would otherwise
-- stamp both identically, which is also what makes the before/after pgTAP
-- proof in `supabase/tests/weekly_goals_test.sql` compare greater rather
-- than equal.
--
-- In `private`, not `public`, so it does not mint a PostgREST RPC endpoint
-- for a function nothing should call directly
-- (`20260722000001_is_blocked_private_schema.sql`'s schema-purpose COMMENT).
CREATE OR REPLACE FUNCTION private.touch_weekly_goals_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER weekly_goals_touch_updated_at
  BEFORE UPDATE ON public.weekly_goals
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_weekly_goals_updated_at();
