-- 20260822000002_clip_retention.sql
--
-- Storage v1.5 (owner "A feels right" 2026-08-22): retention becomes a
-- kept promise instead of an accumulating fib. Flat windows for now -
-- 90 days PRO, 30 days coach-linked - stamped by the client at insert;
-- paid extensions later just move retain_until (billing pass).
--
-- Sweeper shape mirrors push_drain_dispatch exactly (20260716000003):
-- pg_cron -> SECURITY DEFINER dispatcher reading the ALREADY-SEEDED
-- 'push_drain_auth' Vault secret (reused deliberately: one shared
-- internal-function secret, zero new manual seeding steps) ->
-- net.http_post to the clip-sweeper Edge Function, which deletes the
-- storage objects through the storage API (the only path that actually
-- removes the S3 blobs) and then the rows. Guarded no-op while the
-- secret is missing; pg_net failures are async and harmless.
ALTER TABLE public.set_log_clips
  ADD COLUMN IF NOT EXISTS retain_until timestamptz NOT NULL DEFAULT now() + interval '30 days',
  ADD COLUMN IF NOT EXISTS byte_size bigint;

CREATE INDEX IF NOT EXISTS set_log_clips_retain_idx
  ON public.set_log_clips (retain_until);

CREATE OR REPLACE FUNCTION public.clip_sweep_dispatch() RETURNS void
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
    url     := 'https://chjkkwqwdlmaxacwglzm.supabase.co/functions/v1/clip-sweeper',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key,
                                   'Content-Type', 'application/json'),
    body    := '{}'::jsonb
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.clip_sweep_dispatch() FROM PUBLIC, anon, authenticated;

-- Hourly is plenty: retention windows are measured in days, and an
-- hourly batch of 200 clears any realistic backlog.
SELECT cron.schedule('clip-sweep', '17 * * * *',
  $$SELECT public.clip_sweep_dispatch()$$);
