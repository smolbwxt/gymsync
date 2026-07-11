BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a8', 'pa8@t.com'),
  ('00000000-0000-0000-0000-0000000000b8', 'pb8@t.com'),
  ('00000000-0000-0000-0000-0000000000c8', 'pc8@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a8', 'pr_user_a8'),
  ('00000000-0000-0000-0000-0000000000b8', 'pr_user_b8'),
  ('00000000-0000-0000-0000-0000000000c8', 'pr_user_c8');
INSERT INTO routines (id, owner_id, name) VALUES
  ('e0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a8', 'Lobby Routine');
INSERT INTO sessions (id, organizer_id, routine_id, state, scheduled_for) VALUES
  ('f0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a8',
   'e0000000-0000-0000-0000-000000000001', 'editing', now());
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a8', 'ready'),
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b8', 'online');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a8';

-- Positive: participant proposes an add (using seeded bench-press)
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload, affects_exercise_id)
    SELECT '11110000-0000-0000-0000-000000000001',
           'f0000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-0000000000a8',
           'add_exercise',
           jsonb_build_object('exercise_id', e.id, 'position', 1,
                              'target_sets', 4, 'target_reps', '6'),
           e.id
    FROM exercises e WHERE e.slug='bench-press'$$,
  'participant can propose');

-- Proposer's approve vote was auto-cast
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposal_votes
    WHERE proposal_id='11110000-0000-0000-0000-000000000001' AND vote='approve'$$,
  ARRAY[1], 'proposer auto-approves own proposal');

-- Conflict lock: second open proposal on same exercise rejected
SELECT throws_ok(
  $$INSERT INTO routine_proposals (session_id, proposer_id, proposal_type, payload, affects_exercise_id)
    SELECT 'f0000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-0000000000a8',
           'remove_exercise', '{}'::jsonb, e.id
    FROM exercises e WHERE e.slug='bench-press'$$,
  'P0001', 'this exercise has an open proposal',
  'conflicting concurrent edit is serialized');

-- Outsider can neither read nor vote
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c8';
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposals$$,
  ARRAY[0], 'outsider cannot read proposals');
SELECT throws_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('11110000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c8', 'approve')$$,
  '42501', NULL, 'outsider cannot vote');

-- B approves -> unanimous (2/2) -> approved + applied to routine_exercises
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b8';
SELECT lives_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('11110000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b8', 'approve')$$,
  'second participant approves');
SELECT results_eq(
  $$SELECT status FROM routine_proposals
    WHERE id='11110000-0000-0000-0000-000000000001'$$,
  ARRAY['approved'], 'unanimous approval resolves proposal');
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises re
    JOIN exercises e ON e.id = re.exercise_id
    WHERE re.routine_id='e0000000-0000-0000-0000-000000000001'
      AND e.slug='bench-press'$$,
  ARRAY[1], 'approved add_exercise applied to routine');

-- Veto path: B proposes, A vetoes -> vetoed, not applied
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload)
    VALUES ('11110000-0000-0000-0000-000000000002',
            'f0000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-0000000000b8',
            'reorder', '{"ordered_routine_exercise_ids":[]}'::jsonb)$$,
  'participant proposes reorder');
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a8';
-- Split veto into two assertions: PostgreSQL CTE snapshot isolation hides trigger
-- updates from the outer SELECT in the same CTE, so we separate the INSERT and
-- the status check to guarantee the trigger's UPDATE is committed before reading.
SELECT lives_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('11110000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000a8', 'veto')$$,
  'veto vote is accepted');
SELECT results_eq(
  $$SELECT status FROM routine_proposals
    WHERE id='11110000-0000-0000-0000-000000000002'$$,
  ARRAY['vetoed'], 'any veto kills the proposal');

SELECT * FROM finish();
ROLLBACK;
