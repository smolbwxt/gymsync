BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(1);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(),
       '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001',
       e.id, 1, 5, 185.00 FROM e;

SELECT results_eq(
  $$SELECT lifetime_volume_lifted FROM profiles
    WHERE id='00000000-0000-0000-0000-000000000001'$$,
  $$VALUES (925.00::numeric(14,2))$$,
  '5 reps x 185 lbs = 925 lbs added to lifetime volume'
);

SELECT * FROM finish();
ROLLBACK;
