-- Session sub-thread chat RLS (20260719000010_session_chat_subthreads.sql).
-- Covers: participant read/write of a group-backed session thread,
-- non-participant group member locked out of a session thread they didn't
-- join, non-participant insert rejected, author-spoof rejected, group-level
-- chat behavior unchanged (positive + negative), and a solo (group_id NULL)
-- session's thread working for its participants.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'sca@t.com'),  -- group member + session1 participant (organizer)
  ('00000000-0000-0000-0000-0000000000d2', 'scb@t.com'),  -- group member + session1 participant
  ('00000000-0000-0000-0000-0000000000d3', 'scc@t.com'),  -- group member, NOT a session1 participant
  ('00000000-0000-0000-0000-0000000000d4', 'scd@t.com'),  -- outsider: not a group member, not any session participant
  ('00000000-0000-0000-0000-0000000000d5', 'sce@t.com'),  -- solo session (session2) organizer + participant
  ('00000000-0000-0000-0000-0000000000d6', 'scf@t.com');  -- solo session (session2) participant, non-organizer
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'sc_user_a'),
  ('00000000-0000-0000-0000-0000000000d2', 'sc_user_b'),
  ('00000000-0000-0000-0000-0000000000d3', 'sc_user_c'),
  ('00000000-0000-0000-0000-0000000000d4', 'sc_user_d'),
  ('00000000-0000-0000-0000-0000000000d5', 'sc_user_e'),
  ('00000000-0000-0000-0000-0000000000d6', 'sc_user_f');

INSERT INTO groups (id, name, created_by) VALUES
  ('31000000-0000-0000-0000-000000000001', 'Subthread Crew',
   '00000000-0000-0000-0000-0000000000d1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1', 'admin'),
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d2', 'member'),
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d3', 'member');
-- d4 is deliberately NOT a member of this group.

-- session1: group-backed session. Participants are A and B; C is a group
-- member but never joins this session.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('f1000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000d1',
   '31000000-0000-0000-0000-000000000001', 'in_progress');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1', 'ready'),
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d2', 'ready');

-- session2: solo/ad-hoc session, no group (group_id NULL). Participants are
-- E (organizer) and F.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('f1000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000d5',
   NULL, 'in_progress');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000d5', 'ready'),
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000d6', 'ready');

-- ── A: organizer + session1 participant + group member ─────────────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';

SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d1', 'text', 'session thread: first!')$$,
  'session participant can write a session-thread row');

SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     NULL,
     '00000000-0000-0000-0000-0000000000d1', 'text', 'group-level: hello crew')$$,
  'group-level (session_id NULL) insert still works, unchanged');

-- ── B: session1 participant + group member ──────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id = 'f1000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'session participant can read the session thread');

SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d2', 'text', 'session thread: second!')$$,
  'a second (non-organizer) session participant can also write to the thread');

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d1', 'text', 'spoofed session message')$$,
  '42501', NULL, 'author-spoof into a session thread is rejected');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id IS NULL
      AND group_id = '31000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'group-level chat is still readable by group members, unchanged');

-- ── C: group member, but NOT a session1 participant ─────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d3';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id = 'f1000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'group member who is NOT a session participant cannot read that session thread');

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d3', 'text', 'trying to crash the thread')$$,
  '42501', NULL, 'non-participant group member cannot insert into the session thread');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id IS NULL
      AND group_id = '31000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'group-level chat remains open to this group member, unchanged');

-- ── D: total outsider — not a group member, not a participant of anything ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d4';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id = '31000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'outsider cannot read any of this group''s chat (group-level or session-thread), unchanged');

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000001',
     NULL,
     '00000000-0000-0000-0000-0000000000d4', 'text', 'gate-crashing group chat')$$,
  '42501', NULL, 'outsider cannot insert group-level messages, unchanged');

-- ── Solo session (group_id NULL): E organizes, F participates ──────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d5';

SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    (NULL,
     'f1000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000d5', 'text', 'solo thread: warming up')$$,
  'solo-session (group_id NULL) organizer/participant can write the thread');

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d6';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id = 'f1000000-0000-0000-0000-000000000002'$$,
  ARRAY[1], 'solo-session participant can read the thread');

SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    (NULL,
     'f1000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000d6', 'text', 'solo thread: me too')$$,
  'solo-session participant can write the thread');

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d4';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE session_id = 'f1000000-0000-0000-0000-000000000002'$$,
  ARRAY[0], 'non-participant cannot read the solo-session thread');

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    (NULL,
     'f1000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000d4', 'text', 'gate-crashing the solo thread')$$,
  '42501', NULL, 'non-participant cannot write the solo-session thread');

SELECT * FROM finish();
ROLLBACK;
