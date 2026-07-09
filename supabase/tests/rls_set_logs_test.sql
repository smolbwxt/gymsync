BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a'),
  ('00000000-0000-0000-0000-000000000002', 'user_b');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', e.id, 1, 5, 185 FROM e;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Positive: user A can read their own set logs
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs WHERE user_id='00000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'user can read own set logs'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

-- Negative: user B cannot see user A's solo set logs (B is not a session participant)
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs$$,
  ARRAY[0],
  'unrelated user cannot see set logs'
);

-- Negative: user B cannot insert set logs as user A (INSERT WITH CHECK raises 42501)
SELECT throws_ok(
  $$INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index)
    VALUES (gen_random_uuid(),
            '00000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000001',
            (SELECT id FROM exercises LIMIT 1),
            1)$$,
  '42501',
  NULL,
  'user cannot insert set logs for another user'
);

SELECT * FROM finish();
ROLLBACK;
