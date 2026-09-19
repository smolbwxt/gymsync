BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(24);

-- Migration under test: 20260919000101_session_swap_layer.sql
-- (session_participants.self_swaps jsonb, sessions.squad_swaps jsonb,
-- public.apply_squad_swap(), and the squad_swaps clause added to
-- private.session_round_guard). Phase C1 D2. Fixture block: 17xx UUIDs
-- (constraint 17 -- this plan claims 17xx for D2 and 18xx for D4;
-- 01xx-13xx/15xx/16xx are taken).
--
--   A  = ...1701 organizer + participant of S and S_NOROUTINE and AH
--   B  = ...1702 participant of S only
--   C  = ...1703 NOT a participant of anything below
--
--   E1 = ...1711 exercise, slot RE1's original            (routine R1)
--   E2 = ...1712 exercise, slot RE2's original             (routine R1)
--   E3 = ...1713 exercise, used as a swap replacement
--   E4 = ...1714 exercise, slot RE_FOREIGN's original      (routine R2)
--
--   R1 = ...1720 the session S's routine, owned by A
--   R2 = ...1721 a DIFFERENT routine, owned by A -- exists only to give
--        RE_FOREIGN a real routine_exercises row that is not part of S
--
--   RE1        = ...1730 slot 1 of R1 (position 1, exercise E1)
--   RE2        = ...1731 slot 2 of R1 (position 2, exercise E2)
--   RE_FOREIGN = ...1732 slot 1 of R2 (position 1, exercise E4) -- a REAL
--        routine_exercises row, but of a routine S does not use
--
--   S           = ...1740 organizer A, routine_id R1, in_progress,
--        scheduled_for 1 hour in the PAST -- A and B both check_in_state
--        'ready' already (set at INSERT, so no trigger fires). This is
--        also the fixture that pins decision 1's "scheduled_for in the
--        past" half: assertions 5-6 are a self_swaps-only UPDATE on this
--        exact row.
--   S_NOROUTINE = ...1741 organizer A, routine_id NULL, in_progress --
--        used only to prove apply_squad_swap raises the same "slot is not
--        part of this session's routine" error when the session has no
--        routine at all (controller's gate review, R-C-4).
--   AH          = ...1742 organizer A, style 'freestyle', in_progress,
--        scheduled_for NULL, lifting_started_at NULL -- the ad-hoc case.
--        A is check_in_state 'ready' here too. This pins decision 1's
--        "scheduled_for IS NULL" half (assertion 23).
--
-- Unused ids, deliberately never inserted anywhere, to prove the negative
-- paths reject them: UNKNOWN_EXERCISE ...1790, UNKNOWN_SLOT ...1791,
-- FAKE_VENUE ...1792.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000001701', 'swap-a@test.local'),
  ('00000000-0000-4000-e000-000000001702', 'swap-b@test.local'),
  ('00000000-0000-4000-e000-000000001703', 'swap-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000001701', 'swap_a'),
  ('00000000-0000-4000-e000-000000001702', 'swap_b'),
  ('00000000-0000-4000-e000-000000001703', 'swap_c');

INSERT INTO exercises (id, name, slug, category, primary_muscle, equipment) VALUES
  ('00000000-0000-4000-e000-000000001711', 'Swap Test Bench', 'swap-test-bench', 'compound', 'chest', 'barbell'),
  ('00000000-0000-4000-e000-000000001712', 'Swap Test Squat', 'swap-test-squat', 'compound', 'quads', 'barbell'),
  ('00000000-0000-4000-e000-000000001713', 'Swap Test Row', 'swap-test-row', 'compound', 'back', 'barbell'),
  ('00000000-0000-4000-e000-000000001714', 'Swap Test Curl', 'swap-test-curl', 'isolation', 'biceps', 'dumbbell');

INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('00000000-0000-4000-e000-000000001720', '00000000-0000-4000-e000-000000001701', 'Swap Test Routine One', 'private'),
  ('00000000-0000-4000-e000-000000001721', '00000000-0000-4000-e000-000000001701', 'Swap Test Routine Two (foreign)', 'private');

INSERT INTO routine_exercises (id, routine_id, exercise_id, position) VALUES
  ('00000000-0000-4000-e000-000000001730', '00000000-0000-4000-e000-000000001720',
   '00000000-0000-4000-e000-000000001711', 1),
  ('00000000-0000-4000-e000-000000001731', '00000000-0000-4000-e000-000000001720',
   '00000000-0000-4000-e000-000000001712', 2),
  ('00000000-0000-4000-e000-000000001732', '00000000-0000-4000-e000-000000001721',
   '00000000-0000-4000-e000-000000001714', 1);

INSERT INTO sessions (id, routine_id, organizer_id, state, started_at, scheduled_for) VALUES
  ('00000000-0000-4000-e000-000000001740', '00000000-0000-4000-e000-000000001720',
   '00000000-0000-4000-e000-000000001701', 'in_progress', now(), now() - interval '1 hour');
INSERT INTO sessions (id, routine_id, organizer_id, state, started_at, scheduled_for) VALUES
  ('00000000-0000-4000-e000-000000001741', NULL,
   '00000000-0000-4000-e000-000000001701', 'in_progress', now(), now() - interval '1 hour');
INSERT INTO sessions (id, routine_id, organizer_id, state, style, started_at, scheduled_for) VALUES
  ('00000000-0000-4000-e000-000000001742', NULL,
   '00000000-0000-4000-e000-000000001701', 'in_progress', 'freestyle', now(), NULL);

INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001740', '00000000-0000-4000-e000-000000001701', 'ready', now() - interval '50 minutes'),
  ('00000000-0000-4000-e000-000000001740', '00000000-0000-4000-e000-000000001702', 'ready', now() - interval '45 minutes'),
  ('00000000-0000-4000-e000-000000001741', '00000000-0000-4000-e000-000000001701', 'ready', now() - interval '50 minutes'),
  ('00000000-0000-4000-e000-000000001742', '00000000-0000-4000-e000-000000001701', 'ready', now());
-- C is deliberately left out of every session_participants row above.

-- 1-4. The columns themselves, checked before any role switch (precedent:
-- session_participant_energy_test.sql:36-37).
SELECT has_column('public', 'session_participants', 'self_swaps',
  'session_participants.self_swaps exists');
SELECT col_is_null('public', 'session_participants', 'self_swaps',
  'self_swaps is nullable -- NULL means no layer at all');
SELECT has_column('public', 'sessions', 'squad_swaps',
  'sessions.squad_swaps exists');
SELECT col_is_null('public', 'sessions', 'squad_swaps',
  'squad_swaps is nullable -- NULL means no layer at all');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001701';

-- 5-6. As A: an own-row self_swaps UPDATE succeeds on S, whose scheduled_for
-- is an hour in the past -- this is decision 1's "past" half: A is already
-- check_in_state 'ready', so checkin_window_guard does not early-return on
-- NEW.check_in_state IS DISTINCT FROM 'ready' (it isn't distinct, both are
-- 'ready'), but its scheduled_for check (now() < scheduled_for - 20 min)
-- fails open because scheduled_for is safely in the past. engine_guard
-- never fires: late_minutes/burpees_owed/turn_order are untouched. Read
-- back in a SECOND statement (constraint 17).
SELECT lives_ok(
  $$UPDATE session_participants
       SET self_swaps = '{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001712"}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001740'
       AND user_id = '00000000-0000-4000-e000-000000001701'$$,
  'A writes her own self_swaps on S -- no new policy needed, both BEFORE UPDATE triggers pass');
SELECT results_eq(
  $$SELECT self_swaps FROM session_participants
     WHERE session_id = '00000000-0000-4000-e000-000000001740'
       AND user_id = '00000000-0000-4000-e000-000000001701'$$,
  $$VALUES ('{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001712"}'::jsonb)$$,
  'A''s self_swaps reads back exactly what was written');

-- 7. As B: the same UPDATE against A's row affects zero rows -- RLS, not
-- an exception (precedent: session_venue_todays_scale_test.sql:119-127).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001702';
SELECT is_empty(
  $$UPDATE session_participants
       SET self_swaps = '{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001713"}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001740'
       AND user_id = '00000000-0000-4000-e000-000000001701'
    RETURNING 1$$,
  'B cannot write A''s self_swaps -- zero rows, not an exception');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001701';

-- 8. As A: a direct client UPDATE of squad_swaps (NULL -> value) is refused
-- by the new clause in private.session_round_guard.
SELECT throws_ok(
  $$UPDATE sessions SET squad_swaps = '{"foo": "bar"}'::jsonb
     WHERE id = '00000000-0000-4000-e000-000000001740'$$,
  'P0001', 'squad_swaps is written through apply_squad_swap',
  'a direct write of squad_swaps (NULL -> value) is refused');

-- 9-10. As A: apply_squad_swap(S, RE1, E3) succeeds -- the function's own
-- return value IS the merged object (mirrors claim_session_venue's own
-- proof style, session_venue_todays_scale_test.sql:80-87), and a SECOND
-- statement reads sessions.squad_swaps back to confirm the same thing
-- landed durably.
SELECT results_eq(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001713')$$,
  $$VALUES ('{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001713"}'::jsonb)$$,
  'A applies a squad swap on slot RE1 -- the RPC returns the merged object');
SELECT results_eq(
  $$SELECT squad_swaps FROM sessions WHERE id = '00000000-0000-4000-e000-000000001740'$$,
  $$VALUES ('{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001713"}'::jsonb)$$,
  'sessions.squad_swaps reads back the same merged object');

-- 11. Merging a second slot keeps the first.
SELECT results_eq(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001731',
      '00000000-0000-4000-e000-000000001711')$$,
  $$VALUES ('{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001713",
             "00000000-0000-4000-e000-000000001731": "00000000-0000-4000-e000-000000001711"}'::jsonb)$$,
  'swapping RE2 keeps RE1''s swap -- merge, not replace');

-- 12. Re-swapping the same slot overwrites, it does not accumulate.
SELECT results_eq(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001711')$$,
  $$VALUES ('{"00000000-0000-4000-e000-000000001730": "00000000-0000-4000-e000-000000001711",
             "00000000-0000-4000-e000-000000001731": "00000000-0000-4000-e000-000000001711"}'::jsonb)$$,
  'RE1 re-swapped -- its old value is overwritten, RE2 is untouched');

-- 13. As A: now that squad_swaps holds a real value, a direct client
-- UPDATE (value -> value) is refused too, not only the NULL -> value edge.
SELECT throws_ok(
  $$UPDATE sessions SET squad_swaps = '{"foo": "bar"}'::jsonb
     WHERE id = '00000000-0000-4000-e000-000000001740'$$,
  'P0001', 'squad_swaps is written through apply_squad_swap',
  'a direct write of squad_swaps (value -> value) is refused too');

-- 14. As A: a column the guard does not own updates normally -- the guard
-- is narrow, not a blanket lock on every session write (precedent:
-- session_venue_todays_scale_test.sql:224-232).
SELECT lives_ok(
  $$UPDATE sessions SET scheduled_for = scheduled_for - interval '5 minutes'
     WHERE id = '00000000-0000-4000-e000-000000001740'$$,
  'a column the guard does not own updates normally');

-- 15. The venue_id clause survives the CREATE OR REPLACE that added the
-- squad_swaps clause -- one assertion is enough (per dispatch).
SELECT throws_ok(
  $$UPDATE sessions SET venue_id = '00000000-0000-4000-e000-000000001792'
     WHERE id = '00000000-0000-4000-e000-000000001740'$$,
  'P0001', 'venue_id is claimed through claim_session_venue',
  'the venue_id clause still fires after the guard was replaced');

-- 16. As C: not a participant of S at all.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001703';
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001713')$$,
  'P0001', 'not a participant of this session',
  'a non-participant cannot apply a squad swap');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001701';

-- 17. An unknown replacement id is refused.
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001790')$$,
  'P0001', 'replacement is not a known exercise',
  'an unknown replacement exercise id is refused');

-- 18. The fourth error (controller's gate review, R-C-4): a slot id that
-- names no routine_exercises row at all.
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001791',
      '00000000-0000-4000-e000-000000001713')$$,
  'P0001', 'slot is not part of this session''s routine',
  'a slot id that names no routine_exercises row at all is refused');

-- 19. Same error: a REAL routine_exercises row, but of a DIFFERENT
-- routine than the session's own (RE_FOREIGN belongs to R2, S uses R1).
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001732',
      '00000000-0000-4000-e000-000000001713')$$,
  'P0001', 'slot is not part of this session''s routine',
  'a real slot of a different routine is refused, not just an unknown uuid');

-- 20. Same error: a session with routine_id NULL has no slots at all, so
-- even a real routine_exercises row (RE1) is refused for it.
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001741',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001713')$$,
  'P0001', 'slot is not part of this session''s routine',
  'a session with no routine has no slots -- the same error, not a different one');

-- 21. Unauthenticated: `authenticated` role but no JWT sub claim, so
-- auth.uid() is NULL and the function's first gate raises before any of
-- the others run (precedent: venue_rack_counts_test.sql:156-164).
SET LOCAL request.jwt.claim.sub = '';
SELECT throws_ok(
  $$SELECT public.apply_squad_swap(
      '00000000-0000-4000-e000-000000001740',
      '00000000-0000-4000-e000-000000001730',
      '00000000-0000-4000-e000-000000001713')$$,
  'P0001', 'sign-in required',
  'a caller with no JWT sub cannot apply a squad swap');

-- 22. anon holds no EXECUTE.
SELECT ok(
  NOT has_function_privilege('anon', 'public.apply_squad_swap(uuid,uuid,uuid)', 'EXECUTE'),
  'anon cannot execute apply_squad_swap');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001701';

-- 23. Decision 1's "scheduled_for IS NULL" half: a self_swaps-only UPDATE
-- on AH (freestyle, scheduled_for NULL, lifting_started_at NULL, already
-- check_in_state 'ready') passes checkin_window_guard, which fails open
-- when scheduled_for IS NULL, and engine_guard, which never sees a
-- penalty-field change.
SELECT lives_ok(
  $$UPDATE session_participants
       SET self_swaps = '{"00000000-0000-4000-e000-000000001799": "00000000-0000-4000-e000-000000001798"}'::jsonb
     WHERE session_id = '00000000-0000-4000-e000-000000001742'
       AND user_id = '00000000-0000-4000-e000-000000001701'$$,
  'A writes her own self_swaps on the ad-hoc session AH -- scheduled_for IS NULL fails open');

-- 24. The INSERT door (review-data.md, blocking; migration 000103): a session
-- cannot be BORN with squad_swaps. The sessions INSERT policy has no column
-- list, so without the insert guard an organizer could seed the layer at
-- creation and skip every check apply_squad_swap makes. BEFORE ROW triggers
-- run before the RLS WITH CHECK, so the caller sees this P0001. The fixture
-- inserts at the top of this file (squad_swaps left NULL) are the proof that
-- ordinary inserts still pass the same trigger.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001701';
SELECT throws_ok(
  $$INSERT INTO sessions (id, routine_id, organizer_id, state, scheduled_for, squad_swaps) VALUES
      ('00000000-0000-4000-e000-000000001749', '00000000-0000-4000-e000-000000001720',
       '00000000-0000-4000-e000-000000001701', 'scheduled', now() + interval '1 day',
       '{"00000000-0000-4000-e000-000000001799": "00000000-0000-4000-e000-000000001798"}'::jsonb)$$,
  'P0001', 'squad_swaps is written through apply_squad_swap',
  'a session cannot be inserted with squad_swaps already set');

SELECT * FROM finish();
ROLLBACK;
