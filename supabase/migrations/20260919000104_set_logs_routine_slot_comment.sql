-- D6 (Phase C1; final whole-branch review, non-blocking): the column comment
-- on set_logs.routine_exercise_id still stated the FIRST fallback rule
-- ("readers fall back to per-exercise_id attribution"). The app's shipped rule
-- (S2 fix round, SlotProgress) is stricter and different: a NULL-slot row is
-- never dropped -- it is placed in routine order, each slot filled up to its
-- target before the next. Comment only; no schema or behaviour change.
--
-- APPLIED: live 2026-09-19 as `set_logs_routine_slot_comment` (controller, Supabase MCP).

COMMENT ON COLUMN public.set_logs.routine_exercise_id IS
  'The routine_exercises row (the SLOT) this set was logged against, if any (Phase C1 D3). No foreign key: routine_exercises rows are deleted when a routine is edited, and a logged set is history. NULL for freeform sets and for every row logged before this column existed. Readers NEVER drop a NULL-slot row: progress is counted per slot as the rows attributed to it, plus unattributed rows of the slot''s effective (swap-layered) exercise placed in routine order, each slot filled up to its target before the next (SlotProgress in the app) -- so a routine naming one lift twice cannot double count, and a session logged before this column existed lands where it landed before.';
