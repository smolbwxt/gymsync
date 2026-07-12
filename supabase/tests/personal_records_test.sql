BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'pra@t.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'prb@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'pr_owner'),
  ('00000000-0000-0000-0000-0000000000e2', 'pr_outsider');

-- ── 1. Owner can insert their own personal record (lives_ok) ──────────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e1';

SELECT lives_ok(
  $$INSERT INTO personal_records
      (id, user_id, exercise_id, weight, reps, previous_best, session_id) VALUES
      ('e0000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-0000000000e1',
       (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1),
       185, 5, 175, NULL)$$,
  'owner can insert their own personal record'
);

-- ── 2. Owner can select their own personal record ──────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM personal_records
      WHERE user_id='00000000-0000-0000-0000-0000000000e1'$$,
  ARRAY[1],
  'owner can select their own personal record'
);

-- ── 3. Owner cannot UPDATE their own record — no UPDATE policy (silently 0 rows) ─
SELECT results_eq(
  $$WITH upd AS (
      UPDATE personal_records SET weight = 999
      WHERE user_id='00000000-0000-0000-0000-0000000000e1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'owner cannot update personal records (immutable, no policy)'
);

-- ── 4. Outsider insert (as owner user_id) rejected (42501) ─────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e2';

SELECT throws_ok(
  $$INSERT INTO personal_records
      (user_id, exercise_id, weight, reps, previous_best) VALUES
      ('00000000-0000-0000-0000-0000000000e1',
       (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1),
       200, 5, 185)$$,
  '42501', NULL,
  'outsider cannot insert personal record for another user'
);

-- ── 5. Outsider select returns 0 rows ───────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM personal_records
      WHERE user_id='00000000-0000-0000-0000-0000000000e1'$$,
  ARRAY[0],
  'outsider cannot select owner personal records'
);

-- ── 6. Outsider cannot insert+select their own row and then read owner's row ────
SELECT lives_ok(
  $$INSERT INTO personal_records
      (user_id, exercise_id, weight, reps, previous_best) VALUES
      ('00000000-0000-0000-0000-0000000000e2',
       (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1),
       135, 5, 115)$$,
  'outsider can insert their own personal record'
);

SELECT * FROM finish();
ROLLBACK;
