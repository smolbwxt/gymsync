BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000e9', 'sa-a@t.com'),
  ('00000000-0000-0000-0000-0000000000f9', 'sa-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000e9', 'sa_user_a'),
  ('00000000-0000-0000-0000-0000000000f9', 'sa_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('cc110000-0000-0000-0000-000000000001', 'Announce Crew',
   '00000000-0000-0000-0000-0000000000e9');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('cc110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e9', 'admin'),
  ('cc110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f9', 'member');
INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('dd110000-0000-0000-0000-000000000001',
   'cc110000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000e9',
   'America/New_York', (now() + interval '4 weeks')::date);
INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
  ('dd110000-0000-0000-0000-000000000001', 2, '19:00'),
  ('dd110000-0000-0000-0000-000000000001', 6, '07:00');

-- Bulk series-occurrence inserts stay SILENT
INSERT INTO sessions (id, organizer_id, group_id, series_id, state, scheduled_for) VALUES
  ('ee110000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001',
   'dd110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '1 day'),
  ('ee110000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001',
   'dd110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '3 days');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001' AND kind='system_session'$$,
  ARRAY[0], 'series occurrences do not announce individually');

-- Non-series sessions still announce
INSERT INTO sessions (organizer_id, group_id, state, scheduled_for) VALUES
  ('00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '2 days');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001' AND kind='system_session'$$,
  ARRAY[1], 'single sessions still announce');

SET LOCAL role authenticated;

-- Non-organizer cannot finalize
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f9';
SELECT throws_ok(
  $$SELECT public.finalize_series('dd110000-0000-0000-0000-000000000001')$$,
  'P0001', 'only the series organizer may finalize',
  'non-organizer cannot finalize');

-- Organizer finalizes → exactly ONE summary containing weekday abbreviations
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e9';
SELECT lives_ok(
  $$SELECT public.finalize_series('dd110000-0000-0000-0000-000000000001')$$,
  'organizer finalizes');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001'
      AND kind='system_session' AND body LIKE '🔁%Mon%Fri%'$$,
  ARRAY[1], 'one series summary with weekday names');

-- Sessions DELETE policy: organizer deletes scheduled, member cannot
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM sessions WHERE id='ee110000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1], 'organizer deletes own scheduled session');
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f9';
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM sessions WHERE id='ee110000-0000-0000-0000-000000000002' RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0], 'non-organizer cannot delete sessions');

SELECT * FROM finish();
ROLLBACK;
