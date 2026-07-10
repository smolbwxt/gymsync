BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

-- Setup as postgres: auth users + profiles (impersonation is reserved for assertions)
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@test.com'),
  ('00000000-0000-0000-0000-000000000003', 'c@test.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a'),
  ('00000000-0000-0000-0000-000000000002', 'user_b');

-- Impersonate user A
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Positive: user A can update their own profile (exactly 1 row affected)
SELECT results_eq(
  $$WITH u AS (UPDATE profiles SET display_name='Alpha'
               WHERE id='00000000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM u$$,
  ARRAY[1],
  'user can update own profile'
);

-- Negative: user A cannot update user B's profile.
-- RLS USING silently filters the row (no error), so assert 0 rows affected.
SELECT results_eq(
  $$WITH u AS (UPDATE profiles SET display_name='hack'
               WHERE id='00000000-0000-0000-0000-000000000002' RETURNING 1)
    SELECT count(*)::int FROM u$$,
  ARRAY[0],
  'user cannot update other profile'
);

-- Positive: authenticated user can read any profile (public directory)
SELECT results_eq(
  $$SELECT count(*)::int FROM profiles WHERE id='00000000-0000-0000-0000-000000000002'$$,
  ARRAY[1],
  'user can read other profile'
);

-- Negative: duplicate username rejected. User C inserts under their OWN id
-- (passes RLS WITH CHECK) so the unique index is what fires -> 23505.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
SELECT throws_ok(
  $$INSERT INTO profiles (id, username)
    VALUES ('00000000-0000-0000-0000-000000000003', 'user_a')$$,
  '23505',
  NULL,
  'duplicate username rejected'
);

SELECT * FROM finish();
ROLLBACK;
