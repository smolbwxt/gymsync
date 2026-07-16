BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

-- ============================================================
-- mark_no_shows() — Phase S Task 1 (20260719000003_mark_no_shows.sql)
-- Design doc Flow 6: "If late_minutes exceeds threshold (default 15),
-- check_in_state → no_show ... She can still join late but burpees
-- compound."
-- ============================================================

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- ns1 alice  = organizer of every fixture session
-- ns2 bob    = invited, over-threshold session -> flips to no_show; also
--              the caller for the "clients can't invoke this directly" check
-- ns3 carol  = ready, in_progress, far past threshold -> must NEVER flip
-- ns4 dana   = online, over-threshold session -> flips to no_show
-- ns5 erin   = late, UNDER-threshold session -> stays 'late' (no flip)
-- ns6 kate   = late, over-threshold session -> flips to no_show
-- ns7 frank  = invited, ad-hoc session (scheduled_for NULL) -> unaffected
-- ns8 grace  = invited, completed session -> unaffected
-- ns9 henry  = invited, abandoned session -> unaffected
-- nsa iris   = invited, re-join fixture -> flips to no_show, then re-checks
--              in (Flow 6 late rejoin), then must stay 'ready' on a later
--              mark_no_shows() run

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
  ('a0000000-0000-0000-0000-0000000000aa', 'ns_iris@t.com');
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
  ('a0000000-0000-0000-0000-0000000000aa', 'ns_iris');

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
-- default) — bob (invited), dana (online), kate (late) all flip.
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', now() - interval '16 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a2', 'invited'),
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a4', 'online'),
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a6', 'late');

-- UNDER-threshold session: scheduled 14 minutes ago (under the 15-minute
-- default) — erin (late) must stay 'late'.
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a1',
   'lobby_open', now() - interval '14 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a5', 'late');

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


-- ============================================================
-- mark_no_shows(): first invocation
-- ============================================================
SELECT public.mark_no_shows();

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
  $$VALUES ('no_show')$$,
  'over-threshold (16min): late participant flips to no_show'
);

SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE session_id = 'b0000000-0000-0000-0000-000000000002'
      AND user_id = 'a0000000-0000-0000-0000-0000000000a5'$$,
  $$VALUES ('late')$$,
  'under-threshold (14min): late participant stays late, does not flip'
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
