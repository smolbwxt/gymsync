-- Phase O / Task 1 sweep-proof, fix-wave 2: series_group_id() relocated to
-- private schema (20260726000003_series_group_id_private_schema.sql).
--
-- The INSERT negative case below deliberately isolates series_group_id's
-- OWN contribution to "organizer writes series days"' compound gate
-- (is_series_organizer(...) AND is_group_member(series_group_id(...))): a
-- departed-group organizer still passes is_series_organizer (a fact about
-- session_series.organizer_id, unaffected by group membership) but must
-- fail on the series_group_id-derived is_group_member check — same
-- "departed member" isolation technique is_group_member's own sweep-proof
-- file used for sessions DELETE. UPDATE/DELETE share the identical compound
-- shape and are covered positively here; their own negative cases have
-- pre-existing coverage in rls_series_test.sql / series_announcements_test.
-- sql, re-proven by a full-suite green run against these now-repointed
-- policies.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

INSERT INTO auth.users (id, email) VALUES
  ('f4000000-0000-0000-0000-0000000000a1', 'f4a1@t.com'),  -- Dana: group member + series organizer
  ('f4000000-0000-0000-0000-0000000000a2', 'f4a2@t.com'),  -- Erin: plain group member
  ('f4000000-0000-0000-0000-0000000000a3', 'f4a3@t.com');  -- Frank: outsider
INSERT INTO profiles (id, username) VALUES
  ('f4000000-0000-0000-0000-0000000000a1', 'f4_dana'),
  ('f4000000-0000-0000-0000-0000000000a2', 'f4_erin'),
  ('f4000000-0000-0000-0000-0000000000a3', 'f4_frank');

INSERT INTO groups (id, name, created_by) VALUES
  ('f4000000-0000-0000-0000-000000000b01', 'Series Sweep Crew', 'f4000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('f4000000-0000-0000-0000-000000000b01', 'f4000000-0000-0000-0000-0000000000a1', 'admin'),
  ('f4000000-0000-0000-0000-000000000b01', 'f4000000-0000-0000-0000-0000000000a2', 'member');

INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('f4000000-0000-0000-0000-000000000d01', 'f4000000-0000-0000-0000-000000000b01',
   'f4000000-0000-0000-0000-0000000000a1', 'UTC', (now() + interval '4 weeks')::date);
INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
  ('f4000000-0000-0000-0000-000000000d01', 2, '18:00');

-- Second, unrelated group + series — used only for the no-widening proof
-- (series_group_id must return the CORRECT group per series, not a
-- memoized/static value from the first call).
INSERT INTO groups (id, name, created_by) VALUES
  ('f4000000-0000-0000-0000-000000000b02', 'Other Group', 'f4000000-0000-0000-0000-0000000000a3');
INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('f4000000-0000-0000-0000-000000000d02', 'f4000000-0000-0000-0000-000000000b02',
   'f4000000-0000-0000-0000-0000000000a3', 'UTC', (now() + interval '4 weeks')::date);

SET LOCAL role authenticated;

-- ============================================================
-- 1-2. session_series_days SELECT ("group members read series days").
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f4000000-0000-0000-0000-0000000000a2';  -- Erin (member)
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series_days WHERE series_id = 'f4000000-0000-0000-0000-000000000d01'$$,
  ARRAY[1], 'positive: a group member reads the series'' days via private.series_group_id');

SET LOCAL request.jwt.claim.sub = 'f4000000-0000-0000-0000-0000000000a3';  -- Frank (outsider)
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series_days WHERE series_id = 'f4000000-0000-0000-0000-000000000d01'$$,
  ARRAY[0], 'negative: an outsider cannot read the series'' days');

-- ============================================================
-- 3. session_series_days INSERT ("organizer writes series days") —
-- positive, organizer who is still a group member.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'f4000000-0000-0000-0000-0000000000a1';  -- Dana (organizer + member)
SELECT lives_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('f4000000-0000-0000-0000-000000000d01', 3, '18:00')$$,
  'positive: the organizer, still a group member, can add a series day'
);

-- ============================================================
-- 4. session_series_days INSERT — negative, isolating series_group_id's
-- role: Dana self-leaves the group (still the series organizer per
-- session_series.organizer_id, which is untouched by this) so
-- is_series_organizer alone would pass, but private.series_group_id-derived
-- is_group_member now fails.
-- ============================================================
SELECT lives_ok(
  $$DELETE FROM group_members
    WHERE group_id = 'f4000000-0000-0000-0000-000000000b01'
      AND user_id  = 'f4000000-0000-0000-0000-0000000000a1'$$,
  'fixture step: Dana self-leaves the group (self-leave branch of a separate policy)'
);

SELECT throws_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('f4000000-0000-0000-0000-000000000d01', 4, '18:00')$$,
  '42501', NULL,
  'negative: a departed organizer (is_series_organizer true, but no longer resolved as a group member via series_group_id) is rejected'
);

-- Restore Dana's membership (direct, bypassing RLS) so the remaining
-- positive UPDATE/DELETE cases below reflect an ordinary current-member
-- organizer, not the departed-organizer edge case just proven above.
SET LOCAL role postgres;
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('f4000000-0000-0000-0000-000000000b01', 'f4000000-0000-0000-0000-0000000000a1', 'admin');

-- ============================================================
-- 5-6. session_series_days UPDATE / DELETE ("organizer updates/deletes
-- series days") — positive only (negative shares the identical compound
-- gate already proven above).
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f4000000-0000-0000-0000-0000000000a1';  -- Dana (organizer, member again)
SELECT lives_ok(
  $$UPDATE session_series_days SET time_local = '19:00'
    WHERE series_id = 'f4000000-0000-0000-0000-000000000d01' AND weekday = 2$$,
  'positive: the organizer, a current group member, can update a series day'
);

SELECT lives_ok(
  $$DELETE FROM session_series_days
    WHERE series_id = 'f4000000-0000-0000-0000-000000000d01' AND weekday = 3$$,
  'positive: the organizer, a current group member, can delete a series day'
);

-- ============================================================
-- 7-8. Relocation proof — direct-call correctness, no widening across a
-- SECOND, unrelated series/group pair.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.series_group_id('f4000000-0000-0000-0000-000000000d01')$$,
  ARRAY['f4000000-0000-0000-0000-000000000b01'::uuid],
  'private.series_group_id(series 1) resolves to group 1'
);

SELECT results_eq(
  $$SELECT private.series_group_id('f4000000-0000-0000-0000-000000000d02')$$,
  ARRAY['f4000000-0000-0000-0000-000000000b02'::uuid],
  'no widening: private.series_group_id(series 2) resolves to group 2, not group 1'
);

-- ============================================================
-- 9. Schema USAGE denial.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'f4000000-0000-0000-0000-0000000000a1';  -- Dana

SELECT throws_ok(
  $$SELECT private.series_group_id('f4000000-0000-0000-0000-000000000d01')$$,
  '42501', NULL,
  'authenticated cannot name private.series_group_id directly: no USAGE on schema private'
);

-- ============================================================
-- 10-11. Oracle closed: gone from public, calling by name fails.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'series_group_id'$$,
  ARRAY[0], 'public.series_group_id no longer exists in any form — the RPC oracle is closed');

SELECT throws_ok(
  $$SELECT public.series_group_id('f4000000-0000-0000-0000-000000000d01')$$,
  '42883', NULL,
  'calling public.series_group_id by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
