BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@t.com');

INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a'),
  ('00000000-0000-0000-0000-000000000002', 'user_b');

INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'A Private', 'private'),
  ('10000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000002', 'B Private', 'private');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Positive: user A can read their own routine
SELECT results_eq(
  $$SELECT count(*)::int FROM routines WHERE owner_id='00000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'user can read own routines'
);

-- Negative: user A cannot see user B's private routine
SELECT results_eq(
  $$SELECT count(*)::int FROM routines WHERE owner_id='00000000-0000-0000-0000-000000000002'$$,
  ARRAY[0],
  'user cannot read others private routines'
);

-- Positive: user A can insert their own routine
SELECT lives_ok(
  $$INSERT INTO routines (owner_id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'New')$$,
  'user can insert own routine'
);

-- Negative: user A cannot insert as user B (INSERT WITH CHECK raises 42501)
SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name) VALUES ('00000000-0000-0000-0000-000000000002', 'Hack')$$,
  '42501',
  NULL,
  'user cannot insert routine owned by another'
);

SELECT * FROM finish();
ROLLBACK;
