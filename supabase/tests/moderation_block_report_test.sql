-- Phase M / Task 1: block/report backend
-- (20260721000001_moderation_block_report.sql).
-- Covers: user_reports insert/select RLS (+ negative cross-user read,
-- + negative reporter-spoof insert); blocked_users insert/select RLS
-- (+ negative cross-user read, + negative blocker-spoof insert); the
-- headline enforcement — chat rows authored by a blocked user vanish for
-- the blocker but remain visible to a non-blocking third party, while a
-- non-blocked author's messages are unaffected; friend-request rejection
-- in both block directions (addressee-blocked-requester,
-- requester-blocked-addressee); and a non-blocked pair's friend request
-- going through unaffected (regression).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(20);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'mf1@t.com'),  -- Alice: reporter/blocker
  ('00000000-0000-0000-0000-0000000000f2', 'mf2@t.com'),  -- Bob: reported/blocked, chat author
  ('00000000-0000-0000-0000-0000000000f3', 'mf3@t.com'),  -- Carol: non-blocking third party
  ('00000000-0000-0000-0000-0000000000f4', 'mf4@t.com'),  -- Dave: friend requester (gets blocked by Eve)
  ('00000000-0000-0000-0000-0000000000f5', 'mf5@t.com'),  -- Eve: blocks Dave
  ('00000000-0000-0000-0000-0000000000f6', 'mf6@t.com'),  -- Frank: blocks Grace, then requests her
  ('00000000-0000-0000-0000-0000000000f7', 'mf7@t.com'),  -- Grace: blocked by Frank
  ('00000000-0000-0000-0000-0000000000f8', 'mf8@t.com'),  -- Henry: regression requester (unblocked)
  ('00000000-0000-0000-0000-0000000000f9', 'mf9@t.com');  -- Iris: regression addressee (unblocked)
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'mod_alice'),
  ('00000000-0000-0000-0000-0000000000f2', 'mod_bob'),
  ('00000000-0000-0000-0000-0000000000f3', 'mod_carol'),
  ('00000000-0000-0000-0000-0000000000f4', 'mod_dave'),
  ('00000000-0000-0000-0000-0000000000f5', 'mod_eve'),
  ('00000000-0000-0000-0000-0000000000f6', 'mod_frank'),
  ('00000000-0000-0000-0000-0000000000f7', 'mod_grace'),
  ('00000000-0000-0000-0000-0000000000f8', 'mod_henry'),
  ('00000000-0000-0000-0000-0000000000f9', 'mod_iris');

INSERT INTO groups (id, name, created_by) VALUES
  ('33000000-0000-0000-0000-000000000001', 'Moderation Crew',
   '00000000-0000-0000-0000-0000000000f1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('33000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f1', 'admin'),
  ('33000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f2', 'member'),
  ('33000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f3', 'member');

-- ============================================================
-- 1. user_reports RLS
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';  -- Alice

SELECT lives_ok(
  $$INSERT INTO user_reports (reporter_id, reported_user_id, reported_content_type, reason) VALUES
    ('00000000-0000-0000-0000-0000000000f1',
     '00000000-0000-0000-0000-0000000000f2', 'profile', 'harassment')$$,
  'reporter can file a report as themselves'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM user_reports
    WHERE reporter_id = '00000000-0000-0000-0000-0000000000f1'$$,
  ARRAY[1], 'reporter can read their own report'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';  -- Bob (the reported user)

SELECT results_eq(
  $$SELECT count(*)::int FROM user_reports$$,
  ARRAY[0], 'reported user cannot read a report filed about them (reporter-only SELECT)'
);

SELECT throws_ok(
  $$INSERT INTO user_reports (reporter_id, reported_user_id, reported_content_type, reason) VALUES
    ('00000000-0000-0000-0000-0000000000f1',
     '00000000-0000-0000-0000-0000000000f3', 'profile', 'spoofed report')$$,
  '42501', NULL, 'cannot file a report pretending to be another reporter'
);

-- ============================================================
-- 2. blocked_users RLS
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';  -- Alice

SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-0000000000f1',
     '00000000-0000-0000-0000-0000000000f2')$$,
  'blocker can block another user as themselves'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM blocked_users
    WHERE blocker_id = '00000000-0000-0000-0000-0000000000f1'$$,
  ARRAY[1], 'blocker can read their own block row'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';  -- Bob (the blocked user)

SELECT results_eq(
  $$SELECT count(*)::int FROM blocked_users$$,
  ARRAY[0], 'blocked user cannot read the block row against them (blocker-only)'
);

SELECT throws_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-0000000000f1',
     '00000000-0000-0000-0000-0000000000f3')$$,
  '42501', NULL, 'cannot insert a block row pretending to be another blocker'
);

-- ============================================================
-- 3. Headline: chat rows from a blocked author vanish for the blocker,
-- remain for a non-blocking third party; a non-blocked author is unaffected.
-- Alice already blocked Bob (step 2 above).
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f2';  -- Bob

SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
    ('43000000-0000-0000-0000-000000000001',
     '33000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000f2', 'text', 'hi from bob')$$,
  'blocked-by-Alice author can still post to the group (block does not gate INSERT)'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f3';  -- Carol

SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
    ('43000000-0000-0000-0000-000000000002',
     '33000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000f3', 'text', 'hi from carol')$$,
  'non-blocked author can post to the group'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';  -- Alice (the blocker)

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id = '33000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'blocker sees only 1 of 2 group messages: the blocked author''s row vanished'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE author_id = '00000000-0000-0000-0000-0000000000f2'$$,
  ARRAY[0], 'blocker cannot see any message authored by the blocked user'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f3';  -- Carol (non-blocking third party)

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id = '33000000-0000-0000-0000-000000000001'$$,
  ARRAY[2], 'non-blocking third party still sees both messages, including the blocked author''s'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';  -- Alice

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE author_id = '00000000-0000-0000-0000-0000000000f3'$$,
  ARRAY[1], 'regression: blocker still sees the non-blocked author''s message unaffected'
);

-- ============================================================
-- 4. Friend-request rejection, both block directions + regression
-- ============================================================

-- Direction A: addressee (Eve) has blocked the requester (Dave).
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f5';  -- Eve

SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-0000000000f5',
     '00000000-0000-0000-0000-0000000000f4')$$,
  'Eve blocks Dave (fixture for direction-A friend-request rejection)'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f4';  -- Dave

SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-0000000000f4',
     '00000000-0000-0000-0000-0000000000f5', 'pending')$$,
  '42501', NULL,
  'friend request rejected: addressee had already blocked the requester'
);

-- Direction B: requester (Frank) has blocked the addressee (Grace).
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f6';  -- Frank

SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-0000000000f6',
     '00000000-0000-0000-0000-0000000000f7')$$,
  'Frank blocks Grace (fixture for direction-B friend-request rejection)'
);

SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-0000000000f6',
     '00000000-0000-0000-0000-0000000000f7', 'pending')$$,
  '42501', NULL,
  'friend request rejected: requester had already blocked the addressee'
);

-- Regression: a non-blocked pair's friend request is unaffected.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f8';  -- Henry

SELECT lives_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-0000000000f8',
     '00000000-0000-0000-0000-0000000000f9', 'pending')$$,
  'regression: non-blocked requester can still send a friend request'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f9';  -- Iris

SELECT results_eq(
  $$SELECT count(*)::int FROM friendships
    WHERE user_id = '00000000-0000-0000-0000-0000000000f8'
      AND friend_id = '00000000-0000-0000-0000-0000000000f9'$$,
  ARRAY[1], 'regression: non-blocked addressee sees the unaffected incoming request'
);

SELECT * FROM finish();
ROLLBACK;
