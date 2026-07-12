-- Task 5: session_duration_edits audit table
-- Referenced in design spec (Phase 1 schema) but not yet materialised in a migration.
-- Consumed by SessionRepository.editDuration (3b).

CREATE TABLE public.session_duration_edits (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id       uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  edited_by        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  old_started_at   timestamptz,
  old_completed_at timestamptz,
  new_started_at   timestamptz NOT NULL,
  new_completed_at timestamptz NOT NULL,
  reason           text,
  edited_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.session_duration_edits ENABLE ROW LEVEL SECURITY;

-- Participants of the session may view all edits for it.
CREATE POLICY "session participants can read duration edits"
  ON public.session_duration_edits FOR SELECT TO authenticated
  USING (public.is_session_participant(session_id, auth.uid())
         OR public.is_session_organizer(session_id, auth.uid()));

-- Any participant may insert an edit row (they supply their own edited_by via RLS).
CREATE POLICY "session participants can insert duration edits"
  ON public.session_duration_edits FOR INSERT TO authenticated
  WITH CHECK (
    edited_by = auth.uid()
    AND (
      public.is_session_participant(session_id, auth.uid())
      OR public.is_session_organizer(session_id, auth.uid())
    )
  );

-- Audit rows are immutable once written.
CREATE INDEX session_duration_edits_session_idx
  ON public.session_duration_edits(session_id, edited_at DESC);
