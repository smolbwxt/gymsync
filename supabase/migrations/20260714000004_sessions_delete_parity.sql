-- Task 6: delete-policy parity — member-gate the sessions DELETE policy.
-- A departed organizer (removed from group_members) must not be able to delete
-- their old group sessions. Groupless (ad-hoc) scheduled sessions are unaffected.

DROP POLICY "organizer deletes own scheduled sessions" ON public.sessions;
CREATE POLICY "organizer deletes own scheduled sessions"
  ON public.sessions FOR DELETE TO authenticated
  USING (organizer_id = auth.uid() AND state = 'scheduled'
         AND (sessions.group_id IS NULL
              OR public.is_group_member(sessions.group_id, auth.uid())));
