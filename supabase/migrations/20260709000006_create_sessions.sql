CREATE TABLE public.sessions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id               uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  organizer_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  state                    text NOT NULL DEFAULT 'in_progress'
                                        CHECK (state IN ('scheduled','lobby_open','editing','voting',
                                                         'locked','in_progress','completed','abandoned')),
  scheduled_for            timestamptz,
  started_at               timestamptz,
  completed_at             timestamptz,
  duration_was_edited      boolean NOT NULL DEFAULT false,
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sessions_organizer_id_idx ON public.sessions(organizer_id);
CREATE INDEX sessions_organizer_completed_idx ON public.sessions(organizer_id, completed_at DESC);

CREATE TABLE public.session_participants (
  session_id       uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  turn_order       integer,
  check_in_state   text CHECK (check_in_state IN ('invited','online','ready','late','no_show')),
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_participants ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helpers break RLS recursion: sessions policies reference
-- session_participants and vice versa, so any direct cross-table subquery in a
-- policy re-enters the other table's RLS and cycles. Definer functions bypass RLS.
CREATE OR REPLACE FUNCTION public.is_session_participant(p_session_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.session_participants
    WHERE session_id = p_session_id AND user_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION public.is_session_organizer(p_session_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE id = p_session_id AND organizer_id = p_user_id
  );
$$;

CREATE POLICY "users can select sessions they participate in"
  ON public.sessions FOR SELECT TO authenticated
  USING (
    organizer_id = auth.uid()
    OR public.is_session_participant(sessions.id, auth.uid())
  );

CREATE POLICY "users can insert sessions as organizer"
  ON public.sessions FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid());

CREATE POLICY "organizer or participant can update session"
  ON public.sessions FOR UPDATE TO authenticated
  USING (
    organizer_id = auth.uid()
    OR public.is_session_participant(sessions.id, auth.uid())
  );

CREATE POLICY "participants readable by other participants"
  ON public.session_participants FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_session_participant(session_participants.session_id, auth.uid())
  );

-- Write policies deliberately exclude SELECT (a FOR ALL policy would add its
-- sessions-subquery to SELECT evaluation and re-create the recursion).
CREATE POLICY "participants insertable only by session organizer"
  ON public.session_participants FOR INSERT TO authenticated
  WITH CHECK (public.is_session_organizer(session_participants.session_id, auth.uid()));

CREATE POLICY "participants updatable only by session organizer"
  ON public.session_participants FOR UPDATE TO authenticated
  USING (public.is_session_organizer(session_participants.session_id, auth.uid()))
  WITH CHECK (public.is_session_organizer(session_participants.session_id, auth.uid()));

CREATE POLICY "participants deletable only by session organizer"
  ON public.session_participants FOR DELETE TO authenticated
  USING (public.is_session_organizer(session_participants.session_id, auth.uid()));
