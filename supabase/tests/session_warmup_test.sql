BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

-- Warm-up phase (20260803000004): lifting begins when the LAST present
-- participant votes "I'm warm", or when the organizer force-starts.
-- Fixture block: 0bxx UUIDs. Session b10 (in_progress, organizer A):
-- A (ready, 1), B (online, 2), C (late, 3) — one voter per presence
-- state — plus D (no_show, 4) and E (left, 5), the two non-present
-- states that must never block unanimity. Session b11 (in_progress,
-- organizer A): A (ready, 1), B (online, 2) — the force-start fixture.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000000b01', 'warm-a@test.local'),
  ('00000000-0000-4000-e000-000000000b02', 'warm-b@test.local'),
  ('00000000-0000-4000-e000-000000000b03', 'warm-c@test.local'),
  ('00000000-0000-4000-e000-000000000b04', 'warm-d@test.local'),
  ('00000000-0000-4000-e000-000000000b05', 'warm-e@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000000b01', 'warm_a'),
  ('00000000-0000-4000-e000-000000000b02', 'warm_b'),
  ('00000000-0000-4000-e000-000000000b03', 'warm_c'),
  ('00000000-0000-4000-e000-000000000b04', 'warm_d'),
  ('00000000-0000-4000-e000-000000000b05', 'warm_e');

INSERT INTO sessions (id, organizer_id, state, started_at, current_turn_user_id)
VALUES
  ('00000000-0000-4000-e000-000000000b10',
   '00000000-0000-4000-e000-000000000b01',
   'in_progress', now(), '00000000-0000-4000-e000-000000000b01'),
  ('00000000-0000-4000-e000-000000000b11',
   '00000000-0000-4000-e000-000000000b01',
   'in_progress', now(), '00000000-0000-4000-e000-000000000b01');

INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state) VALUES
  ('00000000-0000-4000-e000-000000000b10', '00000000-0000-4000-e000-000000000b01', 1, 'ready'),
  ('00000000-0000-4000-e000-000000000b10', '00000000-0000-4000-e000-000000000b02', 2, 'online'),
  ('00000000-0000-4000-e000-000000000b10', '00000000-0000-4000-e000-000000000b03', 3, 'late'),
  ('00000000-0000-4000-e000-000000000b10', '00000000-0000-4000-e000-000000000b04', 4, 'no_show'),
  ('00000000-0000-4000-e000-000000000b10', '00000000-0000-4000-e000-000000000b05', 5, 'left'),
  ('00000000-0000-4000-e000-000000000b11', '00000000-0000-4000-e000-000000000b01', 1, 'ready'),
  ('00000000-0000-4000-e000-000000000b11', '00000000-0000-4000-e000-000000000b02', 2, 'online');

-- 1. Old-client safety: warmup_minutes defaults to 0 (= today's behaviour).
SELECT results_eq(
  $$SELECT warmup_minutes FROM sessions
     WHERE id = '00000000-0000-4000-e000-000000000b10'$$,
  $$VALUES (0)$$,
  'warmup_minutes defaults to 0');

-- 2. …and the CHECK caps the window at 60.
SELECT throws_ok(
  $$UPDATE sessions SET warmup_minutes = 61
     WHERE id = '00000000-0000-4000-e000-000000000b10'$$,
  '23514', NULL,
  'warmup_minutes CHECK rejects 61');

SET LOCAL role authenticated;

-- 3. A non-participant cannot vote (E is not in session b11).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b05';
SELECT throws_ok(
  $$SELECT public.mark_warmup_ready('00000000-0000-4000-e000-000000000b11')$$,
  'P0001', 'not a session participant',
  'a non-participant cannot vote');

-- 4./5. A non-last present vote records but does NOT start lifting.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b01';
SELECT results_eq(
  $$SELECT public.mark_warmup_ready('00000000-0000-4000-e000-000000000b10')$$,
  $$VALUES (false)$$,
  'first present vote returns false');
RESET role;
SELECT ok(
  (SELECT lifting_started_at FROM sessions
    WHERE id = '00000000-0000-4000-e000-000000000b10') IS NULL,
  'lifting_started_at stays NULL while present votes are outstanding');

-- 6. Second of three present voters: still waiting.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b02';
SELECT results_eq(
  $$SELECT public.mark_warmup_ready('00000000-0000-4000-e000-000000000b10')$$,
  $$VALUES (false)$$,
  'second present vote returns false');

-- 7./8. THE FEATURE UNDER TEST: the LAST present vote (C, 'late') begins
--       lifting immediately — D (no_show) and E (left) are not waited on.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b03';
SELECT results_eq(
  $$SELECT public.mark_warmup_ready('00000000-0000-4000-e000-000000000b10')$$,
  $$VALUES (true)$$,
  'last present vote returns true');
RESET role;
SELECT ok(
  (SELECT lifting_started_at FROM sessions
    WHERE id = '00000000-0000-4000-e000-000000000b10') IS NOT NULL,
  'last present vote sets lifting_started_at');

-- 9. Proof the non-present states did not block: neither D nor E ever
--    voted, yet lifting started anyway.
SELECT results_eq(
  $$SELECT warmup_ready FROM session_participants
     WHERE session_id = '00000000-0000-4000-e000-000000000b10'
       AND user_id IN ('00000000-0000-4000-e000-000000000b04',
                       '00000000-0000-4000-e000-000000000b05')
     ORDER BY user_id$$,
  $$VALUES (false), (false)$$,
  'no_show and left never voted, and did not block unanimity');

-- 10./11. Force-start is organizer-only: B (participant, not organizer)
--         is rejected and changes nothing.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b02';
SELECT throws_ok(
  $$SELECT public.start_lifting('00000000-0000-4000-e000-000000000b11')$$,
  'P0001', 'only the organizer may start lifting',
  'a non-organizer cannot force-start');
RESET role;
SELECT ok(
  (SELECT lifting_started_at FROM sessions
    WHERE id = '00000000-0000-4000-e000-000000000b11') IS NULL,
  'a rejected force-start leaves lifting_started_at NULL');

-- 12./13. The organizer's force-start (AFK escape hatch) begins lifting
--         with votes still outstanding (nobody voted in b11).
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b01';
SELECT results_eq(
  $$SELECT public.start_lifting('00000000-0000-4000-e000-000000000b11')$$,
  $$VALUES (true)$$,
  'organizer force-start returns true');
RESET role;
SELECT ok(
  (SELECT lifting_started_at FROM sessions
    WHERE id = '00000000-0000-4000-e000-000000000b11') IS NOT NULL,
  'organizer force-start sets lifting_started_at');

-- 14. Replayed force-start is a no-op: lifting already began.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000b01';
SELECT results_eq(
  $$SELECT public.start_lifting('00000000-0000-4000-e000-000000000b11')$$,
  $$VALUES (false)$$,
  'a second force-start returns false');

RESET role;
SELECT * FROM finish();
ROLLBACK;
