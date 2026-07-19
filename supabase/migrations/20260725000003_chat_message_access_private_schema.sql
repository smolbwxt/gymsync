-- ============================================================
-- Phase O / Task 1: DEFINER-helper sweep, items 4-5 of 6 —
-- message_group_id() and can_access_message()
-- ============================================================
-- Batched together (per the task brief's own suggested grouping): both are
-- chat-access helpers with overlapping history on chat_message_reactions,
-- and can_access_message's body already supersedes message_group_id's
-- original call sites.
--
-- ── message_group_id(p_message_id uuid) ──────────────────────────────────
-- Defined once, 20260710000003_create_chat.sql:39-43. SECURITY DEFINER
-- STABLE, search_path pinned, default PUBLIC EXECUTE (no REVOKE/GRANT).
-- Exposure: given ANY message_id, returns that message's group_id — an
-- oracle for chat_messages.group_id that bypasses chat_messages' own RLS
-- (which normally hides group_id on a message the caller can't read).
--
-- CURRENTLY ORPHANED: grep of every migration confirms message_group_id
-- had exactly two original callers — chat_message_reactions' SELECT
-- ("group members read reactions") and INSERT ("members react as
-- themselves") policies, both defined in 20260710000003_create_chat.sql —
-- and BOTH were superseded in 20260719000011_chat_subthread_lock_
-- hardening.sql to use can_access_message() instead (Finding 1: the old
-- message_group_id()->is_group_member() path had zero session awareness).
-- The DELETE policy on chat_message_reactions never called
-- message_group_id() at all (originally user_id = auth.uid() only; also
-- later moved onto can_access_message() by the same migration). No other
-- migration, SQL function body, trigger, or non-SQL caller references it
-- (grepped supabase/functions/**/*.ts and the whole repo — zero direct
-- `.rpc("message_group_id", ...)` calls). Relocated anyway per the task
-- brief's explicit queue (dead-code oracles are still oracles until
-- removed), with no policy repointing needed since there is nothing live
-- to repoint.
--
-- ── can_access_message(p_message_id uuid, p_user_id uuid) ────────────────
-- Defined once, 20260719000011_chat_subthread_lock_hardening.sql:40-51.
-- SECURITY DEFINER STABLE, search_path pinned, default PUBLIC EXECUTE (no
-- REVOKE/GRANT). Exposure: given ANY message_id and ANY user_id, answers
-- "can p_user_id access this message?" — reveals group/session membership
-- shape for an arbitrary pair without the caller needing to already have
-- read access to the message row itself.
--
-- Live dependents (grep-confirmed, all three last defined in
-- 20260719000011_chat_subthread_lock_hardening.sql, never redefined
-- since): chat_message_reactions SELECT ("group members read reactions"),
-- INSERT ("members react as themselves"), DELETE ("user removes own
-- reaction"). No SQL-function-body callers, no non-SQL callers.
--
-- can_access_message's own body calls is_group_member() and
-- is_session_participant() internally. is_group_member was relocated to
-- `private` in the immediately-preceding migration
-- (20260725000002_is_group_member_private_schema.sql), so this body is
-- updated to call private.is_group_member. is_session_participant is NOT
-- relocated (blocked — see task report: supabase/functions/livekit-token/
-- index.ts calls it directly via `.rpc("is_session_participant", ...)`,
-- and PostgREST route generation is schema-based regardless of caller
-- role, so moving it would break that Edge Function), so that call stays
-- `public.is_session_participant`, unchanged.
-- ============================================================

-- ── 1. private.message_group_id() — same contract, unreachable schema ───
CREATE FUNCTION private.message_group_id(p_message_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT group_id FROM public.chat_messages WHERE id = p_message_id;
$$;

-- ── 2. private.can_access_message() — same contract, unreachable schema,
--    is_group_member call repointed to private (is_session_participant
--    stays public — see header) ──────────────────────────────────────────
CREATE FUNCTION private.can_access_message(p_message_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_messages m
    WHERE m.id = p_message_id
      AND (
        (m.session_id IS NULL AND private.is_group_member(m.group_id, p_user_id))
        OR (m.session_id IS NOT NULL AND public.is_session_participant(m.session_id, p_user_id))
      )
  );
$$;

-- ── 3. Repoint the three dependent policies (chat_message_reactions) ────
DROP POLICY "group members read reactions" ON public.chat_message_reactions;
CREATE POLICY "group members read reactions"
  ON public.chat_message_reactions FOR SELECT TO authenticated
  USING (private.can_access_message(chat_message_reactions.message_id, auth.uid()));

DROP POLICY "members react as themselves" ON public.chat_message_reactions;
CREATE POLICY "members react as themselves"
  ON public.chat_message_reactions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND private.can_access_message(chat_message_reactions.message_id, auth.uid()));

DROP POLICY "user removes own reaction" ON public.chat_message_reactions;
CREATE POLICY "user removes own reaction"
  ON public.chat_message_reactions FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         AND private.can_access_message(chat_message_reactions.message_id, auth.uid()));

-- ── 4. Drop both oracles ─────────────────────────────────────────────────
-- can_access_message first (it depends on nothing else being dropped);
-- message_group_id has no dependents to wait on either. Order between the
-- two doesn't matter (neither calls the other) — message_group_id second
-- simply to mirror the file's own read order above.
DROP FUNCTION public.can_access_message(uuid, uuid);
DROP FUNCTION public.message_group_id(uuid);
