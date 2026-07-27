BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

-- Owner-delete policy (20260730000003). Fixture shape per rls_chat_test.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000000501', 'del-a@test.local'),
  ('00000000-0000-4000-e000-000000000502', 'del-b@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000000501', 'del_a'),
  ('00000000-0000-4000-e000-000000000502', 'del_b');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000501';

-- A solo session + one set for user A.
INSERT INTO sessions (id, state, organizer_id)
  VALUES ('70000000-0000-4000-e000-000000000501', 'in_progress',
          '00000000-0000-4000-e000-000000000501');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
  SELECT '80000000-0000-4000-e000-000000000501',
         '00000000-0000-4000-e000-000000000501',
         '70000000-0000-4000-e000-000000000501',
         id, 1, 5, 2255
  FROM exercises LIMIT 1;

-- 1. The fixture row exists (guards a vacuous pass below).
SELECT is(
  (SELECT count(*) FROM set_logs
   WHERE id = '80000000-0000-4000-e000-000000000501')::int,
  1, 'fixture set exists');

-- 2. Another user's DELETE silently matches nothing.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000502';
DELETE FROM set_logs WHERE id = '80000000-0000-4000-e000-000000000501';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000501';
SELECT is(
  (SELECT count(*) FROM set_logs
   WHERE id = '80000000-0000-4000-e000-000000000501')::int,
  1, 'non-owner DELETE touched nothing');

-- 3-4. The owner deletes their mistyped set, and it is gone.
SELECT lives_ok(
  $$DELETE FROM set_logs WHERE id = '80000000-0000-4000-e000-000000000501'$$,
  'owner deletes their own set');
SELECT is(
  (SELECT count(*) FROM set_logs
   WHERE id = '80000000-0000-4000-e000-000000000501')::int,
  0, 'the set is actually gone');

SELECT * FROM finish();
ROLLBACK;
