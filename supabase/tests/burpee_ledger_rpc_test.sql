BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- Organizer/admin A, existing member B, late-joining member C (added AFTER
-- the session already ran), outsider D (never joins the group at all).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000ba101', 'bl-a@t.com'),
  ('00000000-0000-0000-0000-0000000ba102', 'bl-b@t.com'),
  ('00000000-0000-0000-0000-0000000ba103', 'bl-c@t.com'),
  ('00000000-0000-0000-0000-0000000ba104', 'bl-d@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000ba101', 'bl_user_a'),
  ('00000000-0000-0000-0000-0000000ba102', 'bl_user_b'),
  ('00000000-0000-0000-0000-0000000ba103', 'bl_user_c'),
  ('00000000-0000-0000-0000-0000000ba104', 'bl_user_d');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000bc201',
   'Ledger RPC Crew', '00000000-0000-0000-0000-0000000ba101');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000bc201',
   '00000000-0000-0000-0000-0000000ba101', 'admin'),
  ('00000000-0000-0000-0000-0000000bc201',
   '00000000-0000-0000-0000-0000000ba102', 'member');

-- A session that already ran (completed) BEFORE C ever joins the group.
-- A checked in on time (0 owed); B was late and owes 15.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('00000000-0000-0000-0000-0000000bd301',
   '00000000-0000-0000-0000-0000000ba101',
   '00000000-0000-0000-0000-0000000bc201',
   'completed', now() - interval '5 days');
INSERT INTO session_participants
  (session_id, user_id, check_in_state, late_minutes, burpees_owed) VALUES
  ('00000000-0000-0000-0000-0000000bd301',
   '00000000-0000-0000-0000-0000000ba101', 'ready', 0, 0),
  ('00000000-0000-0000-0000-0000000bd301',
   '00000000-0000-0000-0000-0000000ba102', 'late', 3, 15);

-- C joins the group AFTER the session above already completed. The
-- invite_new_member_to_future_sessions trigger only invites new members to
-- sessions with state='scheduled' AND scheduled_for > now() — this one is
-- 'completed' and in the past, so C gets ZERO session_participants rows for
-- it (reproduces the exact RLS gap group_burpee_ledger fixes).
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000bc201',
   '00000000-0000-0000-0000-0000000ba103', 'member');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE session_id = '00000000-0000-0000-0000-0000000bd301'
      AND user_id = '00000000-0000-0000-0000-0000000ba103'$$,
  ARRAY[0], 'fixture sanity: late joiner C has no participant row for the pre-membership session');

SET LOCAL role authenticated;

-- ── Test: non-member D is rejected ────────────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ba104';
SELECT throws_ok(
  $$SELECT * FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')$$,
  'P0001',
  'not a member of this group',
  'non-member D is rejected with P0001');

-- ── Tests: late-joining member C sees the FULL, true aggregate ───────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ba103';

SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')$$,
  ARRAY[2],
  'late joiner C sees aggregate rows for both A and B, not just sessions C participated in');

SELECT results_eq(
  $$SELECT total_owed FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba102'$$,
  ARRAY[15],
  'C sees B''s true total_owed (15) from the pre-membership session, not undercounted to 0');

SELECT results_eq(
  $$SELECT late_count FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba102'$$,
  ARRAY[1],
  'C sees B''s true late_count (1)');

SELECT results_eq(
  $$SELECT no_show_count FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba102'$$,
  ARRAY[0],
  'B has no no_show rows');

SELECT results_eq(
  $$SELECT total_owed FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba101'$$,
  ARRAY[0],
  'A (checked in on time) owes 0 — confirms per-user sums are not mixed up');

SELECT ok(
  (SELECT last_late_at IS NOT NULL
   FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc201')
   WHERE user_id = '00000000-0000-0000-0000-0000000ba102'),
  'last_late_at is populated for the user whose session contributed debt');

-- ── Task 2 (Phase S) — paid/settled derivation fixtures ──────────────────────
-- Separate group so its participant/session counts don't disturb the
-- count(*) = 2 assertion above. Three members exercise the three paid
-- states: exact-match settlement, partial payment (with a non-penalty set
-- logged too, to prove it's excluded), and never-paid.
SET LOCAL role postgres;

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000ba201', 'bl-admin2@t.com'),
  ('00000000-0000-0000-0000-0000000ba202', 'bl-p1@t.com'),
  ('00000000-0000-0000-0000-0000000ba203', 'bl-p2@t.com'),
  ('00000000-0000-0000-0000-0000000ba204', 'bl-p3@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000ba201', 'bl_admin2'),
  ('00000000-0000-0000-0000-0000000ba202', 'bl_p1'),
  ('00000000-0000-0000-0000-0000000ba203', 'bl_p2'),
  ('00000000-0000-0000-0000-0000000ba204', 'bl_p3');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000bc202',
   'Ledger Paid Crew', '00000000-0000-0000-0000-0000000ba201');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000bc202',
   '00000000-0000-0000-0000-0000000ba201', 'admin'),
  ('00000000-0000-0000-0000-0000000bc202',
   '00000000-0000-0000-0000-0000000ba202', 'member'),
  ('00000000-0000-0000-0000-0000000bc202',
   '00000000-0000-0000-0000-0000000ba203', 'member'),
  ('00000000-0000-0000-0000-0000000bc202',
   '00000000-0000-0000-0000-0000000ba204', 'member');

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('00000000-0000-0000-0000-0000000bd302',
   '00000000-0000-0000-0000-0000000ba201',
   '00000000-0000-0000-0000-0000000bc202',
   'completed', now() - interval '3 days');

-- P1 owes 15 and pays exactly 15 (settled boundary: paid == owed).
-- P2 owes 30, pays only 10 via a penalty set, but ALSO logs a 50-rep
-- normal (non-penalty) set in the same session — proves paid excludes
-- normal work sets, not just that it sums penalty ones.
-- P3 owes 20 and never logs any penalty set (zero-penalty member).
INSERT INTO session_participants
  (session_id, user_id, check_in_state, late_minutes, burpees_owed) VALUES
  ('00000000-0000-0000-0000-0000000bd302',
   '00000000-0000-0000-0000-0000000ba202', 'late', 3, 15),
  ('00000000-0000-0000-0000-0000000bd302',
   '00000000-0000-0000-0000-0000000ba203', 'late', 6, 30),
  ('00000000-0000-0000-0000-0000000bd302',
   '00000000-0000-0000-0000-0000000ba204', 'late', 4, 20);

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, is_penalty)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000ba202',
       '00000000-0000-0000-0000-0000000bd302', ex.id, 1, 15, true
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, is_penalty)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000ba203',
       '00000000-0000-0000-0000-0000000bd302', ex.id, 1, 10, true
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, is_penalty)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000ba203',
       '00000000-0000-0000-0000-0000000bd302', ex.id, 2, 50, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ba202';

SELECT results_eq(
  $$SELECT paid FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba202'$$,
  ARRAY[15],
  'P1 paid = 15 (sum of is_penalty reps) matching owed exactly');

SELECT results_eq(
  $$SELECT settled FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba202'$$,
  ARRAY[true],
  'P1 settled = true at the paid == owed boundary');

SELECT results_eq(
  $$SELECT paid FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba203'$$,
  ARRAY[10],
  'P2 paid = 10 — counts only the is_penalty set, excludes the 50-rep normal set logged in the same session');

SELECT results_eq(
  $$SELECT settled FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba203'$$,
  ARRAY[false],
  'P2 settled = false when paid (10) < owed (30)');

SELECT results_eq(
  $$SELECT paid FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba204'$$,
  ARRAY[0],
  'P3 paid = 0 — zero-penalty member who owes 20 but never logged a penalty set');

SELECT results_eq(
  $$SELECT settled FROM public.group_burpee_ledger('00000000-0000-0000-0000-0000000bc202')
    WHERE user_id = '00000000-0000-0000-0000-0000000ba204'$$,
  ARRAY[false],
  'P3 settled = false (owed 20, paid 0)');

SELECT * FROM finish();
ROLLBACK;
