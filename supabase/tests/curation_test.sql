BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

-- plan(22) -> plan(15), 2026-09-18: assertions 1, 2, 3, 3b, 4, 5 and 5b read
-- soundboard_sounds / soundboard_favorites, which
-- 20260913000104_soundboard_drop.sql drops (plan task D5, decision 5 — the
-- throwables are tabled indefinitely; the implementation is archived at the
-- tag archive/soundboard-throwables-2026-09 and the rows at
-- .superpowers/sdd/2026-09-13-group-session-phase-b-plan/soundboard-rows-2026-09-13.json).
-- scripts/run_pgtap.js runs every file in this directory against the LIVE
-- database, so a suite that reads a dropped table does not fail one
-- assertion — its first dead statement aborts the transaction and takes the
-- whole file with it. The seven soundboard assertions are retired here; the
-- fifteen that survive are the curator/publishing/stars half of this suite
-- and are unchanged.
--
-- The surviving assertions KEEP their historical numbers (6 onward) rather
-- than being renumbered 1-15: user_settings_test.sql's own updated_at proof
-- cites this file by assertion number, and shifting them would silently
-- re-point that citation at a different assertion. The plan() count is the
-- number pgTAP checks; the comment labels are history.

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

-- 1-5b RETIRED (20260913000104_soundboard_drop.sql): the catalog-column,
-- icon-backfill, favorites-RLS and favorites-updated_at assertions all read
-- soundboard_sounds / soundboard_favorites. What they proved is not being
-- given up quietly, so it is written down here: icon/category existed and
-- all four seed slugs carried both; a user could write and read only their
-- own favorites row; and 20260726000005's BEFORE UPDATE trigger bumped
-- updated_at on a slugs-only upsert. The trigger's function goes with the
-- table in the same migration. The same updated_at idiom is still proved
-- against a live table by user_settings_test.sql (20260726000006) and
-- weekly_goals_test.sql (20260906000001), so the clock_timestamp() lesson
-- keeps a home in this suite directory.

-- The role switch below outlives the retired assertions: assertion 6 onward
-- runs as user 101, which is what the removed favorites block used to set up.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000101';

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

-- 7. Publishing is OPEN (20260728000008): any owner may publish public —
--    it's the FEATURED spotlight that's curator-managed now.
SELECT lives_ok(
  $$INSERT INTO routines (owner_id, name, visibility)
    VALUES ('00000000-0000-4000-a000-000000000101', 'Open Public', 'public')$$,
  'non-curator CAN publish a public routine (open publishing)');

-- 7b. …but a non-curator cannot self-feature, on INSERT or UPDATE.
SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name, visibility, is_featured)
    VALUES ('00000000-0000-4000-a000-000000000101', 'Sneaky Featured', 'public', true)$$,
  '42501', NULL, 'non-curator cannot insert a featured routine');
SELECT throws_ok(
  $$UPDATE routines SET is_featured = true
    WHERE owner_id = '00000000-0000-4000-a000-000000000101' AND name = 'Open Public'$$,
  '42501', NULL, 'non-curator cannot update own routine to featured');

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

-- 11. Curator CAN feature their public routine (the managed spotlight).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000102';
SELECT lives_ok(
  $$UPDATE routines SET is_featured = true
    WHERE owner_id = '00000000-0000-4000-a000-000000000102' AND name = 'Featured Pack'$$,
  'curator can feature their published routine');

-- 12-15. Stars (20260728000008): star public as self; no impersonation; no
--         starring private routines (existence leak); unstar own.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-a000-000000000101';
SELECT lives_ok(
  $$INSERT INTO routine_stars (routine_id, user_id)
    SELECT id, '00000000-0000-4000-a000-000000000101' FROM routines WHERE name = 'Featured Pack'$$,
  'user stars a public routine as themself');
SELECT throws_ok(
  $$INSERT INTO routine_stars (routine_id, user_id)
    SELECT id, '00000000-0000-4000-a000-000000000102' FROM routines WHERE name = 'Featured Pack'$$,
  '42501', NULL, 'cannot star as another user');
SELECT throws_ok(
  $$INSERT INTO routine_stars (routine_id, user_id)
    SELECT id, '00000000-0000-4000-a000-000000000101' FROM routines WHERE name = 'My Private'$$,
  '42501', NULL, 'cannot star a private routine');
SELECT lives_ok(
  $$DELETE FROM routine_stars
    WHERE user_id = '00000000-0000-4000-a000-000000000101'$$,
  'user unstars their own star');

SELECT * FROM finish();
ROLLBACK;
