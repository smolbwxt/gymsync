BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

-- ============================================================
-- mark_no_shows() — Phase S Task 1 (20260719000003_mark_no_shows.sql),
-- fixed forward by 20260719000004_mark_no_shows_absence_fix.sql
-- Design doc Flow 6: "If late_minutes exceeds threshold (default 15),
-- check_in_state → no_show ... She can still join late but burpees
-- compound."
--
-- Finding 1 (Critical) regression coverage: 'late' means PRESENT in this
-- schema — evaluate_lateness (20260714000001_session_engine_rpcs.sql,
-- lines 29-31) only sets check_in_state='late' when check_in_at IS NOT
-- NULL. A participant who has actually checked in must never be flipped to
-- no_show, no matter how far past threshold her session is. Fixture ns6
-- kate below now carries check_in_at (as production's evaluate_lateness
-- always does before this state exists) and the assertion direction is
-- flipped accordingly: she stays 'late', she does not flip.
--
-- Finding 2 (Important) regression coverage: fixture nsb leo's session
-- carries a malformed late_penalty->>'no_show_after_minutes' ('abc'). The
-- cron tick must not raise, must fall back to the default 15-minute
-- threshold for that session, and must not prevent any other session in
-- the same batch from being processed.
-- ============================================================

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- ns1 alice  = organizer of every fixture session
-- ns2 bob    = invited, over-threshold session -> flips to no_show; also
--              the caller for the "clients can't invoke this directly" check
-- ns3 carol  = ready, in_progress, far past threshold -> must NEVER flip
-- ns4 dana   = online, over-threshold session -> flips to no_show
-- ns5 erin   = late WITH check_in_at (present), UNDER-threshold session ->
--              stays 'late' (no flip)
-- ns6 kate   = late WITH check_in_at (present), OVER-threshold session ->
--              stays 'late', must NEVER flip (Finding 1: late = present in
--              this schema, absence is the real criterion)
-- ns7 frank  = invited, ad-hoc session (scheduled_for NULL) -> unaffected
-- ns8 grace  = invited, completed session -> unaffected
-- ns9 henry  = invited, abandoned session -> unaffected
-- nsa iris   = invited, re-join fixture -> flips to no_show, then re-checks
--              in (Flow 6 late rejoin), then must stay 'ready' on a later
--              mark_no_shows() run
-- nsb leo    = invited, session whose late_penalty->>'no_show_after_minutes'
--              is malformed ('abc') -> falls back to the default 15-minute
--              threshold, flips to no_show; proves Finding 2's defensive
--              cast doesn't raise and doesn't block other sessions' rows

INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-0000-0000-0000000000a1', 'ns_alice@t.com'),
  ('a0000000-0000-0000-0000-0000000000a2', 'ns_bob@t.com'),
  ('a0000000-0000-0000-0000-0000000000a3', 'ns_carol@t.com'),
  ('a0000000-0000-0000-0000-0000000000a4', 'ns_dana@t.com'),
  ('a0000000-0000-0000-0000-0000000000a5', 'ns_erin@t.com'),
  ('a0000000-0000-0000-0000-0000000000a6', 'ns_kate@t.com'),
  ('a0000000-0000-0000-0000-0000000000a7', 'ns_frank@t.com'),
  ('a0000000-0000-0000-0000-0000000000a8', 'ns_grace@t.com'),
  ('a0000000-0000-0000-0000-0000000000a9', 'ns_henry@t.com'),
  ('a0000000-0000-0000-0000-0000000000aa', 'ns_iris@t.com'),
  ('a0000000-0000-0000-0000-0000000000ab', 'ns_leo@t.com');
INSERT INTO profiles (id, username) VALUES
  ('a0000000-0000-0000-0000-0000000000a1', 'ns_alice'),
  ('a0000000-0000-0000-0000-0000000000a2', 'ns_bob'),
  ('a0000000-0000-0000-0000-0000000000a3', 'ns_carol'),
  ('a0000000-0000-0000-0000-0000000000a4', 'ns_dana'),
  ('a0000000-0000-0000-0000-0000000000a5', 'ns_erin'),
  ('a0000000-0000-0000-0000-0000000000a6', 'ns_kate'),
  ('a0000000-0000-0000-0000-0000000000a7', 'ns_frank'),
  ('a0000000-0000-0000-0000-0000000000a8', 'ns_grace'),
  ('a0000000-0000-0000-0000-0000000000a9', 'ns_henry'),
  ('a0000000-0000-0000-0000-0000000000aa', 'ns_iris'),
  ('a0000000-0000-0000-0000-0000000000ab', 'ns_leo');

-- ============================================================
-- RLS negative, checked FIRST (before any threshold has even elapsed for
-- fixtures not yet inserted): mark_no_shows() is not a client RPC. Mirrors
-- push_cron_test.sql's "clients cannot call enqueue_scheduled_pushes
-- directly" convention.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'a0000000-0000-0000-0000-0000000000a2';
SELECT throws_ok(
  $$SELECT public.mark_no_shows()$$,
  '42501', NULL,
  'clients cannot call mark_no_shows directly'
);

SET LOCAL role postgres;

-- OVER-threshold session: scheduled 16 minutes ago (exceeds the 15-minute
-- default) — bob (invited), dana (online) flip; kate (late, but WITH
-- check_in_at set — she is present, per evaluate_lateness's own semantics)
-- must NOT flip (Finding 1 regression).
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', now() - interval '16 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a2', 'invited', NULL),
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a4', 'online', NULL),
  -- kate checked in 15 minutes ago (1 minute after scheduled_for) — present,
  -- marked 'late' by evaluate_lateness the way production actually produces
  -- this state. The impossible fixture (check_in_at NULL on a 'late' row)
  -- from 20260719000003's test is fixed here per the review finding.
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a6', 'late', now() - interval '15 minutes');

-- UNDER-threshold session: scheduled 14 minutes ago (under the 15-minute
-- default) — erin (late, WITH check_in_at — present) must stay 'late'.
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', now() - interval '14 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  -- erin checked in 13 minutes ago (1 minute after scheduled_for) — present.
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a5', 'late', now() - interval '13 minutes');

-- READY guard: in_progress, scheduled 45 minutes ago (well past threshold)
-- — carol (ready) must NEVER be flipped regardless of elapsed time.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-0000000000a1',
   'in_progress', now() - interval '45 minutes', now() - interval '44 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-0000000000a3', 'ready');

-- Ad-hoc session: scheduled_for IS NULL — must be entirely unaffected
-- (the function's own `scheduled_for IS NOT NULL` guard excludes it).
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', NULL);
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-0000000000a7', 'invited');

-- Completed session, scheduled 45 minutes ago — state filter excludes it.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at, completed_at) VALUES
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-0000000000a1',
   'completed', now() - interval '45 minutes', now() - interval '44 minutes', now() - interval '5 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-0000000000a8', 'invited');

-- Abandoned session, scheduled 45 minutes ago — state filter excludes it.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at, completed_at) VALUES
  ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-0000000000a1',
   'abandoned', now() - interval '45 minutes', now() - interval '44 minutes', now() - interval '5 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-0000000000a9', 'invited');

-- Re-join fixture: in_progress, scheduled 45 minutes ago (over threshold) —
-- iris (invited) flips to no_show on the first run, then rejoins late.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-0000000000a1',
   'in_progress', now() - interval '45 minutes', now() - interval '44 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-0000000000aa', 'invited');

-- Malformed-threshold session (Finding 2 regression): scheduled 20 minutes
-- ago, late_penalty->>'no_show_after_minutes' is the non-numeric 'abc'.
-- The defensive cast must fall back to the default 15-minute threshold
-- (20 > 15, so leo flips) instead of raising and aborting the whole
-- UPDATE — which would otherwise take every other session's flips down
-- with it in the same statement.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, late_penalty) VALUES
  ('b0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', now() - interval '20 minutes',
   '{"exercise":"burpee","per_minute":5,"no_show_after_minutes":"abc"}'::jsonb);
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-0000000000ab', 'invited');


-- ============================================================
-- mark_no_shows(): first invocation
-- ============================================================
SELECT lives_ok(
  $$SELECT public.mark_no_shows()$$,
  'cron tick does not raise despite malformed no_show_after_minutes on another session (Finding 2)'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000001'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a2'$$,
  $$VALUES ('no_show')$$,
  'over-threshold (16min): invited participant flips to no_show'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000001'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a4'$$,
  $$VALUES ('no_show')$$,
  'over-threshold (16min): online participant flips to no_show'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000001'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a6'$$,
  $$VALUES ('late')$$,
  'over-threshold (16min): late participant WITH check_in_at (present) stays late, does NOT flip to no_show (Finding 1)'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000002'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a5'$$,
  $$VALUES ('late')$$,
  'under-threshold (14min): late participant WITH check_in_at (present) stays late, does not flip'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000008'
      AND user_id = 'a0000000-0000-0000-0000-0000000000ab'$$,
  $$VALUES ('no_show')$$,
  'malformed no_show_after_minutes (''abc''): falls back to default 15min threshold, invited participant flips (Finding 2)'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000003'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a3'$$,
  $$VALUES ('ready')$$,
  'ready participant is never flipped, even in_progress and far past threshold'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000004'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a7'$$,
  $$VALUES ('invited')$$,
  'session with NULL scheduled_for (ad-hoc) is unaffected'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000005'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a8'$$,
  $$VALUES ('invited')$$,
  'completed session is unaffected'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000006'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a9'$$,
  $$VALUES ('invited')$$,
  'abandoned session is unaffected'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000007'
      AND user_id = 'a0000000-0000-0000-0000-0000000000aa'$$,
  $$VALUES ('no_show')$$,
  're-join fixture: iris flips to no_show on the first run'
);


-- ============================================================
-- Late re-join (Flow 6: "she can still join late"): the existing
-- self-service check-in path (SessionRepository.checkIn's bare UPDATE under
-- the "participant updates own check-in" RLS policy) flips no_show -> ready
-- with no code changes needed.
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'a0000000-0000-0000-0000-0000000000aa';

SELECT lives_ok(
  $$UPDATE session_participants
    SET check_in_state = 'ready', check_in_at = now(), check_in_method = 'geofence'
    WHERE session_id = 'b0000000-0000-0000-0000-000000000007'
      AND user_id = 'a0000000-0000-0000-0000-0000000000aa'$$,
  'no_show participant can still check in late (Flow 6 rejoin)'
);

SET LOCAL role postgres;
SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000007'
      AND user_id = 'a0000000-0000-0000-0000-0000000000aa'$$,
  $$VALUES ('ready')$$,
  're-join fixture: iris flips back to ready via the ordinary check-in path'
);


-- ============================================================
-- mark_no_shows(): second invocation — idempotent, and does not re-flip a
-- participant who has since checked in (ready is excluded from the guard).
-- ============================================================
SELECT public.mark_no_shows();

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000001'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a2'$$,
  $$VALUES ('no_show')$$,
  'repeated invocation: already-no_show participant is unaffected (idempotent)'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000007'
      AND user_id = 'a0000000-0000-0000-0000-0000000000aa'$$,
  $$VALUES ('ready')$$,
  'repeated invocation: a rejoined (ready) participant is never re-flipped to no_show'
);

SELECT * FROM finish();
ROLLBACK;
