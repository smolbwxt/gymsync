-- Phase O / Task 1 sweep-proof: message_group_id() and can_access_message()
-- relocated to private schema
-- (20260725000003_chat_message_access_private_schema.sql).
--
-- can_access_message's three dependent policies (chat_message_reactions
-- SELECT/INSERT/DELETE) already have coverage in rls_chat_test.sql and
-- session_chat_subthreads_test.sql exercised against these same policies —
-- a full-suite green run after this migration re-proves those. This file
-- adds fresh proofs for: the group-level branch (now routed through
-- private.is_group_member) in both directions including a can_access_
-- message-specific DELETE denial (a departed member loses delete rights on
-- their OWN reaction row, since can_access_message — not just
-- user_id = auth.uid() — gates DELETE too); a light sanity check that the
-- session-thread branch (is_session_participant, unchanged, stays public)
-- still composes correctly; and the relocation-mechanics proof for both
-- functions. message_group_id is currently orphaned (zero live policy
-- dependents — see the migration header), so only its relocation-mechanics
-- proof applies.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users (id, email) VALUES
  ('e3000000-0000-0000-0000-0000000000a1', 'e3a1@t.com'),  -- Remy: author, group member
  ('e3000000-0000-0000-0000-0000000000a2', 'e3a2@t.com'),  -- Sana: reactor, group member (departs later)
  ('e3000000-0000-0000-0000-0000000000a3', 'e3a3@t.com'),  -- Toby: outsider
  ('e3000000-0000-0000-0000-0000000000a4', 'e3a4@t.com'),  -- Uma: session participant (sub-thread)
  ('e3000000-0000-0000-0000-0000000000a5', 'e3a5@t.com');  -- Vic: non-participant
INSERT INTO profiles (id, username) VALUES
  ('e3000000-0000-0000-0000-0000000000a1', 'e3_remy'),
  ('e3000000-0000-0000-0000-0000000000a2', 'e3_sana'),
  ('e3000000-0000-0000-0000-0000000000a3', 'e3_toby'),
  ('e3000000-0000-0000-0000-0000000000a4', 'e3_uma'),
  ('e3000000-0000-0000-0000-0000000000a5', 'e3_vic');
INSERT INTO groups (id, name, created_by) VALUES
  ('e3000000-0000-0000-0000-000000000b01', 'Reaction Crew', 'e3000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('e3000000-0000-0000-0000-000000000b01', 'e3000000-0000-0000-0000-0000000000a1', 'admin'),
  ('e3000000-0000-0000-0000-000000000b01', 'e3000000-0000-0000-0000-0000000000a2', 'member');
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('e3000000-0000-0000-0000-000000000c01', 'e3000000-0000-0000-0000-000000000b01',
   'e3000000-0000-0000-0000-0000000000a1', 'text', 'group-level message');

INSERT INTO sessions (id, organizer_id, group_id, state) VALUES
  ('e3000000-0000-0000-0000-000000000d01', 'e3000000-0000-0000-0000-0000000000a4',
   'e3000000-0000-0000-0000-000000000b01', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('e3000000-0000-0000-0000-000000000d01', 'e3000000-0000-0000-0000-0000000000a4');
INSERT INTO chat_messages (id, group_id, session_id, author_id, kind, body) VALUES
  ('e3000000-0000-0000-0000-000000000c02', 'e3000000-0000-0000-0000-000000000b01',
   'e3000000-0000-0000-0000-000000000d01', 'e3000000-0000-0000-0000-0000000000a4',
   'text', 'sub-thread message');

SET LOCAL role authenticated;

-- ============================================================
-- 1. Group-level branch (now private.is_group_member) — SELECT/INSERT
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a2';  -- Sana (member)
SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('e3000000-0000-0000-0000-000000000c01', 'e3000000-0000-0000-0000-0000000000a2', '💪')$$,
  'positive: group member reacts to a group-level message'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'e3000000-0000-0000-0000-000000000c01'$$,
  ARRAY[1], 'positive: group member reads the reaction back'
);

SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a3';  -- Toby (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'e3000000-0000-0000-0000-000000000c01'$$,
  ARRAY[0], 'negative: outsider cannot read the reaction'
);
SELECT throws_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('e3000000-0000-0000-0000-000000000c01', 'e3000000-0000-0000-0000-0000000000a3', '👀')$$,
  '42501', NULL,
  'negative: outsider cannot react to the group-level message'
);

-- ============================================================
-- 2. DELETE, can_access_message-specific: Sana loses group membership,
-- then can no longer delete her OWN reaction row (user_id = auth.uid()
-- alone is not enough — can_access_message must also still hold).
-- ============================================================
SET LOCAL role postgres;
DELETE FROM group_members
  WHERE group_id = 'e3000000-0000-0000-0000-000000000b01'
    AND user_id  = 'e3000000-0000-0000-0000-0000000000a2';

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a2';  -- Sana (departed)
-- RLS DELETE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as delete_parity_test.sql / user_settings_test.sql) —
-- throws_ok does not apply here.
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM chat_message_reactions
      WHERE message_id = 'e3000000-0000-0000-0000-000000000c01'
        AND user_id = 'e3000000-0000-0000-0000-0000000000a2'
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'negative: departed member cannot delete their own reaction — can_access_message gates DELETE too'
);

SET LOCAL role postgres;
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('e3000000-0000-0000-0000-000000000b01', 'e3000000-0000-0000-0000-0000000000a2', 'member');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a2';  -- Sana (rejoined)
SELECT lives_ok(
  $$DELETE FROM chat_message_reactions
    WHERE message_id = 'e3000000-0000-0000-0000-000000000c01'
      AND user_id = 'e3000000-0000-0000-0000-0000000000a2'$$,
  'positive: current member can delete their own reaction once access is restored'
);

-- ============================================================
-- 3. Session-thread branch sanity (is_session_participant, unchanged —
-- proves the OR-composition inside private.can_access_message still works)
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a4';  -- Uma (participant)
SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('e3000000-0000-0000-0000-000000000c02', 'e3000000-0000-0000-0000-0000000000a4', '🔥')$$,
  'positive: session participant reacts to the sub-thread message'
);

SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a5';  -- Vic (non-participant)
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_message_reactions
    WHERE message_id = 'e3000000-0000-0000-0000-000000000c02'$$,
  ARRAY[0], 'negative: non-participant cannot read the sub-thread reaction'
);

-- ============================================================
-- 4. Relocation proof — can_access_message direct-call correctness
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.can_access_message('e3000000-0000-0000-0000-000000000c01',
                                       'e3000000-0000-0000-0000-0000000000a1')$$,
  ARRAY[true],
  'private.can_access_message: group member can access the group-level message'
);

SELECT results_eq(
  $$SELECT private.can_access_message('e3000000-0000-0000-0000-000000000c01',
                                       'e3000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false],
  'no widening: private.can_access_message is false for the outsider'
);

SELECT results_eq(
  $$SELECT private.message_group_id('e3000000-0000-0000-0000-000000000c01')$$,
  ARRAY['e3000000-0000-0000-0000-000000000b01'::uuid],
  'private.message_group_id returns the correct group_id for the group-level message'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e3000000-0000-0000-0000-0000000000a1';  -- Remy

SELECT throws_ok(
  $$SELECT private.can_access_message('e3000000-0000-0000-0000-000000000c01',
                                       'e3000000-0000-0000-0000-0000000000a1')$$,
  '42501', NULL,
  'authenticated cannot name private.can_access_message directly: no USAGE on schema private'
);
SELECT throws_ok(
  $$SELECT private.message_group_id('e3000000-0000-0000-0000-000000000c01')$$,
  '42501', NULL,
  'authenticated cannot name private.message_group_id directly: no USAGE on schema private'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'can_access_message'$$,
  ARRAY[0],
  'public.can_access_message no longer exists in any form'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'message_group_id'$$,
  ARRAY[0],
  'public.message_group_id no longer exists in any form'
);
SELECT throws_ok(
  $$SELECT public.can_access_message('e3000000-0000-0000-0000-000000000c01',
                                      'e3000000-0000-0000-0000-0000000000a1')$$,
  '42883', NULL,
  'calling public.can_access_message by (schema-qualified) name now fails: function does not exist'
);
SELECT throws_ok(
  $$SELECT public.message_group_id('e3000000-0000-0000-0000-000000000c01')$$,
  '42883', NULL,
  'calling public.message_group_id by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
