-- Phase O / Task 1 sweep-proof, fix-wave 2 fix-forward: chat_messages
-- INSERT ("members send client messages as themselves") repointed to
-- private.is_session_participant
-- (20260726000004_chat_messages_insert_is_session_participant_fixup.sql).
--
-- This policy was missed by 20260726000001's inventory (see that
-- migration's own header, and its fix-forward's header, for the full
-- diagnostic trail). Assertion 1 below is the headline regression proof:
-- it specifically exercises a GROUP-LEVEL send (session_id IS NULL), where
-- the is_session_participant branch of the WITH CHECK is logically
-- unreachable for the row being inserted — this is exactly the case that
-- was broken in production between 20260726000001 and this fix-forward,
-- because Postgres checks EXECUTE on every function OID appearing in a
-- compiled WITH CHECK expression regardless of which AND/OR branch a given
-- row's runtime values would actually reach.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('f6000000-0000-0000-0000-0000000000a1', 'f6a1@t.com'),  -- Gail: organizer + group member
  ('f6000000-0000-0000-0000-0000000000a2', 'f6a2@t.com'),  -- Hank: group member, session participant
  ('f6000000-0000-0000-0000-0000000000a3', 'f6a3@t.com');  -- Ivy: group member, NOT a session participant
INSERT INTO profiles (id, username) VALUES
  ('f6000000-0000-0000-0000-0000000000a1', 'f6_gail'),
  ('f6000000-0000-0000-0000-0000000000a2', 'f6_hank'),
  ('f6000000-0000-0000-0000-0000000000a3', 'f6_ivy');
INSERT INTO groups (id, name, created_by) VALUES
  ('f6000000-0000-0000-0000-000000000b01', 'Fixup Crew', 'f6000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-0000000000a1', 'admin'),
  ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-0000000000a2', 'member'),
  ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-0000000000a3', 'member');
INSERT INTO sessions (id, organizer_id, group_id, state, started_at, last_activity_at) VALUES
  ('f6000000-0000-0000-0000-000000000d01', 'f6000000-0000-0000-0000-0000000000a1',
   'f6000000-0000-0000-0000-000000000b01', 'in_progress', now(), now());
INSERT INTO session_participants (session_id, user_id) VALUES
  ('f6000000-0000-0000-0000-000000000d01', 'f6000000-0000-0000-0000-0000000000a1'),
  ('f6000000-0000-0000-0000-000000000d01', 'f6000000-0000-0000-0000-0000000000a2');
  -- Ivy deliberately NOT a session participant, but IS a group member.

SET LOCAL role authenticated;

-- ============================================================
-- 1. Headline regression proof: group-level send (session_id IS NULL) —
--    the is_session_participant branch is unreachable for this row, and
--    this exact case was the one that broke in production.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f6000000-0000-0000-0000-0000000000a3';  -- Ivy
SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-0000000000a3', 'text', 'group-level test')$$,
  'positive: group-level (session_id NULL) chat send succeeds — is_session_participant branch unreachable but must not ACL-block the row'
);

-- ============================================================
-- 2. Session-scoped send by an actual participant.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f6000000-0000-0000-0000-0000000000a2';  -- Hank (participant)
SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-000000000d01',
     'f6000000-0000-0000-0000-0000000000a2', 'text', 'session-scoped test (participant)')$$,
  'positive: session-scoped send by a real participant succeeds via private.is_session_participant'
);

-- ============================================================
-- 3. Session-scoped send by a group member who is NOT a session
--    participant — negative.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f6000000-0000-0000-0000-0000000000a3';  -- Ivy (group member, not a participant)
SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('f6000000-0000-0000-0000-000000000b01', 'f6000000-0000-0000-0000-000000000d01',
     'f6000000-0000-0000-0000-0000000000a3', 'text', 'session-scoped test (non-participant)')$$,
  '42501', NULL,
  'negative: a group member who is not a session participant cannot send into the session thread'
);

SELECT * FROM finish();
ROLLBACK;
