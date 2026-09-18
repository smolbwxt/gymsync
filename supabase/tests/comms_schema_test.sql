BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- plan(12) -> plan(10), 2026-09-18: assertions 5 and 6 read and wrote
-- soundboard_sounds, which 20260913000104_soundboard_drop.sql drops (plan
-- task D5, decision 5). scripts/run_pgtap.js runs every file in this
-- directory against the LIVE database, so a suite that touches a dropped
-- table aborts its whole transaction, not one assertion. The surviving
-- assertions KEEP their historical numbers (1-4, 7-12) rather than being
-- renumbered — the plan() count is what pgTAP checks; the labels are
-- history.
--
-- Three things this file still proves that LOOK like soundboard and are
-- deliberately kept: assertions 3 and 12 exercise chat_messages.kind =
-- 'soundboard_echo', whose CHECK D5 does not narrow (shipped chat history
-- holds that kind), and assertion 9 asserts the 'soundboard' storage bucket
-- is public, which D5 does not drop either — the objects under it are
-- removed by hand afterwards, the bucket and its read policy stay.

-- ── Fixtures ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000ca1', 'csa@t.com'),
  ('00000000-0000-0000-0000-000000000ca2', 'csb@t.com'),
  ('00000000-0000-0000-0000-000000000ca3', 'csc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000ca1', 'cs_user_a'),
  ('00000000-0000-0000-0000-000000000ca2', 'cs_user_b'),
  ('00000000-0000-0000-0000-000000000ca3', 'cs_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'Comms Crew',
   '00000000-0000-0000-0000-000000000ca1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000ca1', 'admin'),
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000ca2', 'member');

-- ── 1. Member sends audio message with storage_path (lives_ok) ────────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca1';

SELECT lives_ok(
  $$INSERT INTO chat_messages
      (id, group_id, author_id, kind, body, storage_path) VALUES
      ('c1000000-0000-0000-0000-000000000001',
       'b1000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-000000000ca1',
       'audio', '0:05',
       'b1000000-0000-0000-0000-000000000001/c1000000-0000-0000-0000-000000000001.m4a')$$,
  'member can send audio message with storage_path'
);

-- ── 2. Audio without storage_path rejected (42501) ────────────────────────────
SELECT throws_ok(
  $$INSERT INTO chat_messages
      (group_id, author_id, kind, body) VALUES
      ('b1000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-000000000ca1',
       'audio', '0:05')$$,
  '42501', NULL,
  'audio without storage_path rejected'
);

-- ── 3. Member inserts soundboard_echo with payload (lives_ok) ─────────────────
SELECT lives_ok(
  $$INSERT INTO chat_messages
      (group_id, author_id, kind, body, payload) VALUES
      ('b1000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-000000000ca1',
       'soundboard_echo', '🔊 airhorn',
       '{"sound_slug":"airhorn"}')$$,
  'member can insert soundboard_echo with payload'
);

-- ── 4. Outsider audio rejected (42501) ───────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca3';

SELECT throws_ok(
  $$INSERT INTO chat_messages
      (group_id, author_id, kind, body, storage_path) VALUES
      ('b1000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-000000000ca3',
       'audio', '0:05',
       'b1000000-0000-0000-0000-000000000001/outsider.m4a')$$,
  '42501', NULL,
  'outsider audio message rejected'
);

-- ── 5-6 RETIRED (20260913000104_soundboard_drop.sql) ─────────────────────────
-- They proved that any authenticated user could read the soundboard_sounds
-- catalog and that no client could insert into it (the curator path was
-- scripts/add_sound.js, deleted with the drop). The table is gone; the
-- role state they left behind is not needed by what follows — assertion 7
-- sets its own claim, and `role authenticated` has been in effect since
-- assertion 1.

-- ── 7. chat-audio outsider upload rejected (42501) ───────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca3';

SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-audio',
     'b1000000-0000-0000-0000-000000000001/outsider.m4a',
     '00000000-0000-0000-0000-000000000ca3')$$,
  '42501', NULL,
  'outsider cannot upload to chat-audio bucket'
);

-- ── 8. Member upload to chat-audio allowed ───────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca1';

SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-audio',
     'b1000000-0000-0000-0000-000000000001/c1000000-0000-0000-0000-000000000001.m4a',
     '00000000-0000-0000-0000-000000000ca1')$$,
  'member can upload to chat-audio bucket'
);

-- ── 9. soundboard bucket exists and is public ─────────────────────────────────
-- storage.buckets is superuser-accessible; switch to postgres role for these checks.
SET LOCAL role postgres;

SELECT results_eq(
  $$SELECT public::int FROM storage.buckets WHERE id = 'soundboard'$$,
  ARRAY[1],
  'soundboard bucket is public'
);

-- ── 10. chat-audio bucket exists and is private ───────────────────────────────
SELECT results_eq(
  $$SELECT public::int FROM storage.buckets WHERE id = 'chat-audio'$$,
  ARRAY[0],
  'chat-audio bucket is private'
);

-- ── 11. System kinds still blocked for clients ────────────────────────────────
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca1';

SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('b1000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000ca1',
     'system_pr', 'fake')$$,
  '42501', NULL,
  'client cannot insert system_pr (regression)'
);

-- ── 12. soundboard_echo without payload rejected (42501) ──────────────────────
SELECT throws_ok(
  $$INSERT INTO chat_messages
      (group_id, author_id, kind, body) VALUES
      ('b1000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-000000000ca1',
       'soundboard_echo', '🔊 ding')$$,
  '42501', NULL,
  'soundboard_echo without payload rejected'
);

SELECT * FROM finish();
ROLLBACK;
