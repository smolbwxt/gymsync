BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'ga@t.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'gb@t.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'gc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'gr_user_a'),
  ('00000000-0000-0000-0000-0000000000b1', 'gr_user_b'),
  ('00000000-0000-0000-0000-0000000000c1', 'gr_user_c');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

-- Positive: A creates a group and bootstraps self as admin
SELECT lives_ok(
  $$INSERT INTO groups (id, name, created_by) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Push Crew',
     '00000000-0000-0000-0000-0000000000a1')$$,
  'creator can insert group'
);
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1', 'admin')$$,
  'creator can bootstrap self as admin'
);

-- Positive: admin A adds member B
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b1', 'member')$$,
  'admin can add a member'
);

-- Switch to member B
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';

-- Positive: member B can read the group
SELECT results_eq(
  $$SELECT count(*)::int FROM groups WHERE id='20000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'member can read group'
);

-- Negative: non-admin B cannot add member C (WITH CHECK -> 42501)
SELECT throws_ok(
  $$INSERT INTO group_members (group_id, user_id) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c1')$$,
  '42501', NULL, 'non-admin cannot add members'
);

-- Negative: non-admin B cannot rename the group (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (UPDATE groups SET name='Hacked' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'non-admin cannot update group'
);

-- Positive: member B can leave (delete own membership)
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM group_members
      WHERE group_id='20000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000b1'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1], 'member can leave group'
);

-- Switch to outsider C
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';

-- Negative: outsider cannot see the group or its member list
SELECT results_eq(
  $$SELECT count(*)::int FROM groups$$,
  ARRAY[0], 'outsider cannot read groups'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM group_members$$,
  ARRAY[0], 'outsider cannot read group members'
);

SELECT * FROM finish();
ROLLBACK;
