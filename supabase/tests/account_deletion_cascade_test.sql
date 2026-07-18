-- Live-DB proof for the account-deletion-cascade Edge Function
-- (supabase/functions/account-deletion-cascade/index.ts). Closes the
-- reviewer's DDL-vs-deployed-drift concern: index.ts's top-of-file comment
-- and test.ts's in-memory FK-graph fixture (the "documentation, not a live
-- DB proof" test) both derive the cascade/tombstone/handoff map from
-- grepping supabase/migrations/ statically — neither actually executes
-- against a running Postgres. This file does: it replicates the function's
-- own handoff SQL verbatim (created_by + group_members.role='admin'
-- promotion, organizer_id x2), then issues the exact statement
-- `auth.admin.deleteUser()` ultimately performs — `DELETE FROM auth.users`
-- — and asserts the real, deployed schema's ON DELETE actions produce the
-- outcomes the function's header comment and task-3-report.md claim.
--
-- Also covers the group-ownership-handoff fix (reviewer Important #1):
-- User A is deliberately the group's SOLE ADMIN with User B as a plain
-- member — the exact scenario where handing off only groups.created_by
-- (without promoting B to role='admin') would leave the group permanently
-- unmanageable, since admin powers key off group_members.role, not
-- created_by (20260710000002_create_groups.sql:68-100 — is_group_admin(),
-- "admin updates roles", "admin can update/delete group").
--
-- Convention: BEGIN...ROLLBACK (same idiom as every other file in this
-- directory — see e.g. delete_parity_test.sql, moderation_block_report_test.sql).
-- All fixture inserts, the handoff updates, and the terminal
-- `DELETE FROM auth.users` all run inside the one transaction; ROLLBACK at
-- the end is the test's entire teardown — nothing here persists.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

-- ============================================================
-- Fixtures
-- ============================================================
-- User A: the departing user. Sole admin of a group, organizer of a session
-- and a session_series in that group, author of a chat message in it, and
-- owner of a full slate of "personal" rows (gym, push_device, routine +
-- routine_exercise, set_log, blocked_users, session_kudos) covering every
-- CASCADE category the function's header comment documents.
-- User B: a plain (non-admin) member/participant who survives and inherits
-- everything A owned.
INSERT INTO auth.users (id, email) VALUES
  ('dc000000-0000-0000-0000-00000000000a', 'dc-a@t.com'),
  ('dc000000-0000-0000-0000-00000000000b', 'dc-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('dc000000-0000-0000-0000-00000000000a', 'dc_user_a'),
  ('dc000000-0000-0000-0000-00000000000b', 'dc_user_b');

-- Group: A is the creator AND the sole admin; B is a plain member.
INSERT INTO groups (id, name, created_by) VALUES
  ('dc000000-0000-0000-0000-000000000001', 'DC Test Crew',
   'dc000000-0000-0000-0000-00000000000a');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('dc000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-00000000000a', 'admin'),
  ('dc000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-00000000000b', 'member');

-- Session: A organizes, both A and B participate.
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('dc000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-00000000000a',
   'dc000000-0000-0000-0000-000000000001', 'completed');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('dc000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-00000000000a'),
  ('dc000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-00000000000b');

-- session_series: reuses the group above (group_id is NOT NULL on this table).
INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('dc000000-0000-0000-0000-000000000003', 'dc000000-0000-0000-0000-000000000001',
   'dc000000-0000-0000-0000-00000000000a', 'America/New_York', (now() + interval '4 weeks')::date);

-- chat_message authored by A in the shared group — the tombstone case.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('dc000000-0000-0000-0000-000000000004', 'dc000000-0000-0000-0000-000000000001',
   'dc000000-0000-0000-0000-00000000000a', 'text', 'hello from A before deletion');

-- A's "personal" rows — every CASCADE category the header comment cites.
INSERT INTO gyms (id, user_id, name, latitude, longitude) VALUES
  ('dc000000-0000-0000-0000-000000000007', 'dc000000-0000-0000-0000-00000000000a',
   'DC Test Gym', 40.0, -73.0);
INSERT INTO push_devices (id, user_id, apns_token) VALUES
  ('dc000000-0000-0000-0000-000000000008', 'dc000000-0000-0000-0000-00000000000a',
   'dc-test-apns-token-a1');
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('dc000000-0000-0000-0000-000000000005', 'dc000000-0000-0000-0000-00000000000a',
   'A Push Day', 'private');
INSERT INTO routine_exercises (id, routine_id, exercise_id, position) VALUES
  ('dc000000-0000-0000-0000-000000000006', 'dc000000-0000-0000-0000-000000000005',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1);
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight) VALUES
  ('dc000000-0000-0000-0000-000000000009', 'dc000000-0000-0000-0000-00000000000a',
   'dc000000-0000-0000-0000-000000000002',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 5, 135);
INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
  ('dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b');
INSERT INTO session_kudos (session_id, sender_id, recipient_id, emoji) VALUES
  ('dc000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-00000000000a',
   'dc000000-0000-0000-0000-00000000000b', '💪');

-- ============================================================
-- The function's own handoff SQL, replicated verbatim (see
-- SupabaseDeletionGateway.reassignGroupOwner/reassignSessionOrganizer/
-- reassignSeriesOrganizer in index.ts) — run BEFORE the terminal delete,
-- exactly like runAccountDeletion() orders it.
-- ============================================================
UPDATE groups SET created_by = 'dc000000-0000-0000-0000-00000000000b'
  WHERE id = 'dc000000-0000-0000-0000-000000000001';
-- The fix: unconditionally promote the new owner to admin (idempotent
-- no-op if they already are one — B is not, here, so this is the write
-- that actually closes the "unmanageable group" gap).
UPDATE group_members SET role = 'admin'
  WHERE group_id = 'dc000000-0000-0000-0000-000000000001'
    AND user_id = 'dc000000-0000-0000-0000-00000000000b';
UPDATE sessions SET organizer_id = 'dc000000-0000-0000-0000-00000000000b'
  WHERE id = 'dc000000-0000-0000-0000-000000000002';
UPDATE session_series SET organizer_id = 'dc000000-0000-0000-0000-00000000000b'
  WHERE id = 'dc000000-0000-0000-0000-000000000003';

-- ============================================================
-- The terminal delete — this is what `auth.admin.deleteUser()` does under
-- the hood. Everything below this line is Postgres enforcing its own FK
-- constraints, not application code.
-- ============================================================
DELETE FROM auth.users WHERE id = 'dc000000-0000-0000-0000-00000000000a';

-- ============================================================
-- Assertions
-- ============================================================

-- ── A's personal rows are gone (CASCADE) ────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM gyms WHERE user_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'gym cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_devices WHERE user_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'push_device cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM routines WHERE owner_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'owned routine cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises WHERE id = 'dc000000-0000-0000-0000-000000000006'$$,
  ARRAY[0], 'routine_exercise cascaded away transitively via its parent routine');

SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs WHERE user_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'set_log cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM blocked_users
    WHERE blocker_id = 'dc000000-0000-0000-0000-00000000000a'
       OR blocked_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'blocked_users row cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_kudos
    WHERE sender_id = 'dc000000-0000-0000-0000-00000000000a'
       OR recipient_id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'session_kudos row cascaded away with A');

SELECT results_eq(
  $$SELECT count(*)::int FROM profiles WHERE id = 'dc000000-0000-0000-0000-00000000000a'$$,
  ARRAY[0], 'profile cascaded away with the auth.users row');

-- ── group/session/series survive with ownership handed to B ────────────
SELECT results_eq(
  $$SELECT created_by::text FROM groups WHERE id = 'dc000000-0000-0000-0000-000000000001'$$,
  ARRAY['dc000000-0000-0000-0000-00000000000b'],
  'group survives, created_by handed off to B');

SELECT results_eq(
  $$SELECT role FROM group_members
    WHERE group_id = 'dc000000-0000-0000-0000-000000000001'
      AND user_id = 'dc000000-0000-0000-0000-00000000000b'$$,
  ARRAY['admin'],
  'B was promoted to admin — the group is not left unmanageable');

SELECT results_eq(
  $$SELECT organizer_id::text FROM sessions WHERE id = 'dc000000-0000-0000-0000-000000000002'$$,
  ARRAY['dc000000-0000-0000-0000-00000000000b'],
  'session survives, organizer_id handed off to B');

SELECT results_eq(
  $$SELECT organizer_id::text FROM session_series WHERE id = 'dc000000-0000-0000-0000-000000000003'$$,
  ARRAY['dc000000-0000-0000-0000-00000000000b'],
  'session_series survives, organizer_id handed off to B');

-- ── chat_message survives, tombstoned (author_id -> NULL, body intact) ──
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE id = 'dc000000-0000-0000-0000-000000000004'$$,
  ARRAY[1], 'chat_message survives (not cascaded)');

SELECT results_eq(
  $$SELECT (author_id IS NULL) FROM chat_messages WHERE id = 'dc000000-0000-0000-0000-000000000004'$$,
  ARRAY[true], 'chat_message tombstoned: author_id -> NULL');

SELECT results_eq(
  $$SELECT body FROM chat_messages WHERE id = 'dc000000-0000-0000-0000-000000000004'$$,
  ARRAY['hello from A before deletion'], 'tombstoned chat_message body survives intact');

-- ── B's own rows are untouched ──────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM profiles WHERE id = 'dc000000-0000-0000-0000-00000000000b'$$,
  ARRAY[1], 'B''s own profile untouched');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE session_id = 'dc000000-0000-0000-0000-000000000002'$$,
  ARRAY[1],
  'only B''s participant row remains — A''s own participant row cascaded, B''s survived untouched');

SELECT * FROM finish();
ROLLBACK;
