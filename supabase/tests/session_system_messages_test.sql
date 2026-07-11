BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a7', 'ss@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a7', 'ss_user_a');
INSERT INTO groups (id, name, created_by) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'Session Crew',
   '00000000-0000-0000-0000-0000000000a7');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('c0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a7', 'admin');

-- Scheduling a group session announces in chat
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a7',
   'c0000000-0000-0000-0000-000000000001',
   'scheduled', now() + interval '1 day');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[1], 'scheduling announces in group chat');

-- Transition to in_progress announces
UPDATE sessions SET state='in_progress', started_at=now()
  WHERE id='d0000000-0000-0000-0000-000000000001';
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[2], 'start announces');

-- Non-state UPDATE does not announce
UPDATE sessions SET current_turn_user_id='00000000-0000-0000-0000-0000000000a7'
  WHERE id='d0000000-0000-0000-0000-000000000001';
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[2], 'non-state update stays silent');

-- Ad-hoc (no group) session announces nowhere
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000a7', 'scheduled', now() + interval '1 day');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE kind='system_session'$$,
  ARRAY[2], 'groupless session announces nothing');

SELECT * FROM finish();
ROLLBACK;
