-- D3 (Phase C1, plan section 3, decision 3): a logged set records its
-- routine slot. The real table is `set_logs` (20260709000007_create_
-- set_logs.sql), not `session_sets`. It has exercise_id NOT NULL and no
-- notion of which routine row a set was logged for.
--
-- ── why the column exists ───────────────────────────────────────────────
-- routine_exercise_id makes three things honest at once:
--   * a swap mid-exercise -- a slot with sets under two exercise ids breaks
--     per-id counting today (the deliberate gate at
--     WorkoutSessionView.swift:1616). With slot attribution the gate can be
--     lifted -- C1 does not lift it, C2 does, because the gate lives in a
--     view C1 is not rewriting.
--   * a routine naming one lift twice -- the known flaw in the owner-
--     decisions round's R-OD-3.
--   * the recap's volume -- a per-id sum double-counts across a swap; a
--     per-slot dedupe does not.
--
-- ── why there is no foreign key ─────────────────────────────────────────
-- routine_exercises rows are deleted when a routine is edited, and a logged
-- set is history: an FK with ON DELETE CASCADE would delete the set, and one
-- with RESTRICT would block the routine edit. The column is a recorded
-- intent, not a live reference.
--
-- ── why there is no backfill ─────────────────────────────────────────────
-- A row logged before this migration genuinely does not know which slot it
-- was logged for -- inventing one would be a fabricated attribution, not a
-- recovered fact. Every pre-migration row keeps NULL forever, and every
-- cursor reader keeps the per-exercise_id fallback for those rows (S2, same
-- window): a slot's completed count is the number of rows whose
-- routine_exercise_id equals the slot id, plus -- only when the slot has
-- zero such rows -- the number of rows whose exercise_id equals the slot's
-- exercise id and whose routine_exercise_id IS NULL. Byte-identical
-- behaviour for an all-old session, correct behaviour for an all-new one,
-- the old behaviour for the one session that straddles the deploy.
--
-- A freeform ad-hoc workout writes NULL forever, by design: its synthesized
-- rows are never persisted (WorkoutSessionView.swift:249-254), so there is
-- no slot to name -- the per-exercise_id fallback is exactly right for them,
-- forever, not just until a backfill.
--
-- ── no policy change ─────────────────────────────────────────────────────
-- The three shipped set_logs policies -- "users can select their own set
-- logs OR shared session logs" (SELECT), "users can insert their own set
-- logs" (INSERT), "users can update their own set logs" (UPDATE) --
-- (20260709000007_create_set_logs.sql:25-38) all have NO column list, so a
-- lifter writing their own row may already write this column. A fourth
-- policy here would grant nothing while looking like it granted something.
--
-- APPLIED: (held at its gate -- the controller fills this in)

ALTER TABLE public.set_logs
  ADD COLUMN IF NOT EXISTS routine_exercise_id uuid;

COMMENT ON COLUMN public.set_logs.routine_exercise_id IS
  'The routine_exercises row (the SLOT) this set was logged against, if any (Phase C1 D3). No foreign key: routine_exercises rows are deleted when a routine is edited, and a logged set is history -- this is a recorded intent, not a live reference. NULL for every row logged before this migration (no backfill -- a pre-column row genuinely does not know its slot) and for every freeform ad-hoc set, forever. A slot''s completed count is rows matching this column, plus -- only when that is zero -- rows matching exercise_id with this column NULL (the pre-migration fallback).';

CREATE INDEX IF NOT EXISTS set_logs_session_slot_idx
  ON public.set_logs(session_id, routine_exercise_id)
  WHERE routine_exercise_id IS NOT NULL;
