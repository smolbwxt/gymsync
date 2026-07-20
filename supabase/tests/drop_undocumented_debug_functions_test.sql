-- Debt-zero sprint / Task 3, item 1: drop of the 3 undocumented ad-hoc
-- debug functions (20260727000005_drop_undocumented_debug_functions.sql).
--
-- These functions had zero callers (proven live pre-drop via pg_trigger,
-- pg_depend, pg_policies, information_schema.views/triggers, and repo
-- grep — see the migration header and task-3-report.md) — there is no
-- "positive" behavior to preserve, so this test is entirely a
-- public-gone proof, plus two regression guards confirming the real
-- resolve_proposal() trigger (which these were instrumented forks of)
-- and its wiring on routine_proposal_votes are untouched.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

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

-- ============================================================
-- 7-8. Regression guard: the REAL resolve_proposal() trigger (which
-- the 3 dropped functions were instrumented forks of) and its wiring
-- on routine_proposal_votes are untouched by this migration.
-- ============================================================
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'resolve_proposal'$$,
  ARRAY[1],
  'public.resolve_proposal (the real trigger function) still exists, untouched'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_proc p ON t.tgfoid = p.oid
    WHERE c.relname = 'routine_proposal_votes' AND t.tgname = 'proposal_vote_cast'
      AND p.proname = 'resolve_proposal' AND NOT t.tgisinternal$$,
  ARRAY[1],
  'proposal_vote_cast trigger on routine_proposal_votes is still wired to resolve_proposal'
);

SELECT * FROM finish();
ROLLBACK;
