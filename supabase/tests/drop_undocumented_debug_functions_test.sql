-- Debt-zero sprint / Task 3, item 1: drop of the 3 undocumented ad-hoc
-- debug functions (20260727000005_drop_undocumented_debug_functions.sql).
--
-- These functions had zero callers (proven live pre-drop via pg_trigger,
-- pg_depend, pg_policies, information_schema.views/triggers, and repo
-- grep — see the migration header and task-3-report.md) — there is no
-- "positive" behavior to preserve, so this test is entirely a
-- public-gone proof. (Phase B2 D3: a second regression guard, which
-- checked the real resolve_proposal() trigger's wiring on its
-- (now-retired) host table, retired along with that table's other pgTAP
-- references — see D4 for the drop itself.)
--
-- PHASE B2 D4 UPDATE, plan(7) -> plan(6): this file's own assertion 7 —
-- "the real resolve_proposal() trigger function ... is untouched" — was
-- true when written (it guarded against THIS migration's debug-function
-- cleanup accidentally taking the real one with it) but is false now
-- that D4 (20260918000102_routine_proposals_drop.sql) has deliberately
-- dropped public.resolve_proposal() itself: its only trigger lived on
-- routine_proposal_votes, which that migration also drops, and a
-- trigger's function does not go with it automatically (the same
-- reasoning R-B19 applied to the soundboard's touch trigger function).
-- Retired rather than flipped to assert absence — routine_proposals_
-- absent_test.sql (D5) already proves that, and this file's remaining
-- job is the three debug forks, not the function they forked from.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

-- ============================================================
-- 1-2. resolve_proposal_debug: gone from pg_proc, calling by name fails.
-- ============================================================
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'resolve_proposal_debug'$$,
  ARRAY[0],
  'public.resolve_proposal_debug no longer exists in any form'
);

SELECT throws_ok(
  $$SELECT public.resolve_proposal_debug()$$,
  '42883', NULL,
  'calling public.resolve_proposal_debug() by name now fails: function does not exist'
);

-- ============================================================
-- 3-4. resolve_proposal_debug2: gone from pg_proc, calling by name fails.
-- ============================================================
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'resolve_proposal_debug2'$$,
  ARRAY[0],
  'public.resolve_proposal_debug2 no longer exists in any form'
);

SELECT throws_ok(
  $$SELECT public.resolve_proposal_debug2()$$,
  '42883', NULL,
  'calling public.resolve_proposal_debug2() by name now fails: function does not exist'
);

-- ============================================================
-- 5-6. resolve_proposal_debug3: gone from pg_proc, calling by name fails.
-- ============================================================
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'resolve_proposal_debug3'$$,
  ARRAY[0],
  'public.resolve_proposal_debug3 no longer exists in any form'
);

SELECT throws_ok(
  $$SELECT public.resolve_proposal_debug3()$$,
  '42883', NULL,
  'calling public.resolve_proposal_debug3() by name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
