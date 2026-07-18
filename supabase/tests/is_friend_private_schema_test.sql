-- Phase O / Task 1 sweep-proof: is_friend() relocated to private schema
-- (20260725000001_is_friend_private_schema.sql).
--
-- Both dependent policies ("owner and friends can read user streaks" ON
-- user_streaks; "set_logs read: owner, participant, or opted-in friend" ON
-- set_logs) already have thorough positive/negative coverage in
-- supabase/tests/streaks_test.sql (lines ~820-843: accepted friend reads,
-- stranger cannot) and supabase/tests/rls_set_logs_test.sql (the full
-- friend-solo-workout section: friend before/after opt-in, stranger,
-- cross-friend isolation, group-session non-widening, both block
-- directions) — those files run against the SAME live policies this
-- migration repointed to private.is_friend, so a full-suite green run is
-- itself the "both directions" re-proof (identical reasoning to
-- 20260722000001's own test extension, moderation_block_report_test.sql
-- section 5: "those policies would throw / fail closed on every assertion
-- otherwise"). This file adds the genuinely new content: a fresh
-- self-contained positive/negative pair, direct-call correctness of
-- private.is_friend, the schema-USAGE-denial proof, and the
-- public.is_friend-is-gone proof.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('e1000000-0000-0000-0000-0000000000a1', 'e1a1@t.com'),  -- Amara: streak owner
  ('e1000000-0000-0000-0000-0000000000a2', 'e1a2@t.com'),  -- Ben: accepted friend of Amara
  ('e1000000-0000-0000-0000-0000000000a3', 'e1a3@t.com');  -- Cara: stranger to Amara
INSERT INTO profiles (id, username) VALUES
  ('e1000000-0000-0000-0000-0000000000a1', 'e1_amara'),
  ('e1000000-0000-0000-0000-0000000000a2', 'e1_ben'),
  ('e1000000-0000-0000-0000-0000000000a3', 'e1_cara');
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('e1000000-0000-0000-0000-0000000000a1', 'e1000000-0000-0000-0000-0000000000a2', 'accepted');
INSERT INTO user_streaks (user_id, current_streak, longest_streak) VALUES
  ('e1000000-0000-0000-0000-0000000000a1', 3, 5);

-- ============================================================
-- 1. Fresh positive/negative pair on "owner and friends can read user
-- streaks" — the specific policy this migration repointed.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e1000000-0000-0000-0000-0000000000a2';  -- Ben (accepted friend)

SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'e1000000-0000-0000-0000-0000000000a1'$$,
  ARRAY[1],
  'positive: accepted friend reads the owner''s user_streaks row via private.is_friend'
);

SET LOCAL request.jwt.claim.sub = 'e1000000-0000-0000-0000-0000000000a3';  -- Cara (stranger)

SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'e1000000-0000-0000-0000-0000000000a1'$$,
  ARRAY[0],
  'negative: a stranger (no friendship row) cannot read the owner''s user_streaks row'
);

-- ============================================================
-- 2. Relocation proof — direct-call correctness, schema lockdown, oracle
-- closed. Same idiom as moderation_block_report_test.sql section 5.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_friend('e1000000-0000-0000-0000-0000000000a1',
                              'e1000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true],
  'private.is_friend(Amara, Ben) is true: accepted friendship exists'
);

SELECT results_eq(
  $$SELECT private.is_friend('e1000000-0000-0000-0000-0000000000a1',
                              'e1000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false],
  'private.is_friend(Amara, Cara) is false: no friendship row exists'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e1000000-0000-0000-0000-0000000000a1';  -- Amara

SELECT throws_ok(
  $$SELECT private.is_friend('e1000000-0000-0000-0000-0000000000a1',
                              'e1000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot name private.is_friend directly: no USAGE on schema private'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_friend'$$,
  ARRAY[0],
  'public.is_friend no longer exists in any form — the RPC oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.is_friend('e1000000-0000-0000-0000-0000000000a1',
                             'e1000000-0000-0000-0000-0000000000a2')$$,
  '42883', NULL,
  'calling public.is_friend by (schema-qualified) name now fails: function does not exist'
);

-- Widening check: the relocation must not make is_friend answer TRUE for a
-- pair with no accepted friendship, nor grant the stranger read access.
SELECT results_eq(
  $$SELECT private.is_friend('e1000000-0000-0000-0000-0000000000a3',
                              'e1000000-0000-0000-0000-0000000000a1')$$,
  ARRAY[false],
  'no widening: private.is_friend(Cara, Amara) still false in the reverse direction too'
);

SELECT * FROM finish();
ROLLBACK;
