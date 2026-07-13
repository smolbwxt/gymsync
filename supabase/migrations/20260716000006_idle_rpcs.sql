-- ============================================================
-- Phase 3d Task 5: idle-ladder action RPCs — wrap_up_session,
-- still_going. Backs the IDLE_ACTIONS push category's "Wrap Up" /
-- "Still Going" notification actions (non-foreground — called via a
-- direct PostgREST RPC POST from the notification handler, not the
-- supabase-swift client; see PushReceiver.swift's callIdleRPC()).
-- ============================================================
-- NUMBERING NOTE: the brief's original filename was
-- 20260716000004_idle_rpcs.sql, but that number was claimed by
-- 20260716000004_reminder_window_fix.sql (a same-day fix-forward), and
-- 20260716000005 by 20260716000005_claim_push_batch.sql. Renumbered to
-- 20260716000006 per the orchestrator's instruction.

-- ── wrap_up_session: end the session early, same as the 6h auto-abandon's
--    completed_at convention (COALESCE(last_activity_at, started_at), not
--    now()) — the session "ended" when activity actually stopped, not when
--    someone happened to tap the button. Participant-gated identically to
--    touch_session_activity (20260716000003_push_cron.sql): organizer or
--    any participant may call it for their own session.
CREATE OR REPLACE FUNCTION public.wrap_up_session(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR public.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may wrap up the session' USING ERRCODE = 'P0001';
  END IF;

  -- Engine GUC bypass: no guard trigger currently exists on public.sessions
  -- (only session_participants has engine_guard, per 20260714000001_
  -- session_engine_rpcs.sql), but this UPDATE touches `state` — the same
  -- field the cron abandon-transition defensively wraps
  -- (20260716000003_push_cron.sql) — so this mirrors that idiom in case a
  -- future state-guard trigger is added.
  PERFORM set_config('gymsync.engine', 'on', true);

  UPDATE public.sessions
  SET state        = 'completed',
      completed_at = COALESCE(last_activity_at, started_at)
  WHERE id = p_session AND state = 'in_progress';

  PERFORM set_config('gymsync.engine', '', true);
END;
$$;


-- ── still_going: reset the idle clock so the ladder can re-fire from 30min
--    again on the next real idle stretch (design doc Flow 6: "Still Going
--    resets 30-min timer"). Clears BOTH idle-notified flags (not just the
--    30-min one) so a 60-min-tier push that already fired can also re-fire
--    later — matches the "resets the timer" framing, not "dismiss this one
--    tier only". Only touches last_activity_at/idle flags, not `state`, so
--    (unlike wrap_up_session above) there's no engine-guard-adjacent field
--    to defensively wrap — same as touch_session_activity's own UPDATE.
CREATE OR REPLACE FUNCTION public.still_going(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR public.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may confirm the session is still going' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.sessions
  SET last_activity_at    = now(),
      idle_30_notified_at = NULL,
      idle_60_notified_at = NULL
  WHERE id = p_session AND state = 'in_progress';
END;
$$;

-- No REVOKE on either function — both are intended client-callable RPCs
-- (default PostgREST/PUBLIC EXECUTE grant is correct), same as
-- touch_session_activity. Unlike enqueue_scheduled_pushes/push_drain_dispatch,
-- these are the actual notification-action entry points, not internal
-- maintenance jobs.
