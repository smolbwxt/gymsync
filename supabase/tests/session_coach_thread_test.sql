BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Migration under test: 20260912000102_session_coach_thread.sql
-- (coach_chat_threads.session_id, private.session_has_pro,
-- private.coach_thread_session_id, public.session_coach_thread). Plan
-- task D4. Fixture block: 0exx UUIDs (this suite's namespace, constraint 17
-- -- 0exx was free alongside 0axx/D2; 09xx already collides between
-- rotation_presence_test.sql and crew_consistency_honor_test.sql).
--   A = ...0e01 organizer, never Pro   B = ...0e02 crewmate, never Pro
--   C = ...0e03 crewmate, Pro (pro_until = now() + 30 days), e10 only
--   D = ...0e04, a non-participant of either session
--   Session e10 (...0e10): A, B, C -- one Pro member, the crew's thread
--     should unlock.
--   Session e11 (...0e11): A, B only -- nobody Pro, stays locked.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000e01', 'coach-a@test.local'),
  ('00000000-0000-4000-f000-000000000e02', 'coach-b@test.local'),
  ('00000000-0000-4000-f000-000000000e03', 'coach-c@test.local'),
  ('00000000-0000-4000-f000-000000000e04', 'coach-d@test.local');
-- pro_until set directly at fixture time -- guard_pro_until only blocks the
-- authenticated/anon roles (20260730000004_pro_entitlement.sql), and no
-- SET LOCAL role has run yet in this transaction (the same bypass
-- curation_test.sql uses for is_curator).
INSERT INTO profiles (id, username, pro_until) VALUES
  ('00000000-0000-4000-f000-000000000e01', 'coach_a', NULL),
  ('00000000-0000-4000-f000-000000000e02', 'coach_b', NULL),
  ('00000000-0000-4000-f000-000000000e03', 'coach_c', now() + interval '30 days'),
  ('00000000-0000-4000-f000-000000000e04', 'coach_d', NULL);

INSERT INTO sessions (id, organizer_id, state, started_at) VALUES
  ('00000000-0000-4000-f000-000000000e10',
   '00000000-0000-4000-f000-000000000e01', 'in_progress', now()),
  ('00000000-0000-4000-f000-000000000e11',
   '00000000-0000-4000-f000-000000000e01', 'in_progress', now());
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000e10', '00000000-0000-4000-f000-000000000e01'),
  ('00000000-0000-4000-f000-000000000e10', '00000000-0000-4000-f000-000000000e02'),
  ('00000000-0000-4000-f000-000000000e10', '00000000-0000-4000-f000-000000000e03'),
  ('00000000-0000-4000-f000-000000000e11', '00000000-0000-4000-f000-000000000e01'),
  ('00000000-0000-4000-f000-000000000e11', '00000000-0000-4000-f000-000000000e02');
-- D is a participant of neither session.

-- 1-2. The key column, checked before any role switch (precedent:
-- curation_test.sql:19-20).
SELECT has_column('public', 'coach_chat_threads', 'session_id',
  'coach_chat_threads.session_id exists');
SELECT col_type_is('public', 'coach_chat_threads', 'session_id', 'uuid',
  'session_id is uuid');

-- 3. One Pro member lights the whole crew's thread (decision 19).
-- session_has_pro is SECURITY DEFINER and takes no caller identity, so it
-- can be called before any role switch too.
SELECT ok(
  private.session_has_pro('00000000-0000-4000-f000-000000000e10'),
  'session_has_pro is true for e10 -- C is Pro');

-- 4. No Pro member, no unlock.
SELECT ok(
  NOT private.session_has_pro('00000000-0000-4000-f000-000000000e11'),
  'session_has_pro is false for e11 -- nobody is Pro');

-- 5. THE CLOCK, NOT THE COLUMN. session_has_pro filters on
-- pro_until > now(), not merely IS NOT NULL -- a lapsed membership must not
-- unlock the thread.
UPDATE profiles SET pro_until = now() - interval '1 day'
  WHERE id = '00000000-0000-4000-f000-000000000e02';
SELECT ok(
  NOT private.session_has_pro('00000000-0000-4000-f000-000000000e11'),
  'a lapsed pro_until does not unlock -- the gate reads the clock');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e01';

-- 6. A finds (creates) e10's thread, unlocked. Captured into a temp table
-- (visible for the rest of this transaction, rolled back with everything
-- else) so assertion 7 can prove B lands in the SAME room without a second
-- call racing a fresh creation.
CREATE TEMP TABLE a_opens_e10 AS
SELECT * FROM public.session_coach_thread('00000000-0000-4000-f000-000000000e10');

SELECT results_eq(
  $$SELECT thread_id IS NOT NULL, unlocked FROM a_opens_e10$$,
  $$VALUES (true, true)$$,
  'A opens e10''s thread: a real thread_id, unlocked true (C is Pro)');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e02';

-- 7. B lands in the SAME room -- one thread per session, not two. The
-- unique index (coach_chat_threads_session_key) is what makes this a
-- find, not a second create.
SELECT results_eq(
  $$SELECT thread_id FROM public.session_coach_thread('00000000-0000-4000-f000-000000000e10')$$,
  $$SELECT thread_id FROM a_opens_e10$$,
  'B finds the same thread_id A did -- one room, not two');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e04';

-- 8. D is not a participant of e10 -- the RPC's own gate throws before it
-- ever touches coach_chat_threads.
SELECT throws_ok(
  $$SELECT * FROM public.session_coach_thread('00000000-0000-4000-f000-000000000e10')$$,
  'P0001', 'not a participant of this session',
  'a non-participant cannot open the session thread');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e02';

-- 9. B reads the thread it does not own. "own threads" (20260824000005:
-- 20-23, USING (user_id = auth.uid())) alone would have hidden it -- this
-- is the new "session threads readable by participants" policy at work.
SELECT is(
  (SELECT count(*) FROM coach_chat_threads
     WHERE session_id = '00000000-0000-4000-f000-000000000e10')::int,
  1, 'B sees the session thread it does not own');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e04';

-- 10. D, a non-participant, cannot see the room exists -- neither policy
-- (own threads, or the participant read) applies to D.
SELECT is(
  (SELECT count(*) FROM coach_chat_threads
     WHERE session_id = '00000000-0000-4000-f000-000000000e10')::int,
  0, 'D cannot see e10''s thread exists');

SELECT * FROM finish();
ROLLBACK;
