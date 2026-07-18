-- Phase L Task 1: workout_attempts + leaderboard_entries backend core
-- (20260723000001_public_workout_repository.sql).
-- Design doc citations: docs/superpowers/specs/2026-06-28-gymsync-design.md
-- §Public Workout Repository (:404-432), Flow 4 (:790-797), Flow 6 duration-
-- edit rule (:831-836); docs/superpowers/specs/2026-07-18-discover-
-- leaderboards-design.md §1.
--
-- ── Fixtures ─────────────────────────────────────────────────────────────
-- alice   = opted-in attempt (b1..d001) on session1 (b1..c001), started
--           2026-01-01 10:00:00, completed 10:42:13 -> time_seconds=2533
--           (the spec's own "42:13" Murph example, :796). 5 set_logs: 2
--           valid bench-press (185, 195), 1 valid back-squat (225), 1
--           penalty bench-press (999) and 1 failed back-squat (999) that
--           MUST be excluded from every computed metric.
-- bob     = opted-OUT attempt (b1..d002) on session2, completed with zero
--           set_logs — exists purely as the RLS negative fixture (stranger
--           denied, owner still reads).
-- carol   = attempt (b1..d003) on session3 that NEVER completes — isolates
--           the leaderboard_entries INSERT-rejection test from any PK-
--           conflict noise (no entry row exists to collide with). session4
--           (b1..c004) is a second, otherwise-unused session of carol's,
--           isolating the workout_attempts INSERT-rejection test from the
--           (session_id,user_id) UNIQUE constraint (session3 already holds
--           carol's real d003 pairing).
-- stranger = never a participant/owner of anything — pure RLS negative.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

-- ============================================================
-- ── F. routines fix-forward columns (is_featured/default_sort/
--      scoring_metrics/scoring_top_set_exercise_id) ────────────────────────
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('b1000000-0000-0000-0000-00000000a001', 'lb-alice@t.com');
INSERT INTO profiles (id, username) VALUES
  ('b1000000-0000-0000-0000-00000000a001', 'lb_alice');

SELECT lives_ok(
  $$INSERT INTO routines
      (id, owner_id, name, visibility, is_featured, default_sort, scoring_metrics, scoring_top_set_exercise_id)
    VALUES
      ('b1000000-0000-0000-0000-00000000b002', 'b1000000-0000-0000-0000-00000000a001',
       'Featured Test WOD', 'public', true, 'time', ARRAY['time','volume'],
       (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1))$$,
  'routines: is_featured/default_sort/scoring_metrics/scoring_top_set_exercise_id all accept valid values (fix-forward columns)'
);

SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name, visibility, default_sort)
    VALUES ('b1000000-0000-0000-0000-00000000a001', 'Bad Sort WOD', 'private', 'bogus')$$,
  '23514', NULL,
  'routines: default_sort CHECK rejects a value outside time/volume/top_set/recent'
);

-- ============================================================
-- ── Fixtures: users, routine, sessions, attempts, set_logs ─────────────────
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('b1000000-0000-0000-0000-00000000a002', 'lb-bob@t.com'),
  ('b1000000-0000-0000-0000-00000000a003', 'lb-carol@t.com'),
  ('b1000000-0000-0000-0000-00000000a004', 'lb-stranger@t.com');
INSERT INTO profiles (id, username) VALUES
  ('b1000000-0000-0000-0000-00000000a002', 'lb_bob'),
  ('b1000000-0000-0000-0000-00000000a003', 'lb_carol'),
  ('b1000000-0000-0000-0000-00000000a004', 'lb_stranger');

INSERT INTO routines (id, owner_id, name, visibility, is_featured) VALUES
  ('b1000000-0000-0000-0000-00000000b001', 'b1000000-0000-0000-0000-00000000a001',
   'The Test Murph', 'public', true);

INSERT INTO sessions (id, organizer_id, state, started_at) VALUES
  ('b1000000-0000-0000-0000-00000000c001', 'b1000000-0000-0000-0000-00000000a001',
   'in_progress', '2026-01-01 10:00:00+00'),
  ('b1000000-0000-0000-0000-00000000c002', 'b1000000-0000-0000-0000-00000000a002',
   'in_progress', '2026-01-01 09:00:00+00'),
  ('b1000000-0000-0000-0000-00000000c003', 'b1000000-0000-0000-0000-00000000a003',
   'in_progress', '2026-01-01 08:00:00+00'),
  ('b1000000-0000-0000-0000-00000000c004', 'b1000000-0000-0000-0000-00000000a003',
   'in_progress', '2026-01-01 08:00:00+00');

INSERT INTO workout_attempts (id, routine_id, user_id, session_id, is_opt_in_leaderboard, started_at) VALUES
  ('b1000000-0000-0000-0000-00000000d001', 'b1000000-0000-0000-0000-00000000b001',
   'b1000000-0000-0000-0000-00000000a001', 'b1000000-0000-0000-0000-00000000c001',
   true, '2026-01-01 10:00:00+00'),
  ('b1000000-0000-0000-0000-00000000d002', 'b1000000-0000-0000-0000-00000000b001',
   'b1000000-0000-0000-0000-00000000a002', 'b1000000-0000-0000-0000-00000000c002',
   false, '2026-01-01 09:00:00+00'),
  ('b1000000-0000-0000-0000-00000000d003', 'b1000000-0000-0000-0000-00000000b001',
   'b1000000-0000-0000-0000-00000000a003', 'b1000000-0000-0000-0000-00000000c003',
   true, '2026-01-01 08:00:00+00');

-- alice's set_logs: 3 valid (2 bench-press, 1 back-squat) + 1 penalty + 1
-- failed, both on exercises she also has a valid log for, so if the
-- exclusion filter ever regressed the WRONG value (999) would surface
-- directly in the top_sets assertions below, not just an extra jsonb key.
WITH e AS (
  SELECT slug, id FROM exercises WHERE slug IN ('bench-press', 'back-squat')
)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_failed, is_penalty)
SELECT gen_random_uuid(), 'b1000000-0000-0000-0000-00000000a001'::uuid, 'b1000000-0000-0000-0000-00000000c001'::uuid,
       e.id, v.set_index, v.reps, v.weight, v.is_failed, v.is_penalty
FROM (VALUES
  (1, 5, 185.00::numeric, false, false),
  (2, 5, 195.00::numeric, false, false),
  (4, 10, 999.00::numeric, false, true)   -- penalty, must be excluded
) AS v(set_index, reps, weight, is_failed, is_penalty)
JOIN e ON e.slug = 'bench-press'
UNION ALL
SELECT gen_random_uuid(), 'b1000000-0000-0000-0000-00000000a001'::uuid, 'b1000000-0000-0000-0000-00000000c001'::uuid,
       e.id, v.set_index, v.reps, v.weight, v.is_failed, v.is_penalty
FROM (VALUES
  (3, 5, 225.00::numeric, false, false),
  (5, 1, 999.00::numeric, true, false)    -- failed, must be excluded
) AS v(set_index, reps, weight, is_failed, is_penalty)
JOIN e ON e.slug = 'back-squat';

-- ============================================================
-- ── A. Recompute correctness (fires leaderboard_recompute_on_completion) ──
-- ============================================================

UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 10:42:13+00'
  WHERE id = 'b1000000-0000-0000-0000-00000000c001';
UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 09:30:00+00'
  WHERE id = 'b1000000-0000-0000-0000-00000000c002';

SELECT results_eq(
  $$SELECT time_seconds, total_volume FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (2533, 3025.00::numeric(10,2))$$,
  'alice: time_seconds=42:13 exact (2533s), total_volume=3025.00 excludes penalty(999)+failed(999)'
);

SELECT results_eq(
  $$SELECT (top_sets->>(SELECT id::text FROM exercises WHERE slug='bench-press'))::numeric(7,2),
           (top_sets->>(SELECT id::text FROM exercises WHERE slug='back-squat'))::numeric(7,2)
    FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (195.00::numeric(7,2), 225.00::numeric(7,2))$$,
  'alice: top_sets exact per-exercise max weight — penalty (999) and failed (999) sets excluded'
);

SELECT results_eq(
  $$SELECT is_complete FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  ARRAY[true],
  'alice: leaderboard_entries.is_complete flips true on recompute'
);

SELECT results_eq(
  $$SELECT is_complete, completed_at FROM workout_attempts
    WHERE id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (true, '2026-01-01 10:42:13+00'::timestamptz)$$,
  'alice: workout_attempts.is_complete + completed_at set by the recompute trigger'
);

-- ============================================================
-- ── B. RLS reads — opt-in=true (stranger reads) vs opt-in=false
--      (stranger denied, owner still reads), both directions ─────────────
-- ============================================================

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-00000000a004';  -- stranger

SELECT results_eq(
  $$SELECT count(*)::int FROM workout_attempts WHERE id = 'b1000000-0000-0000-0000-00000000d001'$$,
  ARRAY[1], 'stranger CAN read alice''s opted-in workout_attempts row'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  ARRAY[1], 'stranger CAN read alice''s opted-in leaderboard_entries row'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_attempts WHERE id = 'b1000000-0000-0000-0000-00000000d002'$$,
  ARRAY[0], 'stranger CANNOT read bob''s opted-out workout_attempts row'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d002'$$,
  ARRAY[0], 'stranger CANNOT read bob''s opted-out leaderboard_entries row'
);

SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-00000000a002';  -- bob (owner)
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_attempts WHERE id = 'b1000000-0000-0000-0000-00000000d002'$$,
  ARRAY[1], 'bob (owner) can still read his own opted-out workout_attempts row'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d002'$$,
  ARRAY[1], 'bob (owner) can still read his own opted-out leaderboard_entries row'
);

-- ============================================================
-- ── C. No client writes on either table ────────────────────────────────────
-- ============================================================

SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-00000000a003';  -- carol
SELECT throws_ok(
  $$INSERT INTO workout_attempts (routine_id, user_id, session_id)
    VALUES ('b1000000-0000-0000-0000-00000000b001', 'b1000000-0000-0000-0000-00000000a003',
            'b1000000-0000-0000-0000-00000000c004')$$,
  '42501', NULL,
  'client cannot INSERT into workout_attempts (no INSERT policy — Task 2''s RPC is the only path)'
);
SELECT throws_ok(
  $$INSERT INTO leaderboard_entries (attempt_id, user_id)
    VALUES ('b1000000-0000-0000-0000-00000000d003', 'b1000000-0000-0000-0000-00000000a003')$$,
  '42501', NULL,
  'client cannot INSERT into leaderboard_entries (no INSERT policy — trigger-only writes)'
);

SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-00000000a002';  -- bob (owner)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE workout_attempts SET is_opt_in_leaderboard = true
      WHERE id = 'b1000000-0000-0000-0000-00000000d002'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'client (even the owner) cannot UPDATE workout_attempts directly'
);

SET LOCAL request.jwt.claim.sub = 'b1000000-0000-0000-0000-00000000a001';  -- alice (owner)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE leaderboard_entries SET is_edited = true
      WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'client (even the owner) cannot UPDATE leaderboard_entries directly'
);

SET LOCAL role postgres;

-- ============================================================
-- ── D. Duration-edit lock: is_edited flips, time_seconds NEVER updates ─────
-- (Flow 6, :831-836) — replays SessionRepository.editDuration's exact write
-- order: session_duration_edits INSERT first, then the sessions UPDATE.
-- ============================================================

INSERT INTO session_duration_edits
  (session_id, edited_by, old_started_at, old_completed_at, new_started_at, new_completed_at, reason)
VALUES
  ('b1000000-0000-0000-0000-00000000c001', 'b1000000-0000-0000-0000-00000000a001',
   '2026-01-01 10:00:00+00', '2026-01-01 10:42:13+00',
   '2026-01-01 09:58:00+00', '2026-01-01 10:45:00+00', 'corrected timer start');

UPDATE sessions
  SET started_at = '2026-01-01 09:58:00+00',
      completed_at = '2026-01-01 10:45:00+00',
      duration_was_edited = true
  WHERE id = 'b1000000-0000-0000-0000-00000000c001';

SELECT results_eq(
  $$SELECT time_seconds, is_edited FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (2533, true)$$,
  'duration edit: time_seconds stays locked at the ORIGINAL 2533s, is_edited flips to true'
);
SELECT results_eq(
  $$SELECT completed_at FROM workout_attempts
    WHERE id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES ('2026-01-01 10:42:13+00'::timestamptz)$$,
  'duration edit: workout_attempts.completed_at is untouched — the completion trigger never re-fires (UPDATE OF state only)'
);

-- ============================================================
-- ── E. Volume/top_sets refresh on set_log UPDATE/DELETE — time stays locked
-- ============================================================

-- Bump alice's first bench-press set from 185 -> 205 (now the new bench max).
UPDATE set_logs SET weight = 205.00
  WHERE session_id = 'b1000000-0000-0000-0000-00000000c001'
    AND user_id = 'b1000000-0000-0000-0000-00000000a001'
    AND set_index = 1;

SELECT results_eq(
  $$SELECT time_seconds, total_volume, is_edited FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (2533, 3125.00::numeric(10,2), true)$$,
  'set_log UPDATE: total_volume recomputes to 3125.00 (925->1025), time_seconds stays 2533, is_edited is true (20260723000004 fix)'
);
SELECT results_eq(
  $$SELECT (top_sets->>(SELECT id::text FROM exercises WHERE slug='bench-press'))::numeric(7,2)
    FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (205.00::numeric(7,2))$$,
  'set_log UPDATE: top_sets bench-press recomputes to the new max (205)'
);

-- Delete alice's only back-squat set entirely.
DELETE FROM set_logs
  WHERE session_id = 'b1000000-0000-0000-0000-00000000c001'
    AND user_id = 'b1000000-0000-0000-0000-00000000a001'
    AND set_index = 3;

SELECT results_eq(
  $$SELECT time_seconds, total_volume, is_edited FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  $$VALUES (2533, 2000.00::numeric(10,2), true)$$,
  'set_log DELETE: total_volume recomputes to 2000.00 (1125 removed), time_seconds still stays 2533, is_edited still true'
);
SELECT results_eq(
  $$SELECT top_sets ? (SELECT id::text FROM exercises WHERE slug='back-squat')
    FROM leaderboard_entries WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d001'$$,
  ARRAY[false],
  'set_log DELETE: top_sets no longer carries a back-squat key at all'
);

-- Negative control (20260723000004 fix): bob's entry (d002) is opted-out,
-- has zero set_logs, and never receives a duration edit or a set_log
-- UPDATE/DELETE anywhere in this suite — neither edit trigger ever fires for
-- it. is_edited must stay false, proving the refresh trigger's new
-- `is_edited = true` write is scoped to entries it actually mutates, not a
-- blanket flip on the whole table.
SELECT results_eq(
  $$SELECT is_edited FROM leaderboard_entries
    WHERE attempt_id = 'b1000000-0000-0000-0000-00000000d002'$$,
  ARRAY[false],
  'bob: never-edited leaderboard entry (no duration edit, no set_log change) stays is_edited=false'
);

SELECT * FROM finish();
ROLLBACK;
