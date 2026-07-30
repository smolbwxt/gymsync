BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Rotation presence (20260802000001): the turn never lands on someone who
-- hasn't checked in, and a late joiner appends to the rotation's end.
-- Fixture block: 09xx UUIDs. A (organizer, ready, order 1), B (INVITED —
-- never checked in, order 2), C (ready, order 3), D (invited, order 4).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000901', 'rot-a@test.local'),
  ('00000000-0000-4000-f000-000000000902', 'rot-b@test.local'),
  ('00000000-0000-4000-f000-000000000903', 'rot-c@test.local'),
  ('00000000-0000-4000-f000-000000000904', 'rot-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000901', 'rot_a'),
  ('00000000-0000-4000-f000-000000000902', 'rot_b'),
  ('00000000-0000-4000-f000-000000000903', 'rot_c'),
  ('00000000-0000-4000-f000-000000000904', 'rot_d');

INSERT INTO sessions (id, organizer_id, state, started_at, current_turn_user_id)
VALUES ('00000000-0000-4000-f000-000000000910',
        '00000000-0000-4000-f000-000000000901',
        'in_progress', now(),
        '00000000-0000-4000-f000-000000000901');

INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000901', 1, 'ready'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000902', 2, 'invited'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000903', 3, 'ready'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000904', 4, 'invited');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';

-- 1. THE DEFECT UNDER TEST: advancing from A skips B (invited, order 2)
--    and lands on C (ready, order 3). Before this migration it landed on B
--    and the whole room waited on a ghost.
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000910')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000903')$$,
  'advance skips a never-checked-in participant');

-- 2. The wrap ALSO skips invited: from C (order 3), D (invited, 4) is
--    passed over and the wrap returns to A (ready, 1).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000903';
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000910')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000901')$$,
  'the wrap skips invited participants too');

RESET role;

-- 3. LATE JOINER: B checks in while the session is in progress → appended
--    at the rotation's end (max order 4 + 1 = 5), not their original slot.
UPDATE session_participants
   SET check_in_state = 'late'
 WHERE session_id = '00000000-0000-4000-f000-000000000910'
   AND user_id    = '00000000-0000-4000-f000-000000000902';
SELECT results_eq(
  $$SELECT turn_order FROM session_participants
     WHERE session_id = '00000000-0000-4000-f000-000000000910'
       AND user_id    = '00000000-0000-4000-f000-000000000902'$$,
  $$VALUES (5)$$,
  'a mid-session check-in appends to the rotation end');

-- 4. …and once present, the rotation reaches them: from A (order 1), C is
--    next (3); from C, B is now next at their NEW slot (5), passing D.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000910')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000903')$$,
  'present participants rotate normally');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000903';
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000910')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000902')$$,
  'a checked-in late joiner takes their end-of-line turn');

RESET role;

-- 5. A re-transition within presence (late → ready) does NOT reshuffle:
--    only the arrival edge moves you, exactly once.
UPDATE session_participants
   SET check_in_state = 'ready'
 WHERE session_id = '00000000-0000-4000-f000-000000000910'
   AND user_id    = '00000000-0000-4000-f000-000000000902';
SELECT results_eq(
  $$SELECT turn_order FROM session_participants
     WHERE session_id = '00000000-0000-4000-f000-000000000910'
       AND user_id    = '00000000-0000-4000-f000-000000000902'$$,
  $$VALUES (5)$$,
  'late -> ready keeps the assigned end-of-line slot');

-- 6. Pre-start check-ins keep their organizer-assigned order: a lobby_open
--    session's transition must not touch turn_order.
INSERT INTO sessions (id, organizer_id, state, current_turn_user_id)
VALUES ('00000000-0000-4000-f000-000000000911',
        '00000000-0000-4000-f000-000000000901', 'lobby_open',
        '00000000-0000-4000-f000-000000000901');
INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000000911', '00000000-0000-4000-f000-000000000901', 1, 'ready'),
  ('00000000-0000-4000-f000-000000000911', '00000000-0000-4000-f000-000000000904', 2, 'invited');
UPDATE session_participants
   SET check_in_state = 'ready'
 WHERE session_id = '00000000-0000-4000-f000-000000000911'
   AND user_id    = '00000000-0000-4000-f000-000000000904';
SELECT results_eq(
  $$SELECT turn_order FROM session_participants
     WHERE session_id = '00000000-0000-4000-f000-000000000911'
       AND user_id    = '00000000-0000-4000-f000-000000000904'$$,
  $$VALUES (2)$$,
  'a pre-start check-in keeps its assigned order');

-- 7. no_show participants remain excluded (the original guarantee holds).
UPDATE session_participants
   SET check_in_state = 'no_show'
 WHERE session_id = '00000000-0000-4000-f000-000000000910'
   AND user_id    = '00000000-0000-4000-f000-000000000904';
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000902';
SELECT results_eq(
  $$SELECT public.advance_turn('00000000-0000-4000-f000-000000000910')::text$$,
  $$VALUES ('00000000-0000-4000-f000-000000000901')$$,
  'no_show stays excluded after the presence change');

SELECT * FROM finish();
ROLLBACK;
