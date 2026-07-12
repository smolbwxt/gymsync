BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(2);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- User A: was organizer of a group session, but has since been removed from the group.
-- User B: organizer of a groupless (ad-hoc) scheduled session — still a valid delete.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'dp-a@t.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'dp-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'dp_user_a'),
  ('00000000-0000-0000-0000-0000000000e2', 'dp_user_b');

INSERT INTO groups (id, name, created_by) VALUES
  ('cc000000-0000-0000-0000-000000000001', 'Delete Parity Crew',
   '00000000-0000-0000-0000-0000000000e2');
-- A was a member; now removed (no group_members row for A).
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('cc000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e2', 'admin');

-- Group session owned by departed organizer A
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('e0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000e1',
   'cc000000-0000-0000-0000-000000000001',
   'scheduled',
   now() + interval '1 day');

-- Groupless scheduled session owned by B
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('e0000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000e2',
   NULL,
   'scheduled',
   now() + interval '1 day');

SET LOCAL role authenticated;

-- ── Test 1: Departed organizer cannot delete their old group session ───────────
-- Policy requires is_group_member; A was removed → 0 rows deleted.
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e1';
SELECT results_eq(
  $$WITH del AS (DELETE FROM sessions
                 WHERE id = 'e0000000-0000-0000-0000-000000000001'
                 RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'departed organizer cannot delete their old group session');

-- ── Test 2: Organizer still deletes own groupless scheduled session ────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e2';
SELECT results_eq(
  $$WITH del AS (DELETE FROM sessions
                 WHERE id = 'e0000000-0000-0000-0000-000000000002'
                 RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1],
  'organizer still deletes own groupless scheduled session');

SELECT * FROM finish();
ROLLBACK;
