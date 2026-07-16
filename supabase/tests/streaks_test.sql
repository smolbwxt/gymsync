BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(38);

-- ============================================================
-- user_streaks / group_streaks — Phase S Task 3
-- (20260719000006_streaks.sql)
-- Design doc: Flow 7 (docs/superpowers/specs/2026-06-28-gymsync-design.md:838-860),
-- schema (:553-579), RLS (:667-668).
--
-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- alice = solo scheduled streak narrative: increments x2 (A1, A3), an
--         ad-hoc/unscheduled completion in between that must stay neutral
--         (A2, scheduled_for NULL), then a no_show (A4) that breaks current
--         but must leave the longest-streak watermark (2) standing.
-- bob   = baseline completed session (B0) then an `abandoned` session he
--         never checked into (B1, check_in_at NULL) -> breaks.
-- carol = baseline completed session (C0) then an `abandoned` session where
--         she WAS present (C1, check_in_state='late' WITH check_in_at set —
--         deliberately not 'ready', to prove the break predicate is
--         check_in_at IS NULL, never a state-label guess per the
--         mark_no_shows Finding-1 lesson) -> must NOT break.
-- dave/erin/frank = group "Streak Crew" (G1). GS1: all three ready ->
--         group streak increments AND each individual increments. GS2:
--         frank never checks in and gets flipped to no_show WHILE the
--         session is still running (mark_no_shows-style direct flip,
--         simulating Flow 6 "session continues without her") — this must
--         break BOTH frank's individual streak and the group streak
--         *immediately*, before the session even reaches `completed`
--         (the break-moment-equivalence claim in the migration header).
--         When GS2 later completes, dave/erin (still ready) still increment
--         individually; frank and the group do not move again.
-- faye  = alice's accepted friend (RLS positive read).
-- iris  = stranger to alice, non-member of G1 (RLS negatives).
-- grace = never a participant of anything (proves incremental recompute —
--         no row is ever created for a bystander).
-- quinn = dedicated idempotency fixture (Q1): completes once, then two
--         different "double-fire" shapes are replayed and must not
--         double-increment.
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('c0000000-0000-0000-0000-0000000000c1', 'sk_alice@t.com'),
  ('c0000000-0000-0000-0000-0000000000c2', 'sk_bob@t.com'),
  ('c0000000-0000-0000-0000-0000000000c3', 'sk_carol@t.com'),
  ('c0000000-0000-0000-0000-0000000000c4', 'sk_dave@t.com'),
  ('c0000000-0000-0000-0000-0000000000c5', 'sk_erin@t.com'),
  ('c0000000-0000-0000-0000-0000000000c6', 'sk_frank@t.com'),
  ('c0000000-0000-0000-0000-0000000000c7', 'sk_faye@t.com'),
  ('c0000000-0000-0000-0000-0000000000c8', 'sk_iris@t.com'),
  ('c0000000-0000-0000-0000-0000000000c9', 'sk_grace@t.com'),
  ('c0000000-0000-0000-0000-0000000000ca', 'sk_quinn@t.com');
INSERT INTO profiles (id, username) VALUES
  ('c0000000-0000-0000-0000-0000000000c1', 'sk_alice'),
  ('c0000000-0000-0000-0000-0000000000c2', 'sk_bob'),
  ('c0000000-0000-0000-0000-0000000000c3', 'sk_carol'),
  ('c0000000-0000-0000-0000-0000000000c4', 'sk_dave'),
  ('c0000000-0000-0000-0000-0000000000c5', 'sk_erin'),
  ('c0000000-0000-0000-0000-0000000000c6', 'sk_frank'),
  ('c0000000-0000-0000-0000-0000000000c7', 'sk_faye'),
  ('c0000000-0000-0000-0000-0000000000c8', 'sk_iris'),
  ('c0000000-0000-0000-0000-0000000000c9', 'sk_grace'),
  ('c0000000-0000-0000-0000-0000000000ca', 'sk_quinn');

-- alice <-> faye: accepted friendship (RLS positive-read fixture).
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-0000000000c7', 'accepted');

-- Group "Streak Crew" (G1): dave (admin), erin, frank. iris is NOT a member.
INSERT INTO groups (id, name, created_by) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'Streak Crew', 'c0000000-0000-0000-0000-0000000000c4');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c4', 'admin'),
  ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c5', 'member'),
  ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c6', 'member');

-- Second group (G2) for the group_streaks INSERT-rejection test — dave is a
-- member but no streak event has ever touched it, so no row exists yet.
INSERT INTO groups (id, name, created_by) VALUES
  ('d0000000-0000-0000-0000-000000000002', 'Empty Crew', 'c0000000-0000-0000-0000-0000000000c4');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-0000000000c4', 'admin');


-- ============================================================
-- Alice: increment (A1) -> ad-hoc neutral (A2) -> increment (A3) ->
--        no_show break (A4), watermark must survive.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c1',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c1',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000001';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000001'::uuid)$$,
  'alice: solo scheduled session completes ready -> streak increments to 1'
);

-- Ad-hoc / unscheduled (scheduled_for NULL) — must not touch the streak at all.
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-0000000000c1',
   'in_progress', NULL, now() - interval '50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-0000000000c1',
   'ready', now() - interval '48 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '10 minutes'
  WHERE id = 'e0000000-0000-0000-0000-000000000002';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000001'::uuid)$$,
  'alice: ad-hoc (scheduled_for NULL) completion is neutral — streak unchanged'
);

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000c1',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000c1',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000003';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  $$VALUES (2, 2, 'e0000000-0000-0000-0000-000000000003'::uuid)$$,
  'alice: second scheduled completion -> streak increments to 2'
);

-- Never checks in; flipped to no_show (mark_no_shows-style direct UPDATE).
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-0000000000c1',
   'in_progress', now() - interval '20 minutes', now() - interval '19 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-0000000000c1',
   'invited', NULL);
UPDATE session_participants SET check_in_state = 'no_show'
  WHERE session_id = 'e0000000-0000-0000-0000-000000000004'
    AND user_id = 'c0000000-0000-0000-0000-0000000000c1';

-- last_streak_session_id is the last *contributing* (incrementing) session
-- per the schema comment ("most recent streak-contributing session") — a
-- break is not a contribution, so it stays pinned at A3; broken_by_session_id
-- (checked separately below) is the column that records the breaking session.
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  $$VALUES (0, 2, 'e0000000-0000-0000-0000-000000000003'::uuid)$$,
  'alice: no_show breaks current_streak to 0, longest_streak watermark (2) survives'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  $$VALUES ('e0000000-0000-0000-0000-000000000004'::uuid)$$,
  'alice: broken_by_session_id records the no_show session (A4)'
);
SELECT results_eq(
  $$SELECT (broken_at IS NOT NULL) FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  ARRAY[true],
  'alice: broken_at is stamped by the no_show break'
);


-- ============================================================
-- Bob: baseline increment (B0), then `abandoned` without ever checking in
-- (B1) -> breaks.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000c2',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000c2',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000005';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c2'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000005'::uuid)$$,
  'bob: baseline scheduled completion -> streak 1'
);

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-0000000000c2',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-0000000000c2',
   'invited', NULL);
UPDATE sessions SET state = 'abandoned', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-000000000006';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c2'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-000000000005'::uuid)$$,
  'bob: session ends abandoned with no check-in at all -> breaks'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c2'$$,
  $$VALUES ('e0000000-0000-0000-0000-000000000006'::uuid)$$,
  'bob: broken_by_session_id records the abandoned session (B1)'
);
SELECT results_eq(
  $$SELECT (broken_at IS NOT NULL) FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c2'$$,
  ARRAY[true],
  'bob: broken_at is stamped by the abandoned-without-checkin break'
);


-- ============================================================
-- Carol: baseline increment (C0), then `abandoned` where she WAS present
-- (check_in_at set, check_in_state='late' — deliberately not 'ready') ->
-- must NOT break. This is the mark_no_shows Finding-1 lesson replayed:
-- absence is check_in_at IS NULL, never a state-label guess.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-0000000000c3',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-0000000000c3',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000007';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c3'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000007'::uuid)$$,
  'carol: baseline scheduled completion -> streak 1'
);

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-0000000000c3',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-0000000000c3',
   'late', now() - interval '2 hours 50 minutes');
UPDATE sessions SET state = 'abandoned', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-000000000008';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c3'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000007'::uuid)$$,
  'carol: abandoned session WITH check-in does not break (she showed up)'
);
SELECT results_eq(
  $$SELECT (broken_at IS NULL) FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c3'$$,
  ARRAY[true],
  'carol: broken_at is never stamped'
);


-- ============================================================
-- Group "Streak Crew" (G1): dave/erin/frank.
-- GS1: everyone ready -> group increments AND each individual increments.
-- GS2: frank is flipped to no_show WHILE the session is still running
-- (session continues without him, Flow 6) -> breaks frank + the group
-- IMMEDIATELY (before completion). GS2 then completes with dave/erin still
-- ready -> their individuals increment again; frank and the group do not
-- move a second time.
-- ============================================================

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-0000000000c4',
   'd0000000-0000-0000-0000-000000000001',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-0000000000c4', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-0000000000c5', 'ready', now() - interval '2 hours 54 minutes'),
  ('e0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-0000000000c6', 'ready', now() - interval '2 hours 53 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000009';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c4'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS1: dave individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c5'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS1: erin individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c6'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS1: frank individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS1: everyone ready -> group streak increments to 1'
);

-- GS2: dave/erin check in; frank never does.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000c4',
   'd0000000-0000-0000-0000-000000000001',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000c4', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000c5', 'ready', now() - interval '2 hours 54 minutes'),
  ('e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000c6', 'invited', NULL);

-- Frank never checked in; the (simulated) mark_no_shows tick flips him
-- WHILE the session is still in_progress — "session continues without her."
UPDATE session_participants SET check_in_state = 'no_show'
  WHERE session_id = 'e0000000-0000-0000-0000-00000000000a'
    AND user_id = 'c0000000-0000-0000-0000-0000000000c6';

-- last_streak_session_id stays pinned at GS1 (last *contributing* session)
-- on both rows — a break is not a contribution; broken_by_session_id
-- (checked separately) is what records GS2 as the breaking session.
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c6'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS2: frank no_show breaks his individual streak IMMEDIATELY (before session completes)'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c6'$$,
  $$VALUES ('e0000000-0000-0000-0000-00000000000a'::uuid)$$,
  'GS2: frank''s broken_by_session_id records GS2'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS2: frank no_show breaks the group streak IMMEDIATELY (break-moment equivalence)'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES ('e0000000-0000-0000-0000-00000000000a'::uuid)$$,
  'GS2: group''s broken_by_session_id records GS2'
);

-- Session continues and completes with dave/erin ready, frank no_show.
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-00000000000a';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c4'$$,
  $$VALUES (2, 2, 'e0000000-0000-0000-0000-00000000000a'::uuid)$$,
  'GS2 completes: dave (still ready) increments again to 2'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c5'$$,
  $$VALUES (2, 2, 'e0000000-0000-0000-0000-00000000000a'::uuid)$$,
  'GS2 completes: erin (still ready) increments again to 2'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c6'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS2 completes: frank (no_show, not ready) is untouched by the completion event'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-000000000009'::uuid)$$,
  'GS2 completes: group streak does NOT increment — not everyone was ready'
);

-- Bystander: grace was never invited to anything, anywhere. Proves
-- incremental (not global) recompute — no row is ever created for her.
SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c9'$$,
  ARRAY[0],
  'grace: never a participant of anything -> no user_streaks row ever created'
);


-- ============================================================
-- Quinn: idempotency. A completed session must not double-increment,
-- whether re-fired via a same-value `state` UPDATE (trigger-level guard)
-- or a direct duplicate call of the underlying bump primitive
-- (last_streak_session_id guard inside streak_bump_user itself).
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-0000000000ca',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-0000000000ca',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-00000000000b';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000ca'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-00000000000b'::uuid)$$,
  'quinn: baseline completion -> streak 1'
);

-- Refire shape 1: an UPDATE that explicitly re-assigns state='completed'
-- (same value) — the trigger fires (state is in the SET list) but its own
-- OLD/NEW state-diff guard must no-op it.
UPDATE sessions SET state = 'completed', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-00000000000b';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000ca'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-00000000000b'::uuid)$$,
  'quinn: re-asserting state=completed (same value) does not double-increment'
);

-- Refire shape 2: a direct duplicate call of the bump primitive itself for
-- the SAME session (simulates a hypothetical duplicate trigger invocation
-- bypassing the state-diff guard entirely) — the last_streak_session_id
-- guard inside streak_bump_user must still catch it.
SELECT public.streak_bump_user(
  'c0000000-0000-0000-0000-0000000000ca', 'e0000000-0000-0000-0000-00000000000b');

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000ca'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-00000000000b'::uuid)$$,
  'quinn: direct duplicate streak_bump_user call for the same session is a no-op'
);


-- ============================================================
-- RLS: user_streaks — owner + accepted friends read; stranger cannot;
-- no client writes at all (no INSERT/UPDATE policy exists on either table).
-- ============================================================

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c1';  -- alice
SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  ARRAY[1], 'alice can read her own user_streaks row'
);

SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c7';  -- faye (accepted friend)
SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  ARRAY[1], 'accepted friend can read alice''s user_streaks row'
);

SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c8';  -- iris (stranger)
SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'$$,
  ARRAY[0], 'stranger (not a friend) cannot read alice''s user_streaks row'
);

-- Insert rejection: iris has no user_streaks row yet — isolates the RLS
-- failure from any PK-conflict noise.
SELECT throws_ok(
  $$INSERT INTO user_streaks (user_id) VALUES ('c0000000-0000-0000-0000-0000000000c8')$$,
  '42501', NULL,
  'client cannot INSERT into user_streaks (no INSERT policy exists)'
);

-- Update rejection: alice, on her OWN row, still gets 0 rows affected (no
-- UPDATE policy at all — not even the owner can write directly).
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c1';  -- alice
SELECT results_eq(
  $$WITH upd AS (
      UPDATE user_streaks SET current_streak = 999
      WHERE user_id = 'c0000000-0000-0000-0000-0000000000c1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'client (even the owner) cannot UPDATE user_streaks directly'
);


-- ============================================================
-- RLS: group_streaks — members read; non-members cannot; no client writes.
-- ============================================================

SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c4';  -- dave (member of G1)
SELECT results_eq(
  $$SELECT count(*)::int FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'group member (dave) can read group_streaks'
);

SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c8';  -- iris (non-member)
SELECT results_eq(
  $$SELECT count(*)::int FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'non-member (iris) cannot read group_streaks'
);

-- Insert rejection: G2 has no group_streaks row yet, dave IS a legitimate
-- member of G2 — isolates the RLS failure from FK/PK-conflict noise.
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000c4';  -- dave
SELECT throws_ok(
  $$INSERT INTO group_streaks (group_id) VALUES ('d0000000-0000-0000-0000-000000000002')$$,
  '42501', NULL,
  'client cannot INSERT into group_streaks (no INSERT policy exists)'
);

-- Update rejection: dave, a real member of G1, still gets 0 rows affected.
SELECT results_eq(
  $$WITH upd AS (
      UPDATE group_streaks SET current_streak = 999
      WHERE group_id = 'd0000000-0000-0000-0000-000000000001'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'client (even a member) cannot UPDATE group_streaks directly'
);

SET LOCAL role postgres;

SELECT * FROM finish();
ROLLBACK;
