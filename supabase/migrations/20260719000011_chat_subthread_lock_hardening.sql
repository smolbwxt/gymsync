-- ============================================================
-- Security fix-forward: two review findings on session sub-thread chat
-- (20260719000010_session_chat_subthreads.sql, APPLIED LIVE — append-only,
-- this migration replaces policies via DROP + CREATE, it does not edit the
-- applied file).
-- ============================================================
--
-- FINDING 1 (Critical): chat_message_reactions bypasses the sub-thread lock.
-- Its SELECT/INSERT policies (20260710000003_create_chat.sql:61-70) gate
-- purely on is_group_member(message_group_id(message_id), auth.uid()) —
-- zero session awareness. For a group-backed session's sub-thread message,
-- any group member NOT in the session can still insert reactions and read
-- them (and reaction INSERTs broadcast via the realtime publication,
-- 20260711000003_reactions_publication.sql). Defeats participants-only
-- confidentiality on the primary case chat_messages was just locked down
-- for. As a side effect this also fixes the previously-documented
-- (20260719000010, "Deliberately untouched") solo-session gap: for a solo
-- session's sub-thread messages (group_id NULL), the old
-- is_group_member(group_id, ...) path evaluated false for everyone,
-- including the thread's own participants — reactions on solo sub-thread
-- messages were unreachable. The new helper checks session_id first, so
-- solo-session participants can now react to their own thread.
--
-- FINDING 2 (Important): chat_messages INSERT policy's session branch binds
-- session_id but never group_id — a participant of ANY session can insert a
-- sub-thread row carrying an ARBITRARY unrelated group_id, forging
-- push_chat_mention fan-out (20260716000001_push_schema.sql) and
-- touch_session_activity_on_chat activity-timer bumps
-- (20260716000003_push_cron.sql) against a group they don't belong to.
--
-- ── 1. can_access_message() — SECURITY DEFINER helper ──────────────────────
-- Mirrors message_group_id()'s idiom (20260710000003_create_chat.sql:39-43):
-- SQL, SECURITY DEFINER, STABLE, search_path pinned, reads chat_messages
-- directly (bypasses chat_messages RLS — this is what breaks the
-- reactions<->chat_messages RLS recursion the same way message_group_id()
-- always has). Encodes the exact same session-aware predicate as the
-- current chat_messages SELECT policy (20260719000010, #3): a caller can
-- access a message iff it's a group-level row and they're a group member,
-- or it's a session-thread row and they're a participant of that session.
CREATE OR REPLACE FUNCTION public.can_access_message(p_message_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_messages m
    WHERE m.id = p_message_id
      AND (
        (m.session_id IS NULL AND public.is_group_member(m.group_id, p_user_id))
        OR (m.session_id IS NOT NULL AND public.is_session_participant(m.session_id, p_user_id))
      )
  );
$$;

-- ── 2. chat_message_reactions SELECT — fix-forward replace ─────────────────
DROP POLICY "group members read reactions" ON public.chat_message_reactions;
CREATE POLICY "group members read reactions"
  ON public.chat_message_reactions FOR SELECT TO authenticated
  USING (public.can_access_message(chat_message_reactions.message_id, auth.uid()));

-- ── 3. chat_message_reactions INSERT — fix-forward replace ─────────────────
-- Reactor-spoof guard (user_id = auth.uid()) kept exactly as the original
-- policy had it.
DROP POLICY "members react as themselves" ON public.chat_message_reactions;
CREATE POLICY "members react as themselves"
  ON public.chat_message_reactions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.can_access_message(chat_message_reactions.message_id, auth.uid()));

-- ── 4. chat_message_reactions DELETE — same gate applied ───────────────────
-- A DELETE policy exists ("user removes own reaction",
-- 20260710000003_create_chat.sql:72-74) and was never touched by any
-- hardening migration (20260710000006 only touched chat_messages UPDATE).
-- It was previously scoped by user_id = auth.uid() alone, with no
-- message-access check at all. Applying the same can_access_message() gate
-- here for consistency with SELECT/INSERT above — own-row deletion still
-- requires the caller to currently be able to access the underlying
-- message.
DROP POLICY "user removes own reaction" ON public.chat_message_reactions;
CREATE POLICY "user removes own reaction"
  ON public.chat_message_reactions FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         AND public.can_access_message(chat_message_reactions.message_id, auth.uid()));

-- ── 5. chat_messages INSERT — fix-forward replace (Finding 2) ──────────────
-- Transplant of the current live policy (20260719000010_session_chat_
-- subthreads.sql, #4 — "members send client messages as themselves"), verbatim
-- except for one added AND clause in the session branch: the row's group_id
-- must match the session's own group_id (or both be NULL, for a solo
-- session). WITH CHECK subqueries are legal. The session_id IS NULL branch
-- is byte-identical to the current policy — group-level inserts are
-- unaffected.
DROP POLICY "members send client messages as themselves" ON public.chat_messages;
CREATE POLICY "members send client messages as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND (kind NOT IN ('image', 'audio') OR storage_path IS NOT NULL)
    AND (kind <> 'soundboard_echo' OR payload IS NOT NULL)
    AND (
      (chat_messages.session_id IS NULL
       AND public.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid())
          AND chat_messages.group_id IS NOT DISTINCT FROM (
                SELECT s.group_id FROM public.sessions s
                WHERE s.id = chat_messages.session_id))
    )
  );
