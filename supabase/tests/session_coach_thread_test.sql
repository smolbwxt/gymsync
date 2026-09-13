BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

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

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e01';

-- 11. ADDITIVE, NOT SUBTRACTIVE. Proves the migration's own claim ("own
-- threads stays exactly as it is", 20260912000102:67-69): a personal thread
-- (session_id NULL) stays invisible to the new participant policy, which
-- requires session_id IS NOT NULL. B's otherwise-unreachable count is
-- captured into a temp table under B's role (the assertion-6 pattern,
-- applied to a second value) so one results_eq can compare it against A's
-- live count without a second call racing.
CREATE TEMP TABLE a_personal_thread AS
WITH ins AS (
  INSERT INTO public.coach_chat_threads (user_id, session_id, title)
  VALUES ('00000000-0000-4000-f000-000000000e01', NULL, 'personal')
  RETURNING id
)
SELECT id FROM ins;

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e02';

CREATE TEMP TABLE b_personal_count AS
SELECT count(*)::int AS n FROM public.coach_chat_threads
  WHERE id = (SELECT id FROM a_personal_thread);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e01';

SELECT results_eq(
  $$SELECT b.n, (SELECT count(*)::int FROM public.coach_chat_threads
                   WHERE id = (SELECT id FROM a_personal_thread))
    FROM b_personal_count b$$,
  $$VALUES (0, 1)$$,
  'personal thread stays private -- B (a fellow e10 participant) sees 0, A still sees 1');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e02';

-- 12. B posts to the crew's shared thread. Only the columns that are NOT
-- NULL with no default (20260824000002_coach_chat.sql:7-13: user_id, role,
-- body) plus thread_id (20260824000005:26, added later, nullable) are
-- supplied -- id and created_at keep their defaults.
SELECT lives_ok(
  $$INSERT INTO public.coach_chat_messages (user_id, thread_id, role, body)
    VALUES ('00000000-0000-4000-f000-000000000e02',
            (SELECT thread_id FROM a_opens_e10),
            'athlete', 'is anyone else sore today')$$,
  'B posts a message on e10''s session thread');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e01';

-- 13. A, who did not write it, reads B's message anyway. "own chat"
-- (20260824000002:27-29) would not apply -- A does not own this row -- so
-- this is "session thread messages readable by participants"
-- (20260912000102:85-91) at work, same as assertion 9 for the thread
-- itself.
SELECT is(
  (SELECT count(*) FROM coach_chat_messages
     WHERE thread_id = (SELECT thread_id FROM a_opens_e10))::int,
  1, 'A (a fellow participant) reads B''s message');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e04';

-- 14. D, an outsider to e10, sees nothing on the thread -- neither "own
-- chat" (the row is not D's) nor the participant policy (D is not a
-- participant) applies.
SELECT is(
  (SELECT count(*) FROM coach_chat_messages
     WHERE thread_id = (SELECT thread_id FROM a_opens_e10))::int,
  0, 'D sees 0 messages on a thread it is not part of');

-- 15. FIXED BY D5 (20260912000103_coach_chat_messages_scope_own_chat.sql).
-- "session thread messages postable by participants" (20260912000102:93-100)
-- WITH CHECK still correctly evaluates false for D. "own chat"
-- (20260824000002:27-29, tightened by 20260912000103) is no longer a blank
-- check on this table -- its WITH CHECK now also requires
-- private.coach_thread_owner(thread_id) = auth.uid(), and e10's thread is
-- owned by A, not D. Both permissive policies now reject the row, and a
-- single-row INSERT ... VALUES with no policy left to satisfy raises 42501
-- rather than silently inserting nothing -- there is no pre-existing row
-- for a USING clause to filter here, unlike the UPDATE case in
-- session_participant_energy_test.sql assertion 7.
SELECT throws_ok(
  $$INSERT INTO public.coach_chat_messages (user_id, thread_id, role, body)
    VALUES ('00000000-0000-4000-f000-000000000e04',
            (SELECT thread_id FROM a_opens_e10),
            'athlete', 'd is not in this crew')$$,
  '42501', NULL,
  'D''s insert now fails -- "own chat" is scoped to the thread''s owner, and D is not one');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e02';

-- 16. The same fix closes the door on A's personal thread too, not just
-- session threads. B is a fellow e10 participant but owns none of A's
-- personal thread (a_personal_thread, assertion 11), and that thread has
-- no session_id for the participant policy to key off of either --
-- coach_thread_owner(a_personal_thread) = A, not B, so "own chat" rejects
-- it exactly like assertion 15 rejects D.
SELECT throws_ok(
  $$INSERT INTO public.coach_chat_messages (user_id, thread_id, role, body)
    VALUES ('00000000-0000-4000-f000-000000000e02',
            (SELECT id FROM a_personal_thread),
            'athlete', 'peeking into a thread that is not mine')$$,
  '42501', NULL,
  'B cannot insert into A''s personal thread');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000e01';

-- 17. ADDITIVE, NOT SUBTRACTIVE, take two: A can still post to A's own
-- personal thread -- coach_thread_owner(a_personal_thread) = A = auth.uid(),
-- the same shape every athlete message and on-device Coach reply takes
-- (CoachChatRepository.append, CoachChat.swift:112-129) and D5 leaves
-- untouched.
SELECT lives_ok(
  $$INSERT INTO public.coach_chat_messages (user_id, thread_id, role, body)
    VALUES ('00000000-0000-4000-f000-000000000e01',
            (SELECT id FROM a_personal_thread),
            'coach', 'noted -- how did the lift feel')$$,
  'A can still post to their own personal thread');

SELECT * FROM finish();
ROLLBACK;
