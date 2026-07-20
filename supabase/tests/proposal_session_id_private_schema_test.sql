-- Debt-zero sprint / Task 1, item 3: proposal_session_id() relocated to
-- private schema (20260727000004_proposal_session_id_private_schema.sql).
--
-- Both dependent policies (routine_proposal_votes SELECT/INSERT) wrap the
-- call as private.is_session_participant(private.proposal_session_id(...),
-- auth.uid()) — proposal_session_id supplies the session_id operand.
-- proposal_type is deliberately 'reorder' with an empty
-- ordered_routine_exercise_ids payload throughout: routine_proposals'
-- AFTER INSERT trigger (on_proposal_insert) auto-casts the proposer's own
-- approve vote, and routine_proposal_votes' AFTER INSERT trigger
-- (resolve_proposal) applies the proposal once votes are unanimous — an
-- empty-array reorder is a safe no-op apply regardless of whether a given
-- assertion happens to reach unanimity, so the fixture doesn't have to
-- fight the resolution trigger to stay "open."
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

INSERT INTO auth.users (id, email) VALUES
  ('f8000000-0000-0000-0000-0000000000a1', 'f8a1@t.com'),  -- Olive: organizer + participant of session 1, proposes proposal 1
  ('f8000000-0000-0000-0000-0000000000a2', 'f8a2@t.com'),  -- Priya: participant of session 1
  ('f8000000-0000-0000-0000-0000000000a3', 'f8a3@t.com'),  -- Xander: outsider, not a participant of session 1
  ('f8000000-0000-0000-0000-0000000000a4', 'f8a4@t.com');  -- Wendy: organizer + sole participant of session 2, proposes proposal 2
INSERT INTO profiles (id, username) VALUES
  ('f8000000-0000-0000-0000-0000000000a1', 'f8_olive'),
  ('f8000000-0000-0000-0000-0000000000a2', 'f8_priya'),
  ('f8000000-0000-0000-0000-0000000000a3', 'f8_xander'),
  ('f8000000-0000-0000-0000-0000000000a4', 'f8_wendy');

-- Session 1 + proposal 1 — the session/proposal pair under RLS test.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('f8000000-0000-0000-0000-000000000b01', 'f8000000-0000-0000-0000-0000000000a1', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('f8000000-0000-0000-0000-000000000b01', 'f8000000-0000-0000-0000-0000000000a1'),
  ('f8000000-0000-0000-0000-000000000b01', 'f8000000-0000-0000-0000-0000000000a2');

-- Session 2 + proposal 2 — unrelated session, used only for the
-- no-widening direct-call proof.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('f8000000-0000-0000-0000-000000000b02', 'f8000000-0000-0000-0000-0000000000a4', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('f8000000-0000-0000-0000-000000000b02', 'f8000000-0000-0000-0000-0000000000a4');

SET LOCAL role authenticated;

-- ============================================================
-- 1-2. Fixture steps (both are pgTAP assertions, counted in plan(11)):
-- Olive and Wendy each propose on their own session, auto-casting their own
-- approve vote via the on_proposal_insert trigger.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a1';  -- Olive
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload) VALUES
    ('f8000000-0000-0000-0000-000000000c01', 'f8000000-0000-0000-0000-000000000b01',
     'f8000000-0000-0000-0000-0000000000a1', 'reorder',
     '{"ordered_routine_exercise_ids": []}'::jsonb)$$,
  'fixture step: Olive proposes on session 1 (auto-casts her own approve vote via on_proposal_insert)'
);

SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a4';  -- Wendy
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload) VALUES
    ('f8000000-0000-0000-0000-000000000c02', 'f8000000-0000-0000-0000-000000000b02',
     'f8000000-0000-0000-0000-0000000000a4', 'reorder',
     '{"ordered_routine_exercise_ids": []}'::jsonb)$$,
  'fixture step: Wendy proposes on session 2 (unanimous immediately — sole participant — harmless empty-reorder apply)'
);

-- ============================================================
-- 3-4. routine_proposal_votes SELECT ("session participants read votes").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a2';  -- Priya (participant of session 1)
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposal_votes WHERE proposal_id = 'f8000000-0000-0000-0000-000000000c01'$$,
  ARRAY[1],
  'positive: a session participant reads proposal 1''s votes via private.proposal_session_id (sees Olive''s auto-vote)'
);

SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a3';  -- Xander (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposal_votes WHERE proposal_id = 'f8000000-0000-0000-0000-000000000c01'$$,
  ARRAY[0],
  'negative: a non-participant cannot read proposal 1''s votes'
);

-- ============================================================
-- 5-6. routine_proposal_votes INSERT ("session participants vote as
-- themselves").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a2';  -- Priya
SELECT lives_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('f8000000-0000-0000-0000-000000000c01', 'f8000000-0000-0000-0000-0000000000a2', 'approve')$$,
  'positive: a session participant casts her own vote on proposal 1 (reaches unanimity — harmless empty-reorder apply)'
);

SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a3';  -- Xander (outsider)
SELECT throws_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('f8000000-0000-0000-0000-000000000c01', 'f8000000-0000-0000-0000-0000000000a3', 'approve')$$,
  '42501', NULL,
  'negative: a non-participant cannot vote on proposal 1'
);

-- ============================================================
-- 7-8. Relocation proof — direct-call correctness, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.proposal_session_id('f8000000-0000-0000-0000-000000000c01')$$,
  ARRAY['f8000000-0000-0000-0000-000000000b01'::uuid],
  'private.proposal_session_id(proposal 1) resolves to session 1'
);

SELECT results_eq(
  $$SELECT private.proposal_session_id('f8000000-0000-0000-0000-000000000c02')$$,
  ARRAY['f8000000-0000-0000-0000-000000000b02'::uuid],
  'no widening: private.proposal_session_id(proposal 2) resolves to session 2, not session 1'
);

-- ============================================================
-- 9. Schema USAGE denial.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f8000000-0000-0000-0000-0000000000a2';  -- Priya

SELECT throws_ok(
  $$SELECT private.proposal_session_id('f8000000-0000-0000-0000-000000000c01')$$,
  '42501', NULL,
  'authenticated cannot name private.proposal_session_id directly: no USAGE on schema private'
);

-- ============================================================
-- 10-11. Oracle closed: gone from public, calling by name fails.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'proposal_session_id'$$,
  ARRAY[0],
  'public.proposal_session_id no longer exists in any form — the oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.proposal_session_id('f8000000-0000-0000-0000-000000000c01')$$,
  '42883', NULL,
  'calling public.proposal_session_id by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
