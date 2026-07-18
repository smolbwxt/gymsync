BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

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

-- ============================================================
-- Fix-forward (20260722000002) — solo-workout privacy: friend-visibility
-- clause added to the set_logs SELECT policy (Phase M Task 4). See that
-- migration's header for the full predicate/helper rationale.
--
-- Fixtures:
-- A (...0001) / B (...0002) — the original owner/unrelated-user pair from
--   the test above. A gets the missing session_participants row for S1
--   backfilled here (the original fixture above never inserted one — real
--   solo sessions always do, per SessionRepository.startSolo(); without
--   it S1 wouldn't actually satisfy is_solo_session()). B is reused below
--   as S2's second (real) participant.
-- F (...0003) — accepted friend of A. Sees A's solo S1 log only once A
--   opts in (show_solo_workouts=true); never gains access to C's rows
--   (F/C are strangers) or to A's GROUP session S2 log (not solo).
-- Z (...0005) — a stranger to A (no friendship row at all) — proves the
--   opt-in alone is never sufficient without an accepted friendship too.
-- C (...0004) — third party, own solo session S3, show_solo_workouts=true
--   from creation. Isolates that is_friend() is scoped per-owner, not
--   "any friend of anyone."
-- S2 (20000000-...0002) — A organizes a MULTI-participant session with B;
--   A logs a set there too. Proves the friend clause does NOT widen group
--   visibility just because A also has show_solo_workouts=true globally —
--   the master spec's rule is scoped to solo workouts specifically.
-- ============================================================

-- The original test above ends with role still 'authenticated'/B — reset
-- to the default (superuser) role before doing more fixture writes, same
-- as every other test file's fixture-then-RLS-section shape (e.g.
-- streaks_test.sql).
SET LOCAL role postgres;

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000003', 'f@t.com'),
  ('00000000-0000-0000-0000-000000000004', 'c@t.com'),
  ('00000000-0000-0000-0000-000000000005', 'z@t.com');
INSERT INTO profiles (id, username, show_solo_workouts) VALUES
  ('00000000-0000-0000-0000-000000000003', 'user_f', false),
  ('00000000-0000-0000-0000-000000000004', 'user_c', true),
  ('00000000-0000-0000-0000-000000000005', 'user_z', false);

-- A <-> F: accepted friendship.
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'accepted');

-- Backfill: A is the sole participant of her own solo session S1 (the
-- original fixture above never added this row — see note above).
INSERT INTO session_participants (session_id, user_id) VALUES
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

-- C: own solo session S3 + one set_log (show_solo_workouts already true).
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000004', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-000000000004',
       '20000000-0000-0000-0000-000000000003', e.id, 1, 5, 135 FROM e;

-- A + B: a MULTI-participant session S2 (2 participants) with A's own
-- set_log inside it — the "must not widen group visibility" fixture.
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000001', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002');
WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000002', e.id, 1, 5, 185 FROM e;

-- ── F, before A opts in (show_solo_workouts defaults false) ──────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- F
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'friend cannot read owner''s solo set_logs while show_solo_workouts=false'
);

-- A opts in herself (owner-RLS self-update — "users can update their own
-- profile", 20260709000001_create_profiles.sql).
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';  -- A
UPDATE profiles SET show_solo_workouts = true
  WHERE id = '00000000-0000-0000-0000-000000000001';

-- ── F, after A opts in: can read the SOLO log, cannot read the GROUP log ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- F
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'accepted friend reads owner''s solo set_logs once show_solo_workouts=true'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000002'$$,
  ARRAY[0],
  'friend clause does not widen visibility into a MULTI-participant session (not solo), even with show_solo_workouts=true'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000004'$$,
  ARRAY[0],
  'friend of A does not gain access to a THIRD party''s (C''s) rows just by being A''s friend'
);

-- ── B, the S2 participant, DOES read A's group-session log (existing clause) ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';  -- B
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000002'$$,
  ARRAY[1],
  'real session participant reads the owner''s set_logs in a multi-participant session'
);

-- ── Z, a stranger (no friendship row at all): never, even though A opted in ──
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';  -- Z
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'a non-friend never reads the owner''s solo set_logs regardless of show_solo_workouts'
);

-- ============================================================
-- Fix-forward (20260722000003) — whole-branch review Finding 1: a block in
-- EITHER direction must cut solo-workout visibility, even when an accepted
-- friendship row still exists for the pair. See that migration's header
-- for the full is_blocked()-clause rationale (two directions, why neither
-- is implied by the other).
--
-- Each direction gets TWO assertions:
--   (a) the REAL path — block via the normal authenticated INSERT into
--       blocked_users, which also fires the new
--       blocked_users_sever_friendship trigger (friendship gone -> is_friend()
--       alone would already explain the loss of access here);
--   (b) a RECONSTRUCTED "legacy" state — after the real block above, the
--       friendship is re-inserted directly as `postgres` (bypasses RLS,
--       same idiom as the `SET LOCAL role postgres` backfill inserts
--       earlier in this file), simulating a pair that was blocked BEFORE
--       this migration's trigger existed (exactly what this migration's
--       one-time backfill cleans up on a real database, reconstructed
--       fresh here for the test). With is_friend() true again, only the
--       set_logs SELECT policy's own `NOT private.is_blocked(...)` clauses
--       can be responsible for continued denial — this isolates that the
--       policy layer works independently of the trigger, not just
--       incidentally alongside it.
-- ============================================================

SET LOCAL role postgres;

-- New fixture for direction B (viewer blocked owner): G, an accepted
-- friend of A, added after A already has show_solo_workouts=true so no
-- further profile setup is needed.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000006', 'g@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000006', 'user_g');
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000006', 'accepted');

-- ── Direction A: OWNER (A) has blocked the VIEWER (F) ─────────────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';  -- A
SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000003')$$,
  'A (owner) blocks F (viewer) — direction-A fixture'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- F
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'direction A, real path: blocked friend F can no longer read A''s solo set_logs (friendship also severed by trigger)'
);

-- Reconstruct: friendship re-inserted directly (postgres bypasses RLS) —
-- is_friend(A,F) is true again, but A's block on F is still in place.
SET LOCAL role postgres;
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'accepted');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- F
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'direction A, policy-isolated: set_logs SELECT policy''s is_blocked(owner,viewer) clause denies F even though is_friend(A,F) is true again'
);

-- ── Direction B: VIEWER (G) has blocked the OWNER (A) ─────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';  -- G
SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-000000000006',
     '00000000-0000-0000-0000-000000000001')$$,
  'G (viewer) blocks A (owner) — direction-B fixture'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'direction B, real path: G, having blocked A, can no longer read A''s solo set_logs (friendship also severed by trigger)'
);

-- Reconstruct: friendship re-inserted directly — is_friend(A,G) true
-- again, G's block on A still in place.
SET LOCAL role postgres;
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000006', 'accepted');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';  -- G
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs
    WHERE user_id = '00000000-0000-0000-0000-000000000001'
      AND session_id = '20000000-0000-0000-0000-000000000001'$$,
  ARRAY[0],
  'direction B, policy-isolated: set_logs SELECT policy''s is_blocked(viewer,owner) clause denies G even though is_friend(A,G) is true again'
);

SET LOCAL role postgres;

SELECT * FROM finish();
ROLLBACK;
