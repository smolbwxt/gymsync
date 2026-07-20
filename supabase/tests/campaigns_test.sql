BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(36);

-- ============================================================
-- campaigns / campaign_participants / campaign_progress — Phase C Task 1
-- (20260728000001_campaigns_schema.sql, 20260728000002_campaign_progress_
-- trigger.sql)
-- Design doc: Flow 8 (docs/superpowers/specs/2026-06-28-gymsync-design.md:
-- 862-884), schema (:581-614), RLS (:669-671).
--
-- ── Fixtures ──────────────────────────────────────────────────────────────
-- Campaign A (non-draft, active window, individual_target={"sessions":2},
--   curated_routine_ids=[routine_A]). Participants: alice, bob, dave, erin,
--   frank. Carol is deliberately NOT a participant.
--   alice: TWO qualifying completions (routine_A, ready, in-window) ->
--     crosses the sessions=2 target on the 2nd -> completion chat message.
--   bob:   ONE qualifying completion -> 1/2, no completion message yet.
--   carol: completes routine_A but is NOT a campaign_participant -> gate
--     (b) excludes her -> zero campaign_progress row.
--   dave:  IS a participant but completes a non-curated routine (routine_
--     dave) -> gate (a) excludes him -> zero campaign_progress row.
--   erin:  IS a participant, completes routine_A, but completed_at is
--     BEFORE the campaign's starts_at -> window gate excludes her -> zero
--     campaign_progress row.
--   frank: IS a participant, completes routine_A in-window, but his
--     session_participants row is 'no_show' (not 'ready') at completion ->
--     readiness gate excludes him -> zero campaign_progress row.
-- Campaign B (DRAFT, individual_target={"workouts_completed":1},
--   curated_routine_ids=[routine_B]). Sole participant: grace. Grace has
--   NO group memberships -- proves a completion crossing with zero groups
--   silently produces zero chat rows (not an error).
-- Campaign E (non-draft, individual_target=NULL,
--   curated_routine_ids=[routine_E]). Sole participant: karen -- proves a
--   NULL individual_target never raises and never sends a completion
--   message, even though progress still accrues normally.
-- henry: stranger to every campaign (RLS negative reads, aggregate-gate
--   negative).
-- iris:  join/leave RLS positive fixture (joins/leaves Campaign A live).
-- jack:  join-spoof negative-test target (never actually joins anything).
-- "Camp Test Crew": group containing only alice -- backs the completion
--   chat-message fan-out assertion.
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
  ('ca000000-0000-0000-0000-0000000000a1', 'camp_alice@t.com'),
  ('ca000000-0000-0000-0000-0000000000a2', 'camp_bob@t.com'),
  ('ca000000-0000-0000-0000-0000000000a3', 'camp_carol@t.com'),
  ('ca000000-0000-0000-0000-0000000000a4', 'camp_dave@t.com'),
  ('ca000000-0000-0000-0000-0000000000a5', 'camp_erin@t.com'),
  ('ca000000-0000-0000-0000-0000000000a6', 'camp_frank@t.com'),
  ('ca000000-0000-0000-0000-0000000000a7', 'camp_grace@t.com'),
  ('ca000000-0000-0000-0000-0000000000a8', 'camp_henry@t.com'),
  ('ca000000-0000-0000-0000-0000000000a9', 'camp_iris@t.com'),
  ('ca000000-0000-0000-0000-0000000000aa', 'camp_jack@t.com'),
  ('ca000000-0000-0000-0000-0000000000ab', 'camp_karen@t.com');
INSERT INTO profiles (id, username) VALUES
  ('ca000000-0000-0000-0000-0000000000a1', 'ca_alice'),
  ('ca000000-0000-0000-0000-0000000000a2', 'ca_bob'),
  ('ca000000-0000-0000-0000-0000000000a3', 'ca_carol'),
  ('ca000000-0000-0000-0000-0000000000a4', 'ca_dave'),
  ('ca000000-0000-0000-0000-0000000000a5', 'ca_erin'),
  ('ca000000-0000-0000-0000-0000000000a6', 'ca_frank'),
  ('ca000000-0000-0000-0000-0000000000a7', 'ca_grace'),
  ('ca000000-0000-0000-0000-0000000000a8', 'ca_henry'),
  ('ca000000-0000-0000-0000-0000000000a9', 'ca_iris'),
  ('ca000000-0000-0000-0000-0000000000aa', 'ca_jack'),
  ('ca000000-0000-0000-0000-0000000000ab', 'ca_karen');

INSERT INTO groups (id, name, created_by) VALUES
  ('cf000000-0000-0000-0000-000000000001', 'Camp Test Crew', 'ca000000-0000-0000-0000-0000000000a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('cf000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1', 'admin');

-- Routines: routine_A (curated by A), routine_dave (curated by nobody),
-- routine_B (curated by B), routine_E (curated by E).
INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('cd000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1', 'Campaign A Routine', 'private'),
  ('cd000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-0000000000a4', 'Uncurated Routine', 'private'),
  ('cd000000-0000-0000-0000-000000000003', 'ca000000-0000-0000-0000-0000000000a7', 'Campaign B Routine', 'private'),
  ('cd000000-0000-0000-0000-000000000004', 'ca000000-0000-0000-0000-0000000000ab', 'Campaign E Routine', 'private');

-- Campaign A: active window, sessions=2 target.
INSERT INTO campaigns (id, name, description, starts_at, ends_at, individual_target, curated_routine_ids, is_draft) VALUES
  ('cb000000-0000-0000-0000-000000000001', 'Test Campaign A', 'pgTAP fixture',
   now() - interval '2 days', now() + interval '2 days',
   '{"sessions":2}'::jsonb, ARRAY['cd000000-0000-0000-0000-000000000001']::uuid[], false);
-- Campaign B: DRAFT, workouts_completed=1 target.
INSERT INTO campaigns (id, name, description, starts_at, ends_at, individual_target, curated_routine_ids, is_draft) VALUES
  ('cb000000-0000-0000-0000-000000000002', 'Test Campaign B (draft)', 'pgTAP fixture — isolation',
   now() - interval '2 days', now() + interval '2 days',
   '{"workouts_completed":1}'::jsonb, ARRAY['cd000000-0000-0000-0000-000000000003']::uuid[], true);
-- Campaign E: non-draft, NULL individual_target.
INSERT INTO campaigns (id, name, description, starts_at, ends_at, individual_target, curated_routine_ids, is_draft) VALUES
  ('cb000000-0000-0000-0000-000000000003', 'Test Campaign E (no target)', 'pgTAP fixture — null target',
   now() - interval '2 days', now() + interval '2 days',
   NULL, ARRAY['cd000000-0000-0000-0000-000000000004']::uuid[], false);

INSERT INTO campaign_participants (campaign_id, user_id) VALUES
  ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1'), -- alice
  ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a2'), -- bob
  ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a4'), -- dave
  ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a5'), -- erin
  ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a6'), -- frank
  ('cb000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-0000000000a7'), -- grace (draft)
  ('cb000000-0000-0000-0000-000000000003', 'ca000000-0000-0000-0000-0000000000ab'); -- karen


-- ============================================================
-- Alice: session 1 -> 1/2. session 2 -> 2/2, crosses target.
-- ============================================================
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '50 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1', 'ready', now() - interval '48 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), 'ca000000-0000-0000-0000-0000000000a1',
       'ce000000-0000-0000-0000-000000000001', ex.id, 1, 5, 100, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
UPDATE sessions SET state = 'completed', completed_at = now() - interval '10 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000001';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a1'$$,
  $$VALUES (1, 1, 500.00::numeric)$$,
  'alice: 1st qualifying completion -> 1/2, volume 500'
);

INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-0000000000a1',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '40 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-0000000000a1', 'ready', now() - interval '38 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), 'ca000000-0000-0000-0000-0000000000a1',
       'ce000000-0000-0000-0000-000000000002', ex.id, 1, 10, 50, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
UPDATE sessions SET state = 'completed', completed_at = now() - interval '5 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000002';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a1'$$,
  $$VALUES (2, 2, 1000.00::numeric)$$,
  'alice: 2nd qualifying completion -> 2/2, volume 1000, crosses individual_target'
);

-- Idempotency: re-asserting state='completed' (same value) must not
-- double-increment (same OLD/NEW state-diff guard as streaks/leaderboard).
UPDATE sessions SET state = 'completed', completed_at = now()
  WHERE id = 'ce000000-0000-0000-0000-000000000002';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a1'$$,
  $$VALUES (2, 2, 1000.00::numeric)$$,
  'alice: re-asserting state=completed (same value) does not double-increment'
);


-- ============================================================
-- Bob: one qualifying completion -> 1/2, no completion message.
-- ============================================================
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000003', 'ca000000-0000-0000-0000-0000000000a2',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '30 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000003', 'ca000000-0000-0000-0000-0000000000a2', 'ready', now() - interval '28 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), 'ca000000-0000-0000-0000-0000000000a2',
       'ce000000-0000-0000-0000-000000000003', ex.id, 1, 2, 225, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
UPDATE sessions SET state = 'completed', completed_at = now() - interval '5 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000003';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a2'$$,
  $$VALUES (1, 1, 450.00::numeric)$$,
  'bob: 1 qualifying completion -> 1/2, volume 450'
);


-- ============================================================
-- Gate isolation: carol (not a participant), dave (wrong routine),
-- erin (outside window), frank (not ready) -- each excluded by exactly
-- one gate, zero campaign_progress row created for any of them.
-- ============================================================

-- Carol: completes routine_A but never joined Campaign A.
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000004', 'ca000000-0000-0000-0000-0000000000a3',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000004', 'ca000000-0000-0000-0000-0000000000a3', 'ready', now() - interval '18 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000004';

SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a3'$$,
  ARRAY[0], 'carol: not a participant -> gate (b) excludes her, zero progress row'
);

-- Dave: is a participant, but his routine isn't curated by Campaign A.
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000005', 'ca000000-0000-0000-0000-0000000000a4',
   'cd000000-0000-0000-0000-000000000002', 'in_progress', now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000005', 'ca000000-0000-0000-0000-0000000000a4', 'ready', now() - interval '18 minutes');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000005';

SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a4'$$,
  ARRAY[0], 'dave: non-curated routine -> gate (a) excludes him, zero progress row'
);

-- Erin: is a participant, curated routine, but completes BEFORE starts_at.
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000006', 'ca000000-0000-0000-0000-0000000000a5',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '6 days');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000006', 'ca000000-0000-0000-0000-0000000000a5', 'ready', now() - interval '6 days');
UPDATE sessions SET state = 'completed', completed_at = now() - interval '5 days'
  WHERE id = 'ce000000-0000-0000-0000-000000000006';

SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a5'$$,
  ARRAY[0], 'erin: completed before starts_at -> window gate excludes her, zero progress row'
);

-- Frank: is a participant, curated routine, in-window, but never ready.
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000007', 'ca000000-0000-0000-0000-0000000000a6',
   'cd000000-0000-0000-0000-000000000001', 'in_progress', now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000007', 'ca000000-0000-0000-0000-0000000000a6', 'no_show', NULL);
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000007';

SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a6'$$,
  ARRAY[0], 'frank: no_show at completion -> readiness gate excludes him, zero progress row'
);


-- ============================================================
-- Grace: draft Campaign B, workouts_completed=1 target, crosses on her
-- only completion. She belongs to zero groups -- the fan-out INSERT must
-- silently produce zero rows, not error.
-- ============================================================
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000008', 'ca000000-0000-0000-0000-0000000000a7',
   'cd000000-0000-0000-0000-000000000003', 'in_progress', now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000008', 'ca000000-0000-0000-0000-0000000000a7', 'ready', now() - interval '18 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), 'ca000000-0000-0000-0000-0000000000a7',
       'ce000000-0000-0000-0000-000000000008', ex.id, 1, 6, 80, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000008';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000002' AND user_id = 'ca000000-0000-0000-0000-0000000000a7'$$,
  $$VALUES (1, 1, 480.00::numeric)$$,
  'grace: draft campaign, 1/1 crosses workouts_completed target, progress still accrues normally'
);


-- ============================================================
-- Karen: Campaign E has NULL individual_target -- progress accrues but no
-- completion message is ever attempted, no error raised.
-- ============================================================
INSERT INTO sessions (id, organizer_id, routine_id, state, started_at) VALUES
  ('ce000000-0000-0000-0000-000000000009', 'ca000000-0000-0000-0000-0000000000ab',
   'cd000000-0000-0000-0000-000000000004', 'in_progress', now() - interval '20 minutes');
INSERT INTO session_participants (session_id, user_id, check_in_state, check_in_at) VALUES
  ('ce000000-0000-0000-0000-000000000009', 'ca000000-0000-0000-0000-0000000000ab', 'ready', now() - interval '18 minutes');
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight, is_penalty, is_failed)
SELECT gen_random_uuid(), 'ca000000-0000-0000-0000-0000000000ab',
       'ce000000-0000-0000-0000-000000000009', ex.id, 1, 1, 999, false, false
  FROM (SELECT id FROM exercises WHERE slug = 'bench-press' LIMIT 1) ex;
UPDATE sessions SET state = 'completed', completed_at = now() - interval '2 minutes'
  WHERE id = 'ce000000-0000-0000-0000-000000000009';

SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted FROM campaign_progress
    WHERE campaign_id = 'cb000000-0000-0000-0000-000000000003' AND user_id = 'ca000000-0000-0000-0000-0000000000ab'$$,
  $$VALUES (1, 1, 999.00::numeric)$$,
  'karen: NULL individual_target -- progress still accrues normally'
);


-- ============================================================
-- Completion chat message: fires exactly once, only for alice's crossing.
-- ============================================================
SELECT results_eq(
  $$SELECT kind, body, (payload->>'target')::int, (payload->>'value')::int
    FROM chat_messages
    WHERE kind = 'system_campaign' AND payload->>'user_id' = 'ca000000-0000-0000-0000-0000000000a1'$$,
  $$VALUES ('system_campaign'::text,
            '🌊 ca_alice just completed Test Campaign A — 2/2 sessions!'::text,
            2, 2)$$,
  'alice crossing individual_target inserts correct system_campaign chat message, fanned into her group'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_campaign' AND payload->>'user_id' = 'ca000000-0000-0000-0000-0000000000a2'$$,
  ARRAY[0], 'bob: 1/2, has not crossed -- no completion message'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE kind = 'system_campaign' AND payload->>'user_id' = 'ca000000-0000-0000-0000-0000000000ab'$$,
  ARRAY[0], 'karen: NULL individual_target -- no completion message ever attempted'
);

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE kind = 'system_campaign'$$,
  ARRAY[1],
  'exactly one system_campaign message total -- grace''s crossing (zero groups) produced zero chat rows, no error'
);


-- ============================================================
-- campaign_community_progress() — the community-bar aggregate RPC.
-- ============================================================
SET LOCAL role authenticated;

-- Campaign A is non-draft: any authenticated user (even a stranger who
-- never joined) can read the aggregate. Sum across alice(2,2,1000) +
-- bob(1,1,450) = (3,3,1450); carol/dave/erin/frank contribute zero (no
-- progress row exists for any of them).
SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a8'; -- henry, stranger
SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted
    FROM public.campaign_community_progress('cb000000-0000-0000-0000-000000000001')$$,
  $$VALUES (3::bigint, 3::bigint, 1450.00::numeric)$$,
  'campaign_community_progress: non-draft campaign readable by a stranger, correct aggregate'
);

-- Campaign B is draft: henry (non-participant) is rejected.
SELECT throws_ok(
  $$SELECT * FROM public.campaign_community_progress('cb000000-0000-0000-0000-000000000002')$$,
  'P0001', 'campaign not found',
  'campaign_community_progress: draft campaign rejects a non-participant stranger'
);

-- Campaign B, queried by its own participant (grace): succeeds.
SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a7'; -- grace
SELECT results_eq(
  $$SELECT sessions_completed, workouts_completed, volume_lifted
    FROM public.campaign_community_progress('cb000000-0000-0000-0000-000000000002')$$,
  $$VALUES (1::bigint, 1::bigint, 480.00::numeric)$$,
  'campaign_community_progress: draft campaign readable by its own participant'
);


-- ============================================================
-- RLS: campaigns — global read unless draft; no client writes at all.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a8'; -- henry, stranger to everything
SELECT results_eq(
  $$SELECT count(*)::int FROM campaigns WHERE id = 'cb000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'stranger can read a non-draft campaign (global read)'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM campaigns WHERE id = 'cb000000-0000-0000-0000-000000000002'$$,
  ARRAY[0], 'stranger cannot read a draft campaign'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a7'; -- grace, participant of B
SELECT results_eq(
  $$SELECT count(*)::int FROM campaigns WHERE id = 'cb000000-0000-0000-0000-000000000002'$$,
  ARRAY[1], 'a draft campaign''s own participant CAN read it -- Task 3 isolation mechanism'
);

SELECT throws_ok(
  $$INSERT INTO campaigns (name, starts_at, ends_at) VALUES ('hax', now(), now() + interval '1 day')$$,
  '42501', NULL, 'client cannot INSERT into campaigns (no INSERT policy exists -- v1 team curation is service-role only)'
);
SELECT results_eq(
  $$WITH upd AS (
      UPDATE campaigns SET name = 'hax' WHERE id = 'cb000000-0000-0000-0000-000000000001'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'client cannot UPDATE campaigns (no UPDATE policy exists)'
);
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM campaigns WHERE id = 'cb000000-0000-0000-0000-000000000001'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0], 'client cannot DELETE campaigns (no DELETE policy exists)'
);


-- ============================================================
-- RLS: campaign_participants — participants read the roster; owner-scoped
-- join/leave; no UPDATE at all.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a1'; -- alice, participant of A
SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_participants WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001'$$,
  ARRAY[5], 'campaign participant can read the full roster (alice/bob/dave/erin/frank)'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a8'; -- henry, non-participant
SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_participants WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'non-participant cannot read the roster'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a9'; -- iris
SELECT lives_ok(
  $$INSERT INTO campaign_participants (campaign_id, user_id) VALUES
    ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a9')$$,
  'iris can join Campaign A as herself'
);
SELECT throws_ok(
  $$INSERT INTO campaign_participants (campaign_id, user_id) VALUES
    ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000aa')$$,
  '42501', NULL, 'iris cannot join Campaign A on jack''s behalf'
);
SELECT results_eq(
  $$WITH upd AS (
      UPDATE campaign_participants SET joined_at = now()
      WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a9'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'client cannot UPDATE campaign_participants (no UPDATE policy exists)'
);
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM campaign_participants
      WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a9'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1], 'iris can leave Campaign A (delete her own row)'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a1'; -- alice
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM campaign_participants
      WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a2'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0], 'alice cannot remove bob from Campaign A (owner-scoped DELETE only)'
);


-- ============================================================
-- RLS: campaign_progress — participants read; trigger-only writes.
-- ============================================================
SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a1'; -- alice
SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001'$$,
  ARRAY[2], 'campaign participant reads exactly the 2 rows that accrued (alice, bob)'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a8'; -- henry, non-participant
SELECT results_eq(
  $$SELECT count(*)::int FROM campaign_progress WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001'$$,
  ARRAY[0], 'non-participant reads zero campaign_progress rows'
);

SET LOCAL request.jwt.claim.sub = 'ca000000-0000-0000-0000-0000000000a1'; -- alice
SELECT throws_ok(
  $$INSERT INTO campaign_progress (campaign_id, user_id, sessions_completed) VALUES
    ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1', 999)$$,
  '42501', NULL, 'client cannot INSERT into campaign_progress (trigger-only writes)'
);
SELECT results_eq(
  $$WITH upd AS (
      UPDATE campaign_progress SET sessions_completed = 999
      WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a1'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'client (even the owner) cannot UPDATE campaign_progress directly'
);
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM campaign_progress
      WHERE campaign_id = 'cb000000-0000-0000-0000-000000000001' AND user_id = 'ca000000-0000-0000-0000-0000000000a1'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0], 'client (even the owner) cannot DELETE campaign_progress directly'
);


-- ============================================================
-- chat_messages.kind CHECK still enforces after the NOT VALID+VALIDATE
-- extension -- an unrecognized kind is still rejected. Tested as the table
-- owner (bypassing RLS): the client-facing INSERT policy's own kind
-- allow-list ('text','image','audio','soundboard_echo') is already a
-- STRICT SUBSET of the table CHECK's allow-list, so an authenticated
-- client can never reach the CHECK's rejection path for `kind` at all --
-- RLS's 42501 always fires first for any kind a client could try. Only a
-- DEFINER-privileged/owner write (exactly how the trigger itself writes
-- 'system_campaign') can actually exercise the CHECK constraint's own
-- enforcement, which is what this assertion needs to isolate.
-- ============================================================
SET LOCAL role postgres;

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('cf000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-0000000000a1', 'bogus_kind', 'nope')$$,
  '23514', NULL, 'chat_messages.kind CHECK still rejects an unrecognized kind after the extension'
);

SELECT * FROM finish();
ROLLBACK;
