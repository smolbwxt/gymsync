-- Phase O / Task 1 sweep-proof, fix-wave 2: is_session_participant() dual-
-- function relocation (20260726000001_is_session_participant_dual_schema.sql)
-- — the one helper fix-wave 1 (7309db5) deliberately left blocked because
-- supabase/functions/livekit-token/index.ts calls it directly via a
-- service-role PostgREST RPC.
--
-- Unlike every other relocation in this sweep, public.is_session_participant
-- is NOT dropped — it becomes a narrow, service_role-only thin delegation to
-- private.is_session_participant. This file's headline content is proving
-- BOTH halves of that: the oracle is closed for authenticated/anon (the RPC
-- endpoint still exists but 42501s for every client-reachable role), AND the
-- one legitimate caller (service_role, matching livekit-token's exact call
-- shape) still works.
--
-- Representative dependent-policy re-proofs cover four distinct shapes:
-- direct policy call (sessions), direct policy call reading ANOTHER user's
-- row (session_participants), a policy with the helper called TWICE in one
-- WITH CHECK (session_kudos' sender+recipient gate), and a SQL-function-body
-- caller (touch_session_activity). The remaining 9 dependent surfaces (see
-- migration header for the full inventory of 13 policies + 6 function-body
-- callers) are re-proven by re-running the pre-existing suite post-push
-- against the now-repointed policies/bodies — same reasoning this sweep's
-- other test files already established (task-1-report.md, is_group_member's
-- 21-dependent file: "the 'both directions' re-proof ... comes from
-- re-running that pre-existing suite against the now-repointed policies").
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users (id, email) VALUES
  ('f2000000-0000-0000-0000-0000000000a1', 'f2a1@t.com'),  -- Dana: organizer, NOT a participant row
  ('f2000000-0000-0000-0000-0000000000a2', 'f2a2@t.com'),  -- Erin: participant
  ('f2000000-0000-0000-0000-0000000000a3', 'f2a3@t.com'),  -- Gina: participant (kudos recipient / other-row read)
  ('f2000000-0000-0000-0000-0000000000a4', 'f2a4@t.com');  -- Frank: outsider (neither organizer nor participant)
INSERT INTO profiles (id, username) VALUES
  ('f2000000-0000-0000-0000-0000000000a1', 'f2_dana'),
  ('f2000000-0000-0000-0000-0000000000a2', 'f2_erin'),
  ('f2000000-0000-0000-0000-0000000000a3', 'f2_gina'),
  ('f2000000-0000-0000-0000-0000000000a4', 'f2_frank');

INSERT INTO sessions (id, organizer_id, state, started_at, last_activity_at) VALUES
  ('f2000000-0000-0000-0000-000000000d01', 'f2000000-0000-0000-0000-0000000000a1',
   'in_progress', now() - interval '5 minutes', now() - interval '5 minutes');

INSERT INTO session_participants (session_id, user_id) VALUES
  ('f2000000-0000-0000-0000-000000000d01', 'f2000000-0000-0000-0000-0000000000a2'),  -- Erin
  ('f2000000-0000-0000-0000-000000000d01', 'f2000000-0000-0000-0000-0000000000a3');  -- Gina

-- ============================================================
-- 1-2. sessions SELECT ("users can select sessions they participate in")
--      — repointed to private.is_session_participant.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';  -- Erin (participant, not organizer)
SELECT results_eq(
  $$SELECT count(*)::int FROM sessions WHERE id = 'f2000000-0000-0000-0000-000000000d01'$$,
  ARRAY[1],
  'positive: a participant (not the organizer) can read the session via private.is_session_participant'
);

SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a4';  -- Frank (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM sessions WHERE id = 'f2000000-0000-0000-0000-000000000d01'$$,
  ARRAY[0],
  'negative: an outsider cannot read the session'
);

-- ============================================================
-- 3-4. session_participants SELECT ("participants readable by other
--      participants") — reading ANOTHER participant's row, not your own,
--      isolates the private.is_session_participant OR-branch from the
--      trivial user_id = auth.uid() branch.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';  -- Erin reading Gina's row
SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE session_id = 'f2000000-0000-0000-0000-000000000d01'
      AND user_id = 'f2000000-0000-0000-0000-0000000000a3'$$,
  ARRAY[1],
  'positive: a participant can read a DIFFERENT participant''s row (OR-branch, not self)'
);

SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a4';  -- Frank (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE session_id = 'f2000000-0000-0000-0000-000000000d01'$$,
  ARRAY[0],
  'negative: an outsider cannot read any participant row for this session'
);

-- ============================================================
-- 5-6. session_kudos INSERT ("session participants send kudos to session
--      participants") — the helper is called TWICE in this one WITH CHECK
--      (sender leg + recipient leg); both are exercised here.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';  -- Erin (sender, participant)
SELECT lives_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f2000000-0000-0000-0000-000000000d01', 'f2000000-0000-0000-0000-0000000000a2',
     'f2000000-0000-0000-0000-0000000000a3', '🔥')$$,
  'positive: a participant can send kudos to ANOTHER participant (both is_session_participant legs pass)'
);

SELECT throws_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f2000000-0000-0000-0000-000000000d01', 'f2000000-0000-0000-0000-0000000000a2',
     'f2000000-0000-0000-0000-0000000000a4', '💪')$$,
  '42501', NULL,
  'negative: a participant cannot send kudos to a non-participant (recipient leg fails)'
);

-- ============================================================
-- 7-8. touch_session_activity — SQL-function-body caller, repointed to
--      private.is_session_participant (OR'd with private.is_session_organizer).
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';  -- Erin (participant)
SELECT lives_ok(
  $$SELECT public.touch_session_activity('f2000000-0000-0000-0000-000000000d01')$$,
  'positive: a participant passes touch_session_activity''s repointed gate'
);

SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a4';  -- Frank (outsider, non-organizer)
SELECT throws_ok(
  $$SELECT public.touch_session_activity('f2000000-0000-0000-0000-000000000d01')$$,
  'P0001', 'only session participants may send an activity heartbeat',
  'negative: an outsider is rejected by touch_session_activity''s repointed gate'
);

-- ============================================================
-- 9-11. Relocation mechanics: direct-call correctness, no widening, schema
-- USAGE denial.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                           'f2000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true],
  'private.is_session_participant(session, Erin) is true: Erin is a participant'
);

SELECT results_eq(
  $$SELECT private.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                           'f2000000-0000-0000-0000-0000000000a4')$$,
  ARRAY[false],
  'no widening: private.is_session_participant(session, Frank) is false: Frank is not a participant'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';  -- Erin
SELECT throws_ok(
  $$SELECT private.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                           'f2000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot name private.is_session_participant directly: no USAGE on schema private'
);

-- ============================================================
-- 12-15. public.is_session_participant — dual-function design: the RPC
-- endpoint still exists (unlike every other relocation in this sweep) but
-- is now service_role-only. 12-13 prove the oracle is closed for every
-- client-reachable role; 14-15 prove livekit-token's exact call shape
-- (service-role RPC) still works AND is still correct.
-- ============================================================
RESET ROLE;
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f2000000-0000-0000-0000-0000000000a2';
SELECT throws_ok(
  $$SELECT public.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                          'f2000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot call public.is_session_participant directly: EXECUTE revoked'
);

SET LOCAL role anon;
SELECT throws_ok(
  $$SELECT public.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                          'f2000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'anon cannot call public.is_session_participant directly: EXECUTE revoked'
);

SET LOCAL role service_role;
SELECT results_eq(
  $$SELECT public.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                          'f2000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true],
  'positive: service_role (livekit-token''s exact call shape) can call public.is_session_participant and gets the correct true result'
);

SELECT results_eq(
  $$SELECT public.is_session_participant('f2000000-0000-0000-0000-000000000d01',
                                          'f2000000-0000-0000-0000-0000000000a4')$$,
  ARRAY[false],
  'correctness: service_role call for a non-participant (Frank) correctly returns false'
);

-- ============================================================
-- 16-17. Dual-function shape confirmed: public.is_session_participant still
-- exists (NOT dropped, unlike the other six relocations in this sweep) and
-- private.is_session_participant exists alongside it.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_session_participant'$$,
  ARRAY[1],
  'dual-function design: public.is_session_participant still exists (thin delegation, not dropped)'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'is_session_participant'$$,
  ARRAY[1],
  'dual-function design: private.is_session_participant exists (the real, unreachable-via-PostgREST implementation)'
);

SELECT * FROM finish();
ROLLBACK;
