-- 20260912000102_session_coach_thread.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md
-- §3.6 and §6, owner decision 19 — one Coach thread per crew session, shared
-- by the whole crew, unlocked while ANY participant is Pro. Plan:
-- docs/superpowers/plans/2026-09-12-group-session-phase-a-plan.md, task D3.
--
-- WHY A COLUMN AND NOT A TITLE. CoachThreadLauncher already fakes subjects by
-- writing them into `title` (ProgramScheduleView.swift:1106). A title is not a
-- key: it cannot be unique, cannot be joined, and cannot be the subject of an
-- RLS predicate. A crew-readable thread needs all three.
--
-- WHY THE PRO GATE IS SERVER-SIDE. profiles.pro_until is not readable across
-- users (20260730000004_pro_entitlement.sql), so a client asking "is anyone in
-- this session Pro" would be asking about rows it cannot see and would answer
-- "no" for everyone but itself. SECURITY DEFINER is what makes the answer
-- true. The shape is CrewCoachEngine.crewHasCoach's ("one Pro member lights
-- @Coach for the whole crew", CrewCoachEngine.swift:22-25), moved to the
-- server and scoped to session participants instead of group members.

-- 1. The key.
ALTER TABLE public.coach_chat_threads
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES public.sessions(id) ON DELETE CASCADE;

-- ONE thread per session. A partial unique index rather than a table
-- constraint, because every personal thread has session_id NULL and NULLs
-- must not collide.
CREATE UNIQUE INDEX IF NOT EXISTS coach_chat_threads_session_key
  ON public.coach_chat_threads(session_id)
  WHERE session_id IS NOT NULL;

COMMENT ON COLUMN public.coach_chat_threads.session_id IS
  'The session this thread belongs to, or NULL for a personal thread. One thread per session (coach_chat_threads_session_key). Readable by every participant of that session. Spec 2026-09-12-group-session-and-lobby-design.md section 3.6.';

-- 2. The Pro gate, in the private schema like every other predicate helper
-- (private.is_session_participant, private.is_group_member).
CREATE OR REPLACE FUNCTION private.session_has_pro(p_session_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.session_participants sp
      JOIN public.profiles p ON p.id = sp.user_id
     WHERE sp.session_id = p_session_id
       AND p.pro_until IS NOT NULL
       AND p.pro_until > now()
  );
$$;

REVOKE EXECUTE ON FUNCTION private.session_has_pro(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.session_has_pro(uuid) TO authenticated;

-- 3. The thread's own subject, hoisted out of the messages policy so the
-- policy does not have to read coach_chat_threads under RLS (the
-- private.proposal_session_id precedent, 20260727000004).
CREATE OR REPLACE FUNCTION private.coach_thread_session_id(p_thread_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT session_id FROM public.coach_chat_threads WHERE id = p_thread_id;
$$;

REVOKE EXECUTE ON FUNCTION private.coach_thread_session_id(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.coach_thread_session_id(uuid) TO authenticated;

-- 4. The crew's read. ADDITIVE: "own threads" (20260824000005:20-23) stays
-- exactly as it is, and Postgres ORs permissive policies of the same command,
-- so a personal thread is unaffected.
CREATE POLICY "session threads readable by participants"
  ON public.coach_chat_threads FOR SELECT TO authenticated
  USING (
    session_id IS NOT NULL
    AND private.is_session_participant(session_id, auth.uid())
  );

CREATE POLICY "session threads insertable by participants"
  ON public.coach_chat_threads FOR INSERT TO authenticated
  WITH CHECK (
    session_id IS NOT NULL
    AND user_id = auth.uid()
    AND private.is_session_participant(session_id, auth.uid())
  );

CREATE POLICY "session thread messages readable by participants"
  ON public.coach_chat_messages FOR SELECT TO authenticated
  USING (
    thread_id IS NOT NULL
    AND private.is_session_participant(
          private.coach_thread_session_id(thread_id), auth.uid())
  );

CREATE POLICY "session thread messages postable by participants"
  ON public.coach_chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    thread_id IS NOT NULL
    AND user_id = auth.uid()
    AND private.is_session_participant(
          private.coach_thread_session_id(thread_id), auth.uid())
  );

-- 5. The one client-callable entry point: find-or-create this session's
-- thread, and say whether it is unlocked. Find-or-create because two lifters
-- tapping "Talk to Coach" at the same moment must land in ONE room — the
-- unique index makes that a race the ON CONFLICT resolves rather than an
-- error one of them sees.
CREATE OR REPLACE FUNCTION public.session_coach_thread(p_session_id uuid)
RETURNS TABLE (thread_id uuid, unlocked boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread_id uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO v_thread_id
    FROM public.coach_chat_threads
   WHERE session_id = p_session_id;

  IF v_thread_id IS NULL THEN
    INSERT INTO public.coach_chat_threads (user_id, session_id, title)
    VALUES (auth.uid(), p_session_id, 'This session')
    ON CONFLICT (session_id) WHERE session_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_thread_id;

    IF v_thread_id IS NULL THEN
      SELECT id INTO v_thread_id
        FROM public.coach_chat_threads
       WHERE session_id = p_session_id;
    END IF;
  END IF;

  RETURN QUERY SELECT v_thread_id, private.session_has_pro(p_session_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.session_coach_thread(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_coach_thread(uuid) TO authenticated;
