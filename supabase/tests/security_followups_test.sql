BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a4', 'sfa@t.com'),
  ('00000000-0000-0000-0000-0000000000b4', 'sfb@t.com'),
  ('00000000-0000-0000-0000-0000000000c4', 'sfc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a4', 'sf_user_a'),
  ('00000000-0000-0000-0000-0000000000b4', 'sf_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('80000000-0000-0000-0000-000000000001', 'SF Crew',
   '00000000-0000-0000-0000-0000000000a4');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a4', 'admin'),
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b4', 'member');
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('90000000-0000-0000-0000-000000000001',
   '80000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a4', 'text', 'hi');
-- B has a read-state row, then B is removed from the group
INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
  ('80000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000b4',
   '90000000-0000-0000-0000-000000000001');
DELETE FROM group_members
  WHERE group_id='80000000-0000-0000-0000-000000000001'
    AND user_id='00000000-0000-0000-0000-0000000000b4';

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b4';

-- Negative: expelled user cannot update their stale read-state row (0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_read_state SET last_read_message_id = NULL
      WHERE user_id='00000000-0000-0000-0000-0000000000b4' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'expelled member cannot update read state');

-- Positive: current member still can
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a4';
SELECT lives_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('80000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a4',
     '90000000-0000-0000-0000-000000000001')$$,
  'member writes own read state');
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_read_state SET last_read_message_id = NULL
      WHERE user_id='00000000-0000-0000-0000-0000000000a4' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'member updates own read state');

-- Reset to postgres role (bypass RLS) so the insert reaches the index, not RLS.
RESET ROLE;

-- Negative: username differing only in case collides (unique lower index, 23505)
SELECT throws_ok(
  $$INSERT INTO profiles (id, username)
    SELECT '00000000-0000-0000-0000-0000000000c4', 'SF_User_A'$$,
  '23505', NULL, 'case-variant username rejected by unique lower index');

SELECT * FROM finish();
ROLLBACK;
