-- Phase O / Task 1 sweep-proof: is_group_member() relocated to private
-- schema (20260725000002_is_group_member_private_schema.sql).
--
-- is_group_member has the largest fan-out in this sweep (21 policies + 3
-- RPC gate functions). This file adds fresh, self-contained positive/
-- negative proofs for one representative surface per cluster (groups core,
-- chat, storage, series, sessions-delete, streaks, RPC gate) plus the
-- relocation-mechanics proof (gone, direct-call correctness, schema
-- lockdown). The remaining surfaces this migration touched already have
-- thorough member/non-member coverage in the pre-existing suite, exercised
-- against these SAME (now-repointed) policies: rls_groups_test.sql,
-- rls_chat_test.sql, comms_schema_test.sql, storage_policies_test.sql,
-- rls_series_test.sql, series_announcements_test.sql, delete_parity_test.
-- sql, streaks_test.sql, burpee_ledger_rpc_test.sql, group_stats_rpc_test.
-- sql, security_followups_test.sql — a full-suite green run after this
-- migration is the "both directions" re-proof for those, same reasoning
-- as moderation_block_report_test.sql section 5 for is_blocked.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

INSERT INTO auth.users (id, email) VALUES
  ('e2000000-0000-0000-0000-0000000000a1', 'e2a1@t.com'),  -- Cleo: creator/admin/organizer
  ('e2000000-0000-0000-0000-0000000000a2', 'e2a2@t.com'),  -- Milo: plain member
  ('e2000000-0000-0000-0000-0000000000a3', 'e2a3@t.com');  -- Nia: non-member outsider
INSERT INTO profiles (id, username) VALUES
  ('e2000000-0000-0000-0000-0000000000a1', 'e2_cleo'),
  ('e2000000-0000-0000-0000-0000000000a2', 'e2_milo'),
  ('e2000000-0000-0000-0000-0000000000a3', 'e2_nia');
INSERT INTO groups (id, name, created_by) VALUES
  ('e2000000-0000-0000-0000-000000000b01', 'Sweep Crew', 'e2000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('e2000000-0000-0000-0000-000000000b01', 'e2000000-0000-0000-0000-0000000000a1', 'admin'),
  ('e2000000-0000-0000-0000-000000000b01', 'e2000000-0000-0000-0000-0000000000a2', 'member');
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('e2000000-0000-0000-0000-000000000c01', 'e2000000-0000-0000-0000-000000000b01',
   'e2000000-0000-0000-0000-0000000000a1', 'text', 'sweep proof message');
INSERT INTO chat_read_state (group_id, user_id) VALUES
  ('e2000000-0000-0000-0000-000000000b01', 'e2000000-0000-0000-0000-0000000000a1');
INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('e2000000-0000-0000-0000-000000000d01', 'e2000000-0000-0000-0000-000000000b01',
   'e2000000-0000-0000-0000-0000000000a1', 'UTC', (now() + interval '4 weeks')::date);
INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('e2000000-0000-0000-0000-000000000d02', 'e2000000-0000-0000-0000-0000000000a1',
   'e2000000-0000-0000-0000-000000000b01', 'scheduled');
INSERT INTO group_streaks (group_id, current_streak, longest_streak) VALUES
  ('e2000000-0000-0000-0000-000000000b01', 2, 4);

SET LOCAL role authenticated;

-- ============================================================
-- 1. groups SELECT — "members and creator can read group"
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo (member, not creator)
SELECT results_eq(
  $$SELECT count(*)::int FROM groups WHERE id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[1], 'positive: plain member (not creator) reads the group via private.is_group_member');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM groups WHERE id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0], 'negative: outsider cannot read the group');

-- ============================================================
-- 2. group_members SELECT — "members can read membership"
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT results_eq(
  $$SELECT count(*)::int FROM group_members WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[2], 'positive: member reads the full roster');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT results_eq(
  $$SELECT count(*)::int FROM group_members WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0], 'negative: outsider cannot read the roster');

-- ============================================================
-- 3. chat_messages SELECT — group-level branch
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE id = 'e2000000-0000-0000-0000-000000000c01'$$,
  ARRAY[1], 'positive: member reads the group-level chat message');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE id = 'e2000000-0000-0000-0000-000000000c01'$$,
  ARRAY[0], 'negative: outsider cannot read the group-level chat message');

-- ============================================================
-- 4. chat_read_state SELECT
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_read_state WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[1], 'positive: member reads the group''s read-state rows');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_read_state WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0], 'negative: outsider cannot read the group''s read-state rows');

-- ============================================================
-- 5. storage.objects chat-audio upload (chat-images pair is already
-- covered by storage_policies_test.sql; chat-audio uses the identical
-- policy shape, added fresh here for direct coverage)
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-audio', 'e2000000-0000-0000-0000-000000000b01/clip1.m4a',
     'e2000000-0000-0000-0000-0000000000a2')$$,
  'positive: member uploads chat audio to own group folder');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-audio', 'e2000000-0000-0000-0000-000000000b01/hack.m4a',
     'e2000000-0000-0000-0000-0000000000a3')$$,
  '42501', NULL, 'negative: outsider cannot upload chat audio to the group folder');

-- ============================================================
-- 6. session_series SELECT
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series WHERE id = 'e2000000-0000-0000-0000-000000000d01'$$,
  ARRAY[1], 'positive: member reads the group''s session series');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series WHERE id = 'e2000000-0000-0000-0000-000000000d01'$$,
  ARRAY[0], 'negative: outsider cannot read the group''s session series');

-- ============================================================
-- 7. sessions DELETE — group-gated branch ("organizer deletes own
-- scheduled sessions"): organizer must ALSO currently be a group member.
-- ============================================================
SET LOCAL role postgres;
-- Cleo leaves the group (simulates a departed organizer) — sanity-check
-- fixture for the negative case below.
DELETE FROM group_members
  WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'
    AND user_id  = 'e2000000-0000-0000-0000-0000000000a1';

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a1';  -- Cleo (departed organizer)
-- RLS DELETE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as delete_parity_test.sql) — throws_ok does not apply.
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM sessions WHERE id = 'e2000000-0000-0000-0000-000000000d02'
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'negative: departed organizer (no longer a group member) cannot delete the scheduled session'
);

SET LOCAL role postgres;
-- Re-add Cleo so the positive case is a clean "current member" scenario.
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('e2000000-0000-0000-0000-000000000b01', 'e2000000-0000-0000-0000-0000000000a1', 'admin');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a1';  -- Cleo (current member again)
SELECT lives_ok(
  $$DELETE FROM sessions WHERE id = 'e2000000-0000-0000-0000-000000000d02'$$,
  'positive: organizer who is still a group member can delete their scheduled session'
);

-- ============================================================
-- 8. group_streaks SELECT
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT results_eq(
  $$SELECT count(*)::int FROM group_streaks WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[1], 'positive: member reads the group streak row');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT results_eq(
  $$SELECT count(*)::int FROM group_streaks WHERE group_id = 'e2000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0], 'negative: outsider cannot read the group streak row');

-- ============================================================
-- 9. RPC gate — group_stats(uuid), representative of the three
-- SQL-function-body callers this migration updated (group_burpee_ledger,
-- group_stats, group_member_stats all share the identical
-- "IF NOT private.is_group_member(...) THEN RAISE" gate shape).
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo
SELECT lives_ok(
  $$SELECT * FROM group_stats('e2000000-0000-0000-0000-000000000b01')$$,
  'positive: member can call group_stats (gate passes via private.is_group_member)');

SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a3';  -- Nia
SELECT throws_ok(
  $$SELECT * FROM group_stats('e2000000-0000-0000-0000-000000000b01')$$,
  'P0001', 'not a member of this group',
  'negative: non-member is rejected by group_stats'' membership gate'
);

-- ============================================================
-- 10. Relocation proof — direct-call correctness, schema lockdown,
-- oracle closed, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_group_member('e2000000-0000-0000-0000-000000000b01',
                                    'e2000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true],
  'private.is_group_member(group, Milo) is true: Milo is a member'
);

SELECT results_eq(
  $$SELECT private.is_group_member('e2000000-0000-0000-0000-000000000b01',
                                    'e2000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false],
  'no widening: private.is_group_member(group, Nia) is false: Nia was never added'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e2000000-0000-0000-0000-0000000000a2';  -- Milo

SELECT throws_ok(
  $$SELECT private.is_group_member('e2000000-0000-0000-0000-000000000b01',
                                    'e2000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot name private.is_group_member directly: no USAGE on schema private'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_group_member'$$,
  ARRAY[0],
  'public.is_group_member no longer exists in any form — the RPC oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.is_group_member('e2000000-0000-0000-0000-000000000b01',
                                   'e2000000-0000-0000-0000-0000000000a2')$$,
  '42883', NULL,
  'calling public.is_group_member by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
