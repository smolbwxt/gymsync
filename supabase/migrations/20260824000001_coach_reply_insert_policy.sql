-- 20260824000001_coach_reply_insert_policy.sql
--
-- Field #3 2026-08-24: @Coach never answered in crew chats - the
-- coach_reply INSERT was RLS-rejected ("members send text as
-- themselves" checks kind = 'text') and the client's try? swallowed
-- it. Members may post Coach's answer as themselves in their own
-- groups, same membership gate as text.
CREATE POLICY "members post coach replies as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid() AND kind = 'coach_reply'
              AND private.is_group_member(chat_messages.group_id, auth.uid()));
