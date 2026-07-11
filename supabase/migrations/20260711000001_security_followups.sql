-- Follow-up 1 (Phase 2 final review): read-state writes must require CURRENT membership.
DROP POLICY IF EXISTS "user updates own read-state" ON public.chat_read_state;
CREATE POLICY "user updates own read-state"
  ON public.chat_read_state FOR UPDATE TO authenticated
  USING (user_id = auth.uid()
         AND public.is_group_member(chat_read_state.group_id, auth.uid()))
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(chat_read_state.group_id, auth.uid()));

-- Follow-up 2 (REVISED): usernames are case-preserving for display but must be
-- case-insensitively unique, and lookups match any casing.
-- Drop any prior non-unique index with this name before creating the correct UNIQUE one.
DROP INDEX IF EXISTS public.profiles_username_lower_idx;
CREATE UNIQUE INDEX profiles_username_lower_idx
  ON public.profiles (lower(username));
