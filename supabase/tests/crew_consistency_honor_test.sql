BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Spec §3 / plan task S1.2. group_consistency_honor(p_group_id): the 30-day
-- frequency read behind the Crews card's honor line.
-- Fixture block: 09xx UUIDs (this suite's namespace).
--   A = ...0901 member, 2 sessions in-window (the crown)
--   B = ...0902 member, 2 sessions in-window but LATER (loses the tie-break)
--   C = ...0903 member, 1 session 40 days ago (out of the window)
--   D = ...0904 NON-member (the gate)
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor-a@test.local'),
  ('00000000-0000-4000-f000-000000000902', 'honor-b@test.local'),
  ('00000000-0000-4000-f000-000000000903', 'honor-c@test.local'),
  ('00000000-0000-4000-f000-000000000904', 'honor-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor_a'),
  ('00000000-0000-4000-f000-000000000902', 'honor_b'),
  ('00000000-0000-4000-f000-000000000903', 'honor_c'),
  ('00000000-0000-4000-f000-000000000904', 'honor_d');

INSERT INTO groups (id, created_by, name) VALUES
  ('00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'Honor Crew');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000901', 'admin'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000902', 'member'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000903', 'member');

-- Five sessions: A in two (older), B in two (newer — the tie-break loser),
-- C in one that closed 40 days ago, and one A was NOT in that is still open.
INSERT INTO sessions (id, group_id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000000921', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '9 days',  now() - interval '9 days'),
  ('00000000-0000-4000-f000-000000000922', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '5 days',  now() - interval '5 days'),
  ('00000000-0000-4000-f000-000000000923', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000902', 'completed', now() - interval '4 days',  now() - interval '4 days'),
  ('00000000-0000-4000-f000-000000000924', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000902', 'completed', now() - interval '1 day',   now() - interval '1 day'),
  ('00000000-0000-4000-f000-000000000925', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000903', 'completed', now() - interval '40 days', now() - interval '40 days'),
  ('00000000-0000-4000-f000-000000000926', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'in_progress', now(), NULL);
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000921', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000922', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000923', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000924', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000925', '00000000-0000-4000-f000-000000000903'),
  ('00000000-0000-4000-f000-000000000926', '00000000-0000-4000-f000-000000000901');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';

-- 1. A member gets rows.
SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  $$VALUES (2)$$,
  'only members who trained in the window appear');

-- 2. The crown is A: equal counts, earlier last session.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') LIMIT 1$$,
  $$VALUES ('honor_a'::text)$$,
  'a tie goes to the earlier achiever');

-- 3. The count is DISTINCT completed sessions in the window.
SELECT results_eq(
  $$SELECT sessions FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_a'$$,
  $$VALUES (2)$$,
  'the in-progress session does not count');

-- 4. Out of the window is out of the honor.
SELECT is_empty(
  $$SELECT 1 FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_c'$$,
  'a session 40 days old has decayed out');

-- 5. `reached_at` is the member's LATEST qualifying completion.
SELECT results_eq(
  $$SELECT (reached_at::date = (now() - interval '5 days')::date)
      FROM public.group_consistency_honor(
        '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_a'$$,
  $$VALUES (true)$$,
  'reached_at is when they reached the count they hold');

-- 6. Ordering is count DESC first — B alone after A's sessions are removed.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') ORDER BY sessions DESC, username LIMIT 2$$,
  $$VALUES ('honor_a'::text), ('honor_b'::text)$$,
  'both tied members are returned, crown first');

-- 7. A non-member is refused, not given an empty list.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000904';
SELECT throws_ok(
  $$SELECT * FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  'P0001', 'not a member of this group',
  'a non-member cannot read a crew''s honor');

-- 8. anon holds no EXECUTE.
SELECT ok(
  NOT has_function_privilege('anon', 'public.group_consistency_honor(uuid)', 'EXECUTE'),
  'anon cannot execute the honor function');

SELECT * FROM finish();
ROLLBACK;
