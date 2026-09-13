-- 20260912000103_coach_chat_messages_scope_own_chat.sql
--
-- Task D5 -- fixes a gap D4's pgTAP coverage surfaced (session_coach_thread_
-- test.sql assertion 15, 2026-09-13): "own chat" (public.coach_chat_messages,
-- 20260824000002_coach_chat.sql:27-29) is FOR ALL with
-- WITH CHECK (user_id = auth.uid()) and no thread_id scoping at all. Because
-- Postgres ORs every applicable permissive policy for the same command,
-- that WITH CHECK alone is enough to pass an INSERT no matter which thread
-- the row targets -- any authenticated user can write into ANY thread
-- (someone else's personal thread, or a session thread they do not
-- participate in) just by stamping the row with their own user_id. The gap
-- predates this migration -- it has existed since "own chat" was created,
-- before coach_chat_messages even had a thread_id column
-- (20260824000005_coach_chat_threads.sql added that afterward and never
-- revisited this policy). Confirmed live (pg_policy/pg_trigger inspection,
-- and a rolled-back dry run of the full D4 suite) before writing this fix.
--
-- WHO WRITES THIS TABLE. Grepped supabase/functions (zero hits) and
-- GymSyncApp (the only writer: CoachChatRepository.append,
-- GymSyncApp/GymSync/Models/CoachChat.swift:112-129) before choosing the
-- fix, per the "tell me before guessing" rule. append() always runs as the
-- signed-in athlete's own session -- role authenticated, never
-- service_role; there is no server-side writer, the reply itself comes
-- from an on-device FoundationModels session -- and always sets user_id to
-- that caller's own id for BOTH sides of the exchange: the athlete's
-- question (role 'athlete') and the on-device model's reply (role 'coach')
-- go through the identical INSERT shape at CoachHomeView.swift:1191-1194,
-- only role/body differ. thread_id is a non-optional Swift parameter, so no
-- call site can omit it. No writer inserts a 'coach' row tagged with
-- someone else's user_id, or into a thread the caller does not already own
-- or (for a session thread) already participate in -- session_coach_
-- thread's own gate (20260912000102:113-115) is what a session-thread
-- caller must already have cleared to obtain a thread_id to append to in
-- the first place.
--
-- NULL thread_id. The column is nullable (20260824000005:26), but the
-- backfill in that same migration (:33-40) gave every pre-existing message
-- a thread, append() never omits thread_id, nothing in the app UPDATEs
-- this table, and the live table has 0 rows with thread_id NULL (checked
-- before writing this). So the WITH CHECK below does not carve out a
-- NULL-thread_id case -- there is nothing left that would need one, and
-- adding one back would just reopen a smaller version of the same hole.
--
-- SESSION THREADS ARE UNAFFECTED. "session thread messages postable by
-- participants" (20260912000102:93-100) already scopes INSERT to session
-- participants and is untouched here. Postgres ORs permissive policies for
-- the same command, so a genuine participant's post still passes through
-- that policy exactly as before (D4 assertion 12) even on a session thread
-- it did not create, where it now fails the tightened "own chat" check.

-- 1. The thread's owner, hoisted out of the policy the same way D3 hoisted
-- coach_thread_session_id -- so the policy does not read coach_chat_threads
-- under RLS.
CREATE OR REPLACE FUNCTION private.coach_thread_owner(p_thread_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT user_id FROM public.coach_chat_threads WHERE id = p_thread_id;
$$;

REVOKE EXECUTE ON FUNCTION private.coach_thread_owner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.coach_thread_owner(uuid) TO authenticated;

-- 2. Same command scope (FOR ALL), same USING clause -- only WITH CHECK
-- gains the thread-ownership term that was always missing.
DROP POLICY IF EXISTS "own chat" ON public.coach_chat_messages;
CREATE POLICY "own chat" ON public.coach_chat_messages
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND private.coach_thread_owner(thread_id) = auth.uid()
  );
