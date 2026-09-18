BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

-- Migration under test: 20260918000202_session_venue_and_todays_scale.sql
-- (sessions.venue_id, session_participants.todays_scale,
-- public.claim_session_venue) AND 20260918000203_session_venue_guard.sql
-- (review-data.md F1's fix: private.session_round_guard now refuses a
-- client write of a non-NULL venue_id; claim_session_venue returns the
-- session's existing venue, not always NULL, for a caller with no recent
-- check-in). Fixture block: 16xx UUIDs (constraint 17 -- this plan claims
-- 15xx for D2 and 16xx for D4; 01xx-14xx are taken, 13xx/14xx by the held
-- B2 data branch, not this plan's to touch).
--   A = ...1601 organizer + participant, checked into V ~1 hour ago,
--       check_in_state 'ready'
--   B = ...1602 participant, NO venue check-in, check_in_state 'ready'
--   C = ...1603 NOT a participant of S
--   V = ...1610 the venue A is present at -- deleted in assertion 14 to
--       prove the ON DELETE SET NULL path through the guard, so nothing
--       after that assertion depends on V or on A's check-in surviving
--   W = ...1611 a second venue, never claimed -- the target every direct
--       venue_id write in assertions 9 and 12 is rejected against
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

-- 4. As B: no venue check-in of her own -- review-data.md F1's fix means
--    claim_session_venue no longer short-circuits to NULL here. It reads
--    the session's CURRENT venue_id after the (skipped) claim attempt, so
--    B gets A's venue back, not NULL -- first write still wins, and the
--    caller learns what the session's venue actually is either way.
SELECT results_eq(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620'),
           (SELECT venue_id FROM sessions WHERE id = '00000000-0000-4000-e000-000000001620')$$,
  $$VALUES ('00000000-0000-4000-e000-000000001610'::uuid, '00000000-0000-4000-e000-000000001610'::uuid)$$,
  'B has no recent check-in of her own: claim on an already-claimed session returns its venue, not NULL');

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
--    claim_session_venue) on the already-claimed session now throws --
--    review-data.md F1's fix, 20260918000203_session_venue_guard.sql.
--    S is still claimed to V from assertion 3.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001601';
SELECT throws_ok(
  $$UPDATE sessions SET venue_id = '00000000-0000-4000-e000-000000001611'
     WHERE id = '00000000-0000-4000-e000-000000001620'$$,
  'P0001', 'venue_id is claimed through claim_session_venue',
  'a direct overwrite of an already-claimed venue_id is refused');

-- 10. As A: clearing venue_id to NULL directly stays legal on purpose --
--     the ON DELETE SET NULL path (assertion 14) and a manual "forget this
--     venue" both arrive as this same NULL write.
SELECT results_eq(
  $$UPDATE sessions SET venue_id = NULL
     WHERE id = '00000000-0000-4000-e000-000000001620'
    RETURNING venue_id$$,
  $$VALUES (NULL::uuid)$$,
  'a direct clear of venue_id to NULL is legal');

-- 11. As B: no check-in of her own, and S is unclaimed (assertion 10) --
--     claim_session_venue's final read of the session's current venue_id
--     is NULL this time, not another participant's venue.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001602';
SELECT results_eq(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620')$$,
  $$VALUES (NULL::uuid)$$,
  'B has no recent check-in of her own: claim on an unclaimed session returns NULL');

-- 12. As A: the same direct-write guard fires on the NULL -> venue edge
--     too, not only on overwriting an existing value.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001601';
SELECT throws_ok(
  $$UPDATE sessions SET venue_id = '00000000-0000-4000-e000-000000001611'
     WHERE id = '00000000-0000-4000-e000-000000001620'$$,
  'P0001', 'venue_id is claimed through claim_session_venue',
  'a direct write of venue_id on an unclaimed session is refused too');

-- 12b. As A (organizer of her own new session): the INSERT door is shut
--      too (review-data.md F9, migration 000204) -- a session cannot be born
--      with a venue. The fixture INSERT at the top of this file, which
--      leaves venue_id NULL, is the proof that ordinary inserts still pass
--      the same trigger.
SELECT throws_ok(
  $$INSERT INTO sessions (id, organizer_id, state, scheduled_for, venue_id) VALUES
      ('00000000-0000-4000-e000-000000001621',
       '00000000-0000-4000-e000-000000001601', 'scheduled',
       now() + interval '1 day', '00000000-0000-4000-e000-000000001611')$$,
  'P0001', 'venue_id is claimed through claim_session_venue',
  'a session cannot be inserted with venue_id already set');

-- 13. As A: after the clear, her 1-hour-old check-in at V is still inside
--     the 12-hour window, so claim_session_venue claims again.
SELECT results_eq(
  $$SELECT public.claim_session_venue('00000000-0000-4000-e000-000000001620')$$,
  $$VALUES ('00000000-0000-4000-e000-000000001610'::uuid)$$,
  'after a clear, a checked-in participant claims the venue again');

-- 14. Deleting V (as postgres -- ordinary participants hold no DELETE on
--     venues, and that is not what this assertion is about) cascades to
--     sessions.venue_id = NULL through ON DELETE SET NULL, which arrives
--     at the trigger as an UPDATE with NEW.venue_id NULL -- the guard's
--     own NEW.venue_id IS NOT NULL check lets it through without raising.
--     Two statements, not one: a data-modifying CTE and its outer SELECT
--     share a snapshot (and the SET NULL action fires at statement end),
--     so a single query reads the venue from before the delete. This also
--     drops A's check-in (venue_checkins.venue_id ON DELETE CASCADE),
--     which is fine: nothing after these assertions depends on it.
SET LOCAL role postgres;
SELECT lives_ok(
  $$DELETE FROM public.venues WHERE id = '00000000-0000-4000-e000-000000001610'$$,
  'deleting the claimed venue does not raise through the guard');

-- 15. ...and the session's venue is NULL afterwards.
SELECT results_eq(
  $$SELECT venue_id FROM public.sessions
     WHERE id = '00000000-0000-4000-e000-000000001620'$$,
  $$VALUES (NULL::uuid)$$,
  'deleting the claimed venue leaves venue_id NULL');

-- 16. As A: an update to a column the guard does not own (scheduled_for)
--     still passes private.session_round_guard untouched -- the guard is
--     narrow, not a blanket lock on every session write.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001601';
SELECT lives_ok(
  $$UPDATE sessions SET scheduled_for = scheduled_for - interval '5 minutes'
     WHERE id = '00000000-0000-4000-e000-000000001620'$$,
  'a column the guard does not own updates normally');

-- 17. anon holds no EXECUTE (review-data.md F4).
SELECT ok(
  NOT has_function_privilege('anon', 'public.claim_session_venue(uuid)', 'EXECUTE'),
  'anon cannot execute claim_session_venue');

SELECT * FROM finish();
ROLLBACK;
