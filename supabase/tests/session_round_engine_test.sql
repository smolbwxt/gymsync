BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

-- Migration under test: 20260913000102_session_round_engine.sql
-- (private.session_round_guard, public.advance_round,
-- public.set_session_stations). Plan task D4. Fixture block: 10xx UUIDs
-- (this suite's namespace, constraint 17 -- 01xx-09xx and 0axx-0fxx are
-- taken, 0fxx by D2; 10xx was grepped repo-wide against supabase/ and
-- scripts/ before writing this and had no hits).
--   A = ...1001 organizer, ready, turn 1
--   B = ...1002 ready, turn 2
--   C = ...1003 ready, turn 3      -- the lifter whose set closes the round
--   D = ...1004 NO_SHOW, turn 4    -- excluded from the present set
--   E = ...1005 NOT a participant of either session
--   F = ...1006 INVITED, turn 5    -- also excluded (ruling R-B7)
--   S1 = ...1010 in_progress, lifting_started_at set, round 1 opened 10
--                minutes ago
--   S2 = ...1020 lobby_open, lifting_started_at NULL
--   S3 = ...1030 in_progress, lifting_started_at set two minutes ago,
--                round_started_at still NULL (round 1 never closed) --
--                fix round 1, assertion 14
--
-- FIX ROUND 1 (2026-09-13), THREE ASSERTIONS ADDED, plan(13) -> plan(16).
-- review-data.md findings 2-4, addressed after fix-forward migration
-- 20260913000105_advance_round_first_round_opens_at_lifting_start.sql:
--
-- 14 (finding 2): a set logged before lifting_started_at (the warm-up
--    phase) must not count toward round 1's close. New session S3 --
--    round_started_at NULL, so before this fix-forward the predicate fell
--    back to '-infinity' and counted everything; A's only set in S3
--    predates lifting_started_at by three minutes, so advance_round must
--    still return 1, not close.
-- 15 (finding 3): D4 never repeated a direct guarded-column write AFTER an
--    RPC call, so a regression that broke set_config('gymsync.engine',
--    '',true)'s reset would not have been caught. Reuses S1 post-close
--    (assertion 9): a direct UPDATE of round must still throw P0001.
-- 16 (finding 4): the roster/depth predicate had a two-station success
--    (12) and a one-station depth FAILURE (11), but never a one-station
--    SUCCESS covering the whole present roster -- the common small-crew
--    case. Uses S1's exercise_position 2 (not 1, so assertion 13's
--    idempotency short-circuit does not skip validation) with all three
--    present lifters (A, B, C) in one station, exactly at the depth
--    ceiling.
--
-- TWO DEVIATIONS FROM THE BRIEF, BOTH RECORDED.
--
-- (1) plan(13), not the brief's plan(12), and a sixth actor F. The brief
--     predates controller ruling R-B7, which made the round-close predicate
--     and the station roster count the PRESENT crew --
--     check_in_state IN ('online','ready','late'), advance_turn's own
--     rotation set (20260802000001_rotation_presence.sql) -- rather than
--     "everyone who is not a no_show". R-B7 asks this suite to prove both
--     halves for an invited lifter who never arrived. The first half rides
--     on assertion 8, widened to cover BOTH excluded rows; the second half
--     needs an assertion of its own, and that is the thirteenth. Assertion
--     9 is the regression test for the ruling itself: before R-B7, F would
--     have blocked the close and it would return 1.
--
-- (2) The brief's twelve numbered items carry sixteen facts; a fact that
--     needs its own statement cannot always be its own assertion, because a
--     query that both CALLS a volatile function and re-reads the row it
--     writes sees the statement's own pre-call snapshot -- it would pass
--     whether or not the call moved the row, which is a test that cannot
--     fail. So where a fact needs a separate read, it rides on the
--     neighbouring assertion, and two calls are made bare (the
--     `SELECT public.mark_no_shows();` idiom, mark_no_shows_test.sql:288):
--     item 5's "the row still reads 1" is proved by assertion 7, after BOTH
--     failed closes rather than one; item 6's "round_started_at has moved"
--     and item 9's "changes nothing" are proved together by assertion 10,
--     whose `round = 2` reading would be 3 if the stale replay had fired.
--     Item 9's literal return value is the one fact not asserted; the bare
--     call still proves it does not raise, since an exception there would
--     abort the script.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000001001', 'round-a@test.local'),
  ('00000000-0000-4000-f000-000000001002', 'round-b@test.local'),
  ('00000000-0000-4000-f000-000000001003', 'round-c@test.local'),
  ('00000000-0000-4000-f000-000000001004', 'round-d@test.local'),
  ('00000000-0000-4000-f000-000000001005', 'round-e@test.local'),
  ('00000000-0000-4000-f000-000000001006', 'round-f@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000001001', 'round_a'),
  ('00000000-0000-4000-f000-000000001002', 'round_b'),
  ('00000000-0000-4000-f000-000000001003', 'round_c'),
  ('00000000-0000-4000-f000-000000001004', 'round_d'),
  ('00000000-0000-4000-f000-000000001005', 'round_e'),
  ('00000000-0000-4000-f000-000000001006', 'round_f');

-- S1: lifting has started, so the style is frozen; round 1 opened ten
-- minutes ago, so a set logged five minutes ago counts toward closing it.
INSERT INTO sessions (id, organizer_id, state, started_at, lifting_started_at,
                      round_started_at, current_turn_user_id)
VALUES ('00000000-0000-4000-f000-000000001010',
        '00000000-0000-4000-f000-000000001001',
        'in_progress', now() - interval '30 minutes', now() - interval '20 minutes',
        now() - interval '10 minutes',
        '00000000-0000-4000-f000-000000001001');

-- S2: still in the lobby. Same organizer, so assertion 4 needs no second
-- role. The only reason it exists is that assertions 3 and 4 are the two
-- sides of the same rule and a session cannot be both.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('00000000-0000-4000-f000-000000001020',
   '00000000-0000-4000-f000-000000001001', 'lobby_open');

INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000001010', '00000000-0000-4000-f000-000000001001', 1, 'ready'),
  ('00000000-0000-4000-f000-000000001010', '00000000-0000-4000-f000-000000001002', 2, 'ready'),
  ('00000000-0000-4000-f000-000000001010', '00000000-0000-4000-f000-000000001003', 3, 'ready'),
  ('00000000-0000-4000-f000-000000001010', '00000000-0000-4000-f000-000000001004', 4, 'no_show'),
  ('00000000-0000-4000-f000-000000001010', '00000000-0000-4000-f000-000000001006', 5, 'invited'),
  ('00000000-0000-4000-f000-000000001020', '00000000-0000-4000-f000-000000001001', 1, 'ready');
-- E is deliberately in neither session.

-- A and B have logged this round; C has not. weight is left NULL on every
-- fixture set so the PR announcer and the lifetime-volume trigger both bail
-- out early -- this suite is about the round, not about PRs.
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, logged_at) VALUES
  ('00000000-0000-4000-f000-000000001101', '00000000-0000-4000-f000-000000001001',
   '00000000-0000-4000-f000-000000001010',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 10,
   now() - interval '5 minutes'),
  ('00000000-0000-4000-f000-000000001102', '00000000-0000-4000-f000-000000001002',
   '00000000-0000-4000-f000-000000001010',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 10,
   now() - interval '4 minutes');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001001';

-- ── THE GUARD ────────────────────────────────────────────────────────────
-- A is the organizer, so "organizer or participant can update session"
-- (20260709000006, no column list) grants every one of these UPDATEs. That
-- is exactly the point of decision 4: the policy cannot say no, so the
-- trigger has to.

-- 1.
SELECT throws_ok(
  $$UPDATE sessions SET round = 9
     WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  'P0001', 'round, round_started_at and stations are engine-owned',
  'the organizer cannot write the round counter by hand');

-- 2.
SELECT throws_ok(
  $$UPDATE sessions SET stations = '{}'::jsonb
     WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  'P0001', 'round, round_started_at and stations are engine-owned',
  'the organizer cannot write the station assignment by hand');

-- 3. Spec §1: the style is changeable in the lobby until Start.
SELECT throws_ok(
  $$UPDATE sessions SET style = 'freestyle'
     WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  'P0001', 'the style is fixed once lifting has started',
  'the style is frozen once lifting_started_at is set');

-- 4. …and before Start it is not frozen at all.
SELECT results_eq(
  $$UPDATE sessions SET style = 'freestyle'
     WHERE id = '00000000-0000-4000-f000-000000001020'
     RETURNING style$$,
  $$VALUES ('freestyle'::text)$$,
  'the same UPDATE succeeds while lifting_started_at is NULL');

-- ── THE CLOSE RULE ───────────────────────────────────────────────────────

-- 5. C has not logged, so the round is not over. The RPC returns the round
--    the session is in, which is still 1 -- it does not raise, because
--    "not yet" is not an error.
SELECT results_eq(
  $$SELECT public.advance_round('00000000-0000-4000-f000-000000001010')$$,
  $$VALUES (1)$$,
  'the round does not close while a present lifter has not logged');

-- 6. E is not in this session at all.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001005';
SELECT throws_ok(
  $$SELECT public.advance_round('00000000-0000-4000-f000-000000001010')$$,
  'P0001', 'not a participant of this session',
  'a non-participant cannot close the round');

-- C logs a PENALTY set: burpees paid off inside the round window. A penalty
-- is not a set of the round, so this must not close it.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001003';
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, is_penalty) VALUES
  ('00000000-0000-4000-f000-000000001103', '00000000-0000-4000-f000-000000001003',
   '00000000-0000-4000-f000-000000001010',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 20, true);
SELECT public.advance_round('00000000-0000-4000-f000-000000001010');

-- 7. The counter is untouched by BOTH failed closes (assertion 5's and the
--    bare call above).
SELECT results_eq(
  $$SELECT round FROM sessions
     WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  $$VALUES (1)$$,
  'a penalty-only row does not count as the lifter''s set: the counter is still 1');

-- 8. The two rows the close rule must ignore, and the fact that makes
--    ignoring them meaningful: neither has logged anything at all. If
--    either were counted as present, assertion 9 could not close.
SELECT results_eq(
  $$SELECT sp.check_in_state,
           (SELECT count(*) FROM set_logs sl
             WHERE sl.session_id = '00000000-0000-4000-f000-000000001010'
               AND sl.user_id = sp.user_id)
      FROM session_participants sp
     WHERE sp.session_id = '00000000-0000-4000-f000-000000001010'
       AND sp.user_id IN ('00000000-0000-4000-f000-000000001004',
                          '00000000-0000-4000-f000-000000001006')
     ORDER BY sp.check_in_state$$,
  $$VALUES ('invited'::text, 0::bigint), ('no_show'::text, 0::bigint)$$,
  'D (no_show) and F (invited) are both outside the present set and have logged nothing');

-- C logs a real set. Every PRESENT lifter -- A, B, C -- has now logged one
-- since the round opened.
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, logged_at) VALUES
  ('00000000-0000-4000-f000-000000001104', '00000000-0000-4000-f000-000000001003',
   '00000000-0000-4000-f000-000000001010',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 2, 10,
   now() - interval '1 minute');

-- 9. THE ASSERTION THAT COULD HAVE BEEN WRONG, and the regression test for
--    ruling R-B7. The close fires with D (no_show) and F (invited) having
--    logged nothing: under the pre-ruling predicate ("everyone who is not a
--    no_show") F would still be waited on and this would return 1, hanging
--    every round of every session with one invitee who never showed up.
--    Note also who is calling: C, the lifter who just logged -- anyone's
--    call closes it once the condition is true.
SELECT results_eq(
  $$SELECT public.advance_round('00000000-0000-4000-f000-000000001010')$$,
  $$VALUES (2)$$,
  'the round closes when every PRESENT lifter has logged; an invited no-show blocks nothing');

-- A stale replay: a queued close created while the round was 1, draining
-- after the round has already moved to 2. It must be a silent no-op, not a
-- second advance and not an error.
SELECT public.advance_round('00000000-0000-4000-f000-000000001010', 1);

-- 10. Both halves in one read: round_started_at was restamped by the close
--     (it was ten minutes old and now is not), and the round is 2 -- it
--     would read 3 if the stale replay above had fired.
SELECT results_eq(
  $$SELECT round, round_started_at > now() - interval '1 minute'
      FROM sessions WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  $$VALUES (2, true)$$,
  'the close restamped round_started_at, and the stale replay after it moved nothing');

-- ── THE STATIONS ─────────────────────────────────────────────────────────
-- Still as C: any participant may re-mix, and the idempotency below is what
-- makes two of them racing safe.

-- 11. Spec §2: no station is deeper than three. Four lifter_ids in one
--     station, checked before the roster so the crew is told the thing they
--     can act on.
SELECT throws_ok(
  $$SELECT public.set_session_stations(
      '00000000-0000-4000-f000-000000001010', 1,
      '[{"name":"Rack 1",
         "lifter_ids":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002",
                       "00000000-0000-4000-f000-000000001003",
                       "00000000-0000-4000-f000-000000001004"],
         "turn_order":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002",
                       "00000000-0000-4000-f000-000000001003",
                       "00000000-0000-4000-f000-000000001004"]}]'::jsonb)$$,
  'P0001', 'a station may not be deeper than three',
  'a four-deep station is rejected');

-- 12. The round trip, and R-B7's second half. The argument is exactly the
--     "stations" array of the shape D1's column comment documents, the
--     return is exactly that shape wrapped with its exercise_position, and
--     A/B/C ALONE satisfy the roster -- F (invited) and D (no_show) need no
--     station. Before the ruling this call would have raised 'every present
--     lifter belongs to exactly one station'.
SELECT results_eq(
  $$SELECT public.set_session_stations(
      '00000000-0000-4000-f000-000000001010', 1,
      '[{"name":"Rack 1",
         "lifter_ids":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002"],
         "turn_order":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002"]},
        {"name":"Rack 2",
         "lifter_ids":["00000000-0000-4000-f000-000000001003"],
         "turn_order":["00000000-0000-4000-f000-000000001003"]}]'::jsonb)$$,
  $$VALUES ('{"exercise_position": 1,
              "stations": [{"name":"Rack 1",
                            "lifter_ids":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002"],
                            "turn_order":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002"]},
                           {"name":"Rack 2",
                            "lifter_ids":["00000000-0000-4000-f000-000000001003"],
                            "turn_order":["00000000-0000-4000-f000-000000001003"]}]}'::jsonb)$$,
  'the documented jsonb shape round-trips, and only the present crew needs a station');

-- 13. Called again at the SAME exercise position with a DIFFERENT (and
--     independently valid) assignment: the stored value comes back
--     unchanged. The second payload being valid on its own is what makes
--     this a test -- a broken idempotency check would write it and return
--     it, not raise, so the failure would show as the wrong jsonb rather
--     than as an error. That the returned value is still the FIRST payload
--     is also the proof that it wrote once: the function returns what it
--     read out of the row.
SELECT results_eq(
  $$SELECT public.set_session_stations(
      '00000000-0000-4000-f000-000000001010', 1,
      '[{"name":"Rack 9",
         "lifter_ids":["00000000-0000-4000-f000-000000001003",
                       "00000000-0000-4000-f000-000000001002"],
         "turn_order":["00000000-0000-4000-f000-000000001003",
                       "00000000-0000-4000-f000-000000001002"]},
        {"name":"Rack 8",
         "lifter_ids":["00000000-0000-4000-f000-000000001001"],
         "turn_order":["00000000-0000-4000-f000-000000001001"]}]'::jsonb)$$,
  $$VALUES ('{"exercise_position": 1,
              "stations": [{"name":"Rack 1",
                            "lifter_ids":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002"],
                            "turn_order":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002"]},
                           {"name":"Rack 2",
                            "lifter_ids":["00000000-0000-4000-f000-000000001003"],
                            "turn_order":["00000000-0000-4000-f000-000000001003"]}]}'::jsonb)$$,
  'a second re-mix at the same exercise position returns the stored assignment unchanged');

-- ── FIX ROUND 1 ADDITIONS (2026-09-13) ────────────────────────────────────

-- S3: a fresh in_progress session for assertion 14 -- round_started_at is
-- still NULL (round 1 has never closed), lifting_started_at is set two
-- minutes ago. A is both organizer and the only present participant.
INSERT INTO sessions (id, organizer_id, state, lifting_started_at) VALUES
  ('00000000-0000-4000-f000-000000001030',
   '00000000-0000-4000-f000-000000001001',
   'in_progress', now() - interval '2 minutes');

INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-4000-f000-000000001030', '00000000-0000-4000-f000-000000001001', 'ready');

-- A's only set in S3 was logged BEFORE lifting_started_at -- three minutes
-- before it, i.e. during the warm-up phase set_logs_reject_prelive_session
-- does not gate on (finding 2).
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, logged_at) VALUES
  ('00000000-0000-4000-f000-000000001105', '00000000-0000-4000-f000-000000001001',
   '00000000-0000-4000-f000-000000001030',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 10,
   now() - interval '5 minutes');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001001';

-- 14. Fix-forward 20260913000105: before it, COALESCE(v_round_started_at,
--     '-infinity') meant a NULL round_started_at let EVERY set count, so
--     this would have returned 2. After it, COALESCE falls through to
--     v_lifting_started_at first -- A's set predates that, so it still
--     does not count, and the round does not close.
SELECT results_eq(
  $$SELECT public.advance_round('00000000-0000-4000-f000-000000001030')$$,
  $$VALUES (1)$$,
  'a set logged before lifting_started_at does not count toward round 1''s close');

-- 15. Regression guard for finding 3: after a SUCCESSFUL advance_round
--     (assertion 9) reset the GUC via set_config('gymsync.engine','',true)
--     inside the same transaction, a direct client UPDATE of round must
--     still be rejected -- proving the reset held rather than leaving the
--     bypass on for the remainder of this transaction. As A, S1's
--     organizer, exactly as assertion 1 was.
SELECT throws_ok(
  $$UPDATE sessions SET round = 99
     WHERE id = '00000000-0000-4000-f000-000000001010'$$,
  'P0001', 'round, round_started_at and stations are engine-owned',
  'the guard still rejects a direct write after a successful advance_round closed the round');

-- 16. Finding 4: the roster/depth predicate had a two-station success (12)
--     and a one-station depth FAILURE (11), but never a one-station
--     SUCCESS covering the whole present roster -- the common small-crew
--     case (StationSplit.count yields 1 station for any crew <= 3).
--     exercise_position 2, not 1, so assertion 13's idempotency
--     short-circuit does not skip validation of this new payload. As C,
--     matching "any participant may re-mix" above.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001003';
SELECT results_eq(
  $$SELECT public.set_session_stations(
      '00000000-0000-4000-f000-000000001010', 2,
      '[{"name":"Rack 1",
         "lifter_ids":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002",
                       "00000000-0000-4000-f000-000000001003"],
         "turn_order":["00000000-0000-4000-f000-000000001001",
                       "00000000-0000-4000-f000-000000001002",
                       "00000000-0000-4000-f000-000000001003"]}]'::jsonb)$$,
  $$VALUES ('{"exercise_position": 2,
              "stations": [{"name":"Rack 1",
                            "lifter_ids":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002",
                                          "00000000-0000-4000-f000-000000001003"],
                            "turn_order":["00000000-0000-4000-f000-000000001001",
                                          "00000000-0000-4000-f000-000000001002",
                                          "00000000-0000-4000-f000-000000001003"]}]}'::jsonb)$$,
  'a single station holding the whole three-lifter present roster is accepted');

SELECT * FROM finish();
ROLLBACK;
