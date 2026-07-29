BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

-- Rotation guard (20260801000001): advance_turn is replayable.
-- Fixture block: 08xx UUIDs. Three lifters A/B/C in turn_order 1/2/3,
-- session in_progress with A up. A is also the organizer.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000801', 'turn-a@test.local'),
  ('00000000-0000-4000-f000-000000000802', 'turn-b@test.local'),
  ('00000000-0000-4000-f000-000000000803', 'turn-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000801', 'turn_a'),
  ('00000000-0000-4000-f000-000000000802', 'turn_b'),
  ('00000000-0000-4000-f000-000000000803', 'turn_c');

INSERT INTO sessions (id, organizer_id, state, started_at, current_turn_user_id)
VALUES ('00000000-0000-4000-f000-000000000810',
        '00000000-0000-4000-f000-000000000801',
        'in_progress', now(),
        '00000000-0000-4000-f000-000000000801');

INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000000810', '00000000-0000-4000-f000-000000000801', 1, 'ready'),
  ('00000000-0000-4000-f000-000000000810', '00000000-0000-4000-f000-000000000802', 2, 'ready'),
  ('00000000-0000-4000-f000-000000000810', '00000000-0000-4000-f000-000000000803', 3, 'ready');

-- 1. A fresh session starts at version 0.
SELECT results_eq(
  $$SELECT turn_version FROM sessions WHERE id = '00000000-0000-4000-f000-000000000810'$$,
  $$VALUES (0)$$, 'turn_version starts at 0');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000801';

-- 2. The legacy one-argument call still binds (positional), and advances.
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000810')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000802')$$,
  'legacy positional call still advances A -> B');

-- 3. …and bumps the version.
SELECT results_eq(
  $$SELECT turn_version FROM sessions WHERE id = '00000000-0000-4000-f000-000000000810'$$,
  $$VALUES (1)$$, 'a successful advance bumps turn_version');

-- 4. THE BUG THIS EXISTS TO PREVENT: a queued advance that was created when
--    the version was 0, replayed now, must NOT shove the rotation forward a
--    second time. It returns the CURRENT holder and changes nothing.
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000810', 0)::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000802')$$,
  'stale replay (version 0, now 1) is a no-op returning the current holder');

SELECT results_eq(
  $$SELECT current_turn_user_id::text FROM sessions
    WHERE id = '00000000-0000-4000-f000-000000000810'$$,
  $$VALUES ('00000000-0000-4000-f000-000000000802')$$,
  'stale replay did not move the turn');

SELECT results_eq(
  $$SELECT turn_version FROM sessions WHERE id = '00000000-0000-4000-f000-000000000810'$$,
  $$VALUES (1)$$, 'stale replay did not bump the version');

-- 6. A CURRENT-version advance from the lifter whose turn it now is works.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000802';
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000810', 1)::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000803')$$,
  'matching version advances B -> C');

-- 7. The guard runs BEFORE authorization: a stale replay from someone who is
--    no longer the current lifter must be a silent no-op, NOT 'not your
--    turn'. (C is up; B replays an old advance.) This is the case that
--    would otherwise surface a false error to a user who did nothing wrong.
SELECT lives_ok(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000810', 1)$$,
  'stale replay from a non-current lifter is a no-op, not an auth error');

-- 8. But a LIVE (unversioned) call from a non-current, non-organizer lifter
--    is still rejected — the guard must not have opened a hole.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000802';
SELECT throws_ok(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000810')$$,
  'P0001', 'not your turn',
  'unversioned call from a non-current lifter is still rejected');

SELECT * FROM finish();
ROLLBACK;
