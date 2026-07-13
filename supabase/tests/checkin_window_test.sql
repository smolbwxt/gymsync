BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(5);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- User G has two sessions: one starting in 30 minutes (window not open yet —
-- opens at scheduled_for - 20min = +10min from now) and one starting in 15
-- minutes (window already open — opens at -5min from now).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'cw_user_g@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'cw_user_g');

INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('e0000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-0000000000d1', 'lobby_open',
   now() + interval '30 minutes'),
  ('e0000000-0000-0000-0000-000000000102',
   '00000000-0000-0000-0000-0000000000d1', 'lobby_open',
   now() + interval '15 minutes'),
  -- Ad-hoc session: no scheduled time — the window guard must fail open.
  ('e0000000-0000-0000-0000-000000000103',
   '00000000-0000-0000-0000-0000000000d1', 'lobby_open',
   NULL);

INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('e0000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-0000000000d1', 'invited'),
  ('e0000000-0000-0000-0000-000000000102',
   '00000000-0000-0000-0000-0000000000d1', 'invited'),
  ('e0000000-0000-0000-0000-000000000103',
   '00000000-0000-0000-0000-0000000000d1', 'invited');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';

-- ── Test 1: check-in 30 minutes before scheduled start is rejected ────────────
SELECT throws_ok(
  $$UPDATE session_participants
    SET check_in_state = 'ready'
    WHERE session_id = 'e0000000-0000-0000-0000-000000000101'
      AND user_id = '00000000-0000-0000-0000-0000000000d1'$$,
  'P0001',
  'check-in opens 20 minutes before the scheduled start',
  'check-in more than 20 minutes early is rejected');

-- ── Test 2: the rejected attempt leaves check_in_state untouched ──────────────
SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'e0000000-0000-0000-0000-000000000101'
      AND user_id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$VALUES ('invited')$$,
  'rejected early check-in leaves state untouched');

-- ── Test 3: check-in 15 minutes before start (within the 20-min window) succeeds ──
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants
      SET check_in_state = 'ready'
      WHERE session_id = 'e0000000-0000-0000-0000-000000000102'
        AND user_id = '00000000-0000-0000-0000-0000000000d1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1],
  'check-in within the 20-minute window succeeds');

-- ── Test 4: transitions to a non-ready state are unaffected by the guard ──────
-- (sanity check that the trigger is scoped to the check_in_state='ready'
-- transition only, not every UPDATE on the row.)
SELECT lives_ok(
  $$UPDATE session_participants
    SET check_in_state = 'no_show'
    WHERE session_id = 'e0000000-0000-0000-0000-000000000101'
      AND user_id = '00000000-0000-0000-0000-0000000000d1'$$,
  'non-ready transition on the too-early session is unaffected by the check-in guard');

-- ── Test 5: NULL scheduled_for (ad-hoc session) fails open — check-in allowed ──
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants
      SET check_in_state = 'ready'
      WHERE session_id = 'e0000000-0000-0000-0000-000000000103'
        AND user_id = '00000000-0000-0000-0000-0000000000d1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1],
  'ad-hoc session with NULL scheduled_for allows check-in (guard fails open)');

SELECT * FROM finish();
ROLLBACK;
