-- Owner field report 2026-08-21: "can't delete workouts from ledger."
-- sessions had no DELETE policy, so a client delete silently affected
-- zero rows. Organizer-scoped, same shape as set_logs' owner-delete
-- (20260730000003); clients delete their set_logs first, then the row.
CREATE POLICY "sessions organizer delete"
  ON public.sessions FOR DELETE TO authenticated
  USING (organizer_id = auth.uid());

-- EZ bars are lighter than straight bars (owner field report: "should
-- have a lighter bar, which affects loading"). Per-user because home EZ
-- bars vary (15-25 lb); 15 lb is the common standard-EZ default.
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS ez_bar_weight_lbs numeric NOT NULL DEFAULT 15;
