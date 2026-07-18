-- Phase O / Task 1 sweep-proof: is_solo_session() relocated to private
-- schema (20260725000004_is_solo_session_private_schema.sql).
--
-- The one dependent policy ("set_logs read: owner, participant, or
-- opted-in friend" ON set_logs) already has thorough positive/negative
-- coverage in supabase/tests/rls_set_logs_test.sql (friend before/after
-- opt-in, stranger, cross-friend isolation, both block directions) — a
-- full-suite green run after this migration re-proves those directions.
-- This file adds the one genuinely new angle: is_solo_session's OWN gate,
-- isolated from is_friend's (an accepted, opted-in friend must still be
-- denied for a MULTI-participant session, proving the solo-only scope
-- holds specifically because is_solo_session evaluates false there, not
-- because of any other clause) — plus the relocation-mechanics proof.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('e4000000-0000-0000-0000-0000000000a1', 'e4a1@t.com'),  -- Ari: solo owner, opted in
  ('e4000000-0000-0000-0000-0000000000a2', 'e4a2@t.com'),  -- Fen: accepted friend of Ari
  ('e4000000-0000-0000-0000-0000000000a3', 'e4a3@t.com');  -- Bo: second participant in Ari's group session
INSERT INTO profiles (id, username, show_solo_workouts) VALUES
  ('e4000000-0000-0000-0000-0000000000a1', 'e4_ari', true),
  ('e4000000-0000-0000-0000-0000000000a2', 'e4_fen', true),
  ('e4000000-0000-0000-0000-0000000000a3', 'e4_bo', true);
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('e4000000-0000-0000-0000-0000000000a1', 'e4000000-0000-0000-0000-0000000000a2', 'accepted');

-- Solo session: Ari is the ONLY session_participants row -> is_solo_session = true.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('e4000000-0000-0000-0000-000000000d01', 'e4000000-0000-0000-0000-0000000000a1', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('e4000000-0000-0000-0000-000000000d01', 'e4000000-0000-0000-0000-0000000000a1');

-- Multi-participant session: Ari + Bo -> is_solo_session = false, even
-- though Ari still has show_solo_workouts = true globally.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('e4000000-0000-0000-0000-000000000d02', 'e4000000-0000-0000-0000-0000000000a1', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('e4000000-0000-0000-0000-000000000d02', 'e4000000-0000-0000-0000-0000000000a1'),
  ('e4000000-0000-0000-0000-000000000d02', 'e4000000-0000-0000-0000-0000000000a3');

WITH e AS (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT 'e4000000-0000-0000-0000-00000000f001', 'e4000000-0000-0000-0000-0000000000a1',
       'e4000000-0000-0000-0000-000000000d01', e.id, 1, 5, 100 FROM e;
WITH e AS (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT 'e4000000-0000-0000-0000-00000000f002', 'e4000000-0000-0000-0000-0000000000a1',
       'e4000000-0000-0000-0000-000000000d02', e.id, 1, 5, 100 FROM e;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e4000000-0000-0000-0000-0000000000a2';  -- Fen (accepted friend, not a participant of either session)

SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs WHERE id = 'e4000000-0000-0000-0000-00000000f001'$$,
  ARRAY[1],
  'positive: friend reads the SOLO session log via private.is_solo_session'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs WHERE id = 'e4000000-0000-0000-0000-00000000f002'$$,
  ARRAY[0],
  'negative: same opted-in friend is denied the MULTI-participant session log — is_solo_session gates it, not is_friend'
);

-- ============================================================
-- Relocation proof — direct-call correctness, schema lockdown, oracle
-- closed, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_solo_session('e4000000-0000-0000-0000-000000000d01')$$,
  ARRAY[true],
  'private.is_solo_session is true for the single-participant session'
);

SELECT results_eq(
  $$SELECT private.is_solo_session('e4000000-0000-0000-0000-000000000d02')$$,
  ARRAY[false],
  'no widening: private.is_solo_session is false for the two-participant session'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e4000000-0000-0000-0000-0000000000a1';  -- Ari

SELECT throws_ok(
  $$SELECT private.is_solo_session('e4000000-0000-0000-0000-000000000d01')$$,
  '42501', NULL,
  'authenticated cannot name private.is_solo_session directly: no USAGE on schema private'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_solo_session'$$,
  ARRAY[0],
  'public.is_solo_session no longer exists in any form — the oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.is_solo_session('e4000000-0000-0000-0000-000000000d01')$$,
  '42883', NULL,
  'calling public.is_solo_session by (schema-qualified) name now fails: function does not exist'
);

-- Sanity: the migration also transplanted the is_friend / is_blocked
-- clauses in this same policy unchanged — confirm the owner can still
-- always read their own logs regardless of any of this (user_id =
-- auth.uid() clause, untouched by this migration).
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e4000000-0000-0000-0000-0000000000a1';  -- Ari (owner)
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE session_id IN ('e4000000-0000-0000-0000-000000000d01',
                          'e4000000-0000-0000-0000-000000000d02')$$,
  ARRAY[2],
  'regression: owner still reads both of their own set logs unaffected by the relocation'
);

SELECT * FROM finish();
ROLLBACK;
