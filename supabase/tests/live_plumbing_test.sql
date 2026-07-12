BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

-- ── Test 1: set_logs is in supabase_realtime publication ──────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'set_logs'$$,
  ARRAY[1],
  'set_logs is in supabase_realtime publication');

-- ── Fixtures: Organizer (C) and two participants (D, E) ──────────────────────────
-- Session scheduled 10 minutes ago, in lobby_open state (so joins can happen).
-- Insert all fixtures BEFORE setting role to authenticated

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000f0', 'lp_org_c@t.com'),
  ('00000000-0000-0000-0000-0000000000f1', 'lp_user_d@t.com'),
  ('00000000-0000-0000-0000-0000000000f2', 'lp_user_e@t.com'),
  ('00000000-0000-0000-0000-0000000000f3', 'lp_user_f@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000f0', 'lp_org_c'),
  ('00000000-0000-0000-0000-0000000000f1', 'lp_user_d'),
  ('00000000-0000-0000-0000-0000000000f2', 'lp_user_e'),
  ('00000000-0000-0000-0000-0000000000f3', 'lp_user_f');

INSERT INTO sessions (id, organizer_id, state, scheduled_for, room_code, late_penalty) VALUES
  ('d0000000-0000-0000-0000-000000000010',
   '00000000-0000-0000-0000-0000000000f0',
   'lobby_open',
   now() - interval '10 minutes',
   'LIVE123',
   '{"exercise":"burpee","per_minute":5}'::jsonb),
  ('d0000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-0000000000f0',
   'in_progress',
   now() - interval '10 minutes',
   'LIVE456',
   '{"exercise":"burpee","per_minute":5}'::jsonb);

-- Organizer C (checked in, ready), D (checked in, no_show), E (checked in, ready)
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at, turn_order) VALUES
  ('d0000000-0000-0000-0000-000000000010',
   '00000000-0000-0000-0000-0000000000f0',
   'ready',
   now() - interval '15 minutes',
   NULL),
  ('d0000000-0000-0000-0000-000000000010',
   '00000000-0000-0000-0000-0000000000f1',
   'no_show',
   now() - interval '5 minutes',
   NULL),
  ('d0000000-0000-0000-0000-000000000010',
   '00000000-0000-0000-0000-0000000000f2',
   'ready',
   now() - interval '15 minutes',
   NULL),
  -- Session 2 participants (for advance_turn liveness guard test)
  ('d0000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-0000000000f0',
   'ready',
   now() - interval '15 minutes',
   1),
  ('d0000000-0000-0000-0000-000000000011',
   '00000000-0000-0000-0000-0000000000f3',
   'no_show',
   now() - interval '5 minutes',
   2);

-- Now set the authenticated role for test operations
SET LOCAL role authenticated;

-- ── Test 2: no_show participant D re-joins by code → flips to 'online' ──────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
SELECT lives_ok(
  $$SELECT public.join_session_by_code('LIVE123')$$,
  'no_show participant D can rejoin by code');

SELECT results_eq(
  $$SELECT check_in_state
    FROM session_participants
    WHERE session_id = 'd0000000-0000-0000-0000-000000000010'
      AND user_id = '00000000-0000-0000-0000-0000000000f1'$$,
  $$VALUES ('online')$$,
  'D no_show participant flips to online after rejoin');

SELECT results_eq(
  $$SELECT check_in_at IS NULL
    FROM session_participants
    WHERE session_id = 'd0000000-0000-0000-0000-000000000010'
      AND user_id = '00000000-0000-0000-0000-0000000000f1'$$,
  $$VALUES (true)$$,
  'D check_in_at cleared on no_show rejoin');

-- ── Test 3: ready participant E re-joins by code → stays 'ready' ───────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';
SELECT lives_ok(
  $$SELECT public.join_session_by_code('LIVE123')$$,
  'ready participant E can rejoin by code');

SELECT results_eq(
  $$SELECT check_in_state
    FROM session_participants
    WHERE session_id = 'd0000000-0000-0000-0000-000000000010'
      AND user_id = '00000000-0000-0000-0000-0000000000f2'$$,
  $$VALUES ('ready')$$,
  'E ready participant stays ready after rejoin (WHERE guard preserves non-no_show)');

-- ── Test 4: advance_turn with all no_show participants raises P0001 ──────────────
-- Session 2 (in_progress) has organizer C (turn_order 1, ready) and F (turn_order 2, no_show)
-- Set current turn to C and attempt advance (only F available, but F is no_show)
UPDATE sessions
SET current_turn_user_id = '00000000-0000-0000-0000-0000000000f0',
    current_turn_started_at = now()
WHERE id = 'd0000000-0000-0000-0000-000000000011';

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f0';
SELECT throws_ok(
  $$SELECT public.advance_turn('d0000000-0000-0000-0000-000000000011')$$,
  'P0001',
  'no active participants remain',
  'advance_turn raises P0001 when all non-current participants are no_show');

SELECT * FROM finish();
ROLLBACK;
