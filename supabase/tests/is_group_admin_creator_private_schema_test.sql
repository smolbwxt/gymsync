-- Phase O / Task 1 sweep-proof, fix-wave 2: is_group_admin() and
-- is_group_creator() relocated to private schema
-- (20260726000002_is_group_admin_creator_private_schema.sql).
--
-- Representative coverage: groups UPDATE (is_group_admin-only branch),
-- group_members INSERT (the one policy exercising BOTH helpers — admin
-- branch and creator-bootstrap branch, tested separately), and the group
-- avatar storage upload (is_group_admin-only, different table entirely).
-- The remaining dependents (groups DELETE, group_members UPDATE/DELETE,
-- avatar replace) share the identical is_group_admin(group, auth.uid())
-- shape already proven true/false by the direct-call assertions below and
-- already have positive/negative coverage in the pre-existing suite
-- (rls_groups_test.sql, storage_policies_test.sql) — a full-suite green run
-- after this migration is the "both directions" re-proof for those, same
-- reasoning as is_group_member's own sweep-proof file.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users (id, email) VALUES
  ('f3000000-0000-0000-0000-0000000000a1', 'f3a1@t.com'),  -- Cleo: creator, deliberately NOT yet a group_members row
  ('f3000000-0000-0000-0000-0000000000a2', 'f3a2@t.com'),  -- Priya: admin
  ('f3000000-0000-0000-0000-0000000000a3', 'f3a3@t.com'),  -- Milo: plain member
  ('f3000000-0000-0000-0000-0000000000a4', 'f3a4@t.com'),  -- Quinn: outsider, added as a member mid-test
  ('f3000000-0000-0000-0000-0000000000a5', 'f3a5@t.com');  -- Rex: outsider, targeted by Milo's rejected INSERT
INSERT INTO profiles (id, username) VALUES
  ('f3000000-0000-0000-0000-0000000000a1', 'f3_cleo'),
  ('f3000000-0000-0000-0000-0000000000a2', 'f3_priya'),
  ('f3000000-0000-0000-0000-0000000000a3', 'f3_milo'),
  ('f3000000-0000-0000-0000-0000000000a4', 'f3_quinn'),
  ('f3000000-0000-0000-0000-0000000000a5', 'f3_rex');

INSERT INTO groups (id, name, created_by) VALUES
  ('f3000000-0000-0000-0000-000000000b01', 'Admin Sweep Crew', 'f3000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('f3000000-0000-0000-0000-000000000b01', 'f3000000-0000-0000-0000-0000000000a2', 'admin'),
  ('f3000000-0000-0000-0000-000000000b01', 'f3000000-0000-0000-0000-0000000000a3', 'member');

SET LOCAL role authenticated;

-- ============================================================
-- 1-2. groups UPDATE ("admin can update group") — is_group_admin-only.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a2';  -- Priya (admin)
SELECT lives_ok(
  $$UPDATE groups SET name = 'Admin Sweep Crew (renamed)' WHERE id = 'f3000000-0000-0000-0000-000000000b01'$$,
  'positive: admin can update the group via private.is_group_admin'
);

SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a3';  -- Milo (plain member)
-- RLS UPDATE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as is_session_organizer_private_schema_test.sql).
SELECT results_eq(
  $$WITH upd AS (
      UPDATE groups SET name = 'hijacked' WHERE id = 'f3000000-0000-0000-0000-000000000b01'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'negative: a plain member cannot update the group'
);

-- ============================================================
-- 3-5. group_members INSERT ("admin adds members or creator bootstraps") —
-- the one policy this migration's two helpers share, tested via both
-- branches independently.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a2';  -- Priya (admin)
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('f3000000-0000-0000-0000-000000000b01', 'f3000000-0000-0000-0000-0000000000a4', 'member')$$,
  'positive: admin adds a new member (is_group_admin branch)'
);

SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a1';  -- Cleo (creator, no group_members row yet)
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('f3000000-0000-0000-0000-000000000b01', 'f3000000-0000-0000-0000-0000000000a1', 'admin')$$,
  'positive: creator bootstraps their own admin row (is_group_creator branch, not is_group_admin — Cleo had no group_members row at all)'
);

SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a3';  -- Milo (plain member — neither admin nor creator)
SELECT throws_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('f3000000-0000-0000-0000-000000000b01', 'f3000000-0000-0000-0000-0000000000a5', 'member')$$,
  '42501', NULL,
  'negative: a plain member cannot add another (real, existing) user as a member (fails both the admin branch and the creator branch)'
);

-- ============================================================
-- 6-7. storage.objects group-avatar upload ("group admin uploads group
-- avatar") — is_group_admin-only, different table entirely.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a2';  -- Priya (admin)
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/f3000000-0000-0000-0000-000000000b01.jpg',
     'f3000000-0000-0000-0000-0000000000a2')$$,
  'positive: admin uploads the group avatar'
);

SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a3';  -- Milo (plain member)
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/f3000000-0000-0000-0000-000000000b01.jpg',
     'f3000000-0000-0000-0000-0000000000a3')$$,
  '42501', NULL,
  'negative: a plain member cannot upload the group avatar'
);

-- ============================================================
-- 8-11. Relocation proof — direct-call correctness, no widening (both
-- helpers).
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_group_admin('f3000000-0000-0000-0000-000000000b01',
                                   'f3000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[true], 'private.is_group_admin(group, Priya) is true: Priya is an admin');

SELECT results_eq(
  $$SELECT private.is_group_admin('f3000000-0000-0000-0000-000000000b01',
                                   'f3000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false], 'no widening: private.is_group_admin(group, Milo) is false: Milo is a plain member');

SELECT results_eq(
  $$SELECT private.is_group_creator('f3000000-0000-0000-0000-000000000b01',
                                     'f3000000-0000-0000-0000-0000000000a1')$$,
  ARRAY[true], 'private.is_group_creator(group, Cleo) is true: Cleo created the group');

SELECT results_eq(
  $$SELECT private.is_group_creator('f3000000-0000-0000-0000-000000000b01',
                                     'f3000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[false], 'no widening: private.is_group_creator(group, Priya) is false: Priya is an admin, not the creator');

-- ============================================================
-- 12-13. Schema USAGE denial for both relocated helpers.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f3000000-0000-0000-0000-0000000000a2';  -- Priya

SELECT throws_ok(
  $$SELECT private.is_group_admin('f3000000-0000-0000-0000-000000000b01',
                                   'f3000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'authenticated cannot name private.is_group_admin directly: no USAGE on schema private'
);

SELECT throws_ok(
  $$SELECT private.is_group_creator('f3000000-0000-0000-0000-000000000b01',
                                     'f3000000-0000-0000-0000-0000000000a1')$$,
  '42501', NULL,
  'authenticated cannot name private.is_group_creator directly: no USAGE on schema private'
);

-- ============================================================
-- 14-17. Both oracles closed: gone from public, calling by name fails.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_group_admin'$$,
  ARRAY[0], 'public.is_group_admin no longer exists in any form — the RPC oracle is closed');

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_group_creator'$$,
  ARRAY[0], 'public.is_group_creator no longer exists in any form — the RPC oracle is closed');

SELECT throws_ok(
  $$SELECT public.is_group_admin('f3000000-0000-0000-0000-000000000b01',
                                  'f3000000-0000-0000-0000-0000000000a2')$$,
  '42883', NULL,
  'calling public.is_group_admin by (schema-qualified) name now fails: function does not exist'
);

SELECT throws_ok(
  $$SELECT public.is_group_creator('f3000000-0000-0000-0000-000000000b01',
                                    'f3000000-0000-0000-0000-0000000000a1')$$,
  '42883', NULL,
  'calling public.is_group_creator by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
