-- session_pr_counts RPC (20260720000002_session_pr_counts_and_kudos_guard.sql,
-- Finding 1, task-4-report.md).
--
-- Covers: a session participant gets the TRUE per-user PR counts for a
-- multi-lifter session (not just their own — the exact undercount the RPC
-- fixes), a non-participant is rejected with P0001 (gate-first, same as
-- group_burpee_ledger), and the aggregate excludes PRs logged in a
-- DIFFERENT session even for the same user.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

-- ── Fixtures ─────────────────────────────────────────────────────────────
-- A: organizer + participant, 2 PRs in the target session.
-- B: participant, 1 PR in the target session — also has a PR in a SEPARATE
--    session, proving the aggregate is scoped to p_session_id only.
-- C: participant, 0 PRs in the target session (must not appear as a
--    spurious zero row nor inflate anyone else's count).
-- D: outsider — never a participant of the target session.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000ac101', 'pc-a@t.com'),
  ('00000000-0000-0000-0000-0000000ac102', 'pc-b@t.com'),
  ('00000000-0000-0000-0000-0000000ac103', 'pc-c@t.com'),
  ('00000000-0000-0000-0000-0000000ac104', 'pc-d@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000ac101', 'pc_user_a'),
  ('00000000-0000-0000-0000-0000000ac102', 'pc_user_b'),
  ('00000000-0000-0000-0000-0000000ac103', 'pc_user_c'),
  ('00000000-0000-0000-0000-0000000ac104', 'pc_user_d');

INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('00000000-0000-0000-0000-0000000ad201',
   '00000000-0000-0000-0000-0000000ac101', NULL, 'completed');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000ad201', '00000000-0000-0000-0000-0000000ac101', 'ready'),
  ('00000000-0000-0000-0000-0000000ad201', '00000000-0000-0000-0000-0000000ac102', 'ready'),
  ('00000000-0000-0000-0000-0000000ad201', '00000000-0000-0000-0000-0000000ac103', 'ready');

-- A SEPARATE session B also participated in — its PR must not leak into
-- the ad201 aggregate.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('00000000-0000-0000-0000-0000000ad202',
   '00000000-0000-0000-0000-0000000ac102', NULL, 'completed');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000ad202', '00000000-0000-0000-0000-0000000ac102', 'ready');

INSERT INTO personal_records (user_id, exercise_id, weight, reps, previous_best, session_id) VALUES
  ('00000000-0000-0000-0000-0000000ac101',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 185, 5, 175,
   '00000000-0000-0000-0000-0000000ad201'),
  ('00000000-0000-0000-0000-0000000ac101',
   (SELECT id FROM exercises WHERE slug = 'back-squat' LIMIT 1), 275, 3, 260,
   '00000000-0000-0000-0000-0000000ad201'),
  ('00000000-0000-0000-0000-0000000ac102',
   (SELECT id FROM exercises WHERE slug = 'deadlift' LIMIT 1), 315, 1, 300,
   '00000000-0000-0000-0000-0000000ad201'),
  -- B's PR in the OTHER session (ad202) — must be excluded from ad201's count.
  ('00000000-0000-0000-0000-0000000ac102',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 135, 8, 125,
   '00000000-0000-0000-0000-0000000ad202');

SET LOCAL role authenticated;

-- ── 1. Non-participant D is rejected with P0001 ─────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ac104';
SELECT throws_ok(
  $$SELECT * FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')$$,
  'P0001',
  'not a participant of this session',
  'non-participant D is rejected with P0001');

-- ── 2-6. Participant B sees the TRUE multi-user aggregate ───────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ac102';

SELECT results_eq(
  $$SELECT count(*)::int FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')$$,
  ARRAY[2],
  'B sees rows for A and B (2 users with >=1 PR), not just their own');

SELECT results_eq(
  $$SELECT pr_count FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ac101'$$,
  ARRAY[2],
  'B sees A''s TRUE pr_count (2) — the exact undercount-to-0 this RPC fixes for teammates');

SELECT results_eq(
  $$SELECT pr_count FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ac102'$$,
  ARRAY[1],
  'B sees their own pr_count (1) scoped to ad201 only, excluding the ad202 PR');

SELECT results_eq(
  $$SELECT count(*)::int FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ac103'$$,
  ARRAY[0],
  'C (0 PRs) produces no row rather than a spurious zero row');

SELECT results_eq(
  $$SELECT sum(pr_count)::int FROM public.session_pr_counts('00000000-0000-0000-0000-0000000ad201')$$,
  ARRAY[3],
  'sum across all users = 3 (A:2 + B:1) — matches the hero "PRS" total the Swift side sums');

SELECT * FROM finish();
ROLLBACK;
