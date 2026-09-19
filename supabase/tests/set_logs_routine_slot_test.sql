BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Migration under test: 20260919000102_set_logs_routine_slot.sql
-- (set_logs.routine_exercise_id uuid, no FK, no backfill, and
-- set_logs_session_slot_idx). Phase C1 D4. Fixture block: 18xx UUIDs
-- (constraint 17 -- this plan claims 17xx for D2 and 18xx for D4).
--
--   OW    = ...1801 the owner/lifter -- owns routine R, organizes S, and
--           logs both set_logs rows below
--   OTHER = ...1802 a different lifter -- used only to prove the existing
--           INSERT policy still rejects a row naming someone else's
--           user_id; this column adds no new door
--   EX    = ...1811 the exercise both routine_exercises rows and both
--           set_logs rows reference
--   R     = ...1820 OW's routine     RE = ...1830 R's one slot (position 1)
--   S     = ...1840 OW's session, organizer OW
--   SL1   = ...1850 a set logged WITH routine_exercise_id = RE
--   SL2   = ...1851 a set logged WITHOUT it -- the pre-column shape

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000001801', 'slot-ow@test.local'),
  ('00000000-0000-4000-e000-000000001802', 'slot-other@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000001801', 'slot_ow'),
  ('00000000-0000-4000-e000-000000001802', 'slot_other');

INSERT INTO exercises (id, name, slug, category, primary_muscle, equipment) VALUES
  ('00000000-0000-4000-e000-000000001811', 'Slot Test Deadlift', 'slot-test-deadlift', 'compound', 'back', 'barbell');

INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('00000000-0000-4000-e000-000000001820', '00000000-0000-4000-e000-000000001801', 'Slot Test Routine', 'private');
INSERT INTO routine_exercises (id, routine_id, exercise_id, position) VALUES
  ('00000000-0000-4000-e000-000000001830', '00000000-0000-4000-e000-000000001820',
   '00000000-0000-4000-e000-000000001811', 1);

INSERT INTO sessions (id, routine_id, organizer_id, state, started_at) VALUES
  ('00000000-0000-4000-e000-000000001840', '00000000-0000-4000-e000-000000001820',
   '00000000-0000-4000-e000-000000001801', 'in_progress', now());
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-4000-e000-000000001840', '00000000-0000-4000-e000-000000001801', 'ready');

-- 1-4. The column and its index, checked before any role switch
-- (precedent: session_participant_energy_test.sql:36-37).
SELECT has_column('public', 'set_logs', 'routine_exercise_id',
  'set_logs.routine_exercise_id exists');
SELECT col_is_null('public', 'set_logs', 'routine_exercise_id',
  'routine_exercise_id is nullable -- no backfill, and a freeform set writes NULL forever');
SELECT col_type_is('public', 'set_logs', 'routine_exercise_id', 'uuid',
  'routine_exercise_id is uuid');
SELECT has_index('public', 'set_logs', 'set_logs_session_slot_idx',
  'set_logs_session_slot_idx exists');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001801';

-- 5-6. As the owner: an insert WITH routine_exercise_id succeeds, and a
-- SECOND statement reads it back (constraint 17).
SELECT lives_ok(
  $$INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, routine_exercise_id)
    VALUES ('00000000-0000-4000-e000-000000001850',
            '00000000-0000-4000-e000-000000001801',
            '00000000-0000-4000-e000-000000001840',
            '00000000-0000-4000-e000-000000001811', 1,
            '00000000-0000-4000-e000-000000001830')$$,
  'OW logs a set naming its routine slot');
SELECT results_eq(
  $$SELECT routine_exercise_id FROM set_logs
     WHERE id = '00000000-0000-4000-e000-000000001850'$$,
  $$VALUES ('00000000-0000-4000-e000-000000001830'::uuid)$$,
  'the logged set reads back the same slot id');

-- 7. As the owner: an insert WITHOUT it succeeds and reads back NULL in
-- the same statement's RETURNING -- the pre-column shape still works,
-- which is what "no backfill" costs.
SELECT results_eq(
  $$INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index)
    VALUES ('00000000-0000-4000-e000-000000001851',
            '00000000-0000-4000-e000-000000001801',
            '00000000-0000-4000-e000-000000001840',
            '00000000-0000-4000-e000-000000001811', 2)
    RETURNING routine_exercise_id$$,
  $$VALUES (NULL::uuid)$$,
  'a set logged without a slot still inserts and reads back NULL');

-- 8. As OTHER: an insert naming someone else's (OW's) user_id is refused
-- by the existing "users can insert their own set logs" policy -- pinned
-- so the new column cannot be read as a new door (precedent: 42501 for a
-- WITH CHECK failure, set_logs_delete_test.sql-adjacent idiom, curation_
-- test.sql:58).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001802';
SELECT throws_ok(
  $$INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, routine_exercise_id)
    VALUES ('00000000-0000-4000-e000-000000001852',
            '00000000-0000-4000-e000-000000001801',
            '00000000-0000-4000-e000-000000001840',
            '00000000-0000-4000-e000-000000001811', 3,
            '00000000-0000-4000-e000-000000001830')$$,
  '42501', NULL,
  'OTHER cannot log a set as OW, slot column or not');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001801';

-- 9-10. No FK: deleting the routine_exercises row leaves SL1's
-- routine_exercise_id in place, unchanged -- a recorded intent, not a
-- live reference. Two statements, never a data-modifying CTE (constraint
-- 17): the DELETE first, then a separate SELECT proves the set_logs row
-- (and its value) survived.
SELECT lives_ok(
  $$DELETE FROM routine_exercises WHERE id = '00000000-0000-4000-e000-000000001830'$$,
  'the owner deletes the routine_exercises row a logged set points to');
SELECT results_eq(
  $$SELECT routine_exercise_id FROM set_logs
     WHERE id = '00000000-0000-4000-e000-000000001850'$$,
  $$VALUES ('00000000-0000-4000-e000-000000001830'::uuid)$$,
  'the logged set still names the now-deleted slot -- no FK, no CASCADE, no SET NULL');

SELECT * FROM finish();
ROLLBACK;
