BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a9', 'rb@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a9', 'rb_user_a');
-- Routine-less session, single participant (auto-approve on propose)
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('88880000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a9', 'lobby_open', now());
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('88880000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a9', 'ready');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a9';

-- Propose add on the routine-less session: must NOT error, must auto-approve
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload)
    SELECT '99990000-0000-0000-0000-000000000001',
           '88880000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-0000000000a9',
           'add_exercise',
           jsonb_build_object('exercise_id', e.id, 'target_sets', 4, 'target_reps', '6')
    FROM exercises e WHERE e.slug='bench-press'$$,
  'add proposal on routine-less session succeeds');

SELECT results_eq(
  $$SELECT status FROM routine_proposals WHERE id='99990000-0000-0000-0000-000000000001'$$,
  ARRAY['approved'], 'proposal auto-approved');

SELECT results_eq(
  $$SELECT (routine_id IS NOT NULL)::int FROM sessions
    WHERE id='88880000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'session gained a bootstrapped routine');

SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises re
    JOIN sessions s ON s.routine_id = re.routine_id
    WHERE s.id='88880000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'exercise applied to the bootstrapped routine');

SELECT * FROM finish();
ROLLBACK;
