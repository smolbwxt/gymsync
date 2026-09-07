BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- fl_alice — the caller.
-- fl_bob   — ACCEPTED friend, SOLO session, show_solo_workouts TRUE  → visible.
-- fl_cara  — PENDING friend, solo session, show_solo_workouts TRUE   → hidden.
-- fl_dan   — ACCEPTED friend, SOLO session, show_solo_workouts FALSE → hidden,
--            until the flag is flipped mid-test.
-- fl_frank — NO friendship row at all, solo session, opted in    -> hidden.
-- fl_erin  — ACCEPTED friend, CREW session she only PARTICIPATES in,
--            show_solo_workouts FALSE → visible anyway: a crew session is not
--            a solo workout, and she reaches the result through the
--            session_participants arm rather than as organizer.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000f1001', 'fl1@t.com'),
  ('00000000-0000-0000-0000-0000000f1002', 'fl2@t.com'),
  ('00000000-0000-0000-0000-0000000f1003', 'fl3@t.com'),
  ('00000000-0000-0000-0000-0000000f1004', 'fl4@t.com'),
  ('00000000-0000-0000-0000-0000000f1005', 'fl5@t.com'),
  ('00000000-0000-0000-0000-0000000f1006', 'fl6@t.com');
INSERT INTO profiles (id, username, display_name, show_solo_workouts) VALUES
  ('00000000-0000-0000-0000-0000000f1001', 'fl_alice', 'Alice', false),
  ('00000000-0000-0000-0000-0000000f1002', 'fl_bob',   'Bob',   true),
  ('00000000-0000-0000-0000-0000000f1003', 'fl_cara',  'Cara',  true),
  ('00000000-0000-0000-0000-0000000f1004', 'fl_dan',   'Dan',   false),
  ('00000000-0000-0000-0000-0000000f1005', 'fl_erin',  'Erin',  false),
  ('00000000-0000-0000-0000-0000000f1006', 'fl_frank', 'Frank', true);

-- Friendships. Bob's and Cara's rows are stored ALICE -> THEM; Dan's and
-- Erin's are stored THEM -> ALICE, deliberately the other direction, so this
-- test fails if the RPC ever reads friendships one-sidedly.
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f1002', 'accepted'),
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f1003', 'pending'),
  ('00000000-0000-0000-0000-0000000f1004', '00000000-0000-0000-0000-0000000f1001', 'accepted'),
  ('00000000-0000-0000-0000-0000000f1005', '00000000-0000-0000-0000-0000000f1001', 'accepted');

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000f1010', 'Iron Crew',
   '00000000-0000-0000-0000-0000000f1001');
INSERT INTO group_members (group_id, user_id) VALUES
  ('00000000-0000-0000-0000-0000000f1010', '00000000-0000-0000-0000-0000000f1001'),
  ('00000000-0000-0000-0000-0000000f1010', '00000000-0000-0000-0000-0000000f1005');

INSERT INTO sessions (id, organizer_id, group_id, state, started_at) VALUES
  -- Bob, solo, live.
  ('00000000-0000-0000-0000-0000000f1021', '00000000-0000-0000-0000-0000000f1002',
   NULL, 'in_progress', now() - interval '20 minutes'),
  -- Cara, solo, live — but only a PENDING friend.
  ('00000000-0000-0000-0000-0000000f1022', '00000000-0000-0000-0000-0000000f1003',
   NULL, 'in_progress', now() - interval '15 minutes'),
  -- Dan, solo, live — but has not opted into sharing solo workouts.
  ('00000000-0000-0000-0000-0000000f1023', '00000000-0000-0000-0000-0000000f1004',
   NULL, 'in_progress', now() - interval '10 minutes'),
  -- The crew session ALICE organizes and Erin is a participant in.
  ('00000000-0000-0000-0000-0000000f1024', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f1010', 'in_progress', now() - interval '5 minutes'),
  -- Bob also has a session on the books that has not started.
  ('00000000-0000-0000-0000-0000000f1025', '00000000-0000-0000-0000-0000000f1002',
   NULL, 'scheduled', NULL),
  -- Frank, solo, live, opted in — and no friendship with Alice at all.
  ('00000000-0000-0000-0000-0000000f1026', '00000000-0000-0000-0000-0000000f1006',
   NULL, 'in_progress', now() - interval '25 minutes');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-0000-0000-0000000f1021', '00000000-0000-0000-0000-0000000f1002'),
  ('00000000-0000-0000-0000-0000000f1022', '00000000-0000-0000-0000-0000000f1003'),
  ('00000000-0000-0000-0000-0000000f1023', '00000000-0000-0000-0000-0000000f1004'),
  ('00000000-0000-0000-0000-0000000f1024', '00000000-0000-0000-0000-0000000f1001'),
  ('00000000-0000-0000-0000-0000000f1024', '00000000-0000-0000-0000-0000000f1005'),
  ('00000000-0000-0000-0000-0000000f1025', '00000000-0000-0000-0000-0000000f1002'),
  ('00000000-0000-0000-0000-0000000f1026', '00000000-0000-0000-0000-0000000f1006');


-- ============================================================
-- As Alice
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f1001';

-- ── 1. Exactly the two visible friends ────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live()$$,
  ARRAY[2],
  'alice sees exactly the two friends who are live and visible to her'
);

-- ── 2. …and they are Bob and Erin ─────────────────────────────────────────────
--      Erin's friendship row is stored ERIN -> ALICE, so her presence proves
--      the RPC reads `friendships` in BOTH directions. She is also only a
--      PARTICIPANT in her session, not its organizer, so she proves the
--      session_participants arm.
SELECT results_eq(
  $$SELECT username FROM friends_live() ORDER BY username$$,
  $$VALUES ('fl_bob'::text), ('fl_erin'::text)$$,
  'both friendship directions and both the organizer and participant arms resolve'
);

-- ── 3. Bob's row is his LIVE solo session, not his scheduled one ──────────────
SELECT results_eq(
  $$SELECT session_id FROM friends_live() WHERE username = 'fl_bob'$$,
  $$VALUES ('00000000-0000-0000-0000-0000000f1021'::uuid)$$,
  'only an in_progress session is live — a scheduled one is not'
);

-- ── 4. A solo session carries no crew ─────────────────────────────────────────
SELECT ok(
  (SELECT group_id IS NULL AND group_name IS NULL
     FROM friends_live() WHERE username = 'fl_bob'),
  'a solo session returns a NULL group_id and group_name (the strip renders Solo)'
);

-- ── 5. A crew session carries its group's name ────────────────────────────────
--      Alice is a member here, but the join is DEFINER precisely so that a
--      friend training with a crew she is NOT in still renders with a name.
SELECT results_eq(
  $$SELECT group_id, group_name FROM friends_live() WHERE username = 'fl_erin'$$,
  $$VALUES ('00000000-0000-0000-0000-0000000f1010'::uuid, 'Iron Crew'::text)$$,
  'a crew session returns its group id and name'
);

-- ── 6. started_at comes through for the strip's "{when}" ──────────────────────
SELECT ok(
  (SELECT started_at IS NOT NULL FROM friends_live() WHERE username = 'fl_bob'),
  'started_at is populated, so the strip can say when they began'
);

-- ── 7. A PENDING friendship is not a friendship ───────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_cara'$$,
  ARRAY[0],
  'a pending friend request does not put someone on the crew pulse'
);

-- ── 7b. …and a total STRANGER is not either ───────────────────────────────────
--       Cara proves `pending`; Frank has no friendships row at all, which is
--       the case the query's shape makes unreachable but nothing proved. He
--       is mid-session and has opted into sharing solo workouts, so the only
--       thing keeping him out is the absence of a friendship.
SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_frank'$$,
  ARRAY[0],
  'a stranger with no friendships row never reaches the crew pulse'
);

-- ── 8. THE SOLO-PRESENCE GATE, negative case ──────────────────────────────────
--      Dan is an accepted friend, mid-session, and invisible: his session has
--      no group_id, so it is a SOLO WORKOUT, and profiles.show_solo_workouts
--      (NOT NULL DEFAULT false) says friends may not see those. Publishing his
--      live presence while 20260722000002_solo_workout_privacy.sql hides his
--      solo set_logs would be the same leak on a newer surface.
SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_dan'$$,
  ARRAY[0],
  'a solo session is hidden from friends when show_solo_workouts is false'
);

-- ── 9. …and Erin is visible with the SAME flag set false ──────────────────────
--      Which is the point: the gate is on the session being solo, not on the
--      flag alone. A crew session is not a solo workout.
SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_erin'$$,
  ARRAY[1],
  'a crew session is visible regardless of show_solo_workouts'
);

-- ── 10. THE SOLO-PRESENCE GATE, positive case ─────────────────────────────────
--       Same friend, same session, flag flipped: Dan appears. Flipped as
--       postgres because profiles RLS lets a user update only their own row.
SET LOCAL role postgres;
UPDATE profiles SET show_solo_workouts = true
 WHERE id = '00000000-0000-0000-0000-0000000f1004';
SET LOCAL role authenticated;

SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_dan'$$,
  ARRAY[1],
  'the same solo session becomes visible once its owner opts in'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live()$$,
  ARRAY[3],
  'alice now sees three live friends'
);

-- ── 11. Blocking removes a friend from the pulse ──────────────────────────────
--       Two independent mechanisms make this true and both are wanted: the
--       AFTER INSERT trigger on blocked_users severs the friendships row
--       (20260722000003), AND the RPC's own two-direction is_blocked predicate
--       is evaluated live on every call, which covers pairs blocked before
--       that trigger existed.
SELECT lives_ok(
  $$INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
    ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f1002')$$,
  'alice can block bob'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_bob'$$,
  ARRAY[0],
  'a blocked friend disappears from the crew pulse'
);

-- ── 12. …and the OTHER direction: when THEY blocked YOU ───────────────────────
--       The assertion above cannot isolate the RPC's own predicate, because
--       the sever-on-block trigger removes the friendship row too and either
--       mechanism alone would produce zero. So: block in the reverse
--       direction as `postgres` (RLS lets a user write only their OWN blocks),
--       then RE-INSERT the friendship the trigger just severed. Now the
--       friendship exists AND the block exists, and only
--       `NOT private.is_blocked(fi.id, auth.uid())` can hide Erin.
SET LOCAL role postgres;
INSERT INTO blocked_users (blocker_id, blocked_id) VALUES
  ('00000000-0000-0000-0000-0000000f1005', '00000000-0000-0000-0000-0000000f1001');
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-0000000f1005', '00000000-0000-0000-0000-0000000f1001', 'accepted');
SET LOCAL role authenticated;

SELECT results_eq(
  $$SELECT count(*)::int FROM friends_live() WHERE username = 'fl_erin'$$,
  ARRAY[0],
  'a friend who has blocked YOU is hidden by the RPC''s own predicate, not only by the trigger'
);

-- ── 13. The grant posture ─────────────────────────────────────────────────────
--       REVOKE FROM PUBLIC, anon then GRANT TO authenticated — the repo's
--       revoke-then-grant idiom. Asserted through has_function_privilege
--       rather than by switching to `anon` and catching an error, so the
--       assertion is about the GRANT itself and not about whether anon can
--       reach pgTAP's own functions.
SET LOCAL role postgres;
SELECT ok(
  NOT has_function_privilege('anon', 'public.friends_live()', 'EXECUTE'),
  'anon cannot execute friends_live()'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.friends_live()', 'EXECUTE'),
  'authenticated can execute friends_live()'
);

SELECT * FROM finish();
ROLLBACK;
