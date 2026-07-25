BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

-- Fixture users (pattern from curation_test.sql: insert auth.users +
-- profiles rows inside the rolled-back txn).
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-b000-000000000201', 'prog-test-owner@test.local'),
  ('00000000-0000-4000-b000-000000000202', 'prog-test-other@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-b000-000000000201', 'prog_owner'),
  ('00000000-0000-4000-b000-000000000202', 'prog_other');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-b000-000000000201';

-- 1. Owner enrolls in a program.
SELECT lives_ok(
  $$INSERT INTO program_enrollments (user_id, template_slug, focus, baseline, started_on, weeks)
    VALUES ('00000000-0000-4000-b000-000000000201', 'march-to-1rm',
            '{"exercise_ids":["11111111-1111-4111-8111-111111111111"]}',
            '{"11111111-1111-4111-8111-111111111111": 225}', CURRENT_DATE, 8)$$,
  'owner enrolls in a program');

-- 2. …and reads it back.
SELECT is(
  (SELECT count(*) FROM program_enrollments
   WHERE user_id = '00000000-0000-4000-b000-000000000201')::int,
  1, 'owner reads own enrollment');

-- 3. Cannot enroll on someone else's behalf.
SELECT throws_ok(
  $$INSERT INTO program_enrollments (user_id, template_slug, focus, baseline, started_on, weeks)
    VALUES ('00000000-0000-4000-b000-000000000202', 'march-to-1rm', '{}', '{}', CURRENT_DATE, 8)$$,
  '42501', NULL, 'cannot enroll as another user');

-- 4. One active program at a time (partial unique index).
SELECT throws_ok(
  $$INSERT INTO program_enrollments (user_id, template_slug, focus, baseline, started_on, weeks)
    VALUES ('00000000-0000-4000-b000-000000000201', 'leg-strength-block', '{}', '{}', CURRENT_DATE, 6)$$,
  '23505', NULL, 'second concurrent active enrollment rejected');

-- 5. Repeat-week shift: owner moves started_on forward (spec: manual
--    deload = shift started_on 7 days via plain owner UPDATE).
SELECT lives_ok(
  $$UPDATE program_enrollments SET started_on = started_on + 7
    WHERE user_id = '00000000-0000-4000-b000-000000000201' AND ended_at IS NULL$$,
  'owner shifts started_on (repeat week)');

-- 6-7. Cross-user isolation: other user sees nothing, and their UPDATE
--      silently matches zero rows (FOR ALL USING) — owner's row unchanged.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-b000-000000000202';
SELECT is(
  (SELECT count(*) FROM program_enrollments)::int,
  0, 'other user sees no enrollments');
UPDATE program_enrollments SET weeks = 1
  WHERE user_id = '00000000-0000-4000-b000-000000000201';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-b000-000000000201';
SELECT is(
  (SELECT weeks FROM program_enrollments
   WHERE user_id = '00000000-0000-4000-b000-000000000201' AND ended_at IS NULL),
  8, 'cross-user UPDATE touched nothing');

-- 8. ended_reason requires ended_at (pairing CHECK).
SELECT throws_ok(
  $$UPDATE program_enrollments SET ended_reason = 'completed'
    WHERE user_id = '00000000-0000-4000-b000-000000000201' AND ended_at IS NULL$$,
  '23514', NULL, 'ended_reason without ended_at rejected');

-- 9-10. Ending frees the active slot; a new enrollment then succeeds.
SELECT lives_ok(
  $$UPDATE program_enrollments SET ended_at = now(), ended_reason = 'abandoned'
    WHERE user_id = '00000000-0000-4000-b000-000000000201' AND ended_at IS NULL$$,
  'owner ends their program');
SELECT lives_ok(
  $$INSERT INTO program_enrollments (user_id, template_slug, focus, baseline, started_on, weeks)
    VALUES ('00000000-0000-4000-b000-000000000201', 'hypertrophy-block', '{"muscle_group":"quads"}', '{}', CURRENT_DATE, 8)$$,
  'new enrollment after ending the previous one');

-- 11. weeks bounds CHECK — as user 202 (who owns no rows) so RLS passes
--     and the CHECK is the only thing that can reject.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-b000-000000000202';
SELECT throws_ok(
  $$INSERT INTO program_enrollments (user_id, template_slug, focus, baseline, started_on, weeks)
    VALUES ('00000000-0000-4000-b000-000000000202', 'march-to-1rm', '{}', '{}', CURRENT_DATE, 0)$$,
  '23514', NULL, 'weeks = 0 rejected by CHECK');

SELECT * FROM finish();
ROLLBACK;
