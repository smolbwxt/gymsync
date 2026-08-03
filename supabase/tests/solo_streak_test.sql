BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Solo workouts count toward your streak (20260803000005).
--
-- The rule under test: an UNSCHEDULED session bumps a lifter's individual
-- streak only when they logged real (non-penalty) work in it, while every
-- SCHEDULED path keeps its prior behavior exactly. Fixture block: 0cxx.
--
--   c10  unscheduled, solo, A ready, one real set        -> A bumps
--   c11  unscheduled, solo, B ready, NO sets             -> B does not bump
--   c12  unscheduled, solo, C ready, one PENALTY set     -> C does not bump
--   c13  scheduled,   solo, D ready, no sets             -> D bumps (unchanged)
--   c14  unscheduled, group, E+F ready, both logged      -> individuals bump,
--                                                           group does NOT

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000000c01', 'solo-a@test.local'),
  ('00000000-0000-4000-e000-000000000c02', 'solo-b@test.local'),
  ('00000000-0000-4000-e000-000000000c03', 'solo-c@test.local'),
  ('00000000-0000-4000-e000-000000000c04', 'solo-d@test.local'),
  ('00000000-0000-4000-e000-000000000c05', 'solo-e@test.local'),
  ('00000000-0000-4000-e000-000000000c06', 'solo-f@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000000c01', 'solo_a'),
  ('00000000-0000-4000-e000-000000000c02', 'solo_b'),
  ('00000000-0000-4000-e000-000000000c03', 'solo_c'),
  ('00000000-0000-4000-e000-000000000c04', 'solo_d'),
  ('00000000-0000-4000-e000-000000000c05', 'solo_e'),
  ('00000000-0000-4000-e000-000000000c06', 'solo_f');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-4000-e000-000000000c20', 'Solo Streak Crew',
   '00000000-0000-4000-e000-000000000c05');

INSERT INTO sessions (id, organizer_id, state, started_at, scheduled_for, group_id) VALUES
  ('00000000-0000-4000-e000-000000000c10', '00000000-0000-4000-e000-000000000c01',
   'in_progress', now(), NULL, NULL),
  ('00000000-0000-4000-e000-000000000c11', '00000000-0000-4000-e000-000000000c02',
   'in_progress', now(), NULL, NULL),
  ('00000000-0000-4000-e000-000000000c12', '00000000-0000-4000-e000-000000000c03',
   'in_progress', now(), NULL, NULL),
  ('00000000-0000-4000-e000-000000000c13', '00000000-0000-4000-e000-000000000c04',
   'in_progress', now(), now() - interval '1 hour', NULL),
  ('00000000-0000-4000-e000-000000000c14', '00000000-0000-4000-e000-000000000c05',
   'in_progress', now(), NULL, '00000000-0000-4000-e000-000000000c20');

INSERT INTO session_participants (session_id, user_id, turn_order, check_in_state, check_in_at) VALUES
  ('00000000-0000-4000-e000-000000000c10', '00000000-0000-4000-e000-000000000c01', 1, 'ready', now()),
  ('00000000-0000-4000-e000-000000000c11', '00000000-0000-4000-e000-000000000c02', 1, 'ready', now()),
  ('00000000-0000-4000-e000-000000000c12', '00000000-0000-4000-e000-000000000c03', 1, 'ready', now()),
  ('00000000-0000-4000-e000-000000000c13', '00000000-0000-4000-e000-000000000c04', 1, 'ready', now()),
  ('00000000-0000-4000-e000-000000000c14', '00000000-0000-4000-e000-000000000c05', 1, 'ready', now()),
  ('00000000-0000-4000-e000-000000000c14', '00000000-0000-4000-e000-000000000c06', 2, 'ready', now());

-- Real work for A, penalty-only for C, real work for both group members.
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_failed, is_penalty)
SELECT '00000000-0000-4000-e000-000000000c30', '00000000-0000-4000-e000-000000000c01',
       '00000000-0000-4000-e000-000000000c10', e.id, 1, 8, 135, false, false
FROM exercises e LIMIT 1;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_failed, is_penalty)
SELECT '00000000-0000-4000-e000-000000000c31', '00000000-0000-4000-e000-000000000c03',
       '00000000-0000-4000-e000-000000000c12', e.id, 1, 20, NULL, false, true
FROM exercises e LIMIT 1;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_failed, is_penalty)
SELECT '00000000-0000-4000-e000-000000000c32', '00000000-0000-4000-e000-000000000c05',
       '00000000-0000-4000-e000-000000000c14', e.id, 1, 5, 225, false, false
FROM exercises e LIMIT 1;
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_failed, is_penalty)
SELECT '00000000-0000-4000-e000-000000000c33', '00000000-0000-4000-e000-000000000c06',
       '00000000-0000-4000-e000-000000000c14', e.id, 1, 5, 185, false, false
FROM exercises e LIMIT 1;

-- Fire the trigger on every fixture session.
UPDATE sessions SET state = 'completed', completed_at = now()
WHERE id IN ('00000000-0000-4000-e000-000000000c10',
             '00000000-0000-4000-e000-000000000c11',
             '00000000-0000-4000-e000-000000000c12',
             '00000000-0000-4000-e000-000000000c13',
             '00000000-0000-4000-e000-000000000c14');

-- 1: the headline — a solo workout with real sets earns the day.
SELECT is(
  (SELECT current_streak FROM user_streaks
   WHERE user_id = '00000000-0000-4000-e000-000000000c01'),
  1,
  'completed unscheduled solo session WITH logged work bumps the individual streak'
);

-- 2: and it is attributed to that session.
SELECT is(
  (SELECT last_streak_session_id FROM user_streaks
   WHERE user_id = '00000000-0000-4000-e000-000000000c01'),
  '00000000-0000-4000-e000-000000000c10'::uuid,
  'the bump is attributed to the solo session that earned it'
);

-- 3: opening and closing a session earns nothing.
SELECT ok(
  NOT EXISTS (SELECT 1 FROM user_streaks
              WHERE user_id = '00000000-0000-4000-e000-000000000c02'
                AND current_streak > 0),
  'unscheduled session with NO logged sets does not bump'
);

-- 4: paying burpee debt is not a workout.
SELECT ok(
  NOT EXISTS (SELECT 1 FROM user_streaks
              WHERE user_id = '00000000-0000-4000-e000-000000000c03'
                AND current_streak > 0),
  'unscheduled session whose only sets are penalties does not bump'
);

-- 5: regression — scheduled sessions keep bumping with no set requirement.
SELECT is(
  (SELECT current_streak FROM user_streaks
   WHERE user_id = '00000000-0000-4000-e000-000000000c04'),
  1,
  'scheduled session still bumps without logged sets (behavior unchanged)'
);

-- 6 & 7: an unscheduled GROUP session credits the individuals who worked…
SELECT is(
  (SELECT current_streak FROM user_streaks
   WHERE user_id = '00000000-0000-4000-e000-000000000c05'),
  1,
  'unscheduled group session bumps an individual who logged work'
);
SELECT is(
  (SELECT current_streak FROM user_streaks
   WHERE user_id = '00000000-0000-4000-e000-000000000c06'),
  1,
  'unscheduled group session bumps the other individual who logged work'
);

-- 8: …but a crew streak still requires a session they planned together.
SELECT ok(
  NOT EXISTS (SELECT 1 FROM group_streaks
              WHERE group_id = '00000000-0000-4000-e000-000000000c20'
                AND current_streak > 0),
  'group streak stays scheduled-only — an ad-hoc session does not bump the crew'
);

SELECT * FROM finish();
ROLLBACK;
