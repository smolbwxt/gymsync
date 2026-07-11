BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-00000000a1a1', 'lj-a@t.com'),
  ('00000000-0000-0000-0000-00000000b1b1', 'lj-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-00000000a1a1', 'lj_user_a'),
  ('00000000-0000-0000-0000-00000000b1b1', 'lj_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('ff220000-0000-0000-0000-000000000001', 'Joiner Crew',
   '00000000-0000-0000-0000-00000000a1a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('ff220000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-00000000a1a1', 'admin');
-- one future scheduled, one past scheduled, one started
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('ab330000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'scheduled', now() + interval '2 days'),
  ('ab330000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'scheduled', now() - interval '2 days'),
  ('ab330000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'in_progress', now() + interval '3 days');

-- B joins the group → invited to the FUTURE scheduled session only
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('ff220000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-00000000b1b1', 'member');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY[1], 'new member invited to exactly one session');
SELECT results_eq(
  $$SELECT session_id::text FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY['ab330000-0000-0000-0000-000000000001'], 'the future scheduled one');
SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY['invited'], 'as invited');

SELECT * FROM finish();
ROLLBACK;
