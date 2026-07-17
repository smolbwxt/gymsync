-- Session sub-thread chat RLS (20260719000010_session_chat_subthreads.sql).
-- Covers: participant read/write of a group-backed session thread,
-- non-participant group member locked out of a session thread they didn't
-- join, non-participant insert rejected, author-spoof rejected, group-level
-- chat behavior unchanged (positive + negative), and a solo (group_id NULL)
-- session's thread working for its participants.
--
-- Extended (20260719000011_chat_subthread_lock_hardening.sql, security
-- fix-forward) with two attack-path blocks:
--   ATTACK 1 — chat_message_reactions must respect the sub-thread lock: a
--   group member who is NOT a session participant can neither react to nor
--   read reactions on a sub-thread message; a session participant still
--   can; group-level reactions are unchanged for group members.
--   ATTACK 2 — chat_messages INSERT's session branch must bind group_id to
--   the session's own group: a session participant cannot insert a
--   sub-thread row carrying an unrelated group_id (whether or not they
--   belong to that other group); the session's real group_id (or NULL, for
--   a solo session) still works.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(24);

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
   '00000000-0000-0000-0000-0000000000d1'),
  ('31000000-0000-0000-0000-000000000002', 'Rival Crew',
   '00000000-0000-0000-0000-0000000000d4'),
  ('31000000-0000-0000-0000-000000000003', 'A''s Other Crew',
   '00000000-0000-0000-0000-0000000000d1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1', 'admin'),
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d2', 'member'),
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d3', 'member'),
  -- ATTACK 2 fixtures: A ('d1') belongs to G3 too, but G3 is NOT session1's
  -- group (G1) — a real group membership that must still fail the
  -- group_id-binding check. A is deliberately NOT a member of G2 ('Rival
  -- Crew') — the "group they don't belong to at all" case.
  ('31000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000d1', 'admin');
-- d4 is deliberately NOT a member of the Subthread Crew (G1).

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

-- ids pinned (vs. gen_random_uuid() default) so ATTACK 1 below can target
-- these exact rows for reactions without depending on session-aware SELECT
-- visibility to look them up.
SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, session_id, author_id, kind, body) VALUES
    ('f2000000-0000-0000-0000-000000000001',
     '31000000-0000-0000-0000-000000000001',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d1', 'text', 'session thread: first!')$$,
  'session participant can write a session-thread row');

SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, session_id, author_id, kind, body) VALUES
    ('f2000000-0000-0000-0000-000000000002',
     '31000000-0000-0000-0000-000000000001',
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

-- ============================================================
-- ATTACK 1 (20260719000011): chat_message_reactions must respect the
-- sub-thread lock, not just gate on group membership.
-- Target: session1's sub-thread message 'f2000000-...0001'
-- ('session thread: first!', group_id=G1, session_id=session1).
-- ============================================================

-- C: group member of G1, but NOT a session1 participant.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d3';

SELECT throws_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('f2000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d3', '🔥')$$,
  '42501', NULL,
  'group member NOT in the session cannot react to a sub-thread message');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'f2000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'group member NOT in the session cannot read reactions on a sub-thread message');

-- B: session1 participant (not the message author) — still can react + read.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';

SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('f2000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d2', '💪')$$,
  'session participant can still react to a sub-thread message');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'f2000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'session participant can still read reactions on a sub-thread message');

-- Regression: group-level message reactions unchanged for group members.
-- C reacts to the group-level message ('f2000000-...0002', session_id NULL)
-- and reads it back — same group-membership gate as before this migration.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d3';

SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('f2000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000d3', '👍')$$,
  'group-level message reactions unchanged: group member can still react');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'f2000000-0000-0000-0000-000000000002'$$,
  ARRAY[1],
  'group-level message reactions unchanged: group member can still read reactions');

-- ============================================================
-- ATTACK 2 (20260719000011): chat_messages INSERT's session branch must
-- bind group_id to the session's own group_id, not accept any group_id a
-- participant happens to name.
-- A ('d1') is a session1 participant; session1's real group is G1
-- ('31...0001'). G3 ('31...0003') is a group A genuinely belongs to, but
-- it is NOT session1's group. G2 ('31...0002') is a group A does not
-- belong to at all.
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000002',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d1', 'text', 'forged into a group I am not in')$$,
  '42501', NULL,
  'session participant cannot bind a sub-thread row to a group they do not belong to');

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, session_id, author_id, kind, body) VALUES
    ('31000000-0000-0000-0000-000000000003',
     'f1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000d1', 'text', 'forged into a group I AM in, but wrong one')$$,
  '42501', NULL,
  'session participant cannot bind a sub-thread row to a group they belong to that is not the session''s group');

SELECT * FROM finish();
ROLLBACK;
