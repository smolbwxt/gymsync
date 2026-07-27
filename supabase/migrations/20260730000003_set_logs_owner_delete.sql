-- ============================================================
-- set_logs: owner DELETE policy (mistyped-set fix).
-- ============================================================
-- V1 gap review 2026-07-26: a fat-fingered set (2255 instead of 225) was
-- PERMANENT — set_logs had INSERT/SELECT/UPDATE policies but no DELETE, so
-- the client's only options were living with corrupted volume/est-1RM (and
-- possibly a fabricated PR) or nothing. Owner-scoped delete, same shape as
-- the existing owner UPDATE policy.
--
-- Scope note: personal_records rows born from a since-deleted set are NOT
-- cascaded — a PR recompute pipeline is out of scope here, and silently
-- deleting a PR the user may have seen celebrated is its own surprise. The
-- client notes this at the delete site.

CREATE POLICY "users can delete their own set logs"
  ON public.set_logs FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
