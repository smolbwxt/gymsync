BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

-- First set -> PR (nothing prior)
SELECT ok(
  public.is_pr('00000000-0000-0000-0000-000000000001',
               (SELECT id FROM exercises WHERE slug='bench-press'),
               185.00),
  'first log for exercise is a PR'
);

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(),
       '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001',
       e.id, 1, 5, 185.00 FROM e;

-- Same weight -> NOT a PR (must strictly exceed)
SELECT ok(
  NOT public.is_pr('00000000-0000-0000-0000-000000000001',
                   (SELECT id FROM exercises WHERE slug='bench-press'),
                   185.00),
  'matching prior weight is not a PR'
);

-- Higher weight -> PR
SELECT ok(
  public.is_pr('00000000-0000-0000-0000-000000000001',
               (SELECT id FROM exercises WHERE slug='bench-press'),
               190.00),
  'strictly higher weight is a PR'
);

SELECT * FROM finish();
ROLLBACK;
