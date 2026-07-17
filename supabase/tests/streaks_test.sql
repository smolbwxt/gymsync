BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(57);

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
--
-- ── Fix-forward fixtures (20260719000007) ───────────────────────────────────
-- gus/holly = "Gap Crew" (G3): baseline all-ready completion, then a bare
--         `abandoned` transition (holly never checks in, NO no_show flip
--         ever fires) — proves Finding 2's defensive streak_break_group
--         call closes the gap on its own.
-- ivy/jill  = "Gap Crew 2" (G4): baseline all-ready completion, then jill is
--         flipped to no_show (existing mechanism breaks the group first),
--         and THEN the same session reaches `abandoned` (Finding 2's new
--         call fires again, redundantly) — proves the double-break is a
--         harmless no-op, not a double-decrement.
-- sam       = Finding 1(b) structural guard fixture. Broken by a session's
--         no_show flip, then legitimately rejoins ('ready', per Flow 6's
--         no_show -> ready path) and that SAME session reaches `completed`.
--         This replays the race's commit order directly (break commits,
--         THEN the completion path evaluates readiness) without needing two
--         concurrent transactions — asserts current_streak stays 0 and
--         last_streak_session_id is never set to the breaking session.
--
-- ── Late-counts fixtures (20260719000009, the 2026-07-16 user decision) ─────
-- leo   = solo scheduled session completed with check_in_state='late'
--         (check_in_at SET — production-real: a late row is present, just
--         tardy) -> streak increments, proving the individual predicate now
--         accepts 'late' as well as 'ready'.
-- mia/nora/oren = "Late Crew" (G5): mia is 'late' (check_in_at set), nora
--         and oren are 'ready'. Proves the group all-ready predicate was
--         widened consistently with the individual one — mia's lateness no
--         longer blocks the group's increment, AND mia's own individual
--         streak increments too.
-- pete  = solo scheduled session that reaches `completed` while pete's row
--         is still 'invited' (check_in_at NULL, never checked in at all —
--         not no_show, not abandoned, just still-invited at completion).
--         Proves 'invited' stays excluded under the widened predicate: no
--         user_streaks row is ever created for him, same as bystander grace.
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
  ('c0000000-0000-0000-0000-0000000000ca', 'sk_quinn@t.com'),
  ('c0000000-0000-0000-0000-0000000000cb', 'sk_gus@t.com'),
  ('c0000000-0000-0000-0000-0000000000cc', 'sk_holly@t.com'),
  ('c0000000-0000-0000-0000-0000000000cd', 'sk_ivy@t.com'),
  ('c0000000-0000-0000-0000-0000000000ce', 'sk_jill@t.com'),
  ('c0000000-0000-0000-0000-0000000000cf', 'sk_sam@t.com'),
  ('c0000000-0000-0000-0000-0000000000d0', 'sk_leo@t.com'),
  ('c0000000-0000-0000-0000-0000000000d1', 'sk_mia@t.com'),
  ('c0000000-0000-0000-0000-0000000000d2', 'sk_nora@t.com'),
  ('c0000000-0000-0000-0000-0000000000d3', 'sk_oren@t.com'),
  ('c0000000-0000-0000-0000-0000000000d4', 'sk_pete@t.com');
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
  ('c0000000-0000-0000-0000-0000000000ca', 'sk_quinn'),
  ('c0000000-0000-0000-0000-0000000000cb', 'sk_gus'),
  ('c0000000-0000-0000-0000-0000000000cc', 'sk_holly'),
  ('c0000000-0000-0000-0000-0000000000cd', 'sk_ivy'),
  ('c0000000-0000-0000-0000-0000000000ce', 'sk_jill'),
  ('c0000000-0000-0000-0000-0000000000cf', 'sk_sam'),
  ('c0000000-0000-0000-0000-0000000000d0', 'sk_leo'),
  ('c0000000-0000-0000-0000-0000000000d1', 'sk_mia'),
  ('c0000000-0000-0000-0000-0000000000d2', 'sk_nora'),
  ('c0000000-0000-0000-0000-0000000000d3', 'sk_oren'),
  ('c0000000-0000-0000-0000-0000000000d4', 'sk_pete');

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

-- Group "Gap Crew" (G3): gus (admin), holly. Finding 2 — bare abandoned gap.
INSERT INTO groups (id, name, created_by) VALUES
  ('d0000000-0000-0000-0000-000000000003', 'Gap Crew', 'c0000000-0000-0000-0000-0000000000cb');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('d0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000cb', 'admin'),
  ('d0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000cc', 'member');

-- Group "Gap Crew 2" (G4): ivy (admin), jill. Finding 2 — no_show-then-
-- abandoned double-break idempotency.
INSERT INTO groups (id, name, created_by) VALUES
  ('d0000000-0000-0000-0000-000000000004', 'Gap Crew 2', 'c0000000-0000-0000-0000-0000000000cd');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-0000000000cd', 'admin'),
  ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-0000000000ce', 'member');

-- Group "Late Crew" (G5): mia (admin), nora, oren. 20260719000009 —
-- late-counts group fixture.
INSERT INTO groups (id, name, created_by) VALUES
  ('d0000000-0000-0000-0000-000000000005', 'Late Crew', 'c0000000-0000-0000-0000-0000000000d1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000d1', 'admin'),
  ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000d2', 'member'),
  ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000d3', 'member');


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
-- Fix-forward (20260719000007) — Finding 2: Gap Crew (G3).
-- Baseline all-ready completion, then a bare `abandoned` transition where
-- holly never checks in and NO no_show flip ever fires (unlike GS2 above,
-- where frank was explicitly flipped to no_show mid-session). Before
-- 20260719000007 the abandoned branch never called streak_break_group, so
-- this session reaching 'abandoned' would have left the group streak
-- standing at 1 forever. Proves the defensive call closes that gap on its
-- own, without relying on a prior no_show.
-- ============================================================

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-0000000000cb',
   'd0000000-0000-0000-0000-000000000003',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-0000000000cb', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-0000000000cc', 'ready', now() - interval '2 hours 54 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-00000000000c';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000003'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-00000000000c'::uuid)$$,
  'Gap Crew: baseline all-ready completion -> group streak increments to 1'
);

-- Holly never checks in (check_in_at stays NULL); the session goes straight
-- to 'abandoned' with NO no_show flip ever applied to her row.
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000d', 'c0000000-0000-0000-0000-0000000000cb',
   'd0000000-0000-0000-0000-000000000003',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000d', 'c0000000-0000-0000-0000-0000000000cb', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-00000000000d', 'c0000000-0000-0000-0000-0000000000cc', 'invited', NULL);
UPDATE sessions SET state = 'abandoned', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-00000000000d';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000003'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-00000000000c'::uuid)$$,
  'Gap Crew: bare abandoned transition (holly never checked in, no no_show ever fired) breaks the group streak'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000003'$$,
  $$VALUES ('e0000000-0000-0000-0000-00000000000d'::uuid)$$,
  'Gap Crew: broken_by_session_id records the bare-abandoned session'
);
SELECT results_eq(
  $$SELECT (broken_at IS NOT NULL) FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000003'$$,
  ARRAY[true],
  'Gap Crew: broken_at is stamped by the defensive abandoned-branch group break'
);


-- ============================================================
-- Fix-forward (20260719000007) — Finding 2 idempotency: Gap Crew 2 (G4).
-- Baseline all-ready completion, then jill is flipped to no_show (existing
-- mechanism breaks the group first, exactly like GS2's frank above), and
-- THEN the SAME session transitions to 'abandoned' (the new defensive call
-- fires again, redundantly, for a session that already broke this group).
-- Must land in the identical broken state either write alone would produce
-- — no double-decrement, no corruption of the longest_streak watermark.
-- ============================================================

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000e', 'c0000000-0000-0000-0000-0000000000cd',
   'd0000000-0000-0000-0000-000000000004',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000e', 'c0000000-0000-0000-0000-0000000000cd', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-00000000000e', 'c0000000-0000-0000-0000-0000000000ce', 'ready', now() - interval '2 hours 54 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-00000000000e';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000004'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-00000000000e'::uuid)$$,
  'Gap Crew 2: baseline all-ready completion -> group streak increments to 1'
);

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-00000000000f', 'c0000000-0000-0000-0000-0000000000cd',
   'd0000000-0000-0000-0000-000000000004',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-00000000000f', 'c0000000-0000-0000-0000-0000000000cd', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-00000000000f', 'c0000000-0000-0000-0000-0000000000ce', 'invited', NULL);

-- Jill never checked in; flipped to no_show first (mark_no_shows-style
-- direct UPDATE) — this independently breaks the group via the EXISTING
-- streak_on_no_show trigger, same as frank in GS2.
UPDATE session_participants SET check_in_state = 'no_show'
  WHERE session_id = 'e0000000-0000-0000-0000-00000000000f'
    AND user_id = 'c0000000-0000-0000-0000-0000000000ce';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000004'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-00000000000e'::uuid)$$,
  'Gap Crew 2: jill''s no_show breaks the group streak (existing mechanism, pre-abandon)'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000004'$$,
  $$VALUES ('e0000000-0000-0000-0000-00000000000f'::uuid)$$,
  'Gap Crew 2: broken_by_session_id records the no_show session before abandon'
);

-- The SAME session now reaches 'abandoned' — the new defensive
-- streak_break_group call fires again for a group already broken by this
-- exact session.
UPDATE sessions SET state = 'abandoned', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-00000000000f';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000004'$$,
  $$VALUES (0, 1, 'e0000000-0000-0000-0000-00000000000e'::uuid)$$,
  'Gap Crew 2: redundant abandoned-branch break is a no-op — current/longest/last unchanged'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000004'$$,
  $$VALUES ('e0000000-0000-0000-0000-00000000000f'::uuid)$$,
  'Gap Crew 2: broken_by_session_id still names the same session — no double-break corruption'
);


-- ============================================================
-- Fix-forward (20260719000007) — Finding 1(b) structural guard: sam.
-- Replays the race's commit order directly (can't exercise the true
-- concurrent race in single-transaction pgTAP): sam's streak is broken by a
-- no_show for session X, then she legitimately rejoins ('ready' — Flow 6's
-- own no_show -> ready path, established in 20260719000003's header) and
-- that SAME session X reaches 'completed'. Without the broken_by_session_id
-- guard added to streak_bump_user in this migration, the completion
-- trigger's readiness loop would find her genuinely 'ready' (not a stale
-- read — the FOR UPDATE fix alone cannot prevent this, since nothing is
-- concurrent at this point) and streak_bump_user's last_streak_session_id
-- guard would not block it (breaks never touch that column), silently
-- re-crediting current_streak using session X.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000010', 'c0000000-0000-0000-0000-0000000000cf',
   'in_progress', now() - interval '20 minutes', now() - interval '19 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000010', 'c0000000-0000-0000-0000-0000000000cf',
   'invited', NULL);

-- Break lands first (simulates mark_no_shows()'s commit winning the race).
UPDATE session_participants SET check_in_state = 'no_show'
  WHERE session_id = 'e0000000-0000-0000-0000-000000000010'
    AND user_id = 'c0000000-0000-0000-0000-0000000000cf';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000cf'$$,
  $$VALUES (0, 0, NULL::uuid)$$,
  'sam: no_show breaks (never had a prior streak) -> current/longest/last all zero/null'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000cf'$$,
  $$VALUES ('e0000000-0000-0000-0000-000000000010'::uuid)$$,
  'sam: broken_by_session_id records the no_show session'
);

-- Sam legitimately rejoins (Flow 6: "she can still join late") for the
-- SAME session, then it completes with her 'ready'.
UPDATE session_participants SET check_in_state = 'ready', check_in_at = now()
  WHERE session_id = 'e0000000-0000-0000-0000-000000000010'
    AND user_id = 'c0000000-0000-0000-0000-0000000000cf';
UPDATE sessions SET state = 'completed', completed_at = now()
  WHERE id = 'e0000000-0000-0000-0000-000000000010';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000cf'$$,
  $$VALUES (0, 0, NULL::uuid)$$,
  'sam: completing the SAME session she was no_show-broken by does NOT re-credit — current stays 0, last_streak_session_id stays NULL'
);
SELECT results_eq(
  $$SELECT broken_by_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000cf'$$,
  $$VALUES ('e0000000-0000-0000-0000-000000000010'::uuid)$$,
  'sam: broken_by_session_id is unchanged after the guarded completion'
);


-- ============================================================
-- Late-counts (20260719000009) — the 2026-07-16 user decision: late-but-
-- completed KEEPS the streak. leo: solo scheduled session completed with
-- check_in_state='late' (check_in_at SET, production-real) -> increments,
-- same as a 'ready' completion would.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000011', 'c0000000-0000-0000-0000-0000000000d0',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000011', 'c0000000-0000-0000-0000-0000000000d0',
   'late', now() - interval '2 hours 40 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000011';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000d0'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000011'::uuid)$$,
  'leo: solo scheduled session completed while late (check_in_at set) -> streak increments to 1'
);


-- ============================================================
-- Late-counts (20260719000009) — "Late Crew" (G5): mia is late-but-present
-- (check_in_at set), nora and oren are ready. Proves the group all-ready
-- predicate was widened consistently with the individual one: mia's
-- lateness no longer blocks the group's increment, AND mia's own
-- individual streak increments same as nora/oren's.
-- ============================================================

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000012', 'c0000000-0000-0000-0000-0000000000d1',
   'd0000000-0000-0000-0000-000000000005',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000012', 'c0000000-0000-0000-0000-0000000000d1', 'late', now() - interval '2 hours 40 minutes'),
  ('e0000000-0000-0000-0000-000000000012', 'c0000000-0000-0000-0000-0000000000d2', 'ready', now() - interval '2 hours 55 minutes'),
  ('e0000000-0000-0000-0000-000000000012', 'c0000000-0000-0000-0000-0000000000d3', 'ready', now() - interval '2 hours 54 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000012';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000d1'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000012'::uuid)$$,
  'Late Crew: mia (late, present) individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000d2'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000012'::uuid)$$,
  'Late Crew: nora (ready) individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000d3'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000012'::uuid)$$,
  'Late Crew: oren (ready) individual streak increments to 1'
);
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id FROM group_streaks
    WHERE group_id = 'd0000000-0000-0000-0000-000000000005'$$,
  $$VALUES (1, 1, 'e0000000-0000-0000-0000-000000000012'::uuid)$$,
  'Late Crew: one late-but-present member no longer blocks the group -> group streak increments to 1'
);


-- ============================================================
-- Late-counts (20260719000009) — pete: session reaches `completed` while
-- pete's row is still 'invited' (check_in_at NULL, never checked in at
-- all — not no_show, not abandoned). Proves 'invited' stays excluded under
-- the widened predicate: no credit, no user_streaks row ever created for
-- him, same as bystander grace above.
-- ============================================================

INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('e0000000-0000-0000-0000-000000000013', 'c0000000-0000-0000-0000-0000000000d4',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('e0000000-0000-0000-0000-000000000013', 'c0000000-0000-0000-0000-0000000000d4',
   'invited', NULL);
UPDATE sessions SET state = 'completed', completed_at = now() - interval '1 hour'
  WHERE id = 'e0000000-0000-0000-0000-000000000013';

SELECT results_eq(
  $$SELECT count(*)::int FROM user_streaks
    WHERE user_id = 'c0000000-0000-0000-0000-0000000000d4'$$,
  ARRAY[0],
  'pete: still-invited (never checked in) at completion -> no credit, no user_streaks row created'
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
