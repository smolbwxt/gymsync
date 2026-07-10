BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'ga@t.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'gb@t.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'gc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'gr_user_a'),
  ('00000000-0000-0000-0000-0000000000b1', 'gr_user_b'),
  ('00000000-0000-0000-0000-0000000000c1', 'gr_user_c');

-- Cap-test fixture: a group already at 25 members
INSERT INTO auth.users (id, email)
SELECT ('00000000-0000-0000-00cc-' || lpad(g::text, 12, '0'))::uuid, 'cap' || g || '@t.com'
FROM generate_series(1, 25) g;
INSERT INTO profiles (id, username)
SELECT ('00000000-0000-0000-00cc-' || lpad(g::text, 12, '0'))::uuid, 'cap_user_' || g
FROM generate_series(1, 25) g;
INSERT INTO groups (id, name, created_by) VALUES
  ('20000000-0000-0000-0000-000000000002', 'Full Crew',
   '00000000-0000-0000-00cc-000000000001');
INSERT INTO group_members (group_id, user_id, role)
SELECT '20000000-0000-0000-0000-000000000002',
       ('00000000-0000-0000-00cc-' || lpad(g::text, 12, '0'))::uuid,
       CASE WHEN g = 1 THEN 'admin' ELSE 'member' END
FROM generate_series(1, 25) g;

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

-- Negative: non-admin cannot escalate their own role (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE group_members SET role='admin'
      WHERE group_id='20000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000b1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'non-admin cannot change roles');

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

-- Switch to full group's admin to test size cap
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-00cc-000000000001';

-- Negative: 26th member is rejected by the size-cap trigger (23514 = check_violation)
SELECT throws_ok(
  $$INSERT INTO group_members (group_id, user_id) VALUES
    ('20000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000000c1')$$,
  '23514', NULL, '26th member is rejected by size cap');

SELECT * FROM finish();
ROLLBACK;
