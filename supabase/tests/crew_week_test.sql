BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Migration under test: 20260918000101_crew_week.sql (task D2, Phase B2
-- brief decisions 1-2, R-B2-14, R-B2-16). Fixture block: 13xx UUIDs (this
-- suite's namespace -- grepped repo-wide against supabase/ and scripts/
-- before writing this; 01xx-12xx are taken, 13xx had no hits).
--
-- One lobby_open session, organizer A, five participants (A, B, C, E, F),
-- one non-participant (D).
--   A = ...1301 organizer; two completed sessions inside the main UTC week
--   B = ...1302 one completed session ONE DAY before the main week starts
--       -- the half-open lower bound, and the row that moves when the
--       window is shifted back a week
--   C = ...1303 zero sessions -- decision 2: a row, not an absence
--   D = ...1304 NOT a participant -- the gate
--   E = ...1305 lowered weekly_session_goal DURING the main week --
--       R-B2-14, the anti-goalpost CASE
--   F = ...1306 two completed sessions either side of a UTC-7 midnight --
--       R-B2-16, the non-UTC boundary
--
-- Main UTC week: [2099-06-08 00:00:00+00, 2099-06-15 00:00:00+00).
-- Mountain (UTC-7) week used only for F's boundary assertion:
-- [2099-06-08 00:00:00-07:00, 2099-06-15 00:00:00-07:00).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000001301', 'crewweek-a@test.local'),
  ('00000000-0000-4000-f000-000000001302', 'crewweek-b@test.local'),
  ('00000000-0000-4000-f000-000000001303', 'crewweek-c@test.local'),
  ('00000000-0000-4000-f000-000000001304', 'crewweek-d@test.local'),
  ('00000000-0000-4000-f000-000000001305', 'crewweek-e@test.local'),
  ('00000000-0000-4000-f000-000000001306', 'crewweek-f@test.local');

-- A: goal 4. B: goal 3. C, F: default (3).
-- E: standing goal 3, but changed_at falls INSIDE the main week and prev
-- is 5 -- the anti-goalpost CASE must return 5, not 3, for this week.
INSERT INTO profiles (id, username, weekly_session_goal,
                       weekly_session_goal_prev, weekly_session_goal_changed_at) VALUES
  ('00000000-0000-4000-f000-000000001301', 'crewweek_a', 4, NULL, NULL),
  ('00000000-0000-4000-f000-000000001302', 'crewweek_b', 3, NULL, NULL),
  ('00000000-0000-4000-f000-000000001303', 'crewweek_c', 3, NULL, NULL),
  ('00000000-0000-4000-f000-000000001304', 'crewweek_d', 3, NULL, NULL),
  ('00000000-0000-4000-f000-000000001305', 'crewweek_e', 3, 5,
     '2099-06-09 12:00:00+00'::timestamptz),
  ('00000000-0000-4000-f000-000000001306', 'crewweek_f', 3, NULL, NULL);

INSERT INTO sessions (id, organizer_id, state) VALUES
  ('00000000-0000-4000-f000-000000001310',
   '00000000-0000-4000-f000-000000001301', 'lobby_open');

INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000001310', '00000000-0000-4000-f000-000000001301', 'ready'),
  ('00000000-0000-4000-f000-000000001310', '00000000-0000-4000-f000-000000001302', 'ready'),
  ('00000000-0000-4000-f000-000000001310', '00000000-0000-4000-f000-000000001303', 'ready'),
  ('00000000-0000-4000-f000-000000001310', '00000000-0000-4000-f000-000000001305', 'ready'),
  ('00000000-0000-4000-f000-000000001310', '00000000-0000-4000-f000-000000001306', 'ready');
-- D is deliberately NOT a participant.

-- A: two completed sessions inside the main UTC week.
INSERT INTO sessions (id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000001321', '00000000-0000-4000-f000-000000001301',
   'completed', '2099-06-09 09:00:00+00', '2099-06-09 10:00:00+00'),
  ('00000000-0000-4000-f000-000000001322', '00000000-0000-4000-f000-000000001301',
   'completed', '2099-06-10 09:00:00+00', '2099-06-10 10:00:00+00');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000001321', '00000000-0000-4000-f000-000000001301'),
  ('00000000-0000-4000-f000-000000001322', '00000000-0000-4000-f000-000000001301');

-- B: one completed session ONE DAY before the main week starts -- outside
-- the half-open lower bound.
INSERT INTO sessions (id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000001323', '00000000-0000-4000-f000-000000001302',
   'completed', '2099-06-07 09:00:00+00', '2099-06-07 10:00:00+00');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000001323', '00000000-0000-4000-f000-000000001302');

-- F: R-B2-16. Two completed sessions straddling a UTC-7 midnight, one on
-- each side of it, expressed as timestamptz literals with the -07:00
-- offset -- the whole reason the signature is timestamptz, not date.
--   F1: 23:30 local the Sunday BEFORE the Mountain week starts -- must NOT
--       count against the Mountain week start.
--   F2: 00:30 local the following Monday -- must count.
-- Both instants also fall inside the main UTC week (06-08 06:30Z and
-- 06-08 07:30Z respectively), so F's done is 2 under the main-week query
-- and exactly 1 under the Mountain-week query -- assertion 10 checks the
-- latter.
INSERT INTO sessions (id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000001324', '00000000-0000-4000-f000-000000001306',
   'completed', '2099-06-07 22:00:00-07:00', '2099-06-07 23:30:00-07:00'),
  ('00000000-0000-4000-f000-000000001325', '00000000-0000-4000-f000-000000001306',
   'completed', '2099-06-07 23:45:00-07:00', '2099-06-08 00:30:00-07:00');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000001324', '00000000-0000-4000-f000-000000001306'),
  ('00000000-0000-4000-f000-000000001325', '00000000-0000-4000-f000-000000001306');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001301';

-- 1. The shipped signature -- (uuid, timestamptz), not the spec's bare
--    (uuid, date) and not the original (uuid, date) draft R-B2-16 replaced.
SELECT has_function('public', 'crew_week', ARRAY['uuid', 'timestamptz'],
  'crew_week takes a timestamptz week start, not a date');

-- 2. Every participant is a row, including C who has trained zero times
--    this week (decision 2) -- five rows (A, B, C, E, F), not four.
SELECT results_eq(
  $$SELECT count(*)::int FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)$$,
  $$VALUES (5)$$,
  'every participant of the session is a row, zero-session members included');

-- 3. A's own count and goal.
SELECT results_eq(
  $$SELECT done, goal FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)
    WHERE username = 'crewweek_a'$$,
  $$VALUES (2, 4)$$,
  'A has two completed sessions this week against a goal of 4');

-- 4. B's session one day before the window does not count.
SELECT results_eq(
  $$SELECT done FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)
    WHERE username = 'crewweek_b'$$,
  $$VALUES (0)$$,
  'a session one day outside the half-open window does not count');

-- 5. The same session counts once the window is shifted back a week --
--    the parameter decides, not the server's clock.
SELECT results_eq(
  $$SELECT done FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-01 00:00:00+00'::timestamptz)
    WHERE username = 'crewweek_b'$$,
  $$VALUES (1)$$,
  'the same session counts when p_week_start moves back to include it');

-- 6. A participant who is not the organizer reads the same rows.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001302';
SELECT results_eq(
  $$SELECT count(*)::int FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)$$,
  $$VALUES (5)$$,
  'any participant, not only the organizer, may read the crew''s week');

-- 7. A non-participant is refused.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001304';
SELECT throws_ok(
  $$SELECT * FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)$$,
  'P0001', 'not a participant of this session',
  'a stranger gets nothing');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001301';

-- 8. SECURITY DEFINER is what makes the cross-member read legal.
SELECT ok(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'crew_week'),
  'crew_week is SECURITY DEFINER');

-- 9. R-B2-14: E lowered the goal mid-week (changed_at inside the window,
--    prev not null) -- this week shows the PREVIOUS goal (5), not the new
--    standing one (3), so a member cannot dodge a crewmate's view of
--    their goal by editing it mid-week.
SELECT results_eq(
  $$SELECT goal FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00+00'::timestamptz)
    WHERE username = 'crewweek_e'$$,
  $$VALUES (5)$$,
  'a goal lowered mid-week still shows the previous goal for that week');

-- 10. R-B2-16: the non-UTC boundary. Under the MOUNTAIN (UTC-7) week
--     start, F's 23:30-local session the Sunday before does not count and
--     the 00:30-local session the following Monday does -- done is 1, not
--     2, even though both instants fall inside the main UTC week's count
--     (assertion 2's five rows are unaffected; this reads F under a
--     different p_week_start).
SELECT results_eq(
  $$SELECT done FROM public.crew_week(
      '00000000-0000-4000-f000-000000001310',
      '2099-06-08 00:00:00-07:00'::timestamptz)
    WHERE username = 'crewweek_f'$$,
  $$VALUES (1)$$,
  'a session 23:30 local the Sunday before a UTC-7 week start does not count; 00:30 Monday does');

SELECT * FROM finish();
ROLLBACK;
