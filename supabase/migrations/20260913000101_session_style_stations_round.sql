-- 20260913000101_session_style_stations_round.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md
-- §6 (session styles: rounds, freestyle, together) and owner decisions 1 and
-- 2 -- there is no routine-type column, so the style default is a client-
-- side pure function over the routine's own exercises (see "the five data
-- decisions," decision 2, in the phase plan). Plan: docs/superpowers/plans
-- /2026-09-13-group-session-phase-b-plan.md, task D1.
--
-- NO NEW POLICY, ON PURPOSE. "organizer or participant can update session"
-- (20260709000006_create_sessions.sql) is USING (organizer_id = auth.uid()
-- OR is_session_participant(...)) with no column list, so it already grants
-- the write to all four columns below. That width is correct for style
-- (spec §6: editable by any participant until Start) and wrong for round,
-- stations and round_started_at (decision 4) -- but the fix is D3's
-- private.session_round_guard trigger, not a second policy ORed against the
-- first. This migration adds no policy.
--
-- DEFAULTS READ AS THE SHIPPED ROTATION. style='rounds', round=1, stations
-- NULL: every row that already exists, and every row inserted by code that
-- has not learned about the other two styles yet, reads as a one-station
-- Rounds session at round 1 -- exactly what today's rotation already is. No
-- backfill needed.
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS style text NOT NULL DEFAULT 'rounds'
    CHECK (style IN ('rounds','freestyle','together')),
  ADD COLUMN IF NOT EXISTS stations jsonb,
  ADD COLUMN IF NOT EXISTS round integer NOT NULL DEFAULT 1 CHECK (round >= 1),
  ADD COLUMN IF NOT EXISTS round_started_at timestamptz;

COMMENT ON COLUMN public.sessions.style IS
  'The crew''s round shape for this session: rounds, freestyle or together (decision 1). Set at scheduling from the routine''s own exercises (decision 2 -- no routine-type column exists, so the default is a pure function over exercises.category and routine_exercises.cardio_minutes, computed client-side by SessionStyleDefault). Editable by any participant until Start; once lifting_started_at is set, private.session_round_guard (D3) freezes it. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D1.';

COMMENT ON COLUMN public.sessions.stations IS
  'The CURRENT exercise''s station assignment only -- spec section 6 says explicitly that a separate table is not needed, so this is transient by design and is overwritten, not appended to, at the next re-mix. Written solely by public.set_session_stations (D3); private.session_round_guard (D3) rejects a direct UPDATE. Shape: {"exercise_position": int, "stations": [{"name": text, "lifter_ids": [uuid], "turn_order": [uuid]}]}. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D1.';

COMMENT ON COLUMN public.sessions.round IS
  'The server-owned round counter (spec section 6: "so every client agrees when a round closes") -- decision 4, because the shipped organizer-or-participant UPDATE policy has no column list and would otherwise let any participant write any number here. Advanced only by public.advance_round (D3), which no-ops on a stale p_expected_round the same way advance_turn already no-ops on a stale turn; private.session_round_guard (D3) rejects a direct UPDATE. Starts at 1, the round every shipped session is already in. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D1.';

COMMENT ON COLUMN public.sessions.round_started_at IS
  'Stamped by public.advance_round (D3) in the same UPDATE that increments round; NULL until a session''s first round is opened. This is the timestamp the round-close predicate (D3) measures set_logs.logged_at against, so a set logged before the round opened never counts toward closing it. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D1.';
