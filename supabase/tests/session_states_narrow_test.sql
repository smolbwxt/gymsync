BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

-- Migration under test: 20260913000103_session_states_narrow.sql
-- (sessions_state_check narrowed to scheduled/lobby_open/in_progress/
-- completed/abandoned -- "the five data decisions," decision 6, the three
-- dead states). Plan task D8. Fixture block: 12xx UUIDs (this suite's
-- namespace, constraint 17 -- 01xx-09xx, 0axx-0fxx, 10xx and 11xx are
-- already spoken for (0fxx by D2, 10xx by D4, 11xx reserved for D6); 12xx
-- was grepped repo-wide against supabase/ and scripts/ before writing this
-- and had no hits).
--   A = ...1201 organizer (fixture only). No RLS is under test here, so
--       there is no role switch: these INSERTs run as the pgTAP
--       transaction's default role, exactly as D2's own fixture rows do
--       before its first SET LOCAL role -- the CHECK fires (or doesn't)
--       for any role that can reach the table, and proving that without
--       adding a role switch keeps this suite about the CHECK alone.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000001201', 'narrow-a@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000001201', 'narrow_a');

-- 1-3. The three dead states Phase A costed and deferred -- none of them
-- can be written into sessions.state any more.
SELECT throws_ok(
  $$INSERT INTO sessions (id, organizer_id, state) VALUES
    ('00000000-0000-4000-f000-000000001202',
     '00000000-0000-4000-f000-000000001201', 'editing')$$,
  '23514', NULL, 'editing is rejected -- the narrowed CHECK no longer admits it');

SELECT throws_ok(
  $$INSERT INTO sessions (id, organizer_id, state) VALUES
    ('00000000-0000-4000-f000-000000001203',
     '00000000-0000-4000-f000-000000001201', 'voting')$$,
  '23514', NULL, 'voting is rejected -- the narrowed CHECK no longer admits it');

SELECT throws_ok(
  $$INSERT INTO sessions (id, organizer_id, state) VALUES
    ('00000000-0000-4000-f000-000000001204',
     '00000000-0000-4000-f000-000000001201', 'locked')$$,
  '23514', NULL, 'locked is rejected -- the narrowed CHECK no longer admits it');

-- 4. lobby_open still succeeds -- the CHECK narrowed around the three dead
-- states, it did not tighten around any of the five that remain live.
SELECT lives_ok(
  $$INSERT INTO sessions (id, organizer_id, state) VALUES
    ('00000000-0000-4000-f000-000000001205',
     '00000000-0000-4000-f000-000000001201', 'lobby_open')$$,
  'lobby_open still succeeds -- the narrowed CHECK keeps the five live states');

SELECT * FROM finish();
ROLLBACK;
