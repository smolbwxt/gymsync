-- ============================================================
-- Task 1: Comms schema — soundboard table, audio message kind, audio buckets
-- ============================================================

-- ── 1. soundboard_sounds table ───────────────────────────────────────────────
CREATE TABLE public.soundboard_sounds (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  slug         text        UNIQUE NOT NULL,
  display_name text,
  storage_path text        NOT NULL,
  duration_ms  int,
  is_curated   bool        NOT NULL DEFAULT true
);

ALTER TABLE public.soundboard_sounds ENABLE ROW LEVEL SECURITY;

-- Global authenticated read; NO client writes (service role seeds via superuser).
CREATE POLICY "authenticated users read soundboard sounds"
  ON public.soundboard_sounds FOR SELECT TO authenticated
  USING (true);

-- ── 2. chat_messages.kind CHECK — drop + re-add with 'audio' ─────────────────
-- Constraint name confirmed via pg_constraint: chat_messages_kind_check
ALTER TABLE public.chat_messages
  DROP CONSTRAINT chat_messages_kind_check;

ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_kind_check
  CHECK (kind IN (
    'text', 'image', 'audio',
    'system_pr', 'system_session', 'system_late', 'system_leaderboard',
    'soundboard_echo'
  ));

-- ── 3. INSERT policy — drop + recreate with audio + soundboard_echo ──────────
-- Latest version lives in 20260711000002_storage_buckets.sql:
--   "members send text or image as themselves"
DROP POLICY "members send text or image as themselves" ON public.chat_messages;

CREATE POLICY "members send client messages as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND (kind NOT IN ('image', 'audio') OR storage_path IS NOT NULL)
    AND (kind <> 'soundboard_echo' OR payload IS NOT NULL)
    AND public.is_group_member(chat_messages.group_id, auth.uid())
  );

-- ── 4. UPDATE policy — drop + recreate with extended kinds list ───────────────
-- Latest version lives in 20260711000002_storage_buckets.sql:
--   "author edits own messages"
DROP POLICY "author edits own messages" ON public.chat_messages;

CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (
    author_id = auth.uid()
    AND public.is_group_member(chat_messages.group_id, auth.uid())
  )
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND public.is_group_member(chat_messages.group_id, auth.uid())
  );

-- ── 5. Buckets ───────────────────────────────────────────────────────────────

-- chat-audio: private bucket, path = {group_id}/{message_id}.m4a
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-audio', 'chat-audio', false)
ON CONFLICT (id) DO NOTHING;

-- Mirror chat-images path-derived RLS: folder[1] = group_id
CREATE POLICY "group members upload chat audio"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-audio'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

CREATE POLICY "group members read chat audio"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-audio'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- soundboard: public bucket, authenticated read
INSERT INTO storage.buckets (id, name, public)
VALUES ('soundboard', 'soundboard', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "authenticated users read soundboard files"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'soundboard');
