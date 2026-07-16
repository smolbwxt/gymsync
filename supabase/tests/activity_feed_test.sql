BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- U (caller), T (teammate, owns a private routine used in a non-group session
-- U merely participates in — the RLS-drift edge case activity_feed's
-- SECURITY DEFINER exists for), O (outsider, unrelated solo session).

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000af101', 'af-u@t.com'),
  ('00000000-0000-0000-0000-0000000af102', 'af-o@t.com'),
  ('00000000-0000-0000-0000-0000000af103', 'af-t@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000af101', 'af_user_u'),
  ('00000000-0000-0000-0000-0000000af102', 'af_user_o'),
  ('00000000-0000-0000-0000-0000000af103', 'af_user_t');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000af201',
   'AF Squad', '00000000-0000-0000-0000-0000000af101');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000af201',
   '00000000-0000-0000-0000-0000000af101', 'admin'),
  ('00000000-0000-0000-0000-0000000af201',
   '00000000-0000-0000-0000-0000000af103', 'member');

-- U's own private routine (used in the solo session).
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('00000000-0000-0000-0000-0000000af401',
   '00000000-0000-0000-0000-0000000af101', 'Push Day A', 'private');
-- T's private routine — U is never the owner and it is not public, so under
-- plain SELECT-RLS (INVOKER) U would have NO path to this row at all.
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('00000000-0000-0000-0000-0000000af402',
   '00000000-0000-0000-0000-0000000af103', 'Legs by T', 'private');

-- Session S1: U's solo session (no group), U's own routine.
INSERT INTO sessions (id, organizer_id, group_id, routine_id, state, started_at, completed_at) VALUES
  ('00000000-0000-0000-0000-0000000af301',
   '00000000-0000-0000-0000-0000000af101', NULL,
   '00000000-0000-0000-0000-0000000af401',
   'completed', now() - interval '3 hours', now() - interval '2 hours');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000af301', '00000000-0000-0000-0000-0000000af101', 'ready');
-- 3 valid sets (10 reps x 100 weight = 1000 each -> 3000 total), plus 1
-- penalty set and 1 failed set that must be excluded from both count and volume.
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed) VALUES
  ('00000000-0000-0000-0000-0000000af501', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af301',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 1, 10, 100, false, false),
  ('00000000-0000-0000-0000-0000000af502', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af301',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 2, 10, 100, false, false),
  ('00000000-0000-0000-0000-0000000af503', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af301',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 3, 10, 100, false, false),
  ('00000000-0000-0000-0000-0000000af504', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af301',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 4, 20, 500, true, false),
  ('00000000-0000-0000-0000-0000000af505', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af301',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 5, 20, 500, false, true);
INSERT INTO personal_records (user_id, exercise_id, weight, reps, previous_best, session_id) VALUES
  ('00000000-0000-0000-0000-0000000af101',
   (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1), 100, 10, 90,
   '00000000-0000-0000-0000-0000000af301');

-- Session S2: group session (AF Squad), U + T both participate.
INSERT INTO sessions (id, organizer_id, group_id, routine_id, state, started_at, completed_at) VALUES
  ('00000000-0000-0000-0000-0000000af302',
   '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af201', NULL,
   'completed', now() - interval '2 days', now() - interval '2 days' + interval '1 hour');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000af302', '00000000-0000-0000-0000-0000000af101', 'ready'),
  ('00000000-0000-0000-0000-0000000af302', '00000000-0000-0000-0000-0000000af103', 'ready');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed) VALUES
  ('00000000-0000-0000-0000-0000000af506', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af302',
   (SELECT id FROM exercises WHERE slug = 'back-squat' LIMIT 1), 1, 8, 50, false, false),
  ('00000000-0000-0000-0000-0000000af507', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af302',
   (SELECT id FROM exercises WHERE slug = 'back-squat' LIMIT 1), 2, 8, 50, false, false);

-- Session S3: T organizes a solo (non-group) session on T's own private
-- routine, and adds U as a participant. U logs one set here. Because the
-- organizer can add ANY participant regardless of group/friendship, U has
-- no ownership/public-visibility path to routine af402 under plain RLS.
INSERT INTO sessions (id, organizer_id, group_id, routine_id, state, started_at, completed_at) VALUES
  ('00000000-0000-0000-0000-0000000af303',
   '00000000-0000-0000-0000-0000000af103', NULL,
   '00000000-0000-0000-0000-0000000af402',
   'completed', now() - interval '1 day', now() - interval '1 day' + interval '30 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000af303', '00000000-0000-0000-0000-0000000af103', 'ready'),
  ('00000000-0000-0000-0000-0000000af303', '00000000-0000-0000-0000-0000000af101', 'ready');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed) VALUES
  ('00000000-0000-0000-0000-0000000af508', '00000000-0000-0000-0000-0000000af101',
   '00000000-0000-0000-0000-0000000af303',
   (SELECT id FROM exercises WHERE slug = 'deadlift' LIMIT 1), 1, 5, 40, false, false);

-- Session S4: U's own session, NOT completed — must be excluded from the feed.
INSERT INTO sessions (id, organizer_id, group_id, routine_id, state, started_at) VALUES
  ('00000000-0000-0000-0000-0000000af304',
   '00000000-0000-0000-0000-0000000af101', NULL,
   '00000000-0000-0000-0000-0000000af401',
   'in_progress', now() - interval '10 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000af304', '00000000-0000-0000-0000-0000000af101', 'ready');

-- Session S5: outsider O's own solo session — U never participates.
INSERT INTO sessions (id, organizer_id, group_id, routine_id, state, started_at, completed_at) VALUES
  ('00000000-0000-0000-0000-0000000af305',
   '00000000-0000-0000-0000-0000000af102', NULL, NULL,
   'completed', now() - interval '4 hours', now() - interval '3 hours');
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000af305', '00000000-0000-0000-0000-0000000af102', 'ready');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000af101';

-- ── Positive: U's feed contains exactly S1, S2, S3 (not S4 in-progress, not S5 outsider) ──
SELECT results_eq(
  $$SELECT count(*)::int FROM public.activity_feed(10)$$,
  ARRAY[3],
  'U sees exactly 3 completed sessions they participated in');

-- ── S1 (solo, own routine): all aggregate fields, penalty+failed excluded ──
SELECT results_eq(
  $$SELECT is_group FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af301'$$,
  ARRAY[false], 'S1 is_group = false (no group_id)');

SELECT results_eq(
  $$SELECT display_name FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af301'$$,
  ARRAY['Push Day A'], 'S1 display_name = routine name');

SELECT results_eq(
  $$SELECT set_count FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af301'$$,
  ARRAY[3], 'S1 set_count excludes the penalty and failed sets (5 logged, 3 count)');

SELECT results_eq(
  $$SELECT volume FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af301'$$,
  ARRAY[3000::numeric], 'S1 volume excludes the penalty and failed sets (3 x 10x100)');

SELECT results_eq(
  $$SELECT pr_count FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af301'$$,
  ARRAY[1], 'S1 pr_count = 1');

-- ── S2 (group session): display_name is the GROUP name, not routine (routine_id is NULL here anyway) ──
SELECT results_eq(
  $$SELECT is_group FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af302'$$,
  ARRAY[true], 'S2 is_group = true');

SELECT results_eq(
  $$SELECT display_name FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af302'$$,
  ARRAY['AF Squad'], 'S2 display_name = group name');

SELECT results_eq(
  $$SELECT set_count FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af302'$$,
  ARRAY[2], 'S2 set_count = 2');

SELECT results_eq(
  $$SELECT volume FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af302'$$,
  ARRAY[800::numeric], 'S2 volume = 2 x 8x50');

SELECT results_eq(
  $$SELECT pr_count FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af302'$$,
  ARRAY[0], 'S2 pr_count = 0 (no PRs logged)');

-- ── S3 (DEFINER edge case): U participated in T's solo session on T's private
-- routine. Under plain RLS U has no read path to routines af402, but the
-- feed must still show its true name (not silently fall back to 'Workout').
SELECT results_eq(
  $$SELECT display_name FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af303'$$,
  ARRAY['Legs by T'],
  'S3 display_name resolves to the organizer''s private routine name despite U not owning it (DEFINER bypasses routines RLS)');

-- ── Negative: non-completed S4 and outsider O's S5 are absent from U's feed ──
SELECT results_eq(
  $$SELECT count(*)::int FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af304'$$,
  ARRAY[0], 'non-completed session S4 does not appear in U''s feed');

SELECT results_eq(
  $$SELECT count(*)::int FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af305'$$,
  ARRAY[0], 'outsider O''s solo session S5 does not appear in U''s feed');

-- ── Negative (other direction): O's feed contains only O's own session ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000af102';
SELECT results_eq(
  $$SELECT count(*)::int FROM public.activity_feed(10)$$,
  ARRAY[1],
  'O''s feed contains exactly 1 session (their own)');

SELECT results_eq(
  $$SELECT session_id FROM public.activity_feed(10)$$,
  ARRAY['00000000-0000-0000-0000-0000000af305'::uuid],
  'O''s feed contains only O''s own solo session, not U''s sessions');

SELECT results_eq(
  $$SELECT display_name FROM public.activity_feed(10)
      WHERE session_id = '00000000-0000-0000-0000-0000000af305'$$,
  ARRAY['Workout'], 'S5 display_name = Workout (fallback for solo session with no routine)');

SELECT * FROM finish();
ROLLBACK;
