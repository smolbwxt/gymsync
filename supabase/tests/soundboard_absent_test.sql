BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Migration under test: 20260913000104_soundboard_drop.sql (Phase B task
-- D5/D6, owner decisions 8 and 14, decision 5, ruling R-B19). Proves the
-- subsystem the drop removed is gone and that the two reaction tables'
-- CHECKs land exactly where decision 5 put them -- closed to 'snd:',
-- unchanged for everything else.
--
-- Fixture block: 15xx UUIDs. The old Phase B brief (2026-09-13, task D6)
-- named this file's namespace as 11xx, but that block already carries
-- session_round_engine_test.sql's set_logs sub-ids
-- (...-000000001101 through ...-000000001106, from D4 in the same phase,
-- which the D4 header labels "10xx" but whose set_logs rows fall in 11xx
-- by this repo's own two-hex-digit block convention) -- a pre-existing,
-- out-of-scope collision from an already-merged phase. This file grepped
-- fresh and takes 15xx instead (12xx and 13xx are also taken; 14xx is
-- reserved by the current plan for the routine_proposals absence suite,
-- D5, landing later on this same branch).
--
-- TWO hasnt_function checks, not one: the migration drops BOTH
-- private.owns_soundboard_sound(uuid,text) (decision 5's own object) AND
-- private.touch_soundboard_favorites_updated_at() (R-B19 item 1, added to
-- the migration after decision 5's text was written -- the favorites
-- table's own touch-trigger function, orphaned by DROP TABLE and dropped
-- alongside it).
--
-- TWO "plain emoji still inserts" checks, not zero: decision 5's own text
-- states post_reactions' CHECK is RESTORED (not just narrowed) and
-- chat_message_reactions gains a CHECK it never had before ("closes
-- exactly the 'snd:' door and nothing else"). An assertion that only
-- proves 'snd:' rows are rejected would not catch a CHECK written too
-- strictly (e.g. accidentally excluding a legitimate kudos emoji) -- only
-- proving BOTH the rejection and a plain-emoji acceptance closes that gap.
--
-- A = ...1501, author of a workout post and a chat message in her own
-- group -- both tables' insert policies gate on the row's own author/
-- member, so no second actor is needed for a rejection or acceptance
-- test.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000001501', 'soundabsent-a@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000001501', 'soundabsent_a');

-- workout_posts fixture: a completed session, then the post itself.
INSERT INTO sessions (id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000001510', '00000000-0000-4000-f000-000000001501',
   'completed', now() - interval '1 hour', now());
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000001510', '00000000-0000-4000-f000-000000001501');
INSERT INTO workout_posts (id, author_id, session_id, summary) VALUES
  ('00000000-0000-4000-f000-000000001520', '00000000-0000-4000-f000-000000001501',
   '00000000-0000-4000-f000-000000001510', '{}');

-- chat_message_reactions fixture: a group A is a member of, and one
-- message A sent in it.
INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-4000-f000-000000001530', 'Soundboard Absent Test Crew',
   '00000000-0000-4000-f000-000000001501');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-f000-000000001530', '00000000-0000-4000-f000-000000001501', 'admin');
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-4000-f000-000000001540', '00000000-0000-4000-f000-000000001530',
   '00000000-0000-4000-f000-000000001501', 'text', 'hello, before this suite reacts to it');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000001501';

-- 1/2. The two tables are gone.
SELECT hasnt_table('public', 'soundboard_sounds',
  'soundboard_sounds no longer exists');
SELECT hasnt_table('public', 'soundboard_favorites',
  'soundboard_favorites no longer exists');

-- 3/4. Both functions decision 5 (and R-B19 item 1) name are gone.
SELECT hasnt_function('private', 'owns_soundboard_sound',
  'private.owns_soundboard_sound no longer exists');
SELECT hasnt_function('private', 'touch_soundboard_favorites_updated_at',
  'private.touch_soundboard_favorites_updated_at no longer exists (R-B19 item 1)');

-- 5. post_reactions: the emoji-only list is restored -- a 'snd:' row is a
--    CHECK violation.
SELECT throws_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji) VALUES
      ('00000000-0000-4000-f000-000000001520',
       '00000000-0000-4000-f000-000000001501', 'snd:airhorn')$$,
  '23514', NULL, 'a snd: reaction is rejected on post_reactions');

-- 6. chat_message_reactions: never had a CHECK before the soundboard --
--    now it has exactly the 'snd:' door closed.
SELECT throws_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
      ('00000000-0000-4000-f000-000000001540',
       '00000000-0000-4000-f000-000000001501', 'snd:airhorn')$$,
  '23514', NULL, 'a snd: reaction is rejected on chat_message_reactions');

-- 7. post_reactions still takes its ordinary five-emoji vocabulary --
--    the restore did not narrow it further than it was.
SELECT lives_ok(
  $$INSERT INTO post_reactions (post_id, user_id, emoji) VALUES
      ('00000000-0000-4000-f000-000000001520',
       '00000000-0000-4000-f000-000000001501', '💪')$$,
  'a plain kudos emoji still inserts into post_reactions');

-- 8. chat_message_reactions keeps its open vocabulary otherwise -- only
--    the 'snd:' prefix is closed.
SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
      ('00000000-0000-4000-f000-000000001540',
       '00000000-0000-4000-f000-000000001501', '👍')$$,
  'a plain emoji still inserts into chat_message_reactions');

SELECT * FROM finish();
ROLLBACK;
