BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(23);

-- Pump Check P1 (20260731000001): workout_posts + post_reactions RLS.
-- Visibility matrix: author / accepted friend / stranger / blocked pair.
-- Fixture block: 07xx UUIDs (this suite's namespace).
--   A = ...0701 author   B = ...0702 accepted friend
--   C = ...0703 stranger D = ...0704 blocked pair (D blocked A)

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000701', 'pump-a@test.local'),
  ('00000000-0000-4000-f000-000000000702', 'pump-b@test.local'),
  ('00000000-0000-4000-f000-000000000703', 'pump-c@test.local'),
  ('00000000-0000-4000-f000-000000000704', 'pump-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000701', 'pump_a'),
  ('00000000-0000-4000-f000-000000000702', 'pump_b'),
  ('00000000-0000-4000-f000-000000000703', 'pump_c'),
  ('00000000-0000-4000-f000-000000000704', 'pump_d');

INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-4000-f000-000000000701', '00000000-0000-4000-f000-000000000702', 'accepted');
-- D blocked A (block-severs-friendship makes any A–D friendship moot; the
-- policy's is_blocked clauses must deny regardless).
INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
  ('00000000-0000-4000-f000-000000000704', '00000000-0000-4000-f000-000000000701');

-- A's finished solo session (participant row drives the INSERT gate).
INSERT INTO sessions (id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000000710', '00000000-0000-4000-f000-000000000701',
   'completed', now() - interval '1 hour', now());
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000710', '00000000-0000-4000-f000-000000000701');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';

-- 1. Author posts their own finished session.
SELECT lives_ok(
  $$INSERT INTO workout_posts (id, author_id, session_id, photo_path, summary, is_late)
    VALUES ('00000000-0000-4000-f000-000000000720',
            '00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710',
            'posts/00000000-0000-4000-f000-000000000701/00000000-0000-4000-f000-000000000720.jpg',
            '{"duration_seconds": 2520, "total_volume_lbs": 7240,
              "exercises": [{"name": "Back Squat", "equipment": "barbell",
                             "sets": [{"weight_lbs": 225, "reps": 5, "is_pr": true, "is_failed": false}]}]}',
            false)$$,
  'author can post own finished session');

-- 2. Author cannot spoof another author_id.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary)
    VALUES ('00000000-0000-4000-f000-000000000702',
            '00000000-0000-4000-f000-000000000710', '{}')$$,
  '42501', NULL, 'cannot post as someone else');

-- 3. HR guard: values without the toggle are rejected.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, includes_hr, avg_bpm)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}', false, 142)$$,
  '23514', NULL, 'bpm without includes_hr rejected');

-- 4. No UPDATE policy: an author "edit" matches no row (immutable snapshot).
UPDATE workout_posts SET is_late = true
  WHERE id = '00000000-0000-4000-f000-000000000720';
SELECT results_eq(
  $$SELECT is_late FROM workout_posts WHERE id = '00000000-0000-4000-f000-000000000720'$$,
  $$VALUES (false)$$,
  'posts are immutable — UPDATE silently matches nothing');

-- 5. B cannot post about A's session (not a participant).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000702';
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary)
    VALUES ('00000000-0000-4000-f000-000000000702',
            '00000000-0000-4000-f000-000000000710', '{}')$$,
  '42501', NULL, 'cannot post about a session you were not in');

-- 6. Accepted friend sees the post.
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_posts
    WHERE author_id = '00000000-0000-4000-f000-000000000701'$$,
  $$VALUES (1)$$, 'accepted friend sees the post');

-- 7. Friend reacts.
SELECT lives_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji)
    VALUES ('00000000-0000-4000-f000-000000000720',
            '00000000-0000-4000-f000-000000000702', '🔥')$$,
  'friend can react to a visible post');

-- 8. Reaction user spoof denied.
SELECT throws_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji)
    VALUES ('00000000-0000-4000-f000-000000000720',
            '00000000-0000-4000-f000-000000000701', '💪')$$,
  '42501', NULL, 'cannot react as someone else');

-- 9. Emoji outside the kudos set rejected.
SELECT throws_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji)
    VALUES ('00000000-0000-4000-f000-000000000720',
            '00000000-0000-4000-f000-000000000702', '🙃')$$,
  '23514', NULL, 'emoji outside the kudos set rejected');

-- 9b. The snapshot columns accept a full row.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';
SELECT lives_ok(
  $$INSERT INTO workout_posts (id, author_id, session_id, summary, is_late,
                               completed_at, retake_count, highlight, trajectory, week_start)
    VALUES ('00000000-0000-4000-f000-000000000721',
            '00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710',
            '{"duration_seconds": 2520, "total_volume_lbs": 7240, "routine_name": "Push day", "exercises": []}',
            true, now() - interval '47 minutes', 2,
            '{"kind": "pr", "text": "PR", "weightLbs": 235, "reps": 3}',
            '{"goalLine": "Bench 225 by Oct 18", "weekNumber": 3, "weekCount": 8,
              "standing": "onTrack", "chips": [{"name": "CHEST", "done": 8, "target": 12}]}',
            '2026-09-06')$$,
  'a post carries its trajectory, highlight, retakes and completion');

-- 9c. retake_count defaults to zero, never null.
SELECT results_eq(
  $$SELECT retake_count FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000720'$$,
  $$VALUES (0)$$, 'retake_count defaults to 0 on a row that never set it');

-- 9d. A negative retake count is rejected.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, retake_count)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}', -1)$$,
  '23514', NULL, 'a negative retake count is rejected');

-- 9e. A scalar where an object belongs is rejected.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}', '"pr"')$$,
  '23514', NULL, 'highlight must be a json object');

-- 9e2. The kind domain: `milestone` is ACCEPTED though this release never
-- proposes it (the You hero's MilestoneCatalog will), and an unknown kind is
-- refused. This is the assertion that lets the milestone highlight ship later
-- without a migration.
SELECT lives_ok(
  $$INSERT INTO workout_posts (id, author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000722',
            '00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}',
            '{"kind": "milestone", "text": "Lifetime total crossed", "weightLbs": 1000000}')$$,
  'the milestone kind is already in the column''s domain');
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}',
            '{"kind": "vibes", "text": "felt strong"}')$$,
  '23514', NULL, 'a kind outside the three is rejected');

-- 9f. The snapshot is still IMMUTABLE — no UPDATE policy came with it.
UPDATE workout_posts SET retake_count = 99
  WHERE id = '00000000-0000-4000-f000-000000000721';
SELECT results_eq(
  $$SELECT retake_count FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000721'$$,
  $$VALUES (2)$$,
  'the new columns are as immutable as the old ones');

-- 9g. The friend sees the standing — spec §1's visibility ruling at the row
-- level: `behind` included, no per-post hide, friends-scoped by the SELECT
-- policy that already existed.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000702';
SELECT results_eq(
  $$SELECT trajectory ->> 'standing' FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000721'$$,
  $$VALUES ('onTrack'::text)$$,
  'an accepted friend reads the author''s standing');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';

-- 10. Stranger sees nothing…
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000703';
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_posts$$,
  $$VALUES (0)$$, 'stranger sees no posts');

-- 11. …and cannot react to what they cannot see.
SELECT throws_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji)
    VALUES ('00000000-0000-4000-f000-000000000720',
            '00000000-0000-4000-f000-000000000703', '🔥')$$,
  '42501', NULL, 'stranger cannot react to an invisible post');

-- 12. Blocked pair: D sees nothing (regardless of any past friendship).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000704';
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_posts$$,
  $$VALUES (0)$$, 'blocked pair sees no posts');

-- 13. Non-author delete matches nothing.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000702';
DELETE FROM workout_posts WHERE id = '00000000-0000-4000-f000-000000000720';
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_posts
    WHERE id = '00000000-0000-4000-f000-000000000720'$$,
  $$VALUES (1)$$, 'non-author delete silently matches nothing');

-- 14. Author deletes; 15. reactions cascade with the post.
SELECT lives_ok(
  $$DELETE FROM workout_posts WHERE id = '00000000-0000-4000-f000-000000000720'$$,
  'author deletes own post');
SET LOCAL role postgres;
SELECT results_eq(
  $$SELECT count(*)::int FROM post_reactions
    WHERE post_id = '00000000-0000-4000-f000-000000000720'$$,
  $$VALUES (0)$$, 'reactions cascade-delete with the post');

SELECT * FROM finish();
ROLLBACK;
