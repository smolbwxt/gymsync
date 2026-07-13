-- ============================================================
-- Phase 3d Task 2 fix round: catch-up-safe reminder window;
-- pg_net response-table retention documented (no code change needed).
-- ============================================================
-- FIX 1 (important, live in prod): the 15-minute reminder predicate in
-- 20260716000003_push_cron.sql was boundary-exact — a 60-second-wide window
-- (`scheduled_for >= now()+14min AND < now()+15min`) checked by a 60-second
-- cron tick, with zero slack. Any single delayed or dropped tick (deploy,
-- Supabase platform hiccup, a slow prior statement in the same function)
-- causes scheduled_for to sail past the window entirely — `reminded_at
-- IS NULL` never gets satisfied again on a later tick because scheduled_for
-- is now outside [now()+14min, now()+15min) too, just on the wrong side.
-- That session silently never gets its reminder. There was no way to
-- observe this from pgTAP (which runs the function exactly once or twice
-- per assertion, never simulating a missed tick), so it shipped unnoticed
-- in 20260716000003.
--
-- Fix: widen the predicate to the catch-up-safe unbounded shape —
--   scheduled_for - interval '15 minutes' <= now() AND scheduled_for > now()
-- i.e. "any scheduled session with 15 minutes or less until it starts, that
-- hasn't been reminded yet, and hasn't started yet." This has no artificial
-- upper time-since-window-opened bound: a session stays eligible on every
-- tick from the moment it enters the 15-minute lead time until it starts,
-- so a delayed/dropped tick just means the NEXT tick catches it instead —
-- `reminded_at IS NULL` remains the sole (and correct) idempotency guard,
-- exactly as it already was for the idle/abandon steps below.
--
-- Only the reminder step changes. The idle-30, idle-60, and abandon steps,
-- the activity-tracking triggers/functions, touch_session_activity, and
-- push_drain_dispatch are copied forward IDENTICALLY from
-- 20260716000003_push_cron.sql — no other behavior changes in this
-- migration.
--
-- REVOKE re-issued unconditionally: CREATE OR REPLACE FUNCTION does NOT
-- reset a previously-issued explicit REVOKE on the same function signature
-- (grants are per-role ACL entries on the function's pg_proc row, which
-- CREATE OR REPLACE does not touch when the signature is unchanged) — but
-- per the fix brief this is re-verified by the pgTAP suite's existing
-- 'clients cannot call enqueue_scheduled_pushes directly' assertion
-- (42501), not just asserted here. The REVOKE line below is included
-- unconditionally regardless, as the safest option, and is a no-op if the
-- grant state was already correct.
-- ============================================================

CREATE OR REPLACE FUNCTION public.enqueue_scheduled_pushes()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec record;
BEGIN
  -- ── 15-minute reminder ────────────────────────────────────────────────
  -- Catch-up-safe window: any scheduled_for within the next 15 minutes
  -- (and not yet started) that hasn't been reminded is eligible on every
  -- tick, so a delayed or dropped cron tick can never cause a session to
  -- be silently skipped — the next tick just catches it a little later.
  -- reminded_at IS NULL is the sole idempotency guard (mirrors the
  -- idle-30/idle-60/abandon steps below, which never had a boundary-exact
  -- window in the first place). scheduled_for IS NOT NULL stays explicit
  -- so NULL-scheduled sessions are unambiguously excluded.
  FOR rec IN
    UPDATE public.sessions
    SET reminded_at = now()
    WHERE state = 'scheduled'
      AND scheduled_for IS NOT NULL
      AND scheduled_for - interval '15 minutes' <= now()
      AND scheduled_for > now()
      AND reminded_at IS NULL
    RETURNING id
  LOOP
    PERFORM public.enqueue_push(sp.user_id, 'session_reminder_15min',
      jsonb_build_object('session_id', rec.id))
    FROM public.session_participants sp
    WHERE sp.session_id = rec.id;
  END LOOP;

  -- ── Idle 30min → organizer ───────────────────────────────────────────
  -- COALESCE(last_activity_at, started_at): a freshly-started session with
  -- zero activity yet has last_activity_at = NULL; started_at is the
  -- correct baseline for the idle clock in that case (otherwise a session
  -- with no activity at all would never trip the ladder).
  FOR rec IN
    UPDATE public.sessions
    SET idle_30_notified_at = now()
    WHERE state = 'in_progress'
      AND COALESCE(last_activity_at, started_at) < now() - interval '30 minutes'
      AND idle_30_notified_at IS NULL
    RETURNING id, organizer_id
  LOOP
    PERFORM public.enqueue_push(rec.organizer_id, 'session_idle_30min',
      jsonb_build_object('session_id', rec.id));
  END LOOP;

  -- ── Idle 60min → all participants ────────────────────────────────────
  FOR rec IN
    UPDATE public.sessions
    SET idle_60_notified_at = now()
    WHERE state = 'in_progress'
      AND COALESCE(last_activity_at, started_at) < now() - interval '60 minutes'
      AND idle_60_notified_at IS NULL
    RETURNING id
  LOOP
    PERFORM public.enqueue_push(sp.user_id, 'session_idle_60min',
      jsonb_build_object('session_id', rec.id))
    FROM public.session_participants sp
    WHERE sp.session_id = rec.id;
  END LOOP;

  -- ── Abandon at 6 hours ────────────────────────────────────────────────
  -- No push event fires here — announce_session_lifecycle already fans a
  -- system_session chat message ("🌫️ Session abandoned") out to the group
  -- on this exact state transition (20260712000002_session_system_messages.
  -- sql). The state transition itself is the idempotency guard (it can only
  -- match state='in_progress' once). Engine GUC bypass wraps the UPDATE
  -- defensively, mirroring the idiom in 20260714000001_session_engine_rpcs.
  -- sql, in case a future state-guard trigger is added to sessions — none
  -- exists today (only session_participants has engine_guard).
  PERFORM set_config('gymsync.engine', 'on', true);
  UPDATE public.sessions
  SET state = 'abandoned',
      completed_at = COALESCE(last_activity_at, started_at)
  WHERE state = 'in_progress'
    AND COALESCE(last_activity_at, started_at) < now() - interval '6 hours';
  PERFORM set_config('gymsync.engine', '', true);
END;
$$;

-- Not a client RPC: unrestricted client access would let anyone force
-- reminders/idle-pushes/abandon transitions ahead of schedule. Mirrors the
-- enqueue_push REVOKE in 20260716000002_push_hardening.sql. Re-issued
-- unconditionally here (see header comment) even though CREATE OR REPLACE
-- does not reset an existing REVOKE on an unchanged signature.
REVOKE EXECUTE ON FUNCTION public.enqueue_scheduled_pushes() FROM PUBLIC, anon, authenticated;


-- ============================================================
-- FIX 2 (owed answer, no code change): pg_net response-table retention
-- ============================================================
-- Queried directly against this project's live DB (not assumed):
--
--   select name, setting, unit, category from pg_settings
--   where name ilike '%pg_net%';
--   -- pg_net.ttl           = '6 hours'
--   -- pg_net.batch_size    = '200'
--   -- pg_net.database_name = 'postgres'
--
--   select extversion from pg_extension where extname = 'pg_net';
--   -- 0.20.3
--
--   select count(*) from net._http_response;
--   -- 0 (push_drain_dispatch() has been a guarded no-op since
--   --    20260716000003 — the 'push_drain_auth' Vault secret is not yet
--   --    seeded, Task 7 — so no net.http_post call has ever actually run
--   --    on this project; the 0 count reflects "no traffic yet", not
--   --    "sweeping observed in action")
--
-- pg_net (>= 0.7, this project runs 0.20.3) ships its own background
-- worker that periodically deletes net._http_response rows older than
-- pg_net.ttl — this is automatic, built into the extension, not something
-- this project's migrations need to schedule or maintain. With ttl = 6h,
-- retention is bounded: at steady state the table holds at most ~6 hours
-- of response rows, decaying on its own. This is NOT genuinely unbounded,
-- so per the fix brief no cleanup cron job is added here.
--
-- Once Task 7 seeds the Vault secret and push_drain_dispatch() starts
-- actually calling net.http_post every minute, worth a follow-up spot
-- check (`select count(*), min(created), max(created) from
-- net._http_response;`) to confirm the worker is pruning as expected under
-- real traffic — flagged, not actioned, since there is no real traffic to
-- observe yet.
-- ============================================================
