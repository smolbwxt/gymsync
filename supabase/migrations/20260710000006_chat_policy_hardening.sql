-- Harden message editing: author must still be a group member, and client
-- updates cannot mutate kind away from 'text' (system kinds are trigger-only).
DROP POLICY "author edits own messages" ON public.chat_messages;
CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (author_id = auth.uid()
         AND public.is_group_member(chat_messages.group_id, auth.uid()))
  WITH CHECK (author_id = auth.uid() AND kind = 'text'
              AND public.is_group_member(chat_messages.group_id, auth.uid()));
