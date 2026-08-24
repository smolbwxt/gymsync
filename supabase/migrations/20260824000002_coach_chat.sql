-- 20260824000002_coach_chat.sql
--
-- The dedicated Coach chat (owner 2026-08-24): a persistent thread per
-- athlete, Claude-style - when the on-device context fills, a compact
-- summary is stored and the next exchange continues on a fresh session
-- seeded with it. The athlete never sees a seam.
CREATE TABLE public.coach_chat_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('athlete', 'coach')),
  body       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX coach_chat_user_created_idx
  ON public.coach_chat_messages (user_id, created_at DESC);

CREATE TABLE public.coach_chat_state (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  summary    text NOT NULL DEFAULT '',
  -- Messages newer than this timestamp ride the live context; older
  -- ones live inside the summary.
  summarized_through timestamptz
);

ALTER TABLE public.coach_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_chat_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own chat" ON public.coach_chat_messages
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own chat state" ON public.coach_chat_state
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Research deliveries (Coach-surface spec): the athlete may see their
-- own misses so "the research came back" is tellable.
CREATE POLICY "read own misses" ON public.corpus_misses
  FOR SELECT TO authenticated USING (user_id = auth.uid());
