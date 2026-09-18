-- Debt-zero sprint / Task 3, item 1: drop of the 3 undocumented ad-hoc
-- debug functions (20260727000005_drop_undocumented_debug_functions.sql).
--
-- These functions had zero callers (proven live pre-drop via pg_trigger,
-- pg_depend, pg_policies, information_schema.views/triggers, and repo
-- grep — see the migration header and task-3-report.md) — there is no
-- "positive" behavior to preserve, so this test is entirely a
-- public-gone proof, plus a regression guard confirming the real
-- resolve_proposal() trigger (which these were instrumented forks of)
-- is untouched. (Phase B2 D3: the second regression guard, which checked
-- this trigger's wiring on its (now-retired) host table, retired along
-- with that table's other pgTAP references — see D4 for the drop itself.)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

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
-- 7. Regression guard: the REAL resolve_proposal() trigger function
-- (which the 3 dropped functions were instrumented forks of) is
-- untouched by this migration.
-- ============================================================
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'resolve_proposal'$$,
  ARRAY[1],
  'public.resolve_proposal (the real trigger function) still exists, untouched'
);

SELECT * FROM finish();
ROLLBACK;
