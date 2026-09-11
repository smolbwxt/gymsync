BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(20);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- bg1 alice = owner
-- bg2 erin  = outsider — never touches alice's rows, used for the RLS denials
--
-- Shape copied from `weekly_goals_test.sql` exactly: two fixture auth.users +
-- profiles inside the rolled-back txn, `SET LOCAL role authenticated` plus
-- `SET LOCAL request.jwt.claim.sub`, `ROLLBACK` at the foot.
--
-- THREE ENROLLMENTS FOR ALICE, and the two extra ones are not padding.
-- `UNIQUE (enrollment_id)` means one goal per block, so a test that needs a
-- goal it is about to DESTROY (assertions 13 and 14) cannot borrow the one the
-- RLS block still needs. `one_active_program_per_user` is a PARTIAL unique
-- index (`WHERE ended_at IS NULL`), so the two extras are ended blocks — which
-- is also the honest fixture: a finished block still owns its goal.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000e9101', 'bg1@t.com'),
  ('00000000-0000-0000-0000-0000000e9102', 'bg2@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000e9101', 'bg_alice'),
  ('00000000-0000-0000-0000-0000000e9102', 'bg_erin');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e9101';

INSERT INTO program_enrollments
  (id, user_id, template_slug, focus, baseline, started_on, weeks)
VALUES
  ('00000000-0000-0000-0000-0000000e9201', '00000000-0000-0000-0000-0000000e9101',
   'march-to-1rm', '{}'::jsonb, '{}'::jsonb, '2099-01-04', 8);

INSERT INTO program_enrollments
  (id, user_id, template_slug, focus, baseline, started_on, weeks,
   ended_at, ended_reason)
VALUES
  ('00000000-0000-0000-0000-0000000e9202', '00000000-0000-0000-0000-0000000e9101',
   'leg-strength-block', '{}'::jsonb, '{}'::jsonb, '2099-02-01', 6,
   '2099-03-15T00:00:00Z', 'completed'),
  ('00000000-0000-0000-0000-0000000e9203', '00000000-0000-0000-0000-0000000e9101',
   'hypertrophy-block', '{}'::jsonb, '{}'::jsonb, '2099-04-05', 6,
   '2099-05-17T00:00:00Z', 'completed');


-- ============================================================
-- Owner: insert, defaults, the uniqueness ruling, the two CHECKs
-- ============================================================

-- ── 1. Owner inserts a goal for their own block, omitting every defaulted
--      column (source / target / outcome / created_at / updated_at) ──────────
SELECT lives_ok(
  $$INSERT INTO block_goals (id, user_id, enrollment_id, metric, by_date, preset)
    VALUES ('00000000-0000-0000-0000-0000000e9301',
            '00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9201',
            'lift_one_rep_max', '2099-03-01', 'strength')$$,
  'owner can insert a block goal for their own enrollment'
);

-- ── 2. Column defaults apply when omitted ────────────────────────────────────
--      `source` defaulting to 'coach' is the same resting state
--      `weekly_goals` takes: a goal nobody claimed is Coach's, and only an
--      explicit 'user' write makes it the athlete's. `outcome` is NULL until
--      phase 3 fills it.
SELECT results_eq(
  $$SELECT source, target, outcome IS NULL FROM block_goals
    WHERE id = '00000000-0000-0000-0000-0000000e9301'$$,
  $$VALUES ('coach'::text, '{}'::jsonb, true)$$,
  'source, target and outcome fall back to their column defaults when omitted'
);

-- ── 3. UNIQUE (enrollment_id): ONE PRIMARY GOAL PER BLOCK ────────────────────
--      THIS ASSERTION IS OWNER DECISION 2 IN THE DATABASE. A block with two
--      goals is impossible rather than merely discouraged, which is why no
--      client-side guard is needed and none exists.
SELECT throws_ok(
  $$INSERT INTO block_goals (user_id, enrollment_id, metric)
    VALUES ('00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9201', 'weekly_muscle_sets')$$,
  '23505', NULL,
  'a second goal for the same enrollment violates UNIQUE (enrollment_id)'
);

-- ── 4. source is exactly {coach, user} ───────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO block_goals (user_id, enrollment_id, metric, source)
    VALUES ('00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9202', 'body_weight', 'trainer')$$,
  '23514', NULL,
  'a source outside (coach, user) violates the CHECK constraint'
);

-- ── 5. outcome is exactly {met, missed, partial} ─────────────────────────────
SELECT throws_ok(
  $$INSERT INTO block_goals (user_id, enrollment_id, metric, outcome)
    VALUES ('00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9202', 'body_weight', 'quit')$$,
  '23514', NULL,
  'an outcome outside (met, missed, partial) violates the CHECK constraint'
);

-- ── 6. A metric this build has never heard of is ACCEPTED ────────────────────
--      THE OPEN REGISTRY, ASSERTED. Owner decision 5: phases 2 and 3 add
--      `zone2`, `vo2_max`, `skill_reps` and `pattern_load_percent`, and a CHECK
--      on `metric` would make each of those a migration on a table that did not
--      otherwise change. `GoalMetric(rawValue:)` is the gate on the read side.
--      This assertion exists so a future CHECK cannot be added without failing.
SELECT lives_ok(
  $$INSERT INTO block_goals (id, user_id, enrollment_id, metric, target)
    VALUES ('00000000-0000-0000-0000-0000000e9302',
            '00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9202',
            'zone2_minutes_per_week', '{"targetWeightLbs":225}'::jsonb)$$,
  'a metric string this build has never heard of is accepted — the registry is open'
);

-- ── 7. target keys survive the round trip in CAMELCASE ───────────────────────
--      The same contract `weekly_goals.params` states: the app sets no
--      keyEncodingStrategy anywhere, so `GoalTarget`'s synthesized encoder
--      writes its Swift property names and those names ARE the wire format.
--      Asserted against the jsonb directly, so a future keyEncodingStrategy
--      breaks this test before it breaks an athlete's ladder.
SELECT results_eq(
  $$SELECT target->>'targetWeightLbs' FROM block_goals
    WHERE id = '00000000-0000-0000-0000-0000000e9302'$$,
  $$VALUES ('225'::text)$$,
  'target keeps its camelCase key through the round trip'
);

-- ── 8. updated_at is BlockGoal.updatedAt, so an UPDATE must bump it ──────────
--      `DEFAULT now()` fires on INSERT only and the client write path is an
--      upsert whose row omits the column — the never-bumps bug this repo has
--      fixed three times (20260726000005, 20260726000006, 20260906000001).
--
--      GREATER, not greater-or-equal, and clock_timestamp() is why: now() is
--      frozen at this whole test's transaction start, so a now()-based trigger
--      would stamp the INSERT and this UPDATE identically and the assertion
--      could not tell a working trigger from a missing one.
--
--      The writable CTE must be top-level, not nested inside ok()'s argument
--      list (Postgres: "WITH clause containing a data-modifying statement must
--      be at the top level"), so this whole statement IS the WITH.
WITH before_val AS (
  SELECT updated_at FROM block_goals
  WHERE id = '00000000-0000-0000-0000-0000000e9301'
), after_update AS (
  UPDATE block_goals SET source = 'user'
  WHERE id = '00000000-0000-0000-0000-0000000e9301'
  RETURNING updated_at
)
SELECT ok(
  after_update.updated_at > before_val.updated_at,
  'UPDATE bumps updated_at past its pre-update value (updatedAt is honest after an edit)')
FROM before_val, after_update;


-- ============================================================
-- Rungs: the ladder's persisted weeks
-- ============================================================

-- ── 9. Rungs insert against an owned goal ────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO block_goal_rungs (goal_id, week_index, week_start, target, status)
    VALUES ('00000000-0000-0000-0000-0000000e9301', 0, '2099-01-04',
            '{"targetWeightLbs":190}'::jsonb, 'met'),
           ('00000000-0000-0000-0000-0000000e9301', 1, '2099-01-11',
            '{"targetWeightLbs":195}'::jsonb, 'current')$$,
  'owner can insert rungs against their own goal'
);

-- ── 10. PRIMARY KEY (goal_id, week_index): one rung per week ─────────────────
--       This is what makes re-laddering an upsert on (goal_id, week_index)
--       rather than an insert, and what stops a second derivation from
--       producing a duplicate week.
SELECT throws_ok(
  $$INSERT INTO block_goal_rungs (goal_id, week_index, week_start)
    VALUES ('00000000-0000-0000-0000-0000000e9301', 0, '2099-01-04')$$,
  '23505', NULL,
  'a second rung for the same (goal_id, week_index) violates the primary key'
);

-- ── 11. week_index is 0-based and never negative ─────────────────────────────
SELECT throws_ok(
  $$INSERT INTO block_goal_rungs (goal_id, week_index, week_start)
    VALUES ('00000000-0000-0000-0000-0000000e9301', -1, '2099-01-04')$$,
  '23514', NULL,
  'a negative week_index violates the CHECK constraint'
);

-- ── 12. status is exactly the five RungStatus values ─────────────────────────
--       These five strings ARE `RungStatus`'s raw values (Models/Ladder.swift).
--       If this CHECK and that enum ever drift, this goes red before an athlete
--       meets a decode failure.
SELECT throws_ok(
  $$INSERT INTO block_goal_rungs (goal_id, week_index, week_start, status)
    VALUES ('00000000-0000-0000-0000-0000000e9301', 2, '2099-01-18', 'paused')$$,
  '23514', NULL,
  'a status outside the five violates the CHECK constraint'
);

-- ── 13. Deleting the goal cascades its rungs ─────────────────────────────────
--       On its OWN goal (the third, ended block) rather than on the one the RLS
--       block below still needs — see the fixture comment.
INSERT INTO block_goals (id, user_id, enrollment_id, metric)
VALUES ('00000000-0000-0000-0000-0000000e9303',
        '00000000-0000-0000-0000-0000000e9101',
        '00000000-0000-0000-0000-0000000e9203', 'cumulative_volume');
INSERT INTO block_goal_rungs (goal_id, week_index, week_start)
VALUES ('00000000-0000-0000-0000-0000000e9303', 0, '2099-04-05'),
       ('00000000-0000-0000-0000-0000000e9303', 1, '2099-04-12');
DELETE FROM block_goals WHERE id = '00000000-0000-0000-0000-0000000e9303';

SELECT results_eq(
  $$SELECT count(*)::int FROM block_goal_rungs
    WHERE goal_id = '00000000-0000-0000-0000-0000000e9303'$$,
  ARRAY[0],
  'deleting a goal cascades its rungs to zero'
);

-- ── 14. Deleting the ENROLLMENT cascades the goal — the FK's own promise ─────
--       A block that is gone cannot still have a milestone; the goal belongs to
--       the block, and `ON DELETE CASCADE` on `enrollment_id` says so.
DELETE FROM program_enrollments WHERE id = '00000000-0000-0000-0000-0000000e9202';

SELECT results_eq(
  $$SELECT count(*)::int FROM block_goals
    WHERE id = '00000000-0000-0000-0000-0000000e9302'$$,
  ARRAY[0],
  'deleting the enrollment cascades its goal (and therefore its rungs)'
);


-- ============================================================
-- Outsider: denied on goals AND on rungs
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e9102';

-- ── 15. Outsider sees zero goals (RLS-filtered, not an error) ────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM block_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9101'$$,
  ARRAY[0],
  'outsider cannot see another user''s block goals'
);

-- ── 16. Outsider cannot impersonate-insert a goal for another user (42501) ───
SELECT throws_ok(
  $$INSERT INTO block_goals (user_id, enrollment_id, metric)
    VALUES ('00000000-0000-0000-0000-0000000e9101',
            '00000000-0000-0000-0000-0000000e9201', 'body_weight')$$,
  '42501', NULL,
  'outsider cannot insert a block goal for another user'
);

-- ── 17. Outsider sees zero rungs for someone else's goal ─────────────────────
--       Rungs carry no `user_id` of their own, so this is the EXISTS subquery
--       in the rung SELECT policy doing its job, not a column comparison.
SELECT results_eq(
  $$SELECT count(*)::int FROM block_goal_rungs
    WHERE goal_id = '00000000-0000-0000-0000-0000000e9301'$$,
  ARRAY[0],
  'outsider cannot see the rungs of another user''s goal'
);

-- ── 18. Outsider cannot insert a rung against someone else's goal (42501) ────
--       THIS IS THE ONE THAT PROVES THE `EXISTS` SUBQUERY ACTUALLY GATES. The
--       foreign key resolves (FK checks do not run under RLS), so the only
--       thing that can refuse this write is the policy's WITH CHECK.
SELECT throws_ok(
  $$INSERT INTO block_goal_rungs (goal_id, week_index, week_start)
    VALUES ('00000000-0000-0000-0000-0000000e9301', 9, '2099-01-25')$$,
  '42501', NULL,
  'outsider cannot insert a rung against another user''s goal'
);

-- ── 19. Outsider's UPDATE affects 0 rows (filtered, not an error) ────────────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE block_goals SET metric = 'body_weight'
      WHERE id = '00000000-0000-0000-0000-0000000e9301'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'outsider''s update of another user''s block goal affects 0 rows'
);


-- ============================================================
-- The ladder link: a weekly row outlives the block it described
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e9101';

-- ── 20. ON DELETE SET NULL: deleting the goal must NOT delete the weeks ──────
--       Spec §4, and the reason `weekly_goals.goal_id` is nullable: the athlete
--       trained those weeks. A row whose `goal_id` went NULL is a standalone
--       weekly goal exactly as one written before blocks had goals at all.
INSERT INTO weekly_goals (user_id, week_start, kind, goal_id, rung_index)
VALUES ('00000000-0000-0000-0000-0000000e9101', '2099-06-07', 'lift',
        '00000000-0000-0000-0000-0000000e9301', 1);
DELETE FROM block_goals WHERE id = '00000000-0000-0000-0000-0000000e9301';

SELECT results_eq(
  $$SELECT count(*)::int FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9101'
      AND week_start = '2099-06-07'
      AND goal_id IS NULL$$,
  ARRAY[1],
  'deleting the goal leaves the weekly row standing with goal_id NULL'
);

SELECT * FROM finish();
ROLLBACK;
