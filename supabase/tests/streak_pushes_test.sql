BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(27);

-- ============================================================
-- Streak pushes through the outbox — Phase S Task 4
-- (20260719000008_streak_pushes.sql)
-- Design doc: Flow 7 notifications (docs/superpowers/specs/2026-06-28-
-- gymsync-design.md:856-860), tunables (:1373-1374).
--
-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- alice           = individual milestone: bumped 8x via direct
--                    streak_bump_user calls (session rows exist only to
--                    satisfy the FK — no completion trigger involved), fires
--                    exactly once at the 7th call, never again at the 8th.
-- gina/hank/ivan   = "Push Crew" group milestone: streak_bump_group bumped 8x
--                    -> pushes all 3 members + one system_streak chat message,
--                    exactly once at 7, never again at 8.
-- kate             = break silence: bumped to a NON-milestone streak (2),
--                    then broken -> zero streak_milestone pushes ever, at
--                    any point in her history.
-- jack             = notification_prefs opt-out: opts out of the new 'streak'
--                    category BEFORE being bumped to a milestone -> enqueue
--                    is suppressed (mirrors push_schema_test.sql's
--                    friend_request opt-out fixture).
-- bob/carol/dave/
-- erin/frank       = at-risk cron fixtures, all scheduled sessions:
--   bob   -> scheduled_for +25min, check_in_at NULL, current_streak=5: FIRES.
--   carol -> scheduled_for +35min (outside the 30-min window): does NOT fire.
--   dave  -> scheduled_for +25min but check_in_at IS NOT NULL (checked in):
--            does NOT fire (absence discipline).
--   erin  -> scheduled_for +25min, current_streak=0: does NOT fire.
--   frank -> scheduled_for +5min (catch-up-safe near side of the window,
--            mirrors push_cron_test.sql's reminder-catchup fixture): FIRES.
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('90000000-0000-0000-0000-000000000a01', 'sp_alice@t.com'),
  ('90000000-0000-0000-0000-000000000a02', 'sp_bob@t.com'),
  ('90000000-0000-0000-0000-000000000a03', 'sp_carol@t.com'),
  ('90000000-0000-0000-0000-000000000a04', 'sp_dave@t.com'),
  ('90000000-0000-0000-0000-000000000a05', 'sp_erin@t.com'),
  ('90000000-0000-0000-0000-000000000a06', 'sp_frank@t.com'),
  ('90000000-0000-0000-0000-000000000a07', 'sp_gina@t.com'),
  ('90000000-0000-0000-0000-000000000a08', 'sp_hank@t.com'),
  ('90000000-0000-0000-0000-000000000a09', 'sp_ivan@t.com'),
  ('90000000-0000-0000-0000-000000000a0a', 'sp_jack@t.com'),
  ('90000000-0000-0000-0000-000000000a0b', 'sp_kate@t.com');
INSERT INTO profiles (id, username) VALUES
  ('90000000-0000-0000-0000-000000000a01', 'sp_alice'),
  ('90000000-0000-0000-0000-000000000a02', 'sp_bob'),
  ('90000000-0000-0000-0000-000000000a03', 'sp_carol'),
  ('90000000-0000-0000-0000-000000000a04', 'sp_dave'),
  ('90000000-0000-0000-0000-000000000a05', 'sp_erin'),
  ('90000000-0000-0000-0000-000000000a06', 'sp_frank'),
  ('90000000-0000-0000-0000-000000000a07', 'sp_gina'),
  ('90000000-0000-0000-0000-000000000a08', 'sp_hank'),
  ('90000000-0000-0000-0000-000000000a09', 'sp_ivan'),
  ('90000000-0000-0000-0000-000000000a0a', 'sp_jack'),
  ('90000000-0000-0000-0000-000000000a0b', 'sp_kate');

INSERT INTO groups (id, name, created_by) VALUES
  ('90000000-0000-0000-0000-000000000b01', 'Push Crew', '90000000-0000-0000-0000-000000000a07');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000a07', 'admin'),
  ('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000a08', 'member'),
  ('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000a09', 'member');


-- ============================================================
-- push_event_category(): new 'streak' mapping
-- ============================================================
SELECT results_eq(
  $$SELECT public.push_event_category('streak_milestone')$$,
  $$VALUES ('streak'::text)$$,
  'push_event_category maps streak_milestone -> streak'
);
SELECT results_eq(
  $$SELECT public.push_event_category('streak_at_risk')$$,
  $$VALUES ('streak'::text)$$,
  'push_event_category maps streak_at_risk -> streak'
);


-- ============================================================
-- Individual milestone: alice, fires at exactly 7, not 6 or 8
-- ============================================================
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('90000000-0000-0000-0000-000000000c01', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c02', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c03', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c04', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c05', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c06', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c07', '90000000-0000-0000-0000-000000000a01', 'completed'),
  ('90000000-0000-0000-0000-000000000c08', '90000000-0000-0000-0000-000000000a01', 'completed');

SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c01');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c02');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c03');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c04');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c05');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c06');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a01'$$,
  ARRAY[0],
  'alice: 6th bump (current_streak=6) does not fire a milestone push'
);

SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c07');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a01'$$,
  ARRAY[1],
  'alice: 7th bump (current_streak=7) fires exactly one milestone push'
);
SELECT results_eq(
  $$SELECT payload ->> 'streak' FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a01'$$,
  $$VALUES ('7'::text)$$,
  'alice: milestone push payload carries streak=7'
);

SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a01', '90000000-0000-0000-0000-000000000c08');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a01'$$,
  ARRAY[1],
  'alice: 8th bump (current_streak=8) does not fire a second milestone push'
);


-- ============================================================
-- Group milestone: Push Crew (gina/hank/ivan), fires at exactly 7,
-- pushes every member + inserts one system_streak chat message.
-- ============================================================
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('90000000-0000-0000-0000-000000000c11', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c12', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c13', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c14', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c15', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c16', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c17', '90000000-0000-0000-0000-000000000a07', 'completed'),
  ('90000000-0000-0000-0000-000000000c18', '90000000-0000-0000-0000-000000000a07', 'completed');

SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c11');
SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c12');
SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c13');
SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c14');
SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c15');
SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c16');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND payload ->> 'group_id' = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0],
  'Push Crew: 6th group bump does not fire a milestone push'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_streak' AND group_id = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[0],
  'Push Crew: 6th group bump does not post a system_streak chat message'
);

SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c17');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND payload ->> 'group_id' = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[3],
  'Push Crew: 7th group bump pushes all 3 members exactly once each'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_streak' AND group_id = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[1],
  'Push Crew: 7th group bump posts exactly one system_streak chat message'
);
SELECT results_eq(
  $$SELECT body FROM chat_messages
    WHERE kind = 'system_streak' AND group_id = '90000000-0000-0000-0000-000000000b01'$$,
  $$VALUES ('🔥 Crew streak: 7 sessions strong!'::text)$$,
  'Push Crew: system_streak chat message body names the milestone'
);

SELECT public.streak_bump_group('90000000-0000-0000-0000-000000000b01', '90000000-0000-0000-0000-000000000c18');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND payload ->> 'group_id' = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[3],
  'Push Crew: 8th group bump does not fire a second round of pushes'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_streak' AND group_id = '90000000-0000-0000-0000-000000000b01'$$,
  ARRAY[1],
  'Push Crew: 8th group bump does not post a second chat message'
);


-- ============================================================
-- Break silence: kate. Bumped to a NON-milestone streak (2), then broken —
-- zero streak_milestone pushes at any point (break itself sets
-- current_streak to 0, never a milestone value, so the trigger's own guard
-- keeps it silent; no separate "break" event/push exists anywhere).
-- ============================================================
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('90000000-0000-0000-0000-000000000e01', '90000000-0000-0000-0000-000000000a0b', 'completed'),
  ('90000000-0000-0000-0000-000000000e02', '90000000-0000-0000-0000-000000000a0b', 'completed');

SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0b', '90000000-0000-0000-0000-000000000e01');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0b', '90000000-0000-0000-0000-000000000e02');
SELECT public.streak_break_user('90000000-0000-0000-0000-000000000a0b', '90000000-0000-0000-0000-000000000e02');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a0b'$$,
  ARRAY[0],
  'kate: non-milestone buildup (streak=2) then a break enqueues zero streak_milestone pushes'
);


-- ============================================================
-- notification_prefs: 'streak' category — schema accepts it, opt-out
-- suppresses enqueue (mirrors push_schema_test.sql's friend_request
-- opt-out fixture).
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '90000000-0000-0000-0000-000000000a01';
SELECT lives_ok(
  $$INSERT INTO notification_prefs (user_id, category, enabled) VALUES
    ('90000000-0000-0000-0000-000000000a01', 'streak', true)$$,
  'notification_prefs.category CHECK constraint now accepts ''streak'''
);

SET LOCAL role postgres;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '90000000-0000-0000-0000-000000000a0a';
INSERT INTO notification_prefs (user_id, category, enabled) VALUES
  ('90000000-0000-0000-0000-000000000a0a', 'streak', false);
SET LOCAL role postgres;

INSERT INTO sessions (id, organizer_id, state) VALUES
  ('90000000-0000-0000-0000-000000000c21', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c22', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c23', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c24', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c25', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c26', '90000000-0000-0000-0000-000000000a0a', 'completed'),
  ('90000000-0000-0000-0000-000000000c27', '90000000-0000-0000-0000-000000000a0a', 'completed');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c21');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c22');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c23');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c24');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c25');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c26');
SELECT public.streak_bump_user('90000000-0000-0000-0000-000000000a0a', '90000000-0000-0000-0000-000000000c27');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_milestone' AND user_id = '90000000-0000-0000-0000-000000000a0a'$$,
  ARRAY[0],
  'jack: opted out of the streak category -> milestone at 7 is suppressed'
);


-- ============================================================
-- At-risk cron: enqueue_streak_at_risk_pushes()
-- ============================================================
INSERT INTO user_streaks (user_id, current_streak) VALUES
  ('90000000-0000-0000-0000-000000000a02', 5),  -- bob:   fires
  ('90000000-0000-0000-0000-000000000a03', 5),  -- carol: too far out
  ('90000000-0000-0000-0000-000000000a04', 5),  -- dave:  checked in
  ('90000000-0000-0000-0000-000000000a05', 0),  -- erin:  zero streak
  ('90000000-0000-0000-0000-000000000a06', 3);  -- frank: catch-up (near side)

INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('90000000-0000-0000-0000-000000000d01', '90000000-0000-0000-0000-000000000a02', 'scheduled', now() + interval '25 minutes'),
  ('90000000-0000-0000-0000-000000000d02', '90000000-0000-0000-0000-000000000a03', 'scheduled', now() + interval '35 minutes'),
  ('90000000-0000-0000-0000-000000000d03', '90000000-0000-0000-0000-000000000a04', 'scheduled', now() + interval '25 minutes'),
  ('90000000-0000-0000-0000-000000000d04', '90000000-0000-0000-0000-000000000a05', 'scheduled', now() + interval '25 minutes'),
  ('90000000-0000-0000-0000-000000000d05', '90000000-0000-0000-0000-000000000a06', 'scheduled', now() + interval '5 minutes');

INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('90000000-0000-0000-0000-000000000d01', '90000000-0000-0000-0000-000000000a02', 'invited', NULL),
  ('90000000-0000-0000-0000-000000000d02', '90000000-0000-0000-0000-000000000a03', 'invited', NULL),
  ('90000000-0000-0000-0000-000000000d03', '90000000-0000-0000-0000-000000000a04', 'online', now() - interval '2 minutes'),
  ('90000000-0000-0000-0000-000000000d04', '90000000-0000-0000-0000-000000000a05', 'invited', NULL),
  ('90000000-0000-0000-0000-000000000d05', '90000000-0000-0000-0000-000000000a06', 'invited', NULL);

SELECT public.enqueue_streak_at_risk_pushes();

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a02'$$,
  ARRAY[1],
  'bob (25 min out, not checked in, streak=5): at-risk push fires exactly once'
);
SELECT results_eq(
  $$SELECT payload ->> 'streak' FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a02'$$,
  $$VALUES ('5'::text)$$,
  'bob: at-risk payload carries his current streak (5)'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a03'$$,
  ARRAY[0],
  'carol (35 min out): outside the 30-min window -> no at-risk push'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a04'$$,
  ARRAY[0],
  'dave (checked in, check_in_at IS NOT NULL): no at-risk push — absence discipline'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a05'$$,
  ARRAY[0],
  'erin (current_streak=0): no at-risk push — nothing at risk'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a06'$$,
  ARRAY[1],
  'frank (5 min out): catch-up-safe near side of the window still fires'
);
SELECT results_eq(
  $$SELECT (streak_at_risk_notified_at IS NOT NULL) FROM session_participants
    WHERE session_id = '90000000-0000-0000-0000-000000000d01' AND user_id = '90000000-0000-0000-0000-000000000a02'$$,
  ARRAY[true],
  'bob: streak_at_risk_notified_at is stamped after enqueue (dedupe flag)'
);

-- Second tick — dedupe, no duplicates, carol still excluded.
SELECT public.enqueue_streak_at_risk_pushes();

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a02'$$,
  ARRAY[1],
  'bob: second cron tick does not duplicate the at-risk push'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a06'$$,
  ARRAY[1],
  'frank: second cron tick does not duplicate the at-risk push'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'streak_at_risk' AND user_id = '90000000-0000-0000-0000-000000000a03'$$,
  ARRAY[0],
  'carol: still outside the window on the second tick too'
);


-- ============================================================
-- Security: enqueue_streak_at_risk_pushes() is not a client RPC
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '90000000-0000-0000-0000-000000000a02';
SELECT throws_ok(
  $$SELECT public.enqueue_streak_at_risk_pushes()$$,
  '42501', NULL,
  'clients cannot call enqueue_streak_at_risk_pushes directly'
);

SELECT * FROM finish();
ROLLBACK;
