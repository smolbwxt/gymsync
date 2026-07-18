-- Phase O / Task 1 sweep-proof: is_session_organizer() relocated to
-- private schema (20260725000005_is_session_organizer_private_schema.sql)
-- — the Phase H review add-on item, classified in the migration header as
-- the same exposure class as the six queue helpers and relocated.
--
-- session_participants' three organizer-only write policies and
-- session_calendar_syncs' SELECT policy already have coverage elsewhere
-- (rls_groups_test.sql / sessions_phase3_test.sql-family tests and
-- connected_accounts_calendar_sync_test.sql's 21 assertions respectively).
-- touch_session_activity/wrap_up_session/still_going are covered by
-- push_cron_test.sql, but ONLY in fixtures where the organizer is ALSO a
-- session_participants row — meaning the pre-existing suite never isolates
-- is_session_organizer's OWN branch of the "participant OR organizer" gate
-- from is_session_participant's. This file's headline content is that
-- isolation: an organizer who is deliberately NOT a session_participants
-- row must still pass the gate on is_session_organizer alone. Plus the
-- standard relocation-mechanics proof.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

INSERT INTO auth.users (id, email) VALUES
  ('e5000000-0000-0000-0000-0000000000a1', 'e5a1@t.com'),  -- Otis: organizer, NOT a participant row
  ('e5000000-0000-0000-0000-0000000000a2', 'e5a2@t.com'),  -- Priya: invited participant
  ('e5000000-0000-0000-0000-0000000000a3', 'e5a3@t.com');  -- Quinn: outsider, neither organizer nor participant
INSERT INTO profiles (id, username) VALUES
  ('e5000000-0000-0000-0000-0000000000a1', 'e5_otis'),
  ('e5000000-0000-0000-0000-0000000000a2', 'e5_priya'),
  ('e5000000-0000-0000-0000-0000000000a3', 'e5_quinn');

-- Ad-hoc (groupless) session, organizer Otis. Deliberately NO
-- session_participants row for Otis at fixture time — isolates the
-- is_session_organizer branch from is_session_participant.
INSERT INTO sessions (id, organizer_id, state, started_at, last_activity_at) VALUES
  ('e5000000-0000-0000-0000-000000000d01', 'e5000000-0000-0000-0000-0000000000a1',
   'in_progress', now() - interval '10 minutes', now() - interval '10 minutes');

SET LOCAL role authenticated;

-- ============================================================
-- 1. session_participants INSERT — organizer-only, isolated from
-- participation (Otis is not yet a participant of his own session here).
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a3';  -- Quinn (outsider)
SELECT throws_ok(
  $$INSERT INTO session_participants (session_id, user_id) VALUES
    ('e5000000-0000-0000-0000-000000000d01', 'e5000000-0000-0000-0000-0000000000a2')$$,
  '42501', NULL,
  'negative: a non-organizer cannot insert a participant row for this session'
);

SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a1';  -- Otis (organizer, not yet a participant)
SELECT lives_ok(
  $$INSERT INTO session_participants (session_id, user_id) VALUES
    ('e5000000-0000-0000-0000-000000000d01', 'e5000000-0000-0000-0000-0000000000a2')$$,
  'positive: the organizer (not a participant themselves) can insert a participant row — private.is_session_organizer alone gates this'
);

-- ============================================================
-- 2. session_participants UPDATE / DELETE — organizer-only
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a3';  -- Quinn
-- RLS UPDATE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as user_settings_test.sql) — throws_ok does not apply.
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants SET check_in_state = 'ready'
      WHERE session_id = 'e5000000-0000-0000-0000-000000000d01'
        AND user_id = 'e5000000-0000-0000-0000-0000000000a2'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'negative: a non-organizer cannot update a participant row'
);

SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a1';  -- Otis
SELECT lives_ok(
  $$UPDATE session_participants SET check_in_state = 'ready'
    WHERE session_id = 'e5000000-0000-0000-0000-000000000d01'
      AND user_id = 'e5000000-0000-0000-0000-0000000000a2'$$,
  'positive: the organizer can update a participant row'
);

SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a3';  -- Quinn
-- RLS DELETE with a failing USING clause is a silent 0-row no-op, not an
-- error (same idiom as delete_parity_test.sql) — throws_ok does not apply.
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM session_participants
      WHERE session_id = 'e5000000-0000-0000-0000-000000000d01'
        AND user_id = 'e5000000-0000-0000-0000-0000000000a2'
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'negative: a non-organizer cannot delete a participant row'
);

-- ============================================================
-- 3. touch_session_activity / wrap_up_session / still_going — the
-- headline isolation: Otis is STILL not in session_participants at this
-- point in the file (only Priya was added above) — proves the RPC gate's
-- "OR private.is_session_organizer(...)" branch alone is sufficient.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a3';  -- Quinn (neither organizer nor participant)
SELECT throws_ok(
  $$SELECT public.touch_session_activity('e5000000-0000-0000-0000-000000000d01')$$,
  'P0001', 'only session participants may send an activity heartbeat',
  'negative: a non-organizer, non-participant outsider is rejected by touch_session_activity'
);

SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a1';  -- Otis (organizer only)
SELECT lives_ok(
  $$SELECT public.touch_session_activity('e5000000-0000-0000-0000-000000000d01')$$,
  'positive: the organizer alone (not a session_participants row) passes touch_session_activity''s gate'
);

SELECT lives_ok(
  $$SELECT public.still_going('e5000000-0000-0000-0000-000000000d01')$$,
  'positive: the organizer alone passes still_going''s gate'
);

SELECT lives_ok(
  $$SELECT public.wrap_up_session('e5000000-0000-0000-0000-000000000d01')$$,
  'positive: the organizer alone passes wrap_up_session''s gate'
);

-- ============================================================
-- 4. Relocation proof — direct-call correctness, schema lockdown, oracle
-- closed, no widening.
-- ============================================================
RESET ROLE;

SELECT results_eq(
  $$SELECT private.is_session_organizer('e5000000-0000-0000-0000-000000000d01',
                                         'e5000000-0000-0000-0000-0000000000a1')$$,
  ARRAY[true],
  'private.is_session_organizer(session, Otis) is true: Otis is the organizer'
);

SELECT results_eq(
  $$SELECT private.is_session_organizer('e5000000-0000-0000-0000-000000000d01',
                                         'e5000000-0000-0000-0000-0000000000a3')$$,
  ARRAY[false],
  'no widening: private.is_session_organizer(session, Quinn) is false: Quinn is not the organizer'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'e5000000-0000-0000-0000-0000000000a1';  -- Otis

SELECT throws_ok(
  $$SELECT private.is_session_organizer('e5000000-0000-0000-0000-000000000d01',
                                         'e5000000-0000-0000-0000-0000000000a1')$$,
  '42501', NULL,
  'authenticated cannot name private.is_session_organizer directly: no USAGE on schema private'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT count(*)::int FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_session_organizer'$$,
  ARRAY[0],
  'public.is_session_organizer no longer exists in any form — the oracle is closed'
);

SELECT throws_ok(
  $$SELECT public.is_session_organizer('e5000000-0000-0000-0000-000000000d01',
                                        'e5000000-0000-0000-0000-0000000000a1')$$,
  '42883', NULL,
  'calling public.is_session_organizer by (schema-qualified) name now fails: function does not exist'
);

SELECT * FROM finish();
ROLLBACK;
