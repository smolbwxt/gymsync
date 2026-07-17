-- Kudos RLS (20260720000001_session_kudos.sql).
-- Covers: participant insert + read, one-row-per-tap (repeated taps are
-- separate rows, not an upsert/counter), non-participant read+insert
-- rejected, sender-spoof rejected, recipient-not-a-session-participant
-- rejected (the chat group-binding-fix discipline applied to kudos),
-- emoji outside the frame's 5-icon set rejected (CHECK constraint), and
-- the "no update/delete v1" claim proven (0 rows affected, no policy —
-- same idiom as personal_records_test.sql's immutability check).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

-- ── Fixtures ─────────────────────────────────────────────────────────────
-- a1: organizer + participant (sender in most cases)
-- a2: participant (recipient / reader)
-- a3: participant (unused recipient, kept for realism of a 3-lifter crew)
-- a4: outsider — not a participant of the session at all
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'ka@t.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'kb@t.com'),
  ('00000000-0000-0000-0000-0000000000a3', 'kc@t.com'),
  ('00000000-0000-0000-0000-0000000000a4', 'kd@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'kudos_organizer'),
  ('00000000-0000-0000-0000-0000000000a2', 'kudos_member_b'),
  ('00000000-0000-0000-0000-0000000000a3', 'kudos_member_c'),
  ('00000000-0000-0000-0000-0000000000a4', 'kudos_outsider');

INSERT INTO groups (id, name, created_by) VALUES
  ('32000000-0000-0000-0000-000000000001', 'Kudos Crew',
   '00000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('32000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'admin'),
  ('32000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'member'),
  ('32000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a3', 'member');
-- a4 is deliberately NOT a group member and NOT a session participant.

INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('f3000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a1',
   '32000000-0000-0000-0000-000000000001', 'completed');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('f3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'ready'),
  ('f3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'ready'),
  ('f3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a3', 'ready');

-- ── 1. Session participant sends kudos to a fellow participant ────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

SELECT lives_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000a2', '💪')$$,
  'session participant can send kudos to a fellow participant');

-- ── 2. A different participant can read the session's kudos ───────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';

SELECT results_eq(
  $$SELECT count(*)::int FROM session_kudos
    WHERE session_id = 'f3000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'session participant can read the session''s kudos');

-- ── 3/4. One row per tap: a second tap from the same sender to the same
--   recipient is a SECOND row, not an upsert/increment ─────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

SELECT lives_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000a2', '🔥')$$,
  'a second tap from the same sender to the same recipient is accepted');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_kudos
    WHERE session_id = 'f3000000-0000-0000-0000-000000000001'$$,
  ARRAY[2], 'repeated taps are stored as separate rows (one row per tap, not an upsert)');

-- ── 5/6. Outsider (not a session participant) cannot read or insert ───────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a4';

SELECT results_eq(
  $$SELECT count(*)::int FROM session_kudos
    WHERE session_id = 'f3000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'non-participant cannot read the session''s kudos');

SELECT throws_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a4',
     '00000000-0000-0000-0000-0000000000a2', '💪')$$,
  '42501', NULL,
  'non-participant cannot insert kudos into the session');

-- ── 7. Sender-spoof rejected ────────────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';

SELECT throws_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000a3', '🏆')$$,
  '42501', NULL,
  'sender-spoof is rejected (sender_id must equal auth.uid())');

-- ── 8. Recipient not a session participant rejected (group-binding-fix
--   discipline applied to kudos: a4 is a real profile but never joined
--   this session) ────────────────────────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

SELECT throws_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000a4', '⚡')$$,
  '42501', NULL,
  'kudos to a recipient who is not a participant of this session is rejected');

-- ── 9. Emoji outside the frame's 5-icon set rejected (CHECK constraint,
--   not RLS — 23514 check_violation) ────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
    ('f3000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000a2', '😀')$$,
  '23514', NULL,
  'emoji outside the frame''s 5-icon set is rejected');

-- ── 10/11. No UPDATE/DELETE policy — same idiom as
--   personal_records_test.sql: RLS-enabled + zero policies for a command
--   means the command silently matches 0 rows, not an exception ──────────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_kudos SET emoji = '🏆'
      WHERE sender_id = '00000000-0000-0000-0000-0000000000a1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'kudos rows are immutable — no UPDATE policy (0 rows affected)');

SELECT results_eq(
  $$WITH del AS (
      DELETE FROM session_kudos
      WHERE sender_id = '00000000-0000-0000-0000-0000000000a1'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'kudos taps cannot be retracted — no DELETE policy, v1 (0 rows affected)');

SELECT * FROM finish();
ROLLBACK;
