-- Owner 2026-08-24: "a system very similar to Claude, where we have
-- threads, not one long persistent chat." Threads own the compaction
-- state that 20260824000002 kept per-user; existing messages migrate
-- into one "Earlier conversation" thread per user so nothing is lost.

CREATE TABLE public.coach_chat_threads (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title               text NOT NULL DEFAULT 'New thread',
  summary             text NOT NULL DEFAULT '',
  summarized_through  timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX coach_chat_threads_user_recency
  ON public.coach_chat_threads (user_id, updated_at DESC);

ALTER TABLE public.coach_chat_threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own threads"
  ON public.coach_chat_threads FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

ALTER TABLE public.coach_chat_messages
  ADD COLUMN thread_id uuid REFERENCES public.coach_chat_threads(id) ON DELETE CASCADE;

CREATE INDEX coach_chat_messages_thread_time
  ON public.coach_chat_messages (thread_id, created_at);

-- Migrate: one thread per user with existing messages; carry the old
-- per-user summary onto it, then retire coach_chat_state.
INSERT INTO public.coach_chat_threads (user_id, title)
SELECT DISTINCT user_id, 'Earlier conversation'
FROM public.coach_chat_messages;

UPDATE public.coach_chat_messages m
SET thread_id = t.id
FROM public.coach_chat_threads t
WHERE t.user_id = m.user_id AND m.thread_id IS NULL;

UPDATE public.coach_chat_threads t
SET summary = s.summary,
    summarized_through = s.summarized_through
FROM public.coach_chat_state s
WHERE s.user_id = t.user_id;

DROP TABLE public.coach_chat_state;

-- A new message bumps its thread's recency (the list orders by it).
CREATE OR REPLACE FUNCTION public.coach_chat_touch_thread()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.thread_id IS NOT NULL THEN
    UPDATE public.coach_chat_threads
    SET updated_at = now()
    WHERE id = NEW.thread_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER coach_chat_touch_thread
  AFTER INSERT ON public.coach_chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.coach_chat_touch_thread();
