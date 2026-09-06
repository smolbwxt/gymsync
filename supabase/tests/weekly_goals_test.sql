BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(22);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- wg1 alice = owner
-- wg2 erin  = outsider — never touches alice's row, used for the RLS denials
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000e9001', 'wg1@t.com'),
  ('00000000-0000-0000-0000-0000000e9002', 'wg2@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000e9001', 'wg_alice'),
  ('00000000-0000-0000-0000-0000000e9002', 'wg_erin');


-- ============================================================
-- Owner: insert, defaults, the primary key, the two CHECKs
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e9001';

-- ── 1. Owner can insert own row, omitting source/params/created_at/updated_at ──
--      `params` carries CAMELCASE keys on purpose: the app sets no
--      keyEncodingStrategy anywhere, so `WeeklyGoalParams`' synthesized
--      encoder writes its Swift property names. Assertions 8a/8b below prove
--      that spelling survives the round trip, which is the contract A12's
--      `WeeklyGoalRow` DTO reads.
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind, params) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-09-06', 'muscle_sets',
     '{"muscleTargets":{"chest":12,"back":12},"targetSource":"routines"}'::jsonb)$$,
  'owner can insert own weekly_goals row'
);

-- ── 2. Column defaults apply when omitted (source coach, params {}) ───────────
--      `source` defaulting to 'coach' is the propose-only ruling's resting
--      state: a row nobody claimed is Coach's, and only an explicit 'user'
--      write makes it the athlete's.
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-08-30', 'days')$$,
  'owner can insert a row omitting source and params'
);

SELECT results_eq(
  $$SELECT source, params FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'
      AND week_start = '2026-08-30'$$,
  $$VALUES ('coach'::text, '{}'::jsonb)$$,
  'source and params fall back to their column defaults when omitted'
);

-- ── 3. Owner sees own rows ────────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'$$,
  ARRAY[2],
  'owner sees own weekly_goals rows'
);

-- ── 4. PRIMARY KEY (user_id, week_start): one goal per user per week ──────────
--      This is what makes `save` an upsert on (user_id, week_start) rather
--      than an insert, and what stops a second detection run from producing a
--      duplicate week.
SELECT throws_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-09-06', 'days')$$,
  '23505', NULL,
  'a second row for the same (user_id, week_start) violates the primary key'
);

-- ── 5. All five kind values are accepted ──────────────────────────────────────
--      These five strings ARE `WeeklyGoalKind`'s raw values
--      (Models/WeeklyGoal.swift:21-27). If this CHECK and that enum ever drift,
--      one of these five goes red before a user meets a decode failure.
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-09-13', 'muscle_sets')$$,
  'kind muscle_sets is accepted'
);
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-09-20', 'distance')$$,
  'kind distance is accepted'
);
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-09-27', 'sessions_of_type')$$,
  'kind sessions_of_type is accepted'
);
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-10-04', 'days')$$,
  'kind days is accepted'
);
SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-10-11', 'lift')$$,
  'kind lift is accepted'
);

-- ── 6. A sixth kind is rejected ───────────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-10-18', 'steps')$$,
  '23514', NULL,
  'a kind outside the five violates the CHECK constraint'
);

-- ── 7. source is exactly {coach, user} ────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind, source) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-10-18', 'days', 'trainer')$$,
  '23514', NULL,
  'a source outside (coach, user) violates the CHECK constraint'
);

SELECT lives_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind, source) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-10-18', 'days', 'user')$$,
  'source user is accepted'
);

-- ── 8. params keys survive the round trip in CAMELCASE ────────────────────────
--      The whole of A12's decode depends on this spelling. Asserted against the
--      jsonb directly rather than through the client, so a future
--      keyEncodingStrategy (which nothing in the repo sets today) would break
--      this test before it broke a user's goal.
SELECT results_eq(
  $$SELECT params->'muscleTargets'->>'chest' FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'
      AND week_start = '2026-09-06'$$,
  $$VALUES ('12'::text)$$,
  'params.muscleTargets keeps its camelCase key and nested group targets'
);

SELECT results_eq(
  $$SELECT params->>'targetSource' FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'
      AND week_start = '2026-09-06'$$,
  $$VALUES ('routines'::text)$$,
  'params.targetSource keeps its camelCase key'
);

-- ── 9. updated_at is WeeklyGoal.setAt, so an UPDATE must bump it ──────────────
--      `DEFAULT now()` fires on INSERT only and the client write path is an
--      upsert whose Row does not carry the column, so without the BEFORE UPDATE
--      trigger (20260906000001) `setAt` would be frozen at row-creation time
--      forever — the identical never-bumps bug fixed twice before
--      (20260726000005 soundboard_favorites, 20260726000006 user_settings).
--
--      clock_timestamp(), not now()/transaction_timestamp() (frozen at this
--      whole test's transaction start), is what makes the INSERT-time stamp and
--      this UPDATE's stamp compare GREATER rather than equal — the lesson
--      20260726000006's header records. Writable CTE must be top-level, not
--      nested inside ok()'s argument list (Postgres: "WITH clause containing a
--      data-modifying statement must be at the top level"), so this whole
--      statement IS the WITH.
WITH before_val AS (
  SELECT updated_at FROM weekly_goals
  WHERE user_id = '00000000-0000-0000-0000-0000000e9001' AND week_start = '2026-09-06'
), after_update AS (
  UPDATE weekly_goals SET source = 'user'
  WHERE user_id = '00000000-0000-0000-0000-0000000e9001' AND week_start = '2026-09-06'
  RETURNING updated_at
)
SELECT ok(
  after_update.updated_at > before_val.updated_at,
  'UPDATE bumps updated_at past its pre-update value (setAt is honest after an edit)')
FROM before_val, after_update;

-- ── 10. …and leaves created_at alone ──────────────────────────────────────────
--       The two columns answer different questions ("when did this week's goal
--       first exist" vs "when was it last set"), so a trigger that moved both
--       would make the first unanswerable.
WITH before_val AS (
  SELECT created_at FROM weekly_goals
  WHERE user_id = '00000000-0000-0000-0000-0000000e9001' AND week_start = '2026-09-06'
), after_update AS (
  UPDATE weekly_goals SET kind = 'days'
  WHERE user_id = '00000000-0000-0000-0000-0000000e9001' AND week_start = '2026-09-06'
  RETURNING created_at
)
SELECT ok(
  after_update.created_at = before_val.created_at,
  'UPDATE leaves created_at untouched')
FROM before_val, after_update;


-- ============================================================
-- Outsider: denied read and write, all four verbs
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e9002';

-- ── 11. Outsider sees zero rows (RLS-filtered, not an error) ──────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'$$,
  ARRAY[0],
  'outsider cannot see another user''s weekly goals'
);

-- ── 12. Outsider cannot impersonate-insert a row for another user (42501) ─────
SELECT throws_ok(
  $$INSERT INTO weekly_goals (user_id, week_start, kind) VALUES
    ('00000000-0000-0000-0000-0000000e9001', '2026-11-01', 'days')$$,
  '42501', NULL,
  'outsider cannot insert a weekly_goals row for another user'
);

-- ── 13. Outsider's UPDATE affects 0 rows ──────────────────────────────────────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE weekly_goals SET kind = 'lift'
      WHERE user_id = '00000000-0000-0000-0000-0000000e9001'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'outsider''s update of another user''s weekly goals affects 0 rows'
);

-- ── 14. Outsider's DELETE affects 0 rows ──────────────────────────────────────
--       The editor's LET COACH SET IT deletes the row, so the DELETE policy is
--       a real write path and gets the same denial proof as the other three.
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM weekly_goals
      WHERE user_id = '00000000-0000-0000-0000-0000000e9001'
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'outsider''s delete of another user''s weekly goals affects 0 rows'
);

-- ── 15. postgres-role read confirms alice's rows survived untouched ───────────
--       Eight: 2026-08-30 and 09-06 from the defaults/insert block, the five
--       kind rows (09-13 … 10-11), and the `source = 'user'` row at 10-18.
SET LOCAL role postgres;
SELECT results_eq(
  $$SELECT count(*)::int FROM weekly_goals
    WHERE user_id = '00000000-0000-0000-0000-0000000e9001'$$,
  ARRAY[8],
  'alice''s eight rows are unchanged after the outsider''s attempts'
);

SELECT * FROM finish();
ROLLBACK;
