INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-images', 'chat-images', false)
ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- chat-images: path = {group_id}/{message_id}.jpg — folder derives membership
CREATE POLICY "group members upload chat images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-images'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

CREATE POLICY "group members read chat images"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- avatars: public read (bucket is public); writes restricted.
-- path = groups/{group_id}.jpg — filename derives the admin check
CREATE POLICY "anyone reads avatars"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars');

CREATE POLICY "group admin uploads group avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

CREATE POLICY "group admin replaces group avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

-- chat_messages: clients may now send images (storage_path required for images)
DROP POLICY "members send text as themselves" ON public.chat_messages;
CREATE POLICY "members send text or image as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text','image')
    AND (kind <> 'image' OR storage_path IS NOT NULL)
    AND public.is_group_member(chat_messages.group_id, auth.uid())
  );

-- and edit/soft-delete both kinds (20260710000006 pinned kind='text', which
-- would have made image messages un-deletable)
DROP POLICY "author edits own messages" ON public.chat_messages;
CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (author_id = auth.uid()
         AND public.is_group_member(chat_messages.group_id, auth.uid()))
  WITH CHECK (author_id = auth.uid() AND kind IN ('text','image')
              AND public.is_group_member(chat_messages.group_id, auth.uid()));
