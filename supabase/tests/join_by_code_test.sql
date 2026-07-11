BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

-- Fixtures
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'jbc_a@t.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'jbc_b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'jbc_user_a'),
  ('00000000-0000-0000-0000-0000000000e2', 'jbc_user_b');

-- Create a scheduled session with a room code, owned by user A
-- (Insert as service role so RLS is bypassed for fixture setup)
INSERT INTO sessions (id, organizer_id, state, room_code)
VALUES (
  'c0000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000000e1',
  'scheduled',
  'ABC123'
);
-- Also insert user A as organizer participant
INSERT INTO session_participants (session_id, user_id, check_in_state)
VALUES (
  'c0000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000000e1',
  'online'
);

SET LOCAL role authenticated;

-- Positive: user B joins by code → gets session uuid back + participant row inserted
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e2';

SELECT results_eq(
  $$SELECT public.join_session_by_code('ABC123')$$,
  $$VALUES ('c0000000-0000-0000-0000-000000000001'::uuid)$$,
  'join_session_by_code returns the session uuid'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'
      AND user_id    = '00000000-0000-0000-0000-0000000000e2'
      AND check_in_state = 'online'$$,
  ARRAY[1],
  'participant row created for joining user'
);

-- Negative: garbage code raises P0001 'invalid room code'
SELECT throws_ok(
  $$SELECT public.join_session_by_code('XXXXXX')$$,
  'P0001',
  'invalid room code',
  'bad code raises invalid room code error'
);

SELECT * FROM finish();
ROLLBACK;
