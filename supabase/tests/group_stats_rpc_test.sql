-- group_stats / group_member_stats RPCs (20260720000003_group_stats_rpc.sql,
-- Phase F Task 5; scoping fixed forward by
-- 20260720000004_group_stats_scalars_all_time.sql).
--
-- Covers: correct scalar aggregates + per-member leaderboard rows on a
-- multi-member fixture with penalty/failed sets excluded (checked with real
-- numbers, not just presence/absence), an in-progress session excluded from
-- every aggregate, a departed member's historical activity EXCLUDED from
-- group_member_stats (current-roster leaderboard) but COUNTED in
-- group_stats' scalars (all-time, post-20260720000004), the membership-gate
-- negative on both functions, and an empty-group (no sessions/sets at all)
-- sanity check.
--
-- The sum(member rows) = scalar-totals equality 20260720000003 checked here
-- is GONE (see the "Former invariant" comment below, near the fixture's
-- former location) — it only ever held because both functions shared the
-- same (inconsistent) current-members-only scoping. Replaced with the real
-- post-fix relationship: total_volume >= sum(member_stats.volume), checked
-- with this fixture's exact numbers.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

-- ── Fixtures ─────────────────────────────────────────────────────────────
-- Stats Crew: A (admin), B, C — current members. F joins, logs a set, then
-- LEAVES before the query runs — tests that F's historical volume/PRs still
-- COUNT in group_stats' all-time scalars (post-20260720000004) while F is
-- excluded from group_member_stats' current-roster leaderboard rows. D never
-- joins (outsider, negative test).
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000fa101', 'gs-a@t.com'),
  ('00000000-0000-0000-0000-0000000fa102', 'gs-b@t.com'),
  ('00000000-0000-0000-0000-0000000fa103', 'gs-c@t.com'),
  ('00000000-0000-0000-0000-0000000fa104', 'gs-d@t.com'),
  ('00000000-0000-0000-0000-0000000fa105', 'gs-f@t.com'),
  ('00000000-0000-0000-0000-0000000fa106', 'gs-e@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000fa101', 'gs_user_a'),
  ('00000000-0000-0000-0000-0000000fa102', 'gs_user_b'),
  ('00000000-0000-0000-0000-0000000fa103', 'gs_user_c'),
  ('00000000-0000-0000-0000-0000000fa104', 'gs_user_d'),
  ('00000000-0000-0000-0000-0000000fa105', 'gs_user_f'),
  ('00000000-0000-0000-0000-0000000fa106', 'gs_user_e');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000fb201',
   'Stats Crew', '00000000-0000-0000-0000-0000000fa101'),
  ('00000000-0000-0000-0000-0000000fb202',
   'Empty Crew', '00000000-0000-0000-0000-0000000fa106');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000fb201', '00000000-0000-0000-0000-0000000fa101', 'admin'),
  ('00000000-0000-0000-0000-0000000fb201', '00000000-0000-0000-0000-0000000fa102', 'member'),
  ('00000000-0000-0000-0000-0000000fb201', '00000000-0000-0000-0000-0000000fa103', 'member'),
  ('00000000-0000-0000-0000-0000000fb201', '00000000-0000-0000-0000-0000000fa105', 'member'),
  ('00000000-0000-0000-0000-0000000fb202', '00000000-0000-0000-0000-0000000fa106', 'admin');

-- S1: completed. A logs a normal set (volume 1000), a penalty set (would be
-- +100 if wrongly included), and a failed set (would be +400 if wrongly
-- included). B logs one normal set (volume 1000). C logs nothing. F (about
-- to depart) logs a normal set (volume 300) — this 300 now COUNTS toward
-- group_stats.total_volume (all-time, post-20260720000004) even after F
-- leaves below, but never appears in group_member_stats (current-roster
-- only, unchanged).
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('00000000-0000-0000-0000-0000000fc301',
   '00000000-0000-0000-0000-0000000fa101', '00000000-0000-0000-0000-0000000fb201', 'completed');

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa101',
       '00000000-0000-0000-0000-0000000fc301', ex.id, 1, 10, 100, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa101',
       '00000000-0000-0000-0000-0000000fc301', ex.id, 2, 5, 20, true, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa101',
       '00000000-0000-0000-0000-0000000fc301', ex.id, 3, 8, 50, false, true
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa102',
       '00000000-0000-0000-0000-0000000fc301', ex.id, 1, 5, 200, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa105',
       '00000000-0000-0000-0000-0000000fc301', ex.id, 1, 3, 100, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

INSERT INTO personal_records (user_id, exercise_id, weight, reps, previous_best, session_id) VALUES
  ('00000000-0000-0000-0000-0000000fa101',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 100, 10, 90,
   '00000000-0000-0000-0000-0000000fc301'),
  ('00000000-0000-0000-0000-0000000fa102',
   (SELECT id FROM exercises WHERE slug = 'deadlift' LIMIT 1), 200, 5, 180,
   '00000000-0000-0000-0000-0000000fc301');

-- S2: a SECOND completed session, A logs another normal set (volume 500) —
-- proves per-user totals accumulate ACROSS sessions, and session_count
-- counts both S1 and S2.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('00000000-0000-0000-0000-0000000fc302',
   '00000000-0000-0000-0000-0000000fa101', '00000000-0000-0000-0000-0000000fb201', 'completed');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa101',
       '00000000-0000-0000-0000-0000000fc302', ex.id, 1, 10, 50, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

-- S3: NOT completed (in_progress) — a big set here must NOT leak into any
-- aggregate. If the state filter were missing, total_volume would jump by
-- 10000 and session_count would read 3.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('00000000-0000-0000-0000-0000000fc303',
   '00000000-0000-0000-0000-0000000fa101', '00000000-0000-0000-0000-0000000fb201', 'in_progress');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000fa101',
       '00000000-0000-0000-0000-0000000fc303', ex.id, 1, 100, 100, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

-- F departs the group AFTER logging the S1 set above. Post-20260720000004:
-- their historical 300-volume set MUST still count toward group_stats'
-- all-time total_volume, but must NOT appear as a group_member_stats
-- leaderboard row (current-roster only, unchanged).
DELETE FROM group_members
 WHERE group_id = '00000000-0000-0000-0000-0000000fb201'
   AND user_id = '00000000-0000-0000-0000-0000000fa105';

SET LOCAL role authenticated;

-- ── Membership gate: outsider D rejected on both functions ─────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000fa104';
SELECT throws_ok(
  $$SELECT * FROM public.group_stats('00000000-0000-0000-0000-0000000fb201')$$,
  'P0001', 'not a member of this group',
  'group_stats: non-member D is rejected with P0001');
SELECT throws_ok(
  $$SELECT * FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')$$,
  'P0001', 'not a member of this group',
  'group_member_stats: non-member D is rejected with P0001');

-- ── group_stats: scalar aggregates, queried as member A ────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000fa101';

SELECT results_eq(
  $$SELECT session_count FROM public.group_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[2], 'session_count = 2 (S1 + S2, S3 in_progress excluded)');

SELECT results_eq(
  $$SELECT total_volume FROM public.group_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[2800]::numeric[],
  'total_volume = 2800 (all-time, post-20260720000004: A 1000+500, B 1000, F''s departed 300 NOW COUNTED; A''s penalty/failed 500 still excluded)');

SELECT results_eq(
  $$SELECT total_prs FROM public.group_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[2], 'total_prs = 2 (A + B, one each; unaffected by F, who logged no personal_records row)');

-- ── group_member_stats: per-member leaderboard rows ─────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[3], 'exactly 3 rows: current members A, B, C — departed F excluded');

SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa105'$$,
  ARRAY[0], 'departed member F produces no leaderboard row at all');

SELECT results_eq(
  $$SELECT volume FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa101'$$,
  ARRAY[1500]::numeric[],
  'A''s volume = 1500 (1000 S1 + 500 S2), penalty (100) and failed (400) sets excluded');

SELECT results_eq(
  $$SELECT volume FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa102'$$,
  ARRAY[1000]::numeric[], 'B''s volume = 1000');

SELECT results_eq(
  $$SELECT volume FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa103'$$,
  ARRAY[0]::numeric[],
  'C (zero activity) still appears with volume = 0, not dropped by the LATERAL join');

SELECT results_eq(
  $$SELECT pr_count FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa101'$$,
  ARRAY[1], 'A pr_count = 1');

SELECT results_eq(
  $$SELECT pr_count FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa102'$$,
  ARRAY[1], 'B pr_count = 1');

SELECT results_eq(
  $$SELECT pr_count FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')
    WHERE user_id = '00000000-0000-0000-0000-0000000fa103'$$,
  ARRAY[0], 'C pr_count = 0');

-- Ordered volume desc: A (1500) > B (1000) > C (0).
SELECT results_eq(
  $$SELECT user_id FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY['00000000-0000-0000-0000-0000000fa101'::uuid,
        '00000000-0000-0000-0000-0000000fa102'::uuid,
        '00000000-0000-0000-0000-0000000fa103'::uuid],
  'rows ordered by volume desc: A, B, C');

-- ── Former invariant: the two functions' totals no longer reconcile ────────
-- 20260720000003 checked SUM(member_stats.volume) = group_stats.total_volume
-- (and the pr_count equivalent) as "a real invariant." That equality only
-- ever held because both functions shared the same (inconsistent)
-- current-members-only scoping for volume/PRs — it was a side effect of the
-- bug 20260720000004_group_stats_scalars_all_time.sql fixes, not a property
-- worth preserving. group_stats' scalars are now all-time while
-- group_member_stats stays current-roster BY DESIGN (see that migration's
-- header), so the true relationship is total >= sum(member rows), strict >
-- whenever a departed member contributed history (F's 300 volume here).
-- Checked below with this fixture's exact numbers, matching this file's
-- "real numbers, not presence/absence" discipline, rather than asserting a
-- generic >=.
SELECT results_eq(
  $$SELECT sum(volume)::numeric FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[2500]::numeric[],
  'sum(member_stats.volume) is 2500 (current-roster only, F still excluded here) -- 300 LESS than group_stats.total_volume (2800) asserted above; the two no longer reconcile, by design');

-- total_prs: F logged no personal_records row in this fixture, so the sum
-- happens to still equal total_prs (2 = 2) here. That is a FIXTURE
-- COINCIDENCE, not a restored invariant -- total_prs is all-time (no
-- group_members join, see migration header) exactly like total_volume; a
-- departed member WITH a PR would break this equality the same way F's 300
-- volume breaks the volume one.
SELECT results_eq(
  $$SELECT sum(pr_count)::int FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb201')$$,
  ARRAY[2],
  'sum(member_stats.pr_count) = 2, coincidentally equal to total_prs in this fixture only (F has zero PRs) -- not a guaranteed invariant post-fix');

-- ── Empty-group sanity: a group with a member but zero sessions/sets ────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000fa106';

SELECT results_eq(
  $$SELECT session_count, total_volume, total_prs
    FROM public.group_stats('00000000-0000-0000-0000-0000000fb202')$$,
  $$SELECT 0, 0::numeric, 0$$,
  'empty group: session_count/total_volume/total_prs all 0, no error');

SELECT results_eq(
  $$SELECT user_id, volume, pr_count
    FROM public.group_member_stats('00000000-0000-0000-0000-0000000fb202')$$,
  $$SELECT '00000000-0000-0000-0000-0000000fa106'::uuid, 0::numeric, 0$$,
  'empty group: the one member still gets a row (volume 0, pr_count 0), not an empty result set');

SELECT * FROM finish();
ROLLBACK;
