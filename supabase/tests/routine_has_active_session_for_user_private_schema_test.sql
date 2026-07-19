-- Debt-zero sprint / Task 1, item 1: routine_has_active_session_for_user()
-- relocated to private schema
-- (20260727000002_routine_has_active_session_for_user_private_schema.sql).
--
-- Sole dependent: routine_exercises SELECT ("session participants read
-- session routine exercises"). The routine used throughout is deliberately
-- visibility = 'private' and owned by a THIRD user (Otto) who is neither
-- fixture participant — this isolates the policy under test from the
-- sibling permissive policy "routine_exercises follow parent routine
-- visibility" (owner-or-public), so any positive result here can only come
-- from private.routine_has_active_session_for_user. The no-widening proof
-- uses a SECOND routine/session/participant to confirm the function checks
-- BOTH the routine_id and the user_id per call, not just "is this user a
-- participant of ANY session."
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('f5000000-0000-0000-0000-0000000000a1', 'f5a1@t.com'),  -- Otto: owns both routines, participant of neither
  ('f5000000-0000-0000-0000-0000000000a2', 'f5a2@t.com'),  -- Priya: participant of the session tied to routine 1
  ('f5000000-0000-0000-0000-0000000000a3', 'f5a3@t.com'),  -- Xena: participant of the session tied to routine 2 (different routine)
  ('f5000000-0000-0000-0000-0000000000a4', 'f5a4@t.com');  -- Quinn: outsider, no session participation anywhere
INSERT INTO profiles (id, username) VALUES
  ('f5000000-0000-0000-0000-0000000000a1', 'f5_otto'),
  ('f5000000-0000-0000-0000-0000000000a2', 'f5_priya'),
  ('f5000000-0000-0000-0000-0000000000a3', 'f5_xena'),
  ('f5000000-0000-0000-0000-0000000000a4', 'f5_quinn');

INSERT INTO exercises (id, name, slug, category, primary_muscle, equipment) VALUES
  ('f5000000-0000-0000-0000-000000000e01', 'Sweep Test Squat', 'f5-sweep-test-squat', 'compound', 'quads', 'barbell');

-- Routine 1 (private, owned by Otto) — the routine under test.
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('f5000000-0000-0000-0000-000000000c01', 'f5000000-0000-0000-0000-0000000000a1', 'Routine One', 'private');
INSERT INTO routine_exercises (id, routine_id, exercise_id, position) VALUES
  ('f5000000-0000-0000-0000-000000000d01', 'f5000000-0000-0000-0000-000000000c01',
   'f5000000-0000-0000-0000-000000000e01', 1);
INSERT INTO sessions (id, routine_id, organizer_id, state) VALUES
  ('f5000000-0000-0000-0000-000000000b01', 'f5000000-0000-0000-0000-000000000c01',
   'f5000000-0000-0000-0000-0000000000a1', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('f5000000-0000-0000-0000-000000000b01', 'f5000000-0000-0000-0000-0000000000a2');  -- Priya

-- Routine 2 (private, owned by Otto) — unrelated routine, unrelated session,
-- used only for the no-widening proof.
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('f5000000-0000-0000-0000-000000000c02', 'f5000000-0000-0000-0000-0000000000a1', 'Routine Two', 'private');
INSERT INTO sessions (id, routine_id, organizer_id, state) VALUES
  ('f5000000-0000-0000-0000-000000000b02', 'f5000000-0000-0000-0000-000000000c02',
   'f5000000-0000-0000-0000-0000000000a1', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('f5000000-0000-0000-0000-000000000b02', 'f5000000-0000-0000-0000-0000000000a3');  -- Xena

SET LOCAL role authenticated;

-- ============================================================
-- 1-3. routine_exercises SELECT ("session participants read session
-- routine exercises"), both directions + no-widening.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f5000000-0000-0000-0000-0000000000a2';  -- Priya (participant of routine 1's session)
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises WHERE routine_id = 'f5000000-0000-0000-0000-000000000c01'$$,
  ARRAY[1],
  'positive: a session participant reads a private routine''s exercises via private.routine_has_active_session_for_user'
);

SET LOCAL request.jwt.claim.sub = 'f5000000-0000-0000-0000-0000000000a4';  -- Quinn (outsider, no session participation)
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises WHERE routine_id = 'f5000000-0000-0000-0000-000000000c01'$$,
  ARRAY[0],
  'negative: an outsider with no session participation cannot read the private routine''s exercises'
);

SET LOCAL request.jwt.claim.sub = 'f5000000-0000-0000-0000-0000000000a3';  -- Xena (participant of routine 2's session, NOT routine 1's)
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises WHERE routine_id = 'f5000000-0000-0000-0000-000000000c01'$$,
  ARRAY[0],
  'no widening: a participant of a DIFFERENT routine''s session cannot read routine 1''s exercises'
);

-- ============================================================
-- 4-5. Relocation proof — direct-call correctness, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.routine_has_active_session_for_user(
      'f5000000-0000-0000-0000-000000000c01', 'f5000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true],
  'private.routine_has_active_session_for_user(routine 1, Priya) is true: Priya participates in routine 1''s session'
);

SELECT results_eq(
  $$SELECT private.routine_has_active_session_for_user(
      'f5000000-0000-0000-0000-000000000c01', 'f5000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false],
  'no widening: private.routine_has_active_session_for_user(routine 1, Xena) is false — Xena''s active session is tied to routine 2'
);

-- ============================================================
-- 6. Schema USAGE denial.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f5000000-0000-0000-0000-0000000000a2';  -- Priya

SELECT throws_ok(
  $$SELECT private.routine_has_active_session_for_user(
      'f5000000-0000-0000-0000-000000000c01', 'f5000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot name private.routine_has_active_session_for_user directly: no USAGE on schema private'
);

-- ============================================================
-- 7-8. Oracle closed: gone from public, calling by name fails.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'routine_has_active_session_for_user'$$,
  ARRAY[0],
  'public.routine_has_active_session_for_user no longer exists in any form — the oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.routine_has_active_session_for_user(
      'f5000000-0000-0000-0000-000000000c01', 'f5000000-0000-0000-0000-0000000000a2')$$,
  '42883', NULL,
  'calling public.routine_has_active_session_for_user by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
