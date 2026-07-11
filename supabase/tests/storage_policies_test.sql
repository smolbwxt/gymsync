BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a5', 'sta@t.com'),
  ('00000000-0000-0000-0000-0000000000c5', 'stc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a5', 'st_user_a'),
  ('00000000-0000-0000-0000-0000000000c5', 'st_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Storage Crew',
   '00000000-0000-0000-0000-0000000000a5');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a5', 'admin');

-- Buckets exist
SELECT results_eq(
  $$SELECT count(*)::int FROM storage.buckets WHERE id IN ('chat-images','avatars')$$,
  ARRAY[2], 'both buckets exist');
SELECT results_eq(
  $$SELECT public::int FROM storage.buckets WHERE id='avatars'$$,
  ARRAY[1], 'avatars bucket is public');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a5';

-- Positive: member uploads a chat image under their group's folder
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-images', 'a0000000-0000-0000-0000-000000000001/msg1.jpg',
     '00000000-0000-0000-0000-0000000000a5')$$,
  'member uploads chat image to own group folder');

-- Positive: admin uploads the group avatar
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/a0000000-0000-0000-0000-000000000001.jpg',
     '00000000-0000-0000-0000-0000000000a5')$$,
  'admin uploads group avatar');

-- Positive: member can insert an image chat message (kind now allowed)
SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, storage_path) VALUES
    ('a0000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a5', 'image',
     'a0000000-0000-0000-0000-000000000001/msg1.jpg')$$,
  'member sends image message');

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c5';

-- Negative: outsider cannot upload into that group's chat-images folder (42501)
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-images', 'a0000000-0000-0000-0000-000000000001/hack.jpg',
     '00000000-0000-0000-0000-0000000000c5')$$,
  '42501', NULL, 'outsider cannot upload to group folder');

-- Negative: non-admin cannot overwrite the group avatar (42501)
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/a0000000-0000-0000-0000-000000000001.jpg',
     '00000000-0000-0000-0000-0000000000c5')$$,
  '42501', NULL, 'non-admin cannot upload group avatar');

SELECT * FROM finish();
ROLLBACK;
