BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

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

-- ── 5. soundboard_sounds: authenticated read allowed ─────────────────────────
-- Seed a row as superuser first
SET LOCAL role postgres;
INSERT INTO soundboard_sounds (id, slug, display_name, storage_path, duration_ms)
VALUES ('d0000000-0000-0000-0000-000000000001', 'airhorn', 'Air Horn', 'airhorn.wav', 1200);

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000ca1';

SELECT results_eq(
  $$SELECT count(*)::int FROM soundboard_sounds$$,
  ARRAY[1],
  'authenticated user can read soundboard_sounds'
);

-- ── 6. soundboard_sounds: client INSERT rejected (42501) ──────────────────────
SELECT throws_ok(
  $$INSERT INTO soundboard_sounds (slug, display_name, storage_path)
    VALUES ('boo', 'Boo', 'boo.wav')$$,
  '42501', NULL,
  'client cannot insert into soundboard_sounds'
);

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
