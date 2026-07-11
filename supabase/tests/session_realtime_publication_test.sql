BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(1);
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_publication_tables
    WHERE pubname='supabase_realtime'
      AND tablename IN ('sessions','session_participants',
                        'routine_proposals','routine_proposal_votes')$$,
  ARRAY[4], 'all four session tables are in the realtime publication');
SELECT * FROM finish();
ROLLBACK;
