-- 20260803000003: session participants read the session's routine, and
-- the 'left' check-in state exists. (The routines-policy gap was the
-- 2026-07-31 field bug: members' lobbies said "No routine yet" against a
-- private routine the organizer had chosen.)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

SET LOCAL role postgres;
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000e0001', 'rv_owner@t.com'),
  ('00000000-0000-0000-0000-0000000e0002', 'rv_member@t.com'),
  ('00000000-0000-0000-0000-0000000e0003', 'rv_outsider@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000e0001', 'rv_owner'),
  ('00000000-0000-0000-0000-0000000e0002', 'rv_member'),
  ('00000000-0000-0000-0000-0000000e0003', 'rv_outsider');

INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('e0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000e0001',
   'RV Private Routine', 'private');

INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('e0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000e0001',
   'e0000000-0000-0000-0000-0000000000b1', 'scheduled', NULL);

INSERT INTO session_participants (session_id, user_id, check_in_state, turn_order) VALUES
  ('e0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000e0001', 'ready', 1),
  ('e0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000e0002', 'invited', 2);

-- Member (not the owner) reads the private routine through the session.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e0002';
SELECT ok(
  (SELECT count(*) FROM routines WHERE id = 'e0000000-0000-0000-0000-0000000000b1') = 1,
  'session participant can read the session''s private routine (20260803000003)'
);

-- An outsider still cannot.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000e0003';
SELECT ok(
  (SELECT count(*) FROM routines WHERE id = 'e0000000-0000-0000-0000-0000000000b1') = 0,
  'non-participant still cannot read a private routine'
);

-- 'left' is a legal check-in state; a leaver drops out of the presence trio.
SET LOCAL role postgres;
UPDATE session_participants
   SET check_in_state = 'left'
 WHERE session_id = 'e0000000-0000-0000-0000-0000000000c1'
   AND user_id = '00000000-0000-0000-0000-0000000e0001';
SELECT ok(
  (SELECT check_in_state FROM session_participants
    WHERE session_id = 'e0000000-0000-0000-0000-0000000000c1'
      AND user_id = '00000000-0000-0000-0000-0000000e0001') = 'left',
  '''left'' is an accepted check_in_state'
);
SELECT ok(
  (SELECT count(*) FROM session_participants
    WHERE session_id = 'e0000000-0000-0000-0000-0000000000c1'
      AND check_in_state IN ('online', 'ready', 'late')) = 0,
  'a leaver is outside the presence trio advance_turn selects from'
);

SELECT * FROM finish();
ROLLBACK;
