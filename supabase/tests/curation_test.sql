BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

-- Fixture users (pattern from user_settings_test.sql: insert auth.users +
-- profiles rows inside the rolled-back txn). User 103 gets NO profiles row —
-- it exercises the client signup INSERT path below.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-a000-000000000101', 'cur-test-plain@test.local'),
  ('00000000-0000-4000-a000-000000000102', 'cur-test-curator@test.local'),
  ('00000000-0000-4000-a000-000000000103', 'cur-test-signup@test.local');
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

-- 3b. All four seed slugs backfilled (a renamed/missing slug would have
-- silently no-oped the plain UPDATEs)
SELECT is(
  (SELECT count(*) FROM soundboard_sounds
   WHERE slug IN ('airhorn','lets-go','ding','boo')
     AND icon IS NOT NULL AND category IS NOT NULL)::int,
  4, 'all four seed sounds carry icon + category');

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

-- 5b. Task 6 item 8: UPDATE bumps updated_at (BEFORE UPDATE trigger,
-- 20260726000005) — the client's upsert() only ever sends {user_id,
-- slugs}, so without the trigger this column would stay frozen at
-- row-creation time forever. Trigger uses clock_timestamp() (real
-- wall-clock time), not now()/transaction_timestamp() (frozen at this
-- whole test's transaction start) — the latter would make this row's
-- INSERT-time updated_at and the UPDATE below's stamp compare EQUAL, not
-- greater, since pgTAP runs the entire file in one transaction.
-- The writable CTE (UPDATE ... RETURNING) must be top-level, not nested
-- inside ok()'s argument list (Postgres: "WITH clause containing a
-- data-modifying statement must be at the top level") — so this whole
-- statement IS the WITH, with `SELECT ok(...)` as its final query.
WITH before_val AS (
  SELECT updated_at FROM soundboard_favorites
  WHERE user_id = '00000000-0000-4000-a000-000000000101'
), after_update AS (
  UPDATE soundboard_favorites SET slugs = ARRAY['airhorn']
  WHERE user_id = '00000000-0000-4000-a000-000000000101'
  RETURNING updated_at
)
SELECT ok(
  after_update.updated_at > before_val.updated_at,
  'UPDATE bumps updated_at past its pre-update value')
FROM before_val, after_update;

-- 6. is_curator not client-writable via UPDATE (guard trigger)
SELECT throws_ok(
  $$UPDATE profiles SET is_curator = true
    WHERE id = '00000000-0000-4000-a000-000000000101'$$,
  '42501', NULL, 'authenticated cannot self-promote to curator');

-- 6b-6c. …nor via the signup INSERT path (profiles INSERT policy has no
-- column restriction — the guard trigger's INSERT arm is the only stop)
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000103';
SELECT throws_ok(
  $$INSERT INTO profiles (id, username, is_curator)
    VALUES ('00000000-0000-4000-a000-000000000103', 'cur_sneaky', true)$$,
  '42501', NULL, 'signup INSERT cannot self-promote to curator');
SELECT lives_ok(
  $$INSERT INTO profiles (id, username)
    VALUES ('00000000-0000-4000-a000-000000000103', 'cur_signup')$$,
  'normal signup INSERT unaffected by the guard');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000101';

-- 7. Non-curator cannot publish
SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name, visibility)
    VALUES ('00000000-0000-4000-a000-000000000101', 'Sneaky Public', 'public')$$,
  '42501', NULL, 'non-curator cannot insert public routine');

-- 8. Non-curator private insert still works (lives_ok per the
-- user_settings_test.sql convention, plus an existence check so this can
-- never pass vacuously)
SELECT lives_ok(
  $$INSERT INTO routines (owner_id, name, visibility)
    VALUES ('00000000-0000-4000-a000-000000000101', 'My Private', 'private')$$,
  'non-curator private insert unaffected');
SELECT is(
  (SELECT count(*) FROM routines
   WHERE owner_id = '00000000-0000-4000-a000-000000000101'
     AND name = 'My Private' AND visibility = 'private')::int,
  1, 'private routine row actually exists');

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
