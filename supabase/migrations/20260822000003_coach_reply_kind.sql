-- 20260822000003_coach_reply_kind.sql
--
-- @Coach in crew chats (spec 2026-08-22 §3): the coach's answer posts
-- as a chat message inserted BY THE ASKER (the on-device model runs on
-- their phone; there is no server author), kind 'coach_reply', payload
-- carrying the question. Constraint carried forward from v2
-- (20260728000002) plus the new kind.
ALTER TABLE public.chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_kind_check_v2;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_kind_check_v3
  CHECK (kind IN ('text', 'image', 'audio', 'system_pr', 'system_session',
                  'system_late', 'system_leaderboard', 'system_streak',
                  'system_campaign', 'soundboard_echo', 'coach_reply'))
  NOT VALID;
ALTER TABLE public.chat_messages VALIDATE CONSTRAINT chat_messages_kind_check_v3;
