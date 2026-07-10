CREATE TABLE public.chat_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  session_id   uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  author_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,  -- NULL = system
  kind         text NOT NULL DEFAULT 'text'
                    CHECK (kind IN ('text','image','system_pr','system_session',
                                    'system_late','system_leaderboard','soundboard_echo')),
  body         text,
  payload      jsonb,
  storage_path text,
  reply_to_id  uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  edited_at    timestamptz,
  deleted_at   timestamptz
);
CREATE INDEX chat_messages_group_created_idx
  ON public.chat_messages(group_id, created_at DESC);

CREATE TABLE public.chat_message_reactions (
  message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji      text NOT NULL,
  PRIMARY KEY (message_id, user_id, emoji)
);

CREATE TABLE public.chat_read_state (
  group_id             uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id              uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_message_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  PRIMARY KEY (group_id, user_id)
);

ALTER TABLE public.chat_messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_read_state        ENABLE ROW LEVEL SECURITY;

-- Definer helper so reaction policies don't re-enter chat_messages RLS
CREATE OR REPLACE FUNCTION public.message_group_id(p_message_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT group_id FROM public.chat_messages WHERE id = p_message_id;
$$;

-- chat_messages
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (public.is_group_member(chat_messages.group_id, auth.uid()));

CREATE POLICY "members send text as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid() AND kind = 'text'
              AND public.is_group_member(chat_messages.group_id, auth.uid()));

CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

-- chat_message_reactions
CREATE POLICY "group members read reactions"
  ON public.chat_message_reactions FOR SELECT TO authenticated
  USING (public.is_group_member(
           public.message_group_id(chat_message_reactions.message_id), auth.uid()));

CREATE POLICY "members react as themselves"
  ON public.chat_message_reactions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(
                    public.message_group_id(chat_message_reactions.message_id), auth.uid()));

CREATE POLICY "user removes own reaction"
  ON public.chat_message_reactions FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- chat_read_state
CREATE POLICY "group members read read-state"
  ON public.chat_read_state FOR SELECT TO authenticated
  USING (public.is_group_member(chat_read_state.group_id, auth.uid()));

CREATE POLICY "user inserts own read-state"
  ON public.chat_read_state FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(chat_read_state.group_id, auth.uid()));

CREATE POLICY "user updates own read-state"
  ON public.chat_read_state FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Realtime: stream chat message INSERTs (postgres_changes respects RLS)
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
