-- 20260821000004_sessions_delete_membership_gate.sql
--
-- The ledger-delete policy (20260821000002) was organizer-only with no
-- membership check, which let a DEPARTED organizer delete their old
-- group sessions - the exact invariant delete_parity_test.sql and
-- is_group_member_private_schema_test.sql pin (pgTAP caught it on the
-- next migration-touching push). Solo sessions stay organizer-deletable;
-- group sessions additionally require CURRENT membership, via the same
-- private.is_group_member() helper the other 21 policies use.
DROP POLICY IF EXISTS "sessions organizer delete" ON public.sessions;
CREATE POLICY "sessions organizer delete"
  ON public.sessions FOR DELETE TO authenticated
  USING (
    organizer_id = auth.uid()
    AND (
      group_id IS NULL
      OR private.is_group_member(sessions.group_id, auth.uid())
    )
  );
