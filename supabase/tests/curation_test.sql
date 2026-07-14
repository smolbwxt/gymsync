BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Fixture users (pattern from user_settings_test.sql: insert auth.users +
-- profiles rows inside the rolled-back txn)
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-a000-000000000101', 'cur-test-plain@test.local'),
  ('00000000-0000-4000-a000-000000000102', 'cur-test-curator@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-a000-000000000101', 'cur_plain'),
  ('00000000-0000-4000-a000-000000000102', 'cur_curator');
UPDATE profiles SET is_curator = true
  WHERE id = '00000000-0000-4000-a000-000000000102';

-- 1-2. Catalog columns exist
SELECT has_column('public','soundboard_sounds','icon','icon column exists');
SELECT has_column('public','soundboard_sounds','category','category column exists');

-- 3. Backfill applied (fixture-scoped to the known seed slug)
SELECT is(
  (SELECT icon FROM soundboard_sounds WHERE slug = 'airhorn'),
  '📯', 'airhorn backfilled with emoji icon');

-- 4-5. Favorites RLS: owner can write, non-owner blocked
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000101';
INSERT INTO soundboard_favorites (user_id, slugs)
  VALUES ('00000000-0000-4000-a000-000000000101', ARRAY['ding','boo']);
SELECT is(
  (SELECT slugs FROM soundboard_favorites
   WHERE user_id = '00000000-0000-4000-a000-000000000101'),
  ARRAY['ding','boo'], 'owner writes+reads own favorites');
SELECT throws_ok(
  $$INSERT INTO soundboard_favorites (user_id, slugs)
    VALUES ('00000000-0000-4000-a000-000000000102', ARRAY['ding'])$$,
  '42501', NULL, 'cannot insert favorites for another user');

-- 6. is_curator not client-writable (column privilege)
SELECT throws_ok(
  $$UPDATE profiles SET is_curator = true
    WHERE id = '00000000-0000-4000-a000-000000000101'$$,
  '42501', NULL, 'authenticated cannot self-promote to curator');

-- 7. Non-curator cannot publish
SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name, visibility)
    VALUES ('00000000-0000-4000-a000-000000000101', 'Sneaky Public', 'public')$$,
  '42501', NULL, 'non-curator cannot insert public routine');

-- 8. Non-curator private insert still works
INSERT INTO routines (owner_id, name, visibility)
  VALUES ('00000000-0000-4000-a000-000000000101', 'My Private', 'private');
SELECT pass('non-curator private insert unaffected');

-- 9-10. Curator can publish; everyone can read it
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000102';
INSERT INTO routines (owner_id, name, visibility)
  VALUES ('00000000-0000-4000-a000-000000000102', 'Featured Pack', 'public');
SELECT pass('curator publishes public routine');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000101';
SELECT is(
  (SELECT count(*) FROM routines
   WHERE name = 'Featured Pack' AND visibility = 'public')::int,
  1, 'other users see the published routine');

SELECT * FROM finish();
ROLLBACK;
