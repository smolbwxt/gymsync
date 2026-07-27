BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

-- pro_until guard (20260730000004): the entitlement is server-written only.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000601', 'pro-a@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000601', 'pro_a');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000601';

-- 1. A client cannot grant themself Pro.
SELECT throws_ok(
  $$UPDATE profiles SET pro_until = now() + interval '10 years'
    WHERE id = '00000000-0000-4000-f000-000000000601'$$,
  '42501', NULL, 'client cannot self-grant pro_until');

-- 2. Ordinary profile edits are untouched by the guard.
SELECT lives_ok(
  $$UPDATE profiles SET username = 'pro_a2'
    WHERE id = '00000000-0000-4000-f000-000000000601'$$,
  'normal profile update unaffected');

-- 3. A crafted signup INSERT cannot arrive pre-entitled.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000602';
SET LOCAL role postgres;
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000602', 'pro-b@test.local');
SET LOCAL role authenticated;
SELECT throws_ok(
  $$INSERT INTO profiles (id, username, pro_until)
    VALUES ('00000000-0000-4000-f000-000000000602', 'pro_b', now() + interval '10 years')$$,
  '42501', NULL, 'signup INSERT cannot self-grant pro_until');

SELECT * FROM finish();
ROLLBACK;
