BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(1);
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND tablename='friendships'$$,
  ARRAY[1], 'friendships table is in the realtime publication');
SELECT * FROM finish();
ROLLBACK;
