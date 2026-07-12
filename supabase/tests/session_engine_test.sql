BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- Organizer A and participant B.
-- Session scheduled 10 minutes ago; A checked in on time, B is late.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'eng_a@t.com'),
  ('00000000-0000-0000-0000-0000000000c2', 'eng_b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'eng_user_a'),
  ('00000000-0000-0000-0000-0000000000c2', 'eng_user_b');

INSERT INTO sessions (id, organizer_id, state, scheduled_for, late_penalty) VALUES
  ('d0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000c1',
   'lobby_open',
   now() - interval '10 minutes',
   '{"exercise":"burpee","per_minute":5}'::jsonb);

-- A checked in on time (5 min before scheduled_for), B checked in 5 min late.
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('d0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000c1',
   'ready',
   now() - interval '15 minutes'),  -- on time (before scheduled_for)
  ('d0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000c2',
   'late',
   now() - interval '5 minutes');   -- 5 min late (after scheduled_for)

SET LOCAL role authenticated;

-- ── Test 1: Non-organizer cannot start session ────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';
SELECT throws_ok(
  $$SELECT public.start_session('d0000000-0000-0000-0000-000000000001')$$,
  'P0001',
  'only the organizer may start the session',
  'non-organizer start raises P0001');

-- ── Test 2: Organizer can start session ───────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
SELECT lives_ok(
  $$SELECT public.start_session('d0000000-0000-0000-0000-000000000001')$$,
  'organizer starts session successfully');

-- ── Test 3: Session state is now in_progress ──────────────────────────────────
SELECT results_eq(
  $$SELECT state FROM sessions WHERE id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES ('in_progress')$$,
  'session state is in_progress after start');

-- ── Test 4: turn_orders assigned by check-in time (A=1, B=2) ─────────────────
SELECT results_eq(
  $$SELECT user_id::text, turn_order
    FROM session_participants
    WHERE session_id = 'd0000000-0000-0000-0000-000000000001'
    ORDER BY turn_order$$,
  $$VALUES ('00000000-0000-0000-0000-0000000000c1', 1),
           ('00000000-0000-0000-0000-0000000000c2', 2)$$,
  'turn_orders assigned in check-in order (A first, B second)');

-- ── Test 5: current_turn_user_id = A (first by turn_order) ───────────────────
SELECT results_eq(
  $$SELECT current_turn_user_id::text
    FROM sessions WHERE id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES ('00000000-0000-0000-0000-0000000000c1')$$,
  'current_turn_user_id is A (turn_order 1)');

-- ── Test 6: B's burpees_owed computed (5 per-minute × ~5 late minutes > 0) ────
SELECT ok(
  (SELECT burpees_owed > 0
   FROM session_participants
   WHERE session_id = 'd0000000-0000-0000-0000-000000000001'
     AND user_id = '00000000-0000-0000-0000-0000000000c2'),
  'late participant B has burpees_owed > 0 after start');

-- ── Test 7: B (not current lifter) advance_turn fails 'not your turn' ─────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';
SELECT throws_ok(
  $$SELECT public.advance_turn('d0000000-0000-0000-0000-000000000001')$$,
  'P0001',
  'not your turn',
  'non-current participant cannot advance turn');

-- ── Test 8: A (current lifter) advance_turn returns B's id ────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
SELECT results_eq(
  $$SELECT public.advance_turn('d0000000-0000-0000-0000-000000000001')::text$$,
  $$VALUES ('00000000-0000-0000-0000-0000000000c2')$$,
  'A advance_turn returns B uuid');

-- ── Test 9: current_turn_started_at is recent (within last 5 seconds) ─────────
SELECT ok(
  (SELECT current_turn_started_at >= now() - interval '5 seconds'
   FROM sessions WHERE id = 'd0000000-0000-0000-0000-000000000001'),
  'current_turn_started_at is freshly updated after advance');

-- ── Test 10: B advance_turn wraps around to A ─────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';
SELECT results_eq(
  $$SELECT public.advance_turn('d0000000-0000-0000-0000-000000000001')::text$$,
  $$VALUES ('00000000-0000-0000-0000-0000000000c1')$$,
  'B advance_turn wraps around to A');

-- ── Test 11: B cannot zero own burpees_owed via direct UPDATE ─────────────────
SELECT throws_ok(
  $$UPDATE session_participants
    SET burpees_owed = 0
    WHERE session_id = 'd0000000-0000-0000-0000-000000000001'
      AND user_id = '00000000-0000-0000-0000-0000000000c2'$$,
  'P0001',
  'penalty fields are read-only',
  'direct self-update of burpees_owed raises P0001');

-- ── Test 12: B can still update own check_in_state (non-penalty column) ───────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants
      SET check_in_state = 'ready'
      WHERE session_id = 'd0000000-0000-0000-0000-000000000001'
        AND user_id = '00000000-0000-0000-0000-0000000000c2'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1],
  'B can update own check_in_state (non-penalty field still allowed)');

SELECT * FROM finish();
ROLLBACK;
