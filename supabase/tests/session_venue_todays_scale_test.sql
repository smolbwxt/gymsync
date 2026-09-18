BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

-- Migration under test: 20260918000202_session_venue_and_todays_scale.sql
-- (sessions.venue_id, session_participants.todays_scale,
-- public.claim_session_venue). Fixture block: 16xx UUIDs (constraint 17 --
-- this plan claims 15xx for D2 and 16xx for D4; 01xx-14xx are taken, 13xx/
-- 14xx by the held B2 data branch, not this plan's to touch).
--   A = ...1601 organizer + participant, checked into V ~1 hour ago,
--       check_in_state 'ready'
--   B = ...1602 participant, NO venue check-in, check_in_state 'ready'
--   C = ...1603 NOT a participant of S
--   V = ...1610 the venue A is present at
--   W = ...1611 a second venue, used only to prove a direct UPDATE of
--       sessions.venue_id passes private.session_round_guard (assertion 9)
--   S = ...1620 session, organizer A, scheduled_for 1 hour in the past --
--       satisfies decision 3's checkin_window_guard pass condition
--       (now() >= scheduled_for - 20 minutes) from the start, since both
--       A and B are already check_in_state = 'ready'.
--
-- venue_checkins.created_at (A, 1 hour ago) is relative to now(), not a
-- fixed 2099 date, for the same reason venue_rack_counts_test.sql gives:
-- the 12-hour presence window is the thing under test, and nothing here
-- does a broad current-date scan of venue_checkins.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000001601', 'vts-a@test.local'),
  ('00000000-0000-4000-e000-000000001602', 'vts-b@test.local'),
  ('00000000-0000-4000-e000-000000001603', 'vts-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000001601', 'vts_a'),
  ('00000000-0000-4000-e000-000000001602', 'vts_b'),
  ('00000000-0000-4000-e000-000000001603', 'vts_c');

INSERT INTO venues (id, name, latitude, longitude, created_by) VALUES
  ('00000000-0000-4000-e000-000000001610', 'Venue Claim Gym', 34.0000, -118.0000,
   '00000000-0000-4000-e000-000000001601'),
  ('00000000-0000-4000-e000-000000001611', 'Second Venue', 35.0000, -119.0000,
   '00000000-0000-4000-e000-000000001601');

INSERT INTO venue_checkins (venue_id, user_id, created_at) VALUES
  ('00000000-0000-4000-e000-000000001610', '00000000-0000-4000-e000-000000001601', now() - interval '1 hour');

INSERT INTO sessions (id, organizer_id, state, started_at, scheduled_for) VALUES
  ('00000000-0000-4000-e000-000000001620',
   '00000000-0000-4000-e000-000000001601', 'in_progress', now(),
   now() - interval '1 hour');

INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001620', '00000000-0000-4000-e000-000000001601', 'ready', now() - interval '50 minutes'),
  ('00000000-0000-4000-e000-000000001620', '00000000-0000-4000-e000-000000001602', 'ready', now() - interval '45 minutes');
-- C is deliberately left out of session_participants.

-- 1. The column exists with a foreign key to venues (checked before any
--    role switch -- precedent: session_participant_energy_test.sql:37-39).
SELECT results_eq(
  $$SELECT bool_or(pg_get_constraintdef(oid) LIKE '%venue_id%REFERENCES%venues%')
      FROM pg_constraint
     WHERE conrelid = 'public.sessions'::regclass AND contype = 'f'$$,
  ARRAY[true],
  'sessions.venue_id exists with a foreign key to public.venues');

-- 2. The column exists as jsonb.
SELECT is(
  (SELECT data_type FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'session_participants'
      AND column_name = 'todays_scale'),
  'jsonb', 'session_participants.todays_scale exists as jsonb');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001601';

-- 3. As A: claim_session_venue reads her own recent check-in at V and
--    writes it -- the function's return value IS a fresh read of
--    sessions.venue_id after its own UPDATE, so checking the return
--    proves both facts at once.
SELECT results_eq(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620')$$,
  $$VALUES ('00000000-0000-4000-e000-000000001610'::uuid)$$,
  'A claims the session''s venue from her own 1-hour-old check-in');

-- 4. As B: no venue check-in of her own -- claim returns NULL (the early
--    return before the UPDATE even runs), and A's claim is not overwritten.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001602';
SELECT results_eq(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620'),
           (SELECT venue_id FROM sessions WHERE id = '00000000-0000-4000-e000-000000001620')$$,
  $$VALUES (NULL::uuid, '00000000-0000-4000-e000-000000001610'::uuid)$$,
  'B has no recent check-in of her own: claim returns NULL, first write still wins');

-- 5. As C: not a participant of S at all.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001603';
SELECT throws_ok(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620')$$,
  'P0001', 'not a participant of this session',
  'a non-participant cannot claim a venue for this session');

-- 6. As B: her own row's todays_scale is writable through the existing
--    "participant updates own check-in" policy -- no new policy needed.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001602';
SELECT results_eq(
  $$UPDATE session_participants
       SET todays_scale = '{"exercise_id": "00000000-0000-4000-e000-000000001699", "sets_instead": 2}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001620'
       AND user_id = '00000000-0000-4000-e000-000000001602'
    RETURNING todays_scale$$,
  $$VALUES ('{"exercise_id": "00000000-0000-4000-e000-000000001699", "sets_instead": 2}'::jsonb)$$,
  'B writes todays_scale on her own row -- own-row policy is sufficient');

-- 7. As B: the same UPDATE against A's row affects zero rows -- RLS, not
--    an error.
SELECT is_empty(
  $$UPDATE session_participants
       SET todays_scale = '{"exercise_id": "00000000-0000-4000-e000-000000001699", "sets_instead": 2}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001620'
       AND user_id = '00000000-0000-4000-e000-000000001601'
    RETURNING 1$$,
  'B cannot write todays_scale onto A''s row -- zero rows, not an exception');

-- 8. As B, still check_in_state = 'ready' with scheduled_for an hour in
--    the past: a SECOND todays_scale-only UPDATE still succeeds --
--    checkin_window_guard does not raise on a write that leaves
--    check_in_state alone (decision 3's own pin, mirroring what `energy`
--    already proved for the same trigger).
SELECT results_eq(
  $$UPDATE session_participants
       SET todays_scale = '{"exercise_id": "00000000-0000-4000-e000-000000001699", "sets_instead": 1}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001620'
       AND user_id = '00000000-0000-4000-e000-000000001602'
    RETURNING todays_scale->>'sets_instead'$$,
  $$VALUES ('1')$$,
  'B accepts a smaller reduction later -- checkin_window_guard does not fire on an already-ready row past its own scheduled_for');

-- 9. As A: a direct UPDATE of sessions.venue_id (not through
--    claim_session_venue) passes private.session_round_guard --
--    venue_id is not one of the three engine-owned columns it guards
--    (round, round_started_at, stations), nor the style column.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001601';
SELECT results_eq(
  $$UPDATE sessions SET venue_id = '00000000-0000-4000-e000-000000001611'
     WHERE id = '00000000-0000-4000-e000-000000001620'
    RETURNING venue_id$$,
  $$VALUES ('00000000-0000-4000-e000-000000001611'::uuid)$$,
  'a direct venue_id write passes private.session_round_guard untouched');

SELECT * FROM finish();
ROLLBACK;
