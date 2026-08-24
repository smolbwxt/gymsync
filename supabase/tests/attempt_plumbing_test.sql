-- Phase L Task 2: attempt plumbing — start_attempt RPC + completion social
-- effects (20260723000002_attempt_plumbing.sql).
-- Design doc citations: docs/superpowers/specs/2026-06-28-gymsync-design.md
-- Flow 4 (:790-797), push table (:1176); docs/superpowers/specs/2026-07-18-
-- discover-leaderboards-design.md §2.
--
-- ── Fixtures ─────────────────────────────────────────────────────────────
-- start_attempt scenarios (routine_pub / routine_priv, "Test Murph RPC"):
--   frank    = session_s1 organizer+sole participant. Successfully starts an
--              attempt on routine_pub; a second identical call proves
--              double-start idempotency (same id, still 1 row).
--   stranger2 = never a participant of session_s1 — rejected.
--   session_s1b = frank's second session, isolates the private-routine
--              rejection test from session_s1's unique (session_id,user_id).
--   session_s1c (c006) = Finding 1 fixture: frank IS a participant, but the
--              session RUNS b003 ("Test Murph 2") while the RPC call
--              attempts b001 — proves the routine/session binding gate
--              rejects a mismatched pairing even though both routines are
--              public and frank is a genuine participant.
--   NOTE: c001/c002 now carry routine_id (b001/b002 respectively, matching
--   the routine each test attempts) — previously NULL, which the pre-fix
--   start_attempt never checked. Set to reflect Finding 1's new invariant so
--   the existing success/double-start/private-rejection tests still prove
--   what they always claimed to (a matching routine/session pairing).
--
-- Completion social-effects scenarios ("Test Murph 2", default_sort='time'):
--   dana  = group session (Leaderboard Crew, group_id set), opts in, finishes
--           in 2533s (42:13) -> first-ever entry for this routine, rank=1,
--           gets a system_leaderboard chat message, nobody passed yet.
--   erin  = SOLO session (group_id NULL), opts in, finishes FASTER (2000s)
--           -> takes rank=1, pushes dana to rank=2 -> dana gets exactly one
--           leaderboard_passed enqueue; erin's own solo session posts NO
--           chat message (no group to land one in).
--   gabe  = group session (same group), opts OUT, finishes fastest of all
--           (1000s) -> must get zero chat message, zero push, AND must not
--           appear in — or shift — dana/erin's ranks at all (opt-out never
--           enters the ranked window).
--   faye + gwen (Finding 2 fixture) = ONE group session (c007), BOTH opt in,
--           BOTH complete in the SAME batch (the leaderboard_recompute
--           trigger's FOR loop upserts both in one transaction, same
--           computed_at) — faye 2100s, gwen 2200s, both faster than
--           pre-existing dana (2533s) but slower than pre-existing erin
--           (2000s), so only dana is displaced. Proves: neither faye nor
--           gwen gets pushed about the other (same-batch siblings), and
--           dana gets EXACTLY ONE push — about gwen, her direct post-batch
--           neighbor — not about faye.
--   erin's second attempt (Finding 3 fixture, session c008, solo) = erin
--           attempts the SAME routine again, faster (1900s), landing
--           directly above her OWN older entry. leaderboard_rank_and_passed
--           still (correctly) reports that old entry as "passed" — it's a
--           genuinely pre-existing row — but the completion trigger must
--           not push erin a "someone passed you" about herself.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(27);

-- ============================================================
-- ── Fixtures: users, routines, sessions/participants, group ────────────────
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('c2000000-0000-0000-0000-00000000a001', 'ap-frank@t.com'),
  ('c2000000-0000-0000-0000-00000000a002', 'ap-stranger2@t.com'),
  ('c2000000-0000-0000-0000-00000000a003', 'ap-dana@t.com'),
  ('c2000000-0000-0000-0000-00000000a004', 'ap-erin@t.com'),
  ('c2000000-0000-0000-0000-00000000a005', 'ap-gabe@t.com');
INSERT INTO profiles (id, username) VALUES
  ('c2000000-0000-0000-0000-00000000a001', 'ap_frank'),
  ('c2000000-0000-0000-0000-00000000a002', 'ap_stranger2'),
  ('c2000000-0000-0000-0000-00000000a003', 'ap_dana'),
  ('c2000000-0000-0000-0000-00000000a004', 'ap_erin'),
  ('c2000000-0000-0000-0000-00000000a005', 'ap_gabe');

INSERT INTO routines (id, owner_id, name, visibility, default_sort) VALUES
  ('c2000000-0000-0000-0000-00000000b001', 'c2000000-0000-0000-0000-00000000a001',
   'Test Murph RPC', 'public', 'time'),
  ('c2000000-0000-0000-0000-00000000b002', 'c2000000-0000-0000-0000-00000000a001',
   'Test Murph Private', 'private', 'time'),
  ('c2000000-0000-0000-0000-00000000b003', 'c2000000-0000-0000-0000-00000000a003',
   'Test Murph 2', 'public', 'time');

INSERT INTO groups (id, name, created_by) VALUES
  ('c2000000-0000-0000-0000-00000000f001', 'Leaderboard Crew', 'c2000000-0000-0000-0000-00000000a003');
INSERT INTO group_members (group_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000f001', 'c2000000-0000-0000-0000-00000000a003'),
  ('c2000000-0000-0000-0000-00000000f001', 'c2000000-0000-0000-0000-00000000a005');

INSERT INTO sessions (id, organizer_id, state, started_at, routine_id) VALUES
  ('c2000000-0000-0000-0000-00000000c001', 'c2000000-0000-0000-0000-00000000a001', 'in_progress', now(),
   'c2000000-0000-0000-0000-00000000b001'),
  ('c2000000-0000-0000-0000-00000000c002', 'c2000000-0000-0000-0000-00000000a001', 'in_progress', now(),
   'c2000000-0000-0000-0000-00000000b002'),
  ('c2000000-0000-0000-0000-00000000c006', 'c2000000-0000-0000-0000-00000000a001', 'in_progress', now(),
   'c2000000-0000-0000-0000-00000000b003');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000c001', 'c2000000-0000-0000-0000-00000000a001'),
  ('c2000000-0000-0000-0000-00000000c002', 'c2000000-0000-0000-0000-00000000a001'),
  ('c2000000-0000-0000-0000-00000000c006', 'c2000000-0000-0000-0000-00000000a001');

-- Completion-scenario sessions: dana's is a GROUP session, erin's and gabe's
-- solo/group as described above.
INSERT INTO sessions (id, organizer_id, state, started_at, group_id) VALUES
  ('c2000000-0000-0000-0000-00000000c003', 'c2000000-0000-0000-0000-00000000a003',
   'in_progress', '2026-01-01 10:00:00+00', 'c2000000-0000-0000-0000-00000000f001'),
  ('c2000000-0000-0000-0000-00000000c005', 'c2000000-0000-0000-0000-00000000a005',
   'in_progress', '2026-01-01 10:00:00+00', 'c2000000-0000-0000-0000-00000000f001');
INSERT INTO sessions (id, organizer_id, state, started_at, group_id) VALUES
  ('c2000000-0000-0000-0000-00000000c004', 'c2000000-0000-0000-0000-00000000a004',
   'in_progress', '2026-01-01 10:00:00+00', NULL);
INSERT INTO session_participants (session_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000c003', 'c2000000-0000-0000-0000-00000000a003'),
  ('c2000000-0000-0000-0000-00000000c004', 'c2000000-0000-0000-0000-00000000a004'),
  ('c2000000-0000-0000-0000-00000000c005', 'c2000000-0000-0000-0000-00000000a005');

-- ============================================================
-- ── A. start_attempt RPC ────────────────────────────────────────────────────
-- ============================================================
SET LOCAL role authenticated;

-- frank: participant + public routine -> succeeds
SET LOCAL request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000a001';
SELECT results_eq(
  $$SELECT count(*)::int FROM (
      SELECT public.start_attempt('c2000000-0000-0000-0000-00000000b001',
        'c2000000-0000-0000-0000-00000000c001', true)) x$$,
  ARRAY[1],
  'frank: participant + public routine -> start_attempt succeeds (returns one row)'
);
SELECT results_eq(
  $$SELECT is_opt_in_leaderboard, is_complete, (started_at IS NOT NULL) FROM workout_attempts
    WHERE session_id = 'c2000000-0000-0000-0000-00000000c001'
      AND user_id = 'c2000000-0000-0000-0000-00000000a001'$$,
  $$VALUES (true, false, true)$$,
  'frank: attempt row created with is_opt_in_leaderboard=true, is_complete=false, started_at set'
);

-- double-start: same session/user, second call returns the SAME attempt id.
SELECT results_eq(
  $$SELECT (
      (SELECT public.start_attempt('c2000000-0000-0000-0000-00000000b001',
        'c2000000-0000-0000-0000-00000000c001', true))
      =
      (SELECT id FROM workout_attempts
        WHERE session_id = 'c2000000-0000-0000-0000-00000000c001'
          AND user_id = 'c2000000-0000-0000-0000-00000000a001')
    )$$,
  ARRAY[true],
  'frank: double-start on the same session returns the SAME attempt id'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM workout_attempts
    WHERE session_id = 'c2000000-0000-0000-0000-00000000c001'$$,
  ARRAY[1],
  'frank: double-start does not create a second workout_attempts row'
);

-- non-participant rejected
SET LOCAL request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000a002';
SELECT throws_ok(
  $$SELECT public.start_attempt('c2000000-0000-0000-0000-00000000b001',
      'c2000000-0000-0000-0000-00000000c001', true)$$,
  'P0001', 'must be a participant of the session to start an attempt',
  'stranger (non-participant): start_attempt rejected'
);

-- private routine rejected (frank IS a participant of c002, but the routine
-- is private) — isolated on a separate session so it doesn't collide with
-- session_s1's unique (session_id,user_id) row from the tests above.
SET LOCAL request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000a001';
SELECT throws_ok(
  $$SELECT public.start_attempt('c2000000-0000-0000-0000-00000000b002',
      'c2000000-0000-0000-0000-00000000c002', true)$$,
  'P0001', 'routine must be public to attempt from Discover',
  'frank: private routine rejected even though he IS a session participant'
);

-- Finding 1: routine/session binding gate. frank IS a participant of c006,
-- and b001 IS public — every OTHER gate would pass — but c006 actually runs
-- b003, not b001, so the mismatch must be rejected before visibility is
-- even considered (proves the binding check, not the visibility check, is
-- what's catching this).
SELECT throws_ok(
  $$SELECT public.start_attempt('c2000000-0000-0000-0000-00000000b001',
      'c2000000-0000-0000-0000-00000000c006', true)$$,
  'P0001', 'session must be running the attempted routine',
  'frank: mismatched routine rejected — session c006 runs b003, not the attempted b001'
);

SET LOCAL role postgres;

-- ============================================================
-- ── B. Completion social effects ────────────────────────────────────────────
-- ============================================================

INSERT INTO workout_attempts (id, routine_id, user_id, session_id, is_opt_in_leaderboard, started_at) VALUES
  ('c2000000-0000-0000-0000-00000000d003', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a003', 'c2000000-0000-0000-0000-00000000c003',
   true, '2026-01-01 10:00:00+00'),
  ('c2000000-0000-0000-0000-00000000d004', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a004', 'c2000000-0000-0000-0000-00000000c004',
   true, '2026-01-01 10:00:00+00'),
  ('c2000000-0000-0000-0000-00000000d005', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a005', 'c2000000-0000-0000-0000-00000000c005',
   false, '2026-01-01 10:00:00+00');

-- ── dana completes first (group session): 2533s = 42:13, first-ever entry
-- for this routine -> rank 1, group message posted, nobody passed yet.
UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 10:42:13+00'
  WHERE id = 'c2000000-0000-0000-0000-00000000c003';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_leaderboard' AND group_id = 'c2000000-0000-0000-0000-00000000f001'
      AND payload ->> 'user_id' = 'c2000000-0000-0000-0000-00000000a003'$$,
  ARRAY[1],
  'dana (group attempt): exactly one system_leaderboard chat message posted'
);
SELECT results_eq(
  $$SELECT body ~~ '%ap_dana%Test Murph 2%42:13%#1 globally%' FROM chat_messages
    WHERE kind = 'system_leaderboard' AND payload ->> 'user_id' = 'c2000000-0000-0000-0000-00000000a003'$$,
  ARRAY[true],
  'dana: chat message body carries username, routine name, formatted time, and rank #1'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed'$$,
  ARRAY[0],
  'dana: first-ever entry for this routine -> nobody passed, zero pushes enqueued'
);

-- ── gabe completes second (group session, OPT-OUT), fastest time of all
-- (1000s) -> must produce NO message, NO push, and must not disturb dana's
-- rank (opt-out never enters the ranked window at all).
UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 10:16:40+00'
  WHERE id = 'c2000000-0000-0000-0000-00000000c005';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_leaderboard' AND payload ->> 'user_id' = 'c2000000-0000-0000-0000-00000000a005'$$,
  ARRAY[0],
  'gabe (opt-out, group session): zero chat messages despite being in a group session'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue WHERE event = 'leaderboard_passed'$$,
  ARRAY[0],
  'gabe (opt-out): zero pushes enqueued — his faster time does not displace anyone'
);
SELECT results_eq(
  $$SELECT rnk FROM leaderboard_rank_and_passed('c2000000-0000-0000-0000-00000000d003')$$,
  ARRAY[1],
  'gabe (opt-out): dana''s rank is UNCHANGED at #1 — opt-out entries never enter the ranked window'
);

-- ── erin completes third (SOLO session, group_id NULL), opts in, finishes
-- FASTER than dana (2000s) -> takes rank 1, pushes dana to rank 2 -> dana
-- gets exactly one leaderboard_passed enqueue. Erin's own solo session posts
-- NO chat message (no group to land one in).
UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 10:33:20+00'
  WHERE id = 'c2000000-0000-0000-0000-00000000c004';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_leaderboard' AND payload ->> 'user_id' = 'c2000000-0000-0000-0000-00000000a004'$$,
  ARRAY[0],
  'erin (solo attempt, group_id NULL): zero chat messages — no group to land one in'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed'
      AND user_id = 'c2000000-0000-0000-0000-00000000a003'$$,
  ARRAY[1],
  'dana: erin''s faster attempt displaces her -> exactly ONE leaderboard_passed enqueue to dana'
);
SELECT results_eq(
  $$SELECT payload ->> 'passing_user_id', payload ->> 'new_rank' FROM push_queue
    WHERE event = 'leaderboard_passed' AND user_id = 'c2000000-0000-0000-0000-00000000a003'$$,
  $$VALUES ('c2000000-0000-0000-0000-00000000a004'::text, '1'::text)$$,
  'dana: leaderboard_passed payload names erin as the passer and her new rank (#1)'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed' AND user_id = 'c2000000-0000-0000-0000-00000000a004'$$,
  ARRAY[0],
  'erin: does NOT get a leaderboard_passed push about herself'
);
SELECT results_eq(
  $$SELECT rnk FROM leaderboard_rank_and_passed('c2000000-0000-0000-0000-00000000d004')$$,
  ARRAY[1],
  'erin: her own rank is #1 (fastest opt-in time)'
);
SELECT results_eq(
  $$SELECT rnk FROM leaderboard_rank_and_passed('c2000000-0000-0000-0000-00000000d003')$$,
  ARRAY[2],
  'dana: her rank shifts to #2 after erin''s faster attempt lands'
);

-- ============================================================
-- ── Finding 2: same-session multi-completion ("Attempt with Friends") ───────
-- ============================================================
-- faye + gwen, ONE group session (c007), BOTH opt in, BOTH complete in the
-- SAME batch: leaderboard_recompute_on_session_completion's own FOR loop
-- upserts both of their leaderboard_entries rows in one trigger firing (one
-- transaction => byte-identical computed_at for both). faye 2100s, gwen
-- 2200s — both faster (better rank) than pre-existing dana (2533s, rank 2
-- going in) but slower than pre-existing erin (2000s, rank 1) — so this
-- batch displaces ONLY dana, leaving erin's rank untouched, isolating the
-- assertion to exactly the scenario the finding describes.
INSERT INTO auth.users (id, email) VALUES
  ('c2000000-0000-0000-0000-00000000a006', 'ap-faye@t.com'),
  ('c2000000-0000-0000-0000-00000000a007', 'ap-gwen@t.com');
INSERT INTO profiles (id, username) VALUES
  ('c2000000-0000-0000-0000-00000000a006', 'ap_faye'),
  ('c2000000-0000-0000-0000-00000000a007', 'ap_gwen');
INSERT INTO group_members (group_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000f001', 'c2000000-0000-0000-0000-00000000a006'),
  ('c2000000-0000-0000-0000-00000000f001', 'c2000000-0000-0000-0000-00000000a007');
INSERT INTO sessions (id, organizer_id, state, started_at, group_id) VALUES
  ('c2000000-0000-0000-0000-00000000c007', 'c2000000-0000-0000-0000-00000000a006',
   'in_progress', '2026-01-01 10:00:00+00', 'c2000000-0000-0000-0000-00000000f001');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000c007', 'c2000000-0000-0000-0000-00000000a006'),
  ('c2000000-0000-0000-0000-00000000c007', 'c2000000-0000-0000-0000-00000000a007');
-- Per-attempt started_at varies (not completed_at, which is shared by the
-- whole session) to produce different elapsed times from ONE shared
-- completion timestamp: 11:00:00 - 10:25:00 = 2100s (faye), 11:00:00 -
-- 10:23:20 = 2200s (gwen).
INSERT INTO workout_attempts (id, routine_id, user_id, session_id, is_opt_in_leaderboard, started_at) VALUES
  ('c2000000-0000-0000-0000-00000000d006', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a006', 'c2000000-0000-0000-0000-00000000c007',
   true, '2026-01-01 10:25:00+00'),
  ('c2000000-0000-0000-0000-00000000d007', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a007', 'c2000000-0000-0000-0000-00000000c007',
   true, '2026-01-01 10:23:20+00');

UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 11:00:00+00'
  WHERE id = 'c2000000-0000-0000-0000-00000000c007';

SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed' AND user_id = 'c2000000-0000-0000-0000-00000000a003'
      AND payload ->> 'passing_user_id' IN ('c2000000-0000-0000-0000-00000000a006',
                                             'c2000000-0000-0000-0000-00000000a007')$$,
  ARRAY[1],
  'dana: same-session batch of faye+gwen displaces her -> EXACTLY ONE leaderboard_passed enqueue (not one per new entrant)'
);
SELECT results_eq(
  $$SELECT payload ->> 'passing_user_id', payload ->> 'new_rank' FROM push_queue
    WHERE event = 'leaderboard_passed' AND user_id = 'c2000000-0000-0000-0000-00000000a003'
      AND payload ->> 'passing_user_id' IN ('c2000000-0000-0000-0000-00000000a006',
                                             'c2000000-0000-0000-0000-00000000a007')$$,
  $$VALUES ('c2000000-0000-0000-0000-00000000a007'::text, '3'::text)$$,
  'dana: the one push names gwen (her DIRECT post-batch neighbor, rank 3) — not faye, who is not adjacent to her'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed'
      AND user_id IN ('c2000000-0000-0000-0000-00000000a006', 'c2000000-0000-0000-0000-00000000a007')$$,
  ARRAY[0],
  'faye and gwen: zero leaderboard_passed pushes to either — same-batch siblings never notify each other'
);

-- ============================================================
-- ── Finding 3: self-passing push ────────────────────────────────────────────
-- ============================================================
-- erin attempts the SAME routine a second time (session c008, solo), faster
-- (1900s) than her own earlier entry (2000s, still rank-adjacent — nothing
-- else sits between them). Her old entry is a genuinely PRE-EXISTING row
-- (computed_at from an earlier transaction), so leaderboard_rank_and_passed
-- correctly still reports it as "passed" — Finding 2's batch-cutoff fix does
-- NOT (and should not) suppress it. Only Finding 3's acting-user exclusion
-- in the trigger stops the resulting push from firing.
INSERT INTO sessions (id, organizer_id, state, started_at, group_id) VALUES
  ('c2000000-0000-0000-0000-00000000c008', 'c2000000-0000-0000-0000-00000000a004',
   'in_progress', '2026-01-01 12:00:00+00', NULL);
INSERT INTO session_participants (session_id, user_id) VALUES
  ('c2000000-0000-0000-0000-00000000c008', 'c2000000-0000-0000-0000-00000000a004');
INSERT INTO workout_attempts (id, routine_id, user_id, session_id, is_opt_in_leaderboard, started_at) VALUES
  ('c2000000-0000-0000-0000-00000000d008', 'c2000000-0000-0000-0000-00000000b003',
   'c2000000-0000-0000-0000-00000000a004', 'c2000000-0000-0000-0000-00000000c008',
   true, '2026-01-01 12:00:00+00');

UPDATE sessions SET state = 'completed', completed_at = '2026-01-01 12:31:40+00'
  WHERE id = 'c2000000-0000-0000-0000-00000000c008';

SELECT results_eq(
  $$SELECT rnk, passed_user_id FROM leaderboard_rank_and_passed('c2000000-0000-0000-0000-00000000d008')$$,
  $$VALUES (1, 'c2000000-0000-0000-0000-00000000a004'::uuid)$$,
  'erin: her new faster attempt DOES rank above, and DOES identify, her own older entry as "passed" at the ranking layer'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'leaderboard_passed' AND payload ->> 'attempt_id' = 'c2000000-0000-0000-0000-00000000d008'$$,
  ARRAY[0],
  'erin: despite the ranking layer identifying a passed_user, the trigger''s acting-user guard enqueues ZERO pushes for self-passing'
);

-- ============================================================
-- ── C. Security: internal helper is not a client RPC ────────────────────────
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000a003';
SELECT throws_ok(
  $$SELECT * FROM public.leaderboard_rank_and_passed('c2000000-0000-0000-0000-00000000d003')$$,
  '42501', NULL,
  'clients cannot call leaderboard_rank_and_passed directly'
);
SET LOCAL role postgres;

-- ============================================================
-- ── D. payloads.ts / notification_prefs plumbing already reserved (Task 2
--      only verifies — no schema change was needed, see migration header) ──
-- ============================================================
SELECT results_eq(
  $$SELECT public.push_event_category('leaderboard_passed')$$,
  $$VALUES ('leaderboard_passed'::text)$$,
  'push_event_category maps leaderboard_passed -> leaderboard_passed (reserved since 3d, unchanged)'
);
-- Name-agnostic since 20260824000003 dropped the stale original
-- chat_messages_kind_check (it predated coach_reply and, coexisting
-- with _v3, double-constrained the column): whatever kind CHECK
-- constraint(s) live on chat_messages, every one must allow
-- system_leaderboard.
SELECT results_eq(
  $$SELECT bool_and(pg_get_constraintdef(oid) LIKE '%system_leaderboard%')
    FROM pg_constraint
    WHERE conrelid = 'public.chat_messages'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%kind%'$$,
  ARRAY[true],
  'every live kind CHECK constraint on chat_messages includes system_leaderboard (reserved since chat''s original CREATE TABLE)'
);

SELECT * FROM finish();
ROLLBACK;
