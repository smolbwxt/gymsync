-- 20260912000101_session_participant_energy.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md §6
-- and owner decision 18 — the lobby carries the crew's self-reported energy
-- (1-5) as a group. Plan: docs/superpowers/plans/2026-09-12-group-session
-- -phase-a-plan.md, task D1.
--
-- NO NEW POLICY, ON PURPOSE. "participant updates own check-in"
-- (20260712000001_sessions_phase3_columns.sql:22-25) is
-- USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid()) with no
-- column list, so a lifter can already write their own row; "participants
-- readable by other participants" (20260726000001_is_session_participant
-- _dual_schema.sql:182-187) is row-level, so the crew can already read it.
-- A third policy here would be permissive-ORed with those and would grant
-- nothing while looking like it granted something.
--
-- NULL IS AN ABSENCE, NEVER A ZERO. The widget draws five empty pips and the
-- words "not yet" for NULL (the pump card's lateness-tag rule), so 0 must be
-- unreachable — hence the CHECK's lower bound of 1 rather than a DEFAULT.
--
-- smallint, not integer: a 1-5 scale, and this table is read on every lobby
-- render for every participant.
ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS energy smallint
    CHECK (energy IS NULL OR energy BETWEEN 1 AND 5);

COMMENT ON COLUMN public.session_participants.energy IS
  'Self-reported energy for this session, 1-5. NULL until the lifter answers. Written by the lifter from the lobby (SessionRepository.setEnergy), read by the whole crew through the existing participant SELECT policy. Spec 2026-09-12-group-session-and-lobby-design.md section 6.';
