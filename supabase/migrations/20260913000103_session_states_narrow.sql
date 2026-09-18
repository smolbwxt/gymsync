-- 20260913000103_session_states_narrow.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md.
-- Plan: docs/superpowers/plans/2026-09-13-group-session-phase-b-plan.md,
-- task D7, "the five data decisions," decision 6 -- "the three dead
-- states" -- closed. Phase A's grep found 'editing', 'voting' and 'locked'
-- unreachable (no code path ever writes them) and ruled them not
-- droppable in Phase A, handing the cost to Phase B with the grep
-- attached. Reproduced verbatim here:
--
--   Kind                                  | Where
--   --------------------------------------|-------------------------------
--   the CHECK                             | 20260709000006_create_sessions
--                                         | .sql:5-7
--   a server trigger's deny-list          | 20260803000002_set_logs_reject
--                                         | _prelive.sql:19
--   an edge function's allow-list         | supabase/functions/livekit-
--                                         | token/index.ts:88 + test.ts:451
--   a pgTAP fixture that writes 'editing' | supabase/tests/rls_proposals
--                                         | _test.sql:19
--   a QA seed that writes 'voting' and    | scripts/seed_qa_fixtures.js:99,
--   'locked'                              | :335
--   read-side bucketing, Swift            | SessionRepository.swift:477,
--                                         | LobbyView.swift:120,431,
--                                         | GroupSessionLiveView.swift:347,
--                                         | CrewRoomView.swift:621,
--                                         | GroupView.swift:407,
--                                         | SocialTabView.swift:645,
--                                         | SentryContext.swift:45
--
-- Ruling: this migration narrows the CHECK and fixes the four non-Swift
-- sites in the same commit (livekit-token's allow-list + its test, the QA
-- seed's two arrays, the rls_proposals pgTAP fixture). The server
-- trigger's deny-list (20260803000002_set_logs_reject_prelive.sql) is left
-- untouched -- it becomes a harmless superset once no row can hold the
-- three dropped values, and D7's file list does not include it. The
-- Swift read-side bucketing sets are S13's mechanical cleanup, proved by
-- grep once no row can hold the value.
--
-- Runs after D1 (20260913000101_session_style_stations_round.sql) and D3
-- (20260913000102_session_round_engine.sql), both of which also alter
-- public.sessions -- re-declaring a CHECK on the same table after they
-- land keeps the migration history readable.
--
-- The UPDATE below is what makes the CHECK swap safe regardless of which
-- project runs it: a live, read-only count taken immediately before
-- writing this migration (against chjkkwqwdlmaxacwglzm) found 0 'editing',
-- 2 'voting' and 2 'locked' rows out of 172 sessions total -- exactly the
-- QA seed's own six-row fixture array (scripts/seed_qa_fixtures.js:335)
-- from a prior run, which this same commit also rewrites so it stops
-- producing them. No production code path has ever written any of the
-- three; this UPDATE is a reconciliation, not a behavior change.
UPDATE public.sessions
   SET state = 'lobby_open'
 WHERE state IN ('editing', 'voting', 'locked');

ALTER TABLE public.sessions DROP CONSTRAINT sessions_state_check;
ALTER TABLE public.sessions ADD CONSTRAINT sessions_state_check
  CHECK (state IN ('scheduled', 'lobby_open', 'in_progress', 'completed', 'abandoned'));
