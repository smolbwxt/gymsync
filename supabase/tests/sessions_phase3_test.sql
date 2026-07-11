BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a6', 's3a@t.com'),
  ('00000000-0000-0000-0000-0000000000b6', 's3b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a6', 's3_user_a'),
  ('00000000-0000-0000-0000-0000000000b6', 's3_user_b');
INSERT INTO sessions (id, organizer_id, state, scheduled_for, late_penalty) VALUES
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a6', 'lobby_open',
   now() - interval '10 minutes',
   '{"exercise":"burpee","per_minute":5}'::jsonb);
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a6', 'ready'),
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000b6', 'invited');
-- A checked in on time (before scheduled_for), B checks in 10 min late
UPDATE session_participants SET check_in_at = now() - interval '15 minutes'
  WHERE user_id = '00000000-0000-0000-0000-0000000000a6';

SET LOCAL role authenticated;

-- Positive: B self-serves their own check-in
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b6';
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants
      SET check_in_state='ready', check_in_at=now(), check_in_method='geofence'
      WHERE session_id='b0000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000b6'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'participant can self check-in');

-- Negative: B cannot update A's participant row (0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants SET check_in_state='no_show'
      WHERE session_id='b0000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000a6'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'participant cannot modify another participant row');

-- Negative: non-organizer cannot run the lateness evaluator
SELECT throws_ok(
  $$SELECT public.evaluate_lateness('b0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'only the session organizer may evaluate lateness',
  'non-organizer cannot evaluate lateness');

-- Positive: organizer runs it; B owes 5/min for ~10 late minutes
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a6';
SELECT lives_ok(
  $$SELECT public.evaluate_lateness('b0000000-0000-0000-0000-000000000001')$$,
  'organizer evaluates lateness');
SELECT results_eq(
  $$SELECT (late_minutes BETWEEN 9 AND 11)::int, (burpees_owed = late_minutes*5)::int
    FROM session_participants
    WHERE session_id='b0000000-0000-0000-0000-000000000001'
      AND user_id='00000000-0000-0000-0000-0000000000b6'$$,
  $$VALUES (1, 1)$$,
  'late participant owes per-minute burpees');
SELECT results_eq(
  $$SELECT late_minutes FROM session_participants
    WHERE session_id='b0000000-0000-0000-0000-000000000001'
      AND user_id='00000000-0000-0000-0000-0000000000a6'$$,
  ARRAY[0], 'on-time participant owes nothing');

SELECT * FROM finish();
ROLLBACK;
