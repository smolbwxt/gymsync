BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

-- Migration under test: 20260918000102_routine_proposals_drop.sql (task
-- D4/D5). Proves the routine-proposal flow's tables, its three functions
-- and its publication membership are all gone. Pure catalog checks, no
-- fixture rows needed.
--
-- Fixture block: 14xx (reserved by this plan's own brief for this file;
-- grepped fresh against the branch before writing — 11xx-13xx and 15xx
-- are taken by other suites on this branch).
--
-- SIX assertions, not the brief's four: the brief's plan(4) named only
-- private.proposal_session_id, written before D4 additionally dropped
-- public.on_proposal_insert() and public.resolve_proposal() (R-B19-style
-- orphaned-trigger-function cleanup, not named by decision text — see
-- D4's own header). This suite proves all three are gone, not one.

-- 1/2. The two tables are gone.
SELECT hasnt_table('public', 'routine_proposals',
  'routine_proposals no longer exists');
SELECT hasnt_table('public', 'routine_proposal_votes',
  'routine_proposal_votes no longer exists');

-- 3/4/5. All three functions the drop removed are gone: the session_id
-- oracle decision text names, and the two orphaned trigger functions D4
-- added.
SELECT hasnt_function('private', 'proposal_session_id',
  'private.proposal_session_id no longer exists');
SELECT hasnt_function('public', 'on_proposal_insert',
  'public.on_proposal_insert no longer exists');
SELECT hasnt_function('public', 'resolve_proposal',
  'public.resolve_proposal no longer exists');

-- 6. Neither table is a member of supabase_realtime any more -- the
-- explicit ALTER PUBLICATION ... DROP TABLE lines, not just the implicit
-- removal DROP TABLE would have done, so a hand-edited publication that
-- had drifted from the migration would have failed loudly instead.
SELECT is_empty(
  $$SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename LIKE 'routine_proposal%'$$,
  'neither routine_proposals nor routine_proposal_votes is published any more');

SELECT * FROM finish();
ROLLBACK;
