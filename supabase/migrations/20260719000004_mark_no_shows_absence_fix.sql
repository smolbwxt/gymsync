-- ============================================================
-- Fix-forward for 20260719000003_mark_no_shows.sql (already applied to the
-- live DB — applied migrations are append-only in this repo, so this ships
-- as a NEW migration that CREATE OR REPLACEs the function rather than
-- editing 20260719000003 in place).
-- ============================================================
--
-- ── FINDING 1 (Critical): the flip filter swept up present participants ────
-- 20260719000003's participant filter was
--   COALESCE(sp.check_in_state, 'invited') IN ('invited', 'online', 'late')
-- Read in isolation that looks like "hasn't arrived yet," but in this schema
-- 'late' is NOT an absence state. evaluate_lateness (re-declared with the
-- engine GUC in 20260714000001_session_engine_rpcs.sql, lines 29-31) only
-- ever sets check_in_state = 'late' here:
--   WHEN sp.check_in_at IS NOT NULL AND sp.check_in_at > v_scheduled THEN 'late'
-- i.e. 'late' means "she checked in (check_in_at IS NOT NULL), just after
-- scheduled_for" — she is PRESENT. The old filter therefore flipped actively
-- participating members to no_show:
--   scenario — a session starts 20 minutes late; a member who checked in at
--   +18 minutes is marked 'late' by evaluate_lateness (present, arrived
--   late); the very next mark_no_shows() cron tick (every minute, per
--   20260719000003's cron.schedule) then swept her into 'no_show' anyway,
--   because 'late' was in the IN-list — breaking turn rotation
--   (advance_turn's `check_in_state <> 'no_show'` liveness filter,
--   20260714000001_session_engine_rpcs.sql) and the burpee ledger
--   (group_burpee_ledger's no_show_count, 20260717000002_burpee_ledger_rpc.sql)
--   for someone mid-workout.
-- Flow 6's actual intent (docs/superpowers/specs/2026-06-28-gymsync-design.md,
-- line 815) is ABSENCE beyond threshold, not lateness per se: "If
-- late_minutes exceeds threshold (default 15), check_in_state → no_show;
-- session continues without her." A present-but-late arrival is exactly the
-- "she can still join late" case the same Flow explicitly protects.
--
-- Fix: keep the state-membership IN-list (cheap idempotency guard — once a
-- row is 'no_show' it no longer matches, and it also excludes 'ready' without
-- an extra clause), but AND it with the real, load-bearing absence
-- predicate: `sp.check_in_at IS NULL`. A participant is only swept into
-- no_show if she never checked in at all. This is belt-and-braces by
-- design — even if some future code path ever sets check_in_state='late'
-- without check_in_at (none does today), the absence predicate still
-- protects her.
--
-- ── FINDING 2 (Important): malformed threshold aborted the whole cron tick ─
-- The old cast `(s.late_penalty->>'no_show_after_minutes')::int` raises for
-- any present-but-unparseable value (e.g. an organizer-settings bug writes
-- '"abc"'). Because mark_no_shows() runs the flip as a single UPDATE across
-- every eligible session in one statement, one bad session's cast failure
-- aborted the entire statement — no session's participants got processed
-- that tick, not just the malformed one. Fixed defensively: only attempt the
-- cast when the value is present and looks like a non-negative integer
-- (regex guard), otherwise fall through to the same default-15 the
-- original per_minute-style COALESCE idiom uses. A malformed value degrades
-- to "use the default," not "crash the tick."
-- ============================================================

CREATE OR REPLACE FUNCTION public.mark_no_shows() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.session_participants sp
  SET check_in_state = 'no_show'
  FROM public.sessions s
  WHERE sp.session_id = s.id
    AND s.state IN ('lobby_open', 'in_progress')
    AND s.scheduled_for IS NOT NULL
    AND s.scheduled_for
          + (
              -- Defensive cast: only parse no_show_after_minutes as an int
              -- when it matches ^\d+$ (present, non-negative integer text).
              -- Anything else (missing key, 'abc', a decimal, a negative
              -- sign) falls through the CASE with no match -> NULL ->
              -- COALESCE default of 15. This can never raise, so one
              -- session's malformed late_penalty can't abort the UPDATE for
              -- every other session in the same tick.
              COALESCE(
                (CASE WHEN s.late_penalty ->> 'no_show_after_minutes' ~ '^\d+$'
                      THEN (s.late_penalty ->> 'no_show_after_minutes')::int
                 END),
                15
              ) * interval '1 minute'
            )
        < now()
    -- COALESCE(check_in_state, 'invited'): mirrors push_session_lobby_open's
    -- "who aren't already present" convention (20260716000001_push_schema.
    -- sql) treating a NULL row the same as 'invited'. Every current INSERT
    -- path (join_session_by_code, invite_new_member_to_future_sessions,
    -- live_plumbing's join-by-code rejoin, and the client's own session-
    -- create/invite writes) always sets an explicit value, so this is a
    -- defensive no-op today, not a fix for an observed bug.
    AND COALESCE(sp.check_in_state, 'invited') IN ('invited', 'online', 'late')
    -- The real absence predicate (Finding 1): 'late' means present-but-late
    -- in this schema (evaluate_lateness only sets it when check_in_at IS NOT
    -- NULL), so never sweep a participant who has actually checked in.
    AND sp.check_in_at IS NULL;
END;
$$;

-- No REVOKE / cron.schedule() re-run needed: CREATE OR REPLACE preserves the
-- function's existing REVOKE EXECUTE grants (set once in 20260719000003) and
-- the cron job (also from 20260719000003) already dispatches by name
-- (`SELECT public.mark_no_shows()`), so it picks up this new body on its
-- very next tick with no re-registration.
