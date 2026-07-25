BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

-- Regression lock for the audit's D4 finding (20260729000001): blocking
-- must hide the pair's messages from BOTH sides. Before that migration
-- assertion 4 failed — the blocked user still read the blocker's messages.
-- Fixture shape follows rls_chat_test.sql (auth.users + profiles + group +
-- members inside the rolled-back txn).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-c000-000000000301', 'blk-a@test.local'),
  ('00000000-0000-4000-c000-000000000302', 'blk-b@test.local'),
  ('00000000-0000-4000-c000-000000000303', 'blk-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-c000-000000000301', 'blk_a'),
  ('00000000-0000-4000-c000-000000000302', 'blk_b'),
  ('00000000-0000-4000-c000-000000000303', 'blk_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('30000000-0000-4000-c000-000000000301', 'Block Crew',
   '00000000-0000-4000-c000-000000000301');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('30000000-0000-4000-c000-000000000301', '00000000-0000-4000-c000-000000000301', 'admin'),
  ('30000000-0000-4000-c000-000000000301', '00000000-0000-4000-c000-000000000302', 'member'),
  ('30000000-0000-4000-c000-000000000301', '00000000-0000-4000-c000-000000000303', 'member');

-- One message from each of A, B, C.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('40000000-0000-4000-c000-000000000301', '30000000-0000-4000-c000-000000000301',
   '00000000-0000-4000-c000-000000000301', 'text', 'from A'),
  ('40000000-0000-4000-c000-000000000302', '30000000-0000-4000-c000-000000000301',
   '00000000-0000-4000-c000-000000000302', 'text', 'from B'),
  ('40000000-0000-4000-c000-000000000303', '30000000-0000-4000-c000-000000000301',
   '00000000-0000-4000-c000-000000000303', 'text', 'from C');

SET LOCAL role authenticated;

-- 1-2. Baseline before any block: both A and B see all three messages.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-c000-000000000301';
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301')::int,
  3, 'A sees all 3 messages before any block');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-c000-000000000302';
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301')::int,
  3, 'B sees all 3 messages before any block');

-- A blocks B (one directional blocked_users row — the whole point).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-c000-000000000301';
INSERT INTO blocked_users (blocker_id, blocked_id)
  VALUES ('00000000-0000-4000-c000-000000000301', '00000000-0000-4000-c000-000000000302');

-- 3. The direction that always worked: A no longer sees B's message.
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301'
     AND author_id = '00000000-0000-4000-c000-000000000302')::int,
  0, 'blocker A cannot see blocked B''s messages');

-- 4. THE REGRESSION: the reverse direction. Pre-migration this returned 1
--    (B kept reading the blocker's messages) — the audit's finding.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-c000-000000000302';
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301'
     AND author_id = '00000000-0000-4000-c000-000000000301')::int,
  0, 'blocked B cannot see blocker A''s messages (mutual enforcement)');

-- 5. Blocking is pairwise, not a group-wide mute: B still sees C, and its
--    own message. (Guards against an over-broad fix.)
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301'
     AND author_id <> '00000000-0000-4000-c000-000000000301')::int,
  2, 'blocked B still sees uninvolved C and their own message');

-- 6. Uninvolved third party is entirely unaffected.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-c000-000000000303';
SELECT is(
  (SELECT count(*) FROM chat_messages
   WHERE group_id = '30000000-0000-4000-c000-000000000301')::int,
  3, 'uninvolved C still sees all 3 messages');

SELECT * FROM finish();
ROLLBACK;
