-- Phase B2 D3: all four assertions here exercised the session-proposal
-- bootstrap flow (20260712000007_routine_bootstrap.sql) — a single INSERT
-- into the (now-retired) proposal table fired a trigger chain that
-- assertions 3-4 then inspected the side effects of (sessions.routine_id,
-- routine_exercises). With the INSERT retired (assertions 1-2, which
-- named the proposal table directly), assertions 3-4 have no setup left
-- to test — they are not "unrelated" assertions to keep, they are
-- downstream of the same retired flow. All four retire together, ahead of
-- D4's drop of the two proposal tables (constraint 9's irreversible-gate
-- protocol).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(0);
SELECT * FROM finish();
ROLLBACK;
