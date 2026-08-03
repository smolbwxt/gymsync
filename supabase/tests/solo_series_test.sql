BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- Recurring solo workouts (20260803000006): `session_series.group_id` is
-- nullable, and a series with no group belongs to its organizer alone.
--
-- The risk this pins is privacy, not plumbing: `group_id IS NULL` must never
-- become a hole that exposes one lifter's standing schedule to anyone else.
-- Fixture block: 0dxx. D1 owns solo series d10; D2 is an unrelated lifter;
-- D3 and D4 share group d20 with group series d11.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000000d01', 'ser-a@test.local'),
  ('00000000-0000-4000-e000-000000000d02', 'ser-b@test.local'),
  ('00000000-0000-4000-e000-000000000d03', 'ser-c@test.local'),
  ('00000000-0000-4000-e000-000000000d04', 'ser-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000000d01', 'ser_a'),
  ('00000000-0000-4000-e000-000000000d02', 'ser_b'),
  ('00000000-0000-4000-e000-000000000d03', 'ser_c'),
  ('00000000-0000-4000-e000-000000000d04', 'ser_d');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-4000-e000-000000000d20', 'Series Crew',
   '00000000-0000-4000-e000-000000000d03');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-e000-000000000d20', '00000000-0000-4000-e000-000000000d03', 'admin'),
  ('00000000-0000-4000-e000-000000000d20', '00000000-0000-4000-e000-000000000d04', 'member');

-- 1: the schema change itself — a series with no group is now storable.
SELECT lives_ok(
  $$INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date)
    VALUES ('00000000-0000-4000-e000-000000000d10', NULL,
            '00000000-0000-4000-e000-000000000d01',
            'America/New_York', (now() + interval '8 weeks')::date)$$,
  'a series can be created with no group (solo series)'
);

INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date)
VALUES ('00000000-0000-4000-e000-000000000d11',
        '00000000-0000-4000-e000-000000000d20',
        '00000000-0000-4000-e000-000000000d03',
        'America/New_York', (now() + interval '8 weeks')::date);

INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
  ('00000000-0000-4000-e000-000000000d10', 3, '18:00:00'),
  ('00000000-0000-4000-e000-000000000d11', 3, '18:00:00');

-- ── RLS: the solo series is the organizer's alone ──
SET LOCAL role authenticated;

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d01';  -- owner
SELECT is(
  (SELECT count(*)::int FROM session_series
   WHERE id = '00000000-0000-4000-e000-000000000d10'),
  1, 'the organizer reads their own solo series'
);
SELECT is(
  (SELECT count(*)::int FROM session_series_days
   WHERE series_id = '00000000-0000-4000-e000-000000000d10'),
  1, 'the organizer reads their own solo series days'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d02';  -- stranger
SELECT is(
  (SELECT count(*)::int FROM session_series
   WHERE id = '00000000-0000-4000-e000-000000000d10'),
  0, 'a stranger cannot read someone else''s solo series'
);
SELECT is(
  (SELECT count(*)::int FROM session_series_days
   WHERE series_id = '00000000-0000-4000-e000-000000000d10'),
  0, 'a stranger cannot read someone else''s solo series days'
);

-- A group member is still a stranger to an unrelated lifter's solo series:
-- "no group" must not read as "everyone".
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d04';
SELECT is(
  (SELECT count(*)::int FROM session_series
   WHERE id = '00000000-0000-4000-e000-000000000d10'),
  0, 'group membership grants nothing on an unrelated solo series'
);

-- ── Regression: group series behavior is untouched ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d04';  -- member
SELECT is(
  (SELECT count(*)::int FROM session_series
   WHERE id = '00000000-0000-4000-e000-000000000d11'),
  1, 'a group member still reads the group series'
);
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d02';  -- non-member
SELECT is(
  (SELECT count(*)::int FROM session_series
   WHERE id = '00000000-0000-4000-e000-000000000d11'),
  0, 'a non-member still cannot read the group series'
);

-- ── Writes: you cannot mint a solo series in someone else's name ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d02';
SELECT throws_ok(
  $$INSERT INTO session_series (group_id, organizer_id, timezone, until_date)
    VALUES (NULL, '00000000-0000-4000-e000-000000000d01',
            'America/New_York', (now() + interval '4 weeks')::date)$$,
  '42501',
  NULL,
  'a solo series cannot be created on another user''s behalf'
);

RESET role;

-- ── finalize_series stays silent for a solo series ──
-- (it would otherwise insert a chat_messages row with a NULL group_id)
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000000d01';
SELECT lives_ok(
  $$SELECT finalize_series('00000000-0000-4000-e000-000000000d10')$$,
  'finalize_series succeeds silently for a solo series (nothing to announce)'
);
RESET role;

SELECT * FROM finish();
ROLLBACK;
