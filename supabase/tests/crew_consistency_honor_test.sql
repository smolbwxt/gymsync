BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Spec §3 / plan task S1.2. group_consistency_honor(p_group_id): the 30-day
-- frequency read behind the Crews card's honor line.
-- Fixture block: 09xx UUIDs (this suite's namespace).
--   A = ...0901 member, 2 sessions in-window, and the ORGANIZER of E's three
--   B = ...0902 member, 2 sessions in-window but LATER (loses the tie-break)
--   C = ...0903 member, 1 session 40 days ago (out of the window)
--   D = ...0904 NON-member (the gate)
--   E = ...0905 member, 3 sessions in-window that A organized and only E
--       attended — the attendance-over-organizer case, and the reason the
--       ordering assertion below can tell the function's two sort keys apart
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor-a@test.local'),
  ('00000000-0000-4000-f000-000000000902', 'honor-b@test.local'),
  ('00000000-0000-4000-f000-000000000903', 'honor-c@test.local'),
  ('00000000-0000-4000-f000-000000000904', 'honor-d@test.local'),
  ('00000000-0000-4000-f000-000000000905', 'honor-e@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor_a'),
  ('00000000-0000-4000-f000-000000000902', 'honor_b'),
  ('00000000-0000-4000-f000-000000000903', 'honor_c'),
  ('00000000-0000-4000-f000-000000000904', 'honor_d'),
  ('00000000-0000-4000-f000-000000000905', 'honor_e');

INSERT INTO groups (id, created_by, name) VALUES
  ('00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'Honor Crew');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000901', 'admin'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000902', 'member'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000903', 'member'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000905', 'member');

-- Nine sessions: A in two (older), B in two (newer — the tie-break loser),
-- C in one that closed 40 days ago, one A was NOT in that is still open, and
-- three A ORGANIZED but did not attend (E did).
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
   '00000000-0000-4000-f000-000000000901', 'in_progress', now(), NULL),
  -- A organizes, E lifts. If the function credited organizer_id, A would
  -- read 5 and E would not appear at all.
  ('00000000-0000-4000-f000-000000000927', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '3 days',  now() - interval '3 days'),
  ('00000000-0000-4000-f000-000000000928', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '2 days',  now() - interval '2 days'),
  ('00000000-0000-4000-f000-000000000929', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '12 hours', now() - interval '12 hours');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000921', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000922', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000923', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000924', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000925', '00000000-0000-4000-f000-000000000903'),
  ('00000000-0000-4000-f000-000000000926', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000927', '00000000-0000-4000-f000-000000000905'),
  ('00000000-0000-4000-f000-000000000928', '00000000-0000-4000-f000-000000000905'),
  ('00000000-0000-4000-f000-000000000929', '00000000-0000-4000-f000-000000000905');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';

-- 1. A member gets rows.
SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  $$VALUES (3)$$,
  'only members who trained in the window appear');

-- 2. The crown is the most SESSIONS, not the most recent one: E holds three
--    and also the latest completion, A holds two from five days ago.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') LIMIT 1$$,
  $$VALUES ('honor_e'::text)$$,
  'the crown is the highest count, not the latest session');

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

-- 6. THE FUNCTION'S OWN ORDER, with no ORDER BY of our own on top of it —
--    an outer sort would re-order the rows and prove nothing about the
--    function. Both keys are discriminated by this one sequence: E leads on
--    count DESPITE holding the most recent reached_at (so count is primary),
--    and A precedes B on the earlier reached_at at equal counts (so the
--    tie-break is reached_at ASC). Sorting by reached_at alone would give
--    A, B, E; by count alone, E and then either order of A/B.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  $$VALUES ('honor_e'::text), ('honor_a'::text), ('honor_b'::text)$$,
  'rows come back count DESC, ties to the earlier achiever');

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

-- 9/10. WHO SHOWED UP, NOT WHO SCHEDULED. A organized sessions 927-929 and
--       attended none of them; E attended all three and organized nothing.
--       Before these two, every fixture session had its organizer as its sole
--       participant, so crediting organizer_id would have passed the whole
--       suite.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';
SELECT results_eq(
  $$SELECT sessions FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_e'$$,
  $$VALUES (3)$$,
  'attendance is credited to whoever was in the room');
SELECT results_eq(
  $$SELECT sessions FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_a'$$,
  $$VALUES (2)$$,
  'organizing three sessions you skipped earns nothing');

SELECT * FROM finish();
ROLLBACK;
