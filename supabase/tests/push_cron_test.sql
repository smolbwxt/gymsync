BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(26);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- pd1 alice = organizer of every fixture session
-- pd2 bob   = participant
-- pd3 carol = participant (idle60 fixture only)
-- pd4 dave  = outsider — not a participant/organizer of anything, used for the
--             heartbeat RPC's unauthorized-caller check
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000d0001', 'cron_alice@t.com'),
  ('00000000-0000-0000-0000-0000000d0002', 'cron_bob@t.com'),
  ('00000000-0000-0000-0000-0000000d0003', 'cron_carol@t.com'),
  ('00000000-0000-0000-0000-0000000d0004', 'cron_dave@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000d0001', 'cron_alice'),
  ('00000000-0000-0000-0000-0000000d0002', 'cron_bob'),
  ('00000000-0000-0000-0000-0000000d0003', 'cron_carol'),
  ('00000000-0000-0000-0000-0000000d0004', 'cron_dave');

SET LOCAL role postgres;

-- Group A holds the idle/reminder/heartbeat/set_logs/chat "same group" fixtures.
-- Group B holds only a control session, used to prove the chat trigger's
-- group_id join doesn't leak across groups.
INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000d1001', 'Cron Crew A', '00000000-0000-0000-0000-0000000d0001'),
  ('00000000-0000-0000-0000-0000000d1002', 'Cron Crew B', '00000000-0000-0000-0000-0000000d0001');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000d1001', '00000000-0000-0000-0000-0000000d0001', 'admin'),
  ('00000000-0000-0000-0000-0000000d1001', '00000000-0000-0000-0000-0000000d0002', 'member'),
  ('00000000-0000-0000-0000-0000000d1001', '00000000-0000-0000-0000-0000000d0003', 'member'),
  ('00000000-0000-0000-0000-0000000d1002', '00000000-0000-0000-0000-0000000d0001', 'admin');

-- idle30: 31 minutes since last activity — should trip the 30-min tier only.
INSERT INTO sessions (id, organizer_id, group_id, state, started_at, last_activity_at) VALUES
  ('d0000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress',
   now() - interval '2 hours', now() - interval '31 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-0000000d0001', 'ready'),
  ('d0000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-0000000d0002', 'ready');

-- idle60: 61 minutes since last activity — trips BOTH the 30-min and 60-min
-- tiers together (a delayed-cron catch-up scenario; both firing at once is
-- correct given the implementation, not a bug).
INSERT INTO sessions (id, organizer_id, group_id, state, started_at, last_activity_at) VALUES
  ('d0000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress',
   now() - interval '3 hours', now() - interval '61 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-0000000d0001', 'ready'),
  ('d0000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-0000000d0002', 'ready'),
  ('d0000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-0000000d0003', 'ready');

-- abandon: 6h05m since last activity — should auto-transition to 'abandoned'.
INSERT INTO sessions (id, organizer_id, group_id, state, started_at, last_activity_at) VALUES
  ('d0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress',
   now() - interval '7 hours', now() - interval '6 hours 5 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000d0001', 'ready'),
  ('d0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000d0002', 'ready');

-- reminder: scheduled_for 14m30s out — inside the [now()+14min, now()+15min) window.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'scheduled',
   now() + interval '14 minutes 30 seconds');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000d0001', 'invited'),
  ('d0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000d0002', 'invited');

-- reminder_null: scheduled state but scheduled_for IS NULL — must never enqueue.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'scheduled', NULL);
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000d0001', 'invited'),
  ('d0000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000d0003', 'invited');

-- reminder_catchup (20260716000004 regression): scheduled_for only 5 minutes
-- out — OUTSIDE the old boundary-exact [now()+14min, now()+15min) window,
-- which would have silently skipped this session forever under a single
-- delayed/dropped cron tick. Proves the widened
-- "scheduled_for - 15min <= now() AND scheduled_for > now()" predicate
-- still catches it, i.e. the fix is catch-up-safe.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'scheduled',
   now() + interval '5 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000d0001', 'invited'),
  ('d0000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000d0002', 'invited');

-- heartbeat: fresh in_progress session, no activity recorded yet.
INSERT INTO sessions (id, organizer_id, group_id, state, started_at) VALUES
  ('d0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress', now() - interval '10 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('d0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000d0001', 'ready'),
  ('d0000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000d0002', 'ready');
-- dave (d0004) is deliberately NOT a participant or organizer of this session.


-- ============================================================
-- enqueue_scheduled_pushes(): first invocation
-- ============================================================
SELECT public.enqueue_scheduled_pushes();

-- ── idle30 fixture ──────────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_30min' AND user_id = '00000000-0000-0000-0000-0000000d0001'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000030'$$,
  ARRAY[1],
  'idle 30min: organizer gets exactly one session_idle_30min push'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_60min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000030'$$,
  ARRAY[0],
  'idle 30min fixture: session_idle_60min does not fire at 31 minutes'
);

-- (event filter restricted to session_idle_*: bob also has a legitimate,
-- unrelated session_invite row from the session_participants fixture INSERT
-- itself — zzpush_session_invite, 20260716000001_push_schema.sql — which
-- isn't part of what this assertion is checking.)
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE user_id = '00000000-0000-0000-0000-0000000d0002'
      AND event IN ('session_idle_30min', 'session_idle_60min')
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000030'$$,
  ARRAY[0],
  'idle 30min fixture: non-organizer participant gets no idle push'
);

-- ── idle60 fixture ──────────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_30min' AND user_id = '00000000-0000-0000-0000-0000000d0001'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000060'$$,
  ARRAY[1],
  'idle 60min fixture: organizer also gets the 30min tier (ladder catch-up)'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_60min' AND user_id = '00000000-0000-0000-0000-0000000d0001'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000060'$$,
  ARRAY[1],
  'idle 60min fixture: organizer gets the 60min tier'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_60min'
      AND user_id IN ('00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000d0003')
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000060'$$,
  ARRAY[2],
  'idle 60min fixture: all other participants get session_idle_60min'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_30min'
      AND user_id IN ('00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000d0003')
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000060'$$,
  ARRAY[0],
  'idle 60min fixture: non-organizer participants never get the 30min tier'
);

-- ── abandon fixture ─────────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT state FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000a1'$$,
  $$VALUES ('abandoned')$$,
  'abandon fixture: session state auto-transitions to abandoned at 6 hours'
);

SELECT ok(
  (SELECT completed_at = last_activity_at FROM sessions
   WHERE id = 'd0000000-0000-0000-0000-0000000000a1'),
  'abandon fixture: completed_at is set to last_activity_at'
);

-- ── reminder fixtures ───────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_reminder_15min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-0000000000b1'$$,
  ARRAY[2],
  'reminder fixture: both participants get session_reminder_15min'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_reminder_15min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-0000000000b2'$$,
  ARRAY[0],
  'NULL scheduled_for session never enqueues a reminder'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_reminder_15min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-0000000000b3'$$,
  ARRAY[2],
  'reminder catch-up: session scheduled 5 minutes out (past the old boundary-exact window) still gets reminded — widened window is catch-up-safe'
);

-- ============================================================
-- enqueue_scheduled_pushes(): second invocation — no duplicates
-- ============================================================
SELECT public.enqueue_scheduled_pushes();

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_reminder_15min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-0000000000b1'$$,
  ARRAY[2],
  'reminder window fires only once across repeated invocations'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_30min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000030'$$,
  ARRAY[1],
  'idle 30min push fires only once across repeated invocations'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_idle_60min'
      AND payload ->> 'session_id' = 'd0000000-0000-0000-0000-000000000060'$$,
  ARRAY[3],
  'idle 60min pushes fire only once across repeated invocations'
);


-- ============================================================
-- touch_session_activity(): client foreground heartbeat RPC
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000d0002';

SELECT lives_ok(
  $$SELECT public.touch_session_activity('d0000000-0000-0000-0000-0000000000c1')$$,
  'participant heartbeat succeeds'
);

SET LOCAL role postgres;
SELECT ok(
  (SELECT last_activity_at >= now() - interval '5 seconds'
   FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000c1'),
  'heartbeat RPC updates last_activity_at to now'
);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000d0004';
SELECT throws_ok(
  $$SELECT public.touch_session_activity('d0000000-0000-0000-0000-0000000000c1')$$,
  'P0001', 'only session participants may send an activity heartbeat',
  'non-participant heartbeat is rejected'
);


-- ============================================================
-- set_logs INSERT trigger
-- ============================================================
SET LOCAL role postgres;

INSERT INTO sessions (id, organizer_id, group_id, state, started_at) VALUES
  ('d0000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress', now() - interval '10 minutes'),
  ('d0000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'scheduled', NULL);

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000d0002',
       'd0000000-0000-0000-0000-0000000000d1', e.id, 1, 5, 135.00
FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) e;

SELECT ok(
  (SELECT last_activity_at >= now() - interval '5 seconds'
   FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000d1'),
  'set_logs INSERT touches last_activity_at for an in_progress session'
);

INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000d0002',
       'd0000000-0000-0000-0000-0000000000d2', e.id, 1, 5, 135.00
FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) e;

SELECT ok(
  (SELECT last_activity_at IS NULL FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000d2'),
  'set_logs INSERT does not touch last_activity_at for a non-in_progress session'
);


-- ============================================================
-- chat_messages INSERT trigger (joins via sessions.group_id)
-- ============================================================
INSERT INTO sessions (id, organizer_id, group_id, state, started_at) VALUES
  ('d0000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress', now() - interval '5 minutes'),
  ('d0000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1002', 'in_progress', now() - interval '5 minutes');

INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000d1001', '00000000-0000-0000-0000-0000000d0001',
   'text', 'anyone still lifting?');

SELECT ok(
  (SELECT last_activity_at >= now() - interval '5 seconds'
   FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000e1'),
  'chat_messages INSERT touches last_activity_at for an in_progress session in the same group'
);

SELECT ok(
  (SELECT last_activity_at IS NULL FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000e2'),
  'chat_messages INSERT does not touch a session in a DIFFERENT group'
);


-- ============================================================
-- chat_messages INSERT trigger: system messages do NOT reset the idle
-- clock (regression test, fix round 1) — author_id IS NULL is the "NULL =
-- system" convention (20260710000003_create_chat.sql). Without the guard
-- in touch_session_activity_on_chat(), a system-authored row (e.g. the
-- "session scheduled" announcement announce_session_lifecycle posts when a
-- brand-new session is scheduled into a group that also has an
-- in_progress session) would incorrectly resurrect that unrelated
-- session's activity clock even though no participant did anything. Uses
-- a fixed timestamp literal (not now() - interval) so the assertion is an
-- exact equality check, not a fuzzy "still old" bound.
-- ============================================================
INSERT INTO sessions (id, organizer_id, group_id, state, started_at, last_activity_at) VALUES
  ('d0000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d1001', 'in_progress',
   '2026-01-01 00:00:00+00'::timestamptz, '2026-01-01 00:00:00+00'::timestamptz);

INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000d1001', NULL, 'system_session', 'Session scheduled');

SELECT results_eq(
  $$SELECT last_activity_at FROM sessions WHERE id = 'd0000000-0000-0000-0000-0000000000f1'$$,
  $$VALUES ('2026-01-01 00:00:00+00'::timestamptz)$$,
  'system chat message (author_id IS NULL) does not reset last_activity_at on an in_progress session in the same group'
);


-- ============================================================
-- Security: internal-only maintenance functions are not client-callable
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000d0002';

SELECT throws_ok(
  $$SELECT public.enqueue_scheduled_pushes()$$,
  '42501', NULL,
  'clients cannot call enqueue_scheduled_pushes directly'
);

SELECT throws_ok(
  $$SELECT public.push_drain_dispatch()$$,
  '42501', NULL,
  'clients cannot call push_drain_dispatch directly'
);

SET LOCAL role postgres;
SELECT lives_ok(
  $$SELECT public.push_drain_dispatch()$$,
  'push_drain_dispatch no-ops safely when the vault secret is not yet seeded'
);

SELECT * FROM finish();
ROLLBACK;
