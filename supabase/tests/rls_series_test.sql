BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000b9', 'sr-a@t.com'),
  ('00000000-0000-0000-0000-0000000000c9', 'sr-b@t.com'),
  ('00000000-0000-0000-0000-0000000000d9', 'sr-c@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000b9', 'sr_user_a'),
  ('00000000-0000-0000-0000-0000000000c9', 'sr_user_b'),
  ('00000000-0000-0000-0000-0000000000d9', 'sr_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('aa000000-0000-0000-0000-000000000001', 'Series Crew',
   '00000000-0000-0000-0000-0000000000b9');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b9', 'admin'),
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c9', 'member');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b9';

-- Positive: group member creates a series + days
SELECT lives_ok(
  $$INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
    ('bb000000-0000-0000-0000-000000000001',
     'aa000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b9',
     'America/New_York', (now() + interval '8 weeks')::date)$$,
  'organizer creates series');
SELECT lives_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('bb000000-0000-0000-0000-000000000001', 2, '19:00'),
    ('bb000000-0000-0000-0000-000000000001', 4, '19:00')$$,
  'organizer adds series days');

-- Negative: until_date beyond 26 weeks (23514)
SELECT throws_ok(
  $$INSERT INTO session_series (group_id, organizer_id, timezone, until_date) VALUES
    ('aa000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b9',
     'America/New_York', (now() + interval '30 weeks')::date)$$,
  '23514', NULL, 'until_date capped at 26 weeks');

-- Member B: read yes, mutate no
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c9';
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series$$, ARRAY[1], 'group member reads series');
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series_days$$, ARRAY[2], 'group member reads days');
SELECT results_eq(
  $$WITH upd AS (UPDATE session_series SET until_date = until_date + 7 RETURNING 1)
    SELECT count(*)::int FROM upd$$, ARRAY[0], 'non-organizer cannot edit series');
SELECT results_eq(
  $$WITH del AS (DELETE FROM session_series_days RETURNING 1)
    SELECT count(*)::int FROM del$$, ARRAY[0], 'non-organizer cannot delete days');

-- Outsider C: invisible
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d9';
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series$$, ARRAY[0], 'outsider cannot read series');

SELECT * FROM finish();
ROLLBACK;
