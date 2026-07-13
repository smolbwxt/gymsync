-- ============================================================
-- Phase 3d Task 2: pg_cron enqueuers — reminders, idle ladder,
-- abandon; queue drain schedule.
-- ============================================================
-- NUMBERING NOTE: the original plan named this file
-- 20260716000002_push_cron.sql, but that number was claimed by
-- 20260716000002_push_hardening.sql (a same-day fix-forward for Task 1).
-- This migration is renumbered to 20260716000003.
--
-- SECRET-HANDLING DECISION (push-drain auth): Supabase Vault
-- (`supabase_vault` extension) is ALREADY INSTALLED on this project
-- (confirmed via `list_extensions` — schema `vault`, version 0.3.1), so we
-- use Vault rather than a `push_config` fallback table. push_drain_dispatch()
-- below reads `vault.decrypted_secrets` for a secret named 'push_drain_auth'
-- at RUN TIME (not baked into this migration). Seeding that secret is a
-- documented Task 7 step, run manually against the project:
--     select vault.create_secret('<service-or-shared-secret>', 'push_drain_auth');
-- Until that secret exists, push_drain_dispatch() is a guarded no-op (see
-- below) — it does not error and does not flood any log/response table.
--
-- pg_net SCHEMA RESOLUTION: Supabase's pg_net extension creates its own
-- `net` schema as part of its install script (independent of any `WITH
-- SCHEMA` qualifier passed to CREATE EXTENSION) and exposes net.http_post /
-- net.http_get there — this matches Supabase's own published examples.
-- Verified empirically against this project after applying this migration
-- (see task-2-report.md); `net.http_post` resolves correctly.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;


-- ── sessions: activity + idempotency columns ────────────────────────────────
ALTER TABLE public.sessions
  ADD COLUMN last_activity_at    timestamptz,
  ADD COLUMN reminded_at         timestamptz,
  ADD COLUMN idle_30_notified_at timestamptz,
  ADD COLUMN idle_60_notified_at timestamptz;

-- NOTE: idle_30_notified_at / idle_60_notified_at / last_activity_at are
-- reset by the "Still Going" RPC, which lands in Task 5's migration. This
-- migration only adds the columns and the enqueuer logic that reads/sets
-- them.


-- ============================================================
-- Activity tracking
-- ============================================================
-- Dossier §A.4: "Activity" = any new set_logs, soundboard broadcast, chat
-- message in session thread, or app foreground for >5s by any participant.
-- Soundboard broadcasts are Realtime-only (DB-invisible) — not coverable by
-- a row trigger; the client-foreground heartbeat (touch_session_activity)
-- is the catch-all for that case and for foregrounding.

-- ── set_logs INSERT → that session's last_activity_at ──────────────────────
CREATE OR REPLACE FUNCTION public.touch_session_activity_on_set_log() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.sessions
  SET last_activity_at = now()
  WHERE id = NEW.session_id AND state = 'in_progress';
  RETURN NEW;
END;
$$;

-- "zzpush_" prefix: set_logs already has an AFTER INSERT trigger
-- (pr_announce, 20260710000004_pr_system_messages.sql). Alphabetically-last
-- naming guarantees ours runs after it, matching the convention established
-- in 20260716000001_push_schema.sql (see that file's header comment). The
-- two triggers are independent so ordering doesn't affect correctness today.
CREATE TRIGGER zzpush_touch_activity_set_log
  AFTER INSERT ON public.set_logs
  FOR EACH ROW EXECUTE FUNCTION public.touch_session_activity_on_set_log();


-- ── chat_messages INSERT → in_progress session(s) in that group ────────────
-- Joins via sessions.group_id (per Task 2 contract), not chat_messages'
-- own optional session_id column — a group's live chat during a workout
-- counts as session activity regardless of whether a given message was
-- explicitly tagged with session_id. Guarded to state='in_progress' so this
-- can never resurrect a session that just got marked completed/abandoned by
-- the same top-level statement (announce_session_lifecycle's own
-- chat_messages INSERT, e.g. "Session abandoned", fires with the session's
-- new state already committed, so it does not re-touch last_activity_at).
--
-- author_id IS NULL guard: chat_messages.author_id is NULL for every
-- system-generated row (announce_session_lifecycle, announce_pr, etc. — see
-- "NULL = system" on the column, 20260710000003_create_chat.sql). Without
-- this guard, e.g. scheduling a brand-new session in a group that also has
-- an in_progress session triggers announce_session_lifecycle's "session
-- scheduled" system message, which would incorrectly reset the unrelated
-- in_progress session's idle clock even though no participant did anything.
-- Only human-authored messages (text/image/audio/soundboard_echo) count as
-- activity.
CREATE OR REPLACE FUNCTION public.touch_session_activity_on_chat() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.author_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.sessions
  SET last_activity_at = now()
  WHERE group_id = NEW.group_id AND state = 'in_progress';
  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_touch_activity_chat_message
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_session_activity_on_chat();


-- ── touch_session_activity: client foreground heartbeat RPC ────────────────
-- Called by the app when it foregrounds for >5s while a session is open
-- (Dossier §A.4) and covers soundboard broadcasts (Realtime-only, DB-
-- invisible to a row trigger). Any participant (not just the organizer) may
-- call this for their own session. No-ops (0 rows updated, no error) if the
-- session isn't in_progress — heartbeats from a just-ended session are
-- harmless stragglers, not something the client needs to handle specially.
CREATE OR REPLACE FUNCTION public.touch_session_activity(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR public.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may send an activity heartbeat' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.sessions
  SET last_activity_at = now()
  WHERE id = p_session AND state = 'in_progress';
END;
$$;
-- No REVOKE here — this is the intended client-callable RPC (default
-- PostgREST/PUBLIC EXECUTE grant is correct), unlike enqueue_scheduled_pushes
-- and push_drain_dispatch below.


-- ============================================================
-- enqueue_scheduled_pushes(): run every minute by pg_cron
-- ============================================================
CREATE OR REPLACE FUNCTION public.enqueue_scheduled_pushes()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec record;
BEGIN
  -- ── 15-minute reminder ────────────────────────────────────────────────
  -- Window: scheduled_for in [now()+14min, now()+15min). The 1-minute-wide
  -- window plus the reminded_at guard means each session gets exactly one
  -- reminder even if a cron tick runs a few seconds late. scheduled_for
  -- IS NOT NULL is explicit (not just implied by the range comparison) so
  -- NULL-scheduled sessions are unambiguously excluded.
  FOR rec IN
    UPDATE public.sessions
    SET reminded_at = now()
    WHERE state = 'scheduled'
      AND scheduled_for IS NOT NULL
      AND scheduled_for >= now() + interval '14 minutes'
      AND scheduled_for <  now() + interval '15 minutes'
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
-- enqueue_push REVOKE in 20260716000002_push_hardening.sql.
REVOKE EXECUTE ON FUNCTION public.enqueue_scheduled_pushes() FROM PUBLIC, anon, authenticated;


-- ============================================================
-- push_drain_dispatch(): drains push_queue via the push-dispatcher Edge
-- Function. Run every minute by pg_cron.
-- ============================================================
-- Guarded no-op while the Vault secret isn't seeded yet (Task 7) — IF v_key
-- IS NULL THEN RETURN, no exception, so a bare cron tick before Task 7 never
-- shows up as a cron.job_run_details failure. Once the secret is seeded but
-- before Task 7 deploys the Edge Function, net.http_post calls will 404;
-- pg_net failures are async/fire-and-forget and harmless per the design
-- brief — they do not raise inside this function or block subsequent ticks.
CREATE OR REPLACE FUNCTION public.push_drain_dispatch() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_key text;
BEGIN
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
   WHERE name = 'push_drain_auth'
   LIMIT 1;

  IF v_key IS NULL THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := 'https://chjkkwqwdlmaxacwglzm.supabase.co/functions/v1/push-dispatcher',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key,
                                   'Content-Type', 'application/json'),
    body    := '{}'::jsonb
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.push_drain_dispatch() FROM PUBLIC, anon, authenticated;


-- ============================================================
-- Cron schedules
-- ============================================================
-- Idempotency: the originally-planned approach was `DELETE FROM cron.job
-- WHERE jobname IN (...)` before scheduling, to be safe regardless of
-- cron.schedule()'s upsert semantics. Verified empirically against this
-- project: the migration-applying role does NOT have direct table
-- privileges on cron.job (`permission denied for table job`, 42501) — only
-- EXECUTE on the cron.* functions, which is the access Supabase actually
-- grants on hosted projects. cron.schedule() has upserted by job name since
-- pg_cron 1.4 (this project runs 1.6.4), so calling it again with the same
-- job name updates the existing job in place rather than erroring or
-- duplicating — that upsert IS the idempotency mechanism here, and it's
-- also the only one available given the permission model.
SELECT cron.schedule('push-enqueue', '* * * * *',
  $$SELECT public.enqueue_scheduled_pushes()$$);

SELECT cron.schedule('push-drain', '* * * * *',
  $$SELECT public.push_drain_dispatch()$$);
