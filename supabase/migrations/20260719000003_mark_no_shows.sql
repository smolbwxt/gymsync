-- ============================================================
-- Phase S Task 1: no_show production wiring (cron + threshold + rejoin)
-- ============================================================
-- Closes a recorded product gap: no code path has ever set
-- session_participants.check_in_state = 'no_show'. The value has been a
-- valid enum member since session_participants was created
-- (20260709000006_create_sessions.sql), and several downstream consumers
-- already branch on it — advance_turn's `check_in_state <> 'no_show'`
-- liveness filter (20260714000001_session_engine_rpcs.sql),
-- join_session_by_code's no_show-rejoin ON CONFLICT clause
-- (20260714000002_live_plumbing.sql), group_burpee_ledger's no_show_count
-- (20260717000002_burpee_ledger_rpc.sql) — but nothing has ever produced a
-- 'no_show' row to feed them. This migration adds the producer.
--
-- Design doc Flow 6 ("Late arrival + idle detection",
-- docs/superpowers/specs/2026-06-28-gymsync-design.md, line 815): "If
-- late_minutes exceeds threshold (default 15), check_in_state → no_show;
-- session continues without her. She can still join late but burpees
-- compound."
--
-- ── THRESHOLD KEY (citation) ─────────────────────────────────────────────────
-- evaluate_lateness (20260712000001_sessions_phase3_columns.sql, re-declared
-- identically + engine GUC in 20260714000001_session_engine_rpcs.sql) reads
-- the per-minute burpee rate as `COALESCE((late_penalty->>'per_minute')::int,
-- 5)` off sessions.late_penalty jsonb (NOT NULL DEFAULT
-- '{"exercise":"burpee","per_minute":5}'::jsonb, added in the same
-- migration). No no-show-threshold key exists anywhere in that jsonb today —
-- confirmed by grepping every migration for `late_penalty`/
-- `default_late_penalty` and by BurpeeLedgerView.swift's own "SCHEMA GAP #2"
-- comment: the client renders the p25 proof's "no-show = 25" config clause
-- as absent rather than inventing a number, because "`late_penalty` jsonb
-- only ever carries `per_minute`". groups.default_late_penalty jsonb
-- (20260710000002_create_groups.sql) is the group-level counterpart but is
-- dead schema — no function or client insert path ever reads it to populate
-- a new session's late_penalty (BurpeeLedgerView.swift "SCHEMA GAP #3": no
-- write path either), so it is not a live fallback source and this migration
-- does not consult it, consistent with evaluate_lateness never reading it.
--
-- This migration introduces the key: late_penalty->>'no_show_after_minutes',
-- read with the exact same COALESCE-with-default idiom as per_minute,
-- defaulting to 15 per the design doc's explicit "(default 15)". No column
-- or default-value migration is needed — it is simply a new key read out of
-- the existing jsonb blob, absent on every current row until an organizer
-- (via a future settings UI, out of this task's scope — same SCHEMA GAP #3
-- as the per_minute editor) sets it.
--
-- ── CRON IDIOM (citation) ────────────────────────────────────────────────────
-- Matches enqueue_scheduled_pushes (20260716000003_push_cron.sql, corrected
-- 20260716000004_reminder_window_fix.sql): pure-SQL SECURITY DEFINER
-- function, no client EXECUTE grant, scheduled via cron.schedule() at the
-- same '* * * * *' (every-minute) cadence as the reminder/idle/abandon
-- ladder. cron.schedule()'s upsert-by-jobname semantics (verified against
-- this project, pg_cron 1.6.4, documented in 20260716000003's header) make
-- re-applying this migration idempotent, same as push-enqueue/push-drain.
-- Unlike push_drain_dispatch, mark_no_shows() makes no HTTP call, so it
-- needs neither pg_net nor the Vault-secret pattern — judged the same way
-- the idle_rpcs precedent (20260716000006_idle_rpcs.sql, wrap_up_session/
-- still_going) is plain SQL with no HTTP: mark_no_shows() only reads/writes
-- sessions/session_participants rows directly.
--
-- The WHERE predicate (`s.scheduled_for + threshold < now()`, no upper
-- bound) is catch-up-safe by construction — the same open-ended shape as the
-- idle-30/idle-60/abandon steps in enqueue_scheduled_pushes, NOT the
-- original boundary-exact 1-minute-wide reminder window that
-- 20260716000004_reminder_window_fix.sql had to fix-forward after it
-- silently dropped sessions on a delayed cron tick. A delayed or dropped
-- tick here just means the next tick catches it. Idempotency falls out of
-- the state-membership guard itself (no separate `*_notified_at` column
-- needed): once a row is flipped to 'no_show' it no longer matches
-- `IN ('invited','online','late')`, so re-running the function is a no-op
-- for that row.
--
-- ── ENGINE-GUARD / CHECKIN-WINDOW-GUARD INTERACTION (no bypass needed) ─────
-- engine_guard (20260714000001_session_engine_rpcs.sql) only raises when
-- late_minutes/burpees_owed/turn_order change on a self-row UPDATE — it does
-- not gate check_in_state at all. checkin_window_guard
-- (20260715000003_checkin_window.sql) only fires when
-- `NEW.check_in_state = 'ready'` (its own header comment: "Other transitions
-- (online, late, no_show, etc.) are untouched"). mark_no_shows() only ever
-- sets check_in_state = 'no_show', so neither trigger requires this function
-- to set the gymsync.engine bypass GUC the way start_session/wrap_up_session
-- do for their `sessions.state` writes.
--
-- ── LATE RE-JOIN, Flow 6 ("she can still join late") ────────────────────────
-- SessionRepository.checkIn(sessionID:method:) (GymSyncApp/GymSync/Models/
-- SessionRepository.swift) issues a bare
-- `UPDATE session_participants SET check_in_state='ready', check_in_at=now(),
-- check_in_method=... WHERE session_id=... AND user_id=auth.uid()`, RLS-gated
-- by the "participant updates own check-in" policy
-- (20260712000001_sessions_phase3_columns.sql: `USING (user_id = auth.uid())
-- WITH CHECK (user_id = auth.uid())` — no restriction on the FROM state, so
-- a 'no_show' row is just as updatable as any other). That UPDATE touches
-- none of late_minutes/burpees_owed/turn_order, so engine_guard never fires
-- for it; it sets check_in_state='ready' (not 'no_show'), so
-- checkin_window_guard only enforces its 20-minute-before-start floor, which
-- a no_show rejoin (by definition already well past scheduled_for) always
-- clears. Net: the EXISTING check-in path already permits a no_show → ready
-- flip with zero code changes — verified by pgTAP below (mark_no_shows_
-- test.sql), not just asserted here. No 3b guard constrains this
-- transition; engine_guard's penalty-field guard and this flow operate on
-- disjoint columns, so there is nothing to reconcile.
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
          + (COALESCE((s.late_penalty ->> 'no_show_after_minutes')::int, 15) * interval '1 minute')
        < now()
    -- COALESCE(check_in_state, 'invited'): mirrors push_session_lobby_open's
    -- "who aren't already present" convention (20260716000001_push_schema.
    -- sql) treating a NULL row the same as 'invited'. Every current INSERT
    -- path (join_session_by_code, invite_new_member_to_future_sessions,
    -- live_plumbing's join-by-code rejoin, and the client's own session-
    -- create/invite writes) always sets an explicit value, so this is a
    -- defensive no-op today, not a fix for an observed bug.
    AND COALESCE(sp.check_in_state, 'invited') IN ('invited', 'online', 'late');
END;
$$;

-- Not a client RPC: unrestricted access would let anyone force no-show
-- transitions ahead of schedule (or grief other participants by flipping
-- them early). Mirrors the enqueue_scheduled_pushes REVOKE in
-- 20260716000003_push_cron.sql.
REVOKE EXECUTE ON FUNCTION public.mark_no_shows() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('mark-no-shows', '* * * * *',
  $$SELECT public.mark_no_shows()$$);
