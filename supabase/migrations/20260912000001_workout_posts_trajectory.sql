-- 20260912000001_workout_posts_trajectory.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §6.
-- Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S2.1.
--
-- The pump-check card becomes a TRAJECTORY SNAPSHOT (spec §1). Six additive,
-- nullable-or-defaulted columns; no existing column changes and no existing
-- row moves.
--
-- STILL NO UPDATE POLICY (20260731000001:71-72: "posts are immutable
-- snapshots"). Every column below is written once, at INSERT, by the
-- composer.
--
-- `is_late` IS NOT DROPPED. Spec §6: "is_late stays for old rows and is
-- derived for new ones". The derivation is `posted_at - completed_at`
-- (`PostLateness.isLate`, plan task S2.0) and it happens in the CLIENT at
-- insert, not in a generated column — converting a populated boolean column
-- into a generated one means dropping it, which would erase what every row
-- written before today says about itself.

ALTER TABLE public.workout_posts
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN retake_count int NOT NULL DEFAULT 0 CHECK (retake_count >= 0),
  -- The kind is CHECKED even though this release only ever writes two of the
  -- three. `milestone` is in the domain from day one so the milestone
  -- proposal can ship with the You hero's MilestoneCatalog without a second
  -- migration — a column's domain is cheap to widen and expensive to change
  -- under rows that already use it.
  ADD COLUMN highlight    jsonb CHECK (
    highlight IS NULL OR (
      jsonb_typeof(highlight) = 'object'
      AND highlight ->> 'kind' IN ('topSet', 'pr', 'milestone')
    )),
  ADD COLUMN trajectory   jsonb CHECK (trajectory IS NULL OR jsonb_typeof(trajectory) = 'object'),
  ADD COLUMN goal_id      uuid REFERENCES public.block_goals(id) ON DELETE SET NULL,
  ADD COLUMN week_start   date;

COMMENT ON COLUMN public.workout_posts.completed_at IS
  'The session''s completion, copied at post time. With created_at this is the precise lateness the card prints ("posted 47 min after") and the value is_late is derived from for new rows. NULL on rows written before 2026-09.';
COMMENT ON COLUMN public.workout_posts.retake_count IS
  'How many times the lifter re-shot before posting (spec 2). Shown on the card above zero.';
COMMENT ON COLUMN public.workout_posts.highlight IS
  'The one line the lifter picked from Coach''s proposals: {kind: "topSet"|"pr"|"milestone", text, weightLbs?, reps?}. CamelCase keys, canonical pounds; the feed renders the weight in the VIEWER''S unit (PostHighlight, HighlightText.line). This release proposes topSet and pr only - milestone is reserved for the You hero''s MilestoneCatalog and is already in the domain so no migration is needed when it ships.';
COMMENT ON COLUMN public.workout_posts.trajectory IS
  'Lines 2 and 3 of the card, RESOLVED at post time: {goalLine, weekNumber, weekCount, standing, chips[{name,done,target,fill?}]}. A snapshot rather than a join because block_goals and weekly_goals are own-rows RLS - a friend can never read the author''s goal - and because a ladder re-derives weekly while a post is a moment.';
COMMENT ON COLUMN public.workout_posts.goal_id IS
  'PROVENANCE: which block this post belonged to. NOT what the card renders (see trajectory). ON DELETE SET NULL - retiring a block must not delete the posts made during it.';
COMMENT ON COLUMN public.workout_posts.week_start IS
  'The rung''s week key (weekly_goals.week_start''s shape and rule: the DEVICE calendar''s week, computed by the client via WeekMath).';
