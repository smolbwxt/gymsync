BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a2', 'ca@t.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'cb@t.com'),
  ('00000000-0000-0000-0000-0000000000c2', 'cc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a2', 'ch_user_a'),
  ('00000000-0000-0000-0000-0000000000b2', 'ch_user_b'),
  ('00000000-0000-0000-0000-0000000000c2', 'ch_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('30000000-0000-0000-0000-000000000001', 'Chat Crew',
   '00000000-0000-0000-0000-0000000000a2');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'admin'),
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b2', 'member');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';

-- Positive: member sends a text message
SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2', 'text', 'first!')$$,
  'member can send text message'
);

SELECT lives_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2',
     '40000000-0000-0000-0000-000000000001')$$,
  'member can write own read state');

-- Negative: cannot send as another author (42501)
SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2', 'text', 'spoofed')$$,
  '42501', NULL, 'cannot spoof author');

-- Negative: client cannot insert system kinds (42501)
SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2', 'system_pr', 'fake PR')$$,
  '42501', NULL, 'client cannot insert system messages');

-- Positive: author can soft-delete own message
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_messages SET deleted_at = now()
      WHERE id='40000000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'author can soft-delete own message');

-- Member B: read + react + read-state
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='30000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'member can read group messages');

SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2', '🔥')$$,
  'member can react');

SELECT lives_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2',
     '40000000-0000-0000-0000-000000000001')$$,
  'member can write own read state');

-- Negative: member cannot spoof another user's read state (42501)
SELECT throws_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2',
     '40000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'cannot write another users read state');

-- Negative: member cannot update another user's read state (RLS-filtered = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_read_state SET last_read_message_id = NULL
      WHERE user_id = '00000000-0000-0000-0000-0000000000a2'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'cannot update another users read state');

-- Negative: B cannot edit A's message (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_messages SET body='vandalized'
      WHERE id='40000000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'member cannot edit another authors message');

-- Outsider C
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages$$,
  ARRAY[0], 'outsider cannot read chat');

SELECT throws_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c2', '👀')$$,
  '42501', NULL, 'outsider cannot react');

-- Negative: outsider cannot insert read state for a group they're not in (42501)
SELECT throws_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c2',
     '40000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'outsider cannot insert read state');

SELECT * FROM finish();
ROLLBACK;
