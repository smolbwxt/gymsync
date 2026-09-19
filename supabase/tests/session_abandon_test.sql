BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

-- ============================================================
-- The abandon transition fires nothing — Phase C2 D1
-- (docs/superpowers/plans/2026-09-19-group-session-phase-c2-plan.md,
-- decision 1 and task D1). Pins the premise the whole of decision 1 rests
-- on: a client UPDATE of sessions.state to 'abandoned' (shaped exactly like
-- complete()) is legal under the shipped policy, and every trigger on that
-- transition either no-ops or behaves exactly like the 6-hour reaper
-- (20260716000004_reminder_window_fix.sql:107-122) already does live.
-- Fixture block: 19xx UUIDs (constraint 17; 01xx-13xx/15xx-18xx taken).
--
-- ── Fixtures ──────────────────────────────────────────────────────────────
-- chk   = ...1900 throwaway organizer, used only for the cheap CHECK
--         regression (assertion 1) — kept separate from dana's narrative so
--         that INSERT never touches dana's streak bookkeeping.
-- dana  = ...1901 the lifter. Organizes every other session below.
-- S0    = ...1931 scheduled + completed FIRST, to give dana a real
--         user_streaks row (1, 1, S0, NULL, NULL) — the "before" value
--         assertion 4 proves is byte-identical "after."
-- AH1   = ...1932 ad-hoc solo (scheduled_for/group_id/room_code all NULL),
--         in_progress -> abandoned. THE write under test (assertion 2):
--         organizer or participant can update session
--         (20260726000001_is_session_participant_dual_schema.sql:172-178).
-- AH2   = ...1933 a second ad-hoc solo, SAME shape as AH1, in_progress ->
--         completed with one non-penalty set_logs row. The CONTRAST case
--         (assertion 5): proves the suite tells 'abandoned' apart from
--         'completed' rather than merely observing an absence.
-- group "Abandon Crew" (...1910) / GS1 = ...1934 a session WITH a group,
--         in_progress -> abandoned by its organizer. The second CONTRAST
--         case (assertion 6): proves assertion 3's chat_messages no-op is
--         announce_session_lifecycle's `group_id IS NULL` branch
--         (20260713000002_series_announcements.sql:8-10), not a broken
--         trigger.
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000001900', 'abandon-chk@test.local'),
  ('00000000-0000-4000-e000-000000001901', 'abandon-dana@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000001900', 'abandon_chk'),
  ('00000000-0000-4000-e000-000000001901', 'abandon_dana');

INSERT INTO exercises (id, name, slug, category, primary_muscle, equipment) VALUES
  ('00000000-0000-4000-e000-000000001920', 'Abandon Test Row', 'abandon-test-row', 'compound', 'back', 'barbell');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-4000-e000-000000001910', 'Abandon Crew', '00000000-0000-4000-e000-000000001901');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-e000-000000001910', '00000000-0000-4000-e000-000000001901', 'admin');


-- ============================================================
-- 1. Cheap regression: 'abandoned' is in the sessions.state CHECK
-- (20260913000103_session_states_narrow.sql:57-59). Run before any role
-- switch, exactly like session_states_narrow_test.sql's own fixture rows —
-- no RLS is under test here, only the CHECK.
-- ============================================================
SELECT lives_ok(
  $$INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
    ('00000000-0000-4000-e000-000000001930',
     '00000000-0000-4000-e000-000000001900', 'abandoned', NULL)$$,
  'abandoned is accepted by the narrowed sessions.state CHECK');


-- ============================================================
-- S0: dana's baseline scheduled + completed session, establishing a real
-- user_streaks row BEFORE the abandon write under test.
-- ============================================================
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('00000000-0000-4000-e000-000000001931', '00000000-0000-4000-e000-000000001901',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001931', '00000000-0000-4000-e000-000000001901',
   'ready', now() - interval '2 hours 55 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 hours'
  WHERE id = '00000000-0000-4000-e000-000000001931';

SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id,
           broken_by_session_id, broken_at::text
      FROM user_streaks WHERE user_id = '00000000-0000-4000-e000-000000001901'$$,
  $$VALUES (1, 1, '00000000-0000-4000-e000-000000001931'::uuid, NULL::uuid, NULL::text)$$,
  'dana: S0 baseline completion establishes streak 1 (the "before" value)');


-- ============================================================
-- AH1: dana's ad-hoc solo session (scheduled_for/group_id/room_code all
-- NULL) — THE write S2 makes, no engine GUC, no RPC. Actor is dana,
-- authenticated, exactly as decision 1(a) specifies.
-- ============================================================
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('00000000-0000-4000-e000-000000001932', '00000000-0000-4000-e000-000000001901',
   'in_progress', NULL, now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001932', '00000000-0000-4000-e000-000000001901',
   'ready', now() - interval '19 minutes');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001901';  -- dana

-- 2. An authenticated organizer of an ad-hoc session CAN update state to
-- 'abandoned' under "organizer or participant can update session"
-- (20260726000001_is_session_participant_dual_schema.sql:172-178) — the
-- write itself, then its effect read back in a SECOND statement.
SELECT lives_ok(
  $$UPDATE sessions SET state = 'abandoned', completed_at = now()
     WHERE id = '00000000-0000-4000-e000-000000001932'$$,
  'dana (organizer) can UPDATE her ad-hoc session state to abandoned');

SELECT results_eq(
  $$SELECT state FROM sessions WHERE id = '00000000-0000-4000-e000-000000001932'$$,
  $$VALUES ('abandoned'::text)$$,
  'AH1 reads back as abandoned');

-- 3. What the transition must NOT fire, all scoped to AH1 / dana so a
-- fixture built later in this file (GS1, assertion 6) can never mask a
-- true positive here.
SELECT results_eq(
  $$SELECT count(*)::int FROM leaderboard_entries le
      JOIN workout_attempts wa ON wa.id = le.attempt_id
     WHERE wa.session_id = '00000000-0000-4000-e000-000000001932'$$,
  ARRAY[0],
  'no leaderboard_entries row exists for AH1 — leaderboard_recompute_on_session_completion guards on NEW.state <> ''completed'' (20260723000001_public_workout_repository.sql:256-258)');

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
     WHERE user_id = '00000000-0000-4000-e000-000000001901'
       AND event = 'leaderboard_passed'$$,
  ARRAY[0],
  'no leaderboard_passed push exists for dana — leaderboard_social_effects_on_completion guards the same way (20260723000003_attempt_plumbing_fixes.sql:207-220)');

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
     WHERE (payload->>'session_id')::uuid = '00000000-0000-4000-e000-000000001932'$$,
  ARRAY[0],
  'no chat_messages row exists for AH1 — announce_session_lifecycle returns early on NEW.group_id IS NULL (20260713000002_series_announcements.sql:8-10)');

SELECT results_eq(
  $$SELECT count(*)::int FROM workout_attempts
     WHERE session_id = '00000000-0000-4000-e000-000000001932'$$,
  ARRAY[0],
  'workout_attempts for AH1 is unchanged (stays at zero — no attempt row was ever created)');

-- 4. The streak is untouched: dana's user_streaks row is byte-identical to
-- the S0 "before" snapshot above. streak_on_session_state_change's own
-- v_unscheduled AND NEW.state <> 'completed' early return
-- (20260803000005_solo_workouts_count_toward_streak.sql:49-51) fires before
-- the 'abandoned' branch (:101-121) is ever reached, because AH1's
-- scheduled_for is NULL.
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id,
           broken_by_session_id, broken_at::text
      FROM user_streaks WHERE user_id = '00000000-0000-4000-e000-000000001901'$$,
  $$VALUES (1, 1, '00000000-0000-4000-e000-000000001931'::uuid, NULL::uuid, NULL::text)$$,
  'dana: streak row after AH1 abandons is byte-identical to the "before" value — no bump, no break');

SET LOCAL role postgres;


-- ============================================================
-- AH2: the CONTRAST case (assertion 5). SAME ad-hoc shape as AH1
-- (scheduled_for NULL), but this one reaches 'completed' with one
-- non-penalty set_logs row for dana. Proves the suite tells 'abandoned'
-- apart from 'completed' rather than merely observing an absence.
-- ============================================================
INSERT INTO sessions (id, organizer_id, state, scheduled_for, started_at) VALUES
  ('00000000-0000-4000-e000-000000001933', '00000000-0000-4000-e000-000000001901',
   'in_progress', NULL, now() - interval '15 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001933', '00000000-0000-4000-e000-000000001901',
   'ready', now() - interval '14 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight) VALUES
  ('00000000-0000-4000-e000-000000001940', '00000000-0000-4000-e000-000000001901',
   '00000000-0000-4000-e000-000000001933', '00000000-0000-4000-e000-000000001920',
   1, 8, 135);
-- is_penalty omitted -- NOT NULL DEFAULT false, exactly the "did the work"
-- predicate streak_on_session_state_change's EXISTS clause tests for.

UPDATE sessions SET state = 'completed', completed_at = now()
  WHERE id = '00000000-0000-4000-e000-000000001933';

-- 5. CONTRAST: the same unscheduled shape, but completed with one
-- non-penalty set logged, DOES bump the individual streak
-- (:69-84 — the EXISTS clause over set_logs, gated on NOT v_unscheduled OR
-- that EXISTS).
SELECT results_eq(
  $$SELECT current_streak, longest_streak, last_streak_session_id
      FROM user_streaks WHERE user_id = '00000000-0000-4000-e000-000000001901'$$,
  $$VALUES (2, 2, '00000000-0000-4000-e000-000000001933'::uuid)$$,
  'dana: AH2 completes with one non-penalty set logged -- individual streak bumps to 2 (unlike AH1''s abandon, which left it at 1)');


-- ============================================================
-- GS1: the second CONTRAST case (assertion 6). A session WITH a group_id,
-- abandoned by its organizer, DOES get the chat row -- proving assertion
-- 3's no-op above is the group_id IS NULL branch, not a broken trigger.
-- ============================================================
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for, started_at) VALUES
  ('00000000-0000-4000-e000-000000001934', '00000000-0000-4000-e000-000000001901',
   '00000000-0000-4000-e000-000000001910',
   'in_progress', now() - interval '3 hours', now() - interval '2 hours 50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000001934', '00000000-0000-4000-e000-000000001901',
   'ready', now() - interval '2 hours 55 minutes');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001901';  -- dana

SELECT lives_ok(
  $$UPDATE sessions SET state = 'abandoned', completed_at = now()
     WHERE id = '00000000-0000-4000-e000-000000001934'$$,
  'dana (organizer) can UPDATE her group session state to abandoned');

-- 6. announce_session_lifecycle DOES post the group-null-check no-op
-- happens to skip: a 🌫️ system_session row with this session's id and
-- 'abandoned' state in its payload (:26-40).
SELECT ok(
  (SELECT kind = 'system_session'
          AND body LIKE '%abandoned%'
          AND (payload->>'session_id')::uuid = '00000000-0000-4000-e000-000000001934'
          AND payload->>'state' = 'abandoned'
     FROM chat_messages
    WHERE group_id = '00000000-0000-4000-e000-000000001910'
      AND (payload->>'session_id')::uuid = '00000000-0000-4000-e000-000000001934'),
  'GS1 (has a group) abandoning DOES post the system_session chat row -- the AH1 no-op above was the group_id IS NULL branch, not a broken trigger');

SET LOCAL role postgres;

SELECT * FROM finish();
ROLLBACK;
