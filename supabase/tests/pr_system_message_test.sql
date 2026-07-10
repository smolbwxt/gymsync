BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a3', 'pa@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a3', 'pr_user_a');
INSERT INTO groups (id, name, created_by) VALUES
  ('50000000-0000-0000-0000-000000000001', 'PR Crew',
   '00000000-0000-0000-0000-0000000000a3');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('50000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3', 'admin');

-- Use a seeded exercise (Phase 1 seed guarantees bench-press exists)
-- and a session owned by the user (set_logs requires session context as in Phase 1)
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('60000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('60000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3');

-- First lift: 100 lbs -> PR (no history)
INSERT INTO set_logs (id, session_id, user_id, exercise_id, set_index, reps, weight)
SELECT '70000000-0000-0000-0000-000000000001',
       '60000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-0000000000a3',
       e.id, 1, 5, 100
FROM exercises e WHERE e.slug = 'bench-press';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='50000000-0000-0000-0000-000000000001' AND kind='system_pr'$$,
  ARRAY[1], 'first lift announces a PR in group chat');

SELECT results_eq(
  $$SELECT (payload->>'weight')::numeric::int FROM chat_messages
    WHERE kind='system_pr'
      AND group_id='50000000-0000-0000-0000-000000000001'$$,
  ARRAY[100], 'payload carries the PR weight');

-- Second lift: 90 lbs -> NOT a PR, no new message
INSERT INTO set_logs (id, session_id, user_id, exercise_id, set_index, reps, weight)
SELECT '70000000-0000-0000-0000-000000000002',
       '60000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-0000000000a3',
       e.id, 2, 5, 90
FROM exercises e WHERE e.slug = 'bench-press';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='50000000-0000-0000-0000-000000000001' AND kind='system_pr'$$,
  ARRAY[1], 'lower weight does not announce');

SELECT * FROM finish();
ROLLBACK;
