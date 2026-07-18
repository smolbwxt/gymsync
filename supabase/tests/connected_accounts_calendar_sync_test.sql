-- Phase H / Task 5: connected_accounts + session_calendar_syncs staging RLS
-- (20260724000002_connected_accounts_calendar_sync.sql). Covers: table
-- existence, owner can read non-secret connected_accounts columns, owner is
-- structurally denied SELECT on access_token/refresh_token (both an
-- explicit column SELECT and a `SELECT *`) proving the table-wide-REVOKE +
-- column-scoped-GRANT mechanism actually blocks PostgREST-style access (not
-- merely RLS row-filtering), owner has no INSERT/UPDATE/DELETE surface on
-- either table, an outsider sees zero rows via RLS on both tables, an
-- outsider is equally denied all writes, and a final postgres-role read
-- proves both fixture rows survived every denied attempt untouched.
--
-- Fixture idiom mirrors rls_body_weight_logs_test.sql (single owner/
-- organizer + single outsider, fixtures inserted as the default role before
-- any SET LOCAL role authenticated, `RESET ROLE` for the closing integrity
-- read) -- the closest existing precedent for an owner-scoped table with a
-- SECURITY DEFINER relationship helper (is_session_organizer, reused from
-- 20260709000006_create_sessions.sql for session_calendar_syncs).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

-- ── Fixtures ──────────────────────────────────────────────────────────────
-- ca1 alice = connected_accounts owner + session_calendar_syncs organizer
-- ca2 erin  = outsider -- touches neither alice's account nor her session
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000ca001', 'caa1@t.com'),
  ('00000000-0000-0000-0000-0000000ca002', 'caa2@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000ca001', 'ca_alice'),
  ('00000000-0000-0000-0000-0000000ca002', 'ca_erin');

INSERT INTO sessions (id, organizer_id) VALUES
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000ca001');

INSERT INTO connected_accounts
  (id, user_id, provider, provider_account_id, access_token, refresh_token, scopes, expires_at)
VALUES
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000ca001',
   'google_calendar', 'google-acct-123', 'fixture-access-token', 'fixture-refresh-token',
   ARRAY['https://www.googleapis.com/auth/calendar.events'], now() + interval '1 hour');

INSERT INTO session_calendar_syncs (session_id, provider, external_event_id) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'google_calendar', 'gcal-event-abc123');

-- ============================================================
-- 0. Tables exist
-- ============================================================
SELECT has_table('public', 'connected_accounts', 'connected_accounts table exists');
SELECT has_table('public', 'session_calendar_syncs', 'session_calendar_syncs table exists');

-- ============================================================
-- 1. connected_accounts -- owner (alice)
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ca001';  -- Alice

-- ── 1. Owner can select non-secret metadata columns ────────────────────────
SELECT lives_ok(
  $$SELECT provider, provider_account_id, scopes, expires_at, status, created_at
    FROM connected_accounts WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  'owner can select non-secret connected_accounts columns'
);
SELECT results_eq(
  $$SELECT status FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  ARRAY['active'],
  'owner sees the status column value (active by default)'
);

-- ── 2. Owner is structurally denied SELECT on token columns ───────────────
-- Column-level GRANT/REVOKE denial (42501), not RLS row-filtering -- proves
-- the table-wide-REVOKE + column-scoped-GRANT mechanism actually works.
SELECT throws_ok(
  $$SELECT access_token FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'owner CANNOT select access_token even on their own row'
);
SELECT throws_ok(
  $$SELECT refresh_token FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'owner CANNOT select refresh_token even on their own row'
);
SELECT throws_ok(
  $$SELECT * FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'owner CANNOT select * (touches access_token/refresh_token -> denied)'
);

-- ── 3. Owner has no write surface at all (server-side only) ───────────────
SELECT throws_ok(
  $$INSERT INTO connected_accounts (user_id, provider, access_token, refresh_token)
    VALUES ('00000000-0000-0000-0000-0000000ca001', 'google_calendar', 'x', 'y')$$,
  '42501', NULL,
  'owner cannot INSERT a connected_accounts row (server-side / Edge Function only)'
);
SELECT throws_ok(
  $$UPDATE connected_accounts SET status = 'expired'
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'owner cannot UPDATE their own connected_accounts row (no client-side reconnect toggle)'
);
SELECT throws_ok(
  $$DELETE FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'owner cannot DELETE their own connected_accounts row (disconnect is a future endpoint, not a direct table write)'
);

-- ============================================================
-- 2. connected_accounts -- outsider (erin)
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ca002';  -- Erin

SELECT results_eq(
  $$SELECT count(*)::int FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  ARRAY[0],
  'outsider cannot see alice''s connected_accounts row (RLS row filter)'
);
SELECT throws_ok(
  $$INSERT INTO connected_accounts (user_id, provider, access_token, refresh_token)
    VALUES ('00000000-0000-0000-0000-0000000ca002', 'google_calendar', 'x', 'y')$$,
  '42501', NULL,
  'outsider cannot INSERT a connected_accounts row for themselves either'
);
SELECT throws_ok(
  $$UPDATE connected_accounts SET status = 'expired'
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'outsider cannot UPDATE alice''s connected_accounts row'
);
SELECT throws_ok(
  $$DELETE FROM connected_accounts
    WHERE user_id = '00000000-0000-0000-0000-0000000ca001'$$,
  '42501', NULL,
  'outsider cannot DELETE alice''s connected_accounts row'
);

-- ============================================================
-- 3. session_calendar_syncs -- organizer (alice)
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ca001';  -- Alice

SELECT lives_ok(
  $$SELECT external_event_id FROM session_calendar_syncs
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  'organizer can select their own session''s calendar sync row'
);
SELECT results_eq(
  $$SELECT external_event_id FROM session_calendar_syncs
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  ARRAY['gcal-event-abc123'],
  'organizer sees the correct external_event_id'
);
SELECT throws_ok(
  $$INSERT INTO session_calendar_syncs (session_id, provider, external_event_id)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'google_calendar', 'sneaky-event')$$,
  '42501', NULL,
  'organizer cannot INSERT a session_calendar_syncs row (server-side / Edge Function only)'
);
SELECT throws_ok(
  $$UPDATE session_calendar_syncs SET external_event_id = 'sneaky-event'
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  '42501', NULL,
  'organizer cannot UPDATE their own session_calendar_syncs row'
);
SELECT throws_ok(
  $$DELETE FROM session_calendar_syncs
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  '42501', NULL,
  'organizer cannot DELETE their own session_calendar_syncs row'
);

-- ============================================================
-- 4. session_calendar_syncs -- outsider (erin, not a participant/organizer)
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000ca002';  -- Erin

SELECT results_eq(
  $$SELECT count(*)::int FROM session_calendar_syncs
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'outsider cannot see alice''s session_calendar_syncs row (RLS row filter)'
);
SELECT throws_ok(
  $$INSERT INTO session_calendar_syncs (session_id, provider, external_event_id)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'google_calendar', 'sneaky-event-2')$$,
  '42501', NULL,
  'outsider cannot INSERT a session_calendar_syncs row for alice''s session'
);

-- ============================================================
-- 5. postgres-role read confirms both rows survived every denied attempt
-- ============================================================
RESET ROLE;
SELECT results_eq(
  $$SELECT access_token FROM connected_accounts
    WHERE id = 'c1000000-0000-0000-0000-000000000001'$$,
  ARRAY['fixture-access-token'],
  'alice''s access_token is unchanged after every denied attempt above'
);
SELECT results_eq(
  $$SELECT external_event_id FROM session_calendar_syncs
    WHERE session_id = 'c0000000-0000-0000-0000-000000000001'$$,
  ARRAY['gcal-event-abc123'],
  'the session_calendar_syncs mapping is unchanged after every denied attempt above'
);

SELECT * FROM finish();
ROLLBACK;
