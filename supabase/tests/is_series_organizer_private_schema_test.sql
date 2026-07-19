-- Debt-zero sprint / Task 1, item 2: is_series_organizer() relocated to
-- private schema (20260727000003_is_series_organizer_private_schema.sql).
--
-- All three dependent policies (session_series_days INSERT/UPDATE/DELETE)
-- share the compound gate
-- "private.is_series_organizer(...) AND private.is_group_member(private.
-- series_group_id(...))" — series_group_id's own contribution to that gate
-- was already isolated by series_group_id_private_schema_test.sql (the
-- departed-organizer case). This file isolates is_series_organizer's OWN
-- branch: Erin is a CURRENT group member (so the is_group_member leg always
-- passes) but is never the series organizer, so every negative case here
-- proves is_series_organizer alone is what blocks her.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

INSERT INTO auth.users (id, email) VALUES
  ('f7000000-0000-0000-0000-0000000000a1', 'f7a1@t.com'),  -- Dana: series organizer, group admin
  ('f7000000-0000-0000-0000-0000000000a2', 'f7a2@t.com'),  -- Erin: current group member, NOT the organizer
  ('f7000000-0000-0000-0000-0000000000a3', 'f7a3@t.com');  -- Frank: outsider
INSERT INTO profiles (id, username) VALUES
  ('f7000000-0000-0000-0000-0000000000a1', 'f7_dana'),
  ('f7000000-0000-0000-0000-0000000000a2', 'f7_erin'),
  ('f7000000-0000-0000-0000-0000000000a3', 'f7_frank');

INSERT INTO groups (id, name, created_by) VALUES
  ('f7000000-0000-0000-0000-000000000b01', 'Organizer Sweep Crew', 'f7000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('f7000000-0000-0000-0000-000000000b01', 'f7000000-0000-0000-0000-0000000000a1', 'admin'),
  ('f7000000-0000-0000-0000-000000000b01', 'f7000000-0000-0000-0000-0000000000a2', 'member');

INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('f7000000-0000-0000-0000-000000000d01', 'f7000000-0000-0000-0000-000000000b01',
   'f7000000-0000-0000-0000-0000000000a1', 'UTC', (now() + interval '4 weeks')::date);
-- Baseline days for the UPDATE/DELETE cases, inserted bypassing RLS.
INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
  ('f7000000-0000-0000-0000-000000000d01', 2, '18:00'),
  ('f7000000-0000-0000-0000-000000000d01', 6, '18:00');

SET LOCAL role authenticated;

-- ============================================================
-- 1-2. session_series_days INSERT ("organizer writes series days").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a1';  -- Dana (organizer + member)
SELECT lives_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('f7000000-0000-0000-0000-000000000d01', 4, '18:00')$$,
  'positive: the series organizer, a current group member, can add a series day'
);

SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a2';  -- Erin (member, NOT organizer)
SELECT throws_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('f7000000-0000-0000-0000-000000000d01', 5, '18:00')$$,
  '42501', NULL,
  'negative: a current group member who is not the series organizer cannot add a series day (is_series_organizer alone blocks — is_group_member is satisfied)'
);

-- ============================================================
-- 3-4. session_series_days UPDATE ("organizer updates series days").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a1';  -- Dana
SELECT lives_ok(
  $$UPDATE session_series_days SET time_local = '19:00'
    WHERE series_id = 'f7000000-0000-0000-0000-000000000d01' AND weekday = 2$$,
  'positive: the series organizer can update a series day'
);

SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a2';  -- Erin
-- RLS UPDATE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as is_session_organizer_private_schema_test.sql).
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_series_days SET time_local = '20:00'
      WHERE series_id = 'f7000000-0000-0000-0000-000000000d01' AND weekday = 6
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'negative: a current group member who is not the series organizer cannot update a series day'
);

-- ============================================================
-- 5-6. session_series_days DELETE ("organizer deletes series days").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a1';  -- Dana
SELECT lives_ok(
  $$DELETE FROM session_series_days
    WHERE series_id = 'f7000000-0000-0000-0000-000000000d01' AND weekday = 4$$,
  'positive: the series organizer can delete a series day'
);

SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a2';  -- Erin
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM session_series_days
      WHERE series_id = 'f7000000-0000-0000-0000-000000000d01' AND weekday = 6
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'negative: a current group member who is not the series organizer cannot delete a series day'
);

-- ============================================================
-- 7-8. Relocation proof — direct-call correctness, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_series_organizer('f7000000-0000-0000-0000-000000000d01',
                                        'f7000000-0000-0000-0000-0000000000a1')$$,
  ARRAY[true],
  'private.is_series_organizer(series, Dana) is true: Dana is the series organizer'
);

SELECT results_eq(
  $$SELECT private.is_series_organizer('f7000000-0000-0000-0000-000000000d01',
                                        'f7000000-0000-0000-0000-0000000000a2')$$,
  ARRAY[false],
  'no widening: private.is_series_organizer(series, Erin) is false — Erin is a group member, not the organizer'
);

-- ============================================================
-- 9. Schema USAGE denial.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f7000000-0000-0000-0000-0000000000a1';  -- Dana

SELECT throws_ok(
  $$SELECT private.is_series_organizer('f7000000-0000-0000-0000-000000000d01',
                                        'f7000000-0000-0000-0000-0000000000a1')$$,
  '42501', NULL,
  'authenticated cannot name private.is_series_organizer directly: no USAGE on schema private'
);

-- ============================================================
-- 10-11. Oracle closed: gone from public, calling by name fails.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_series_organizer'$$,
  ARRAY[0],
  'public.is_series_organizer no longer exists in any form — the oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.is_series_organizer('f7000000-0000-0000-0000-000000000d01',
                                       'f7000000-0000-0000-0000-0000000000a1')$$,
  '42883', NULL,
  'calling public.is_series_organizer by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
