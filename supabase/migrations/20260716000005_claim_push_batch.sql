-- ============================================================
-- Phase 3d Task 3: claim_push_batch — atomic outbox claim for
-- push-dispatcher (Edge Function, this same task).
-- ============================================================
-- NUMBERING NOTE: the task brief speculated this might land as
-- 20260716000003_claim_push_batch.sql, but that number was already claimed
-- by 20260716000003_push_cron.sql (Task 2). Renumbered to 20260716000005
-- (000004 is 20260716000004_reminder_window_fix.sql, already applied).
--
-- Why a SQL function instead of a plain REST UPDATE...RETURNING: PostgREST
-- can't express "UPDATE a LIMIT-bounded subset ordered by id, skipping
-- locked rows, in one atomic statement" — that shape requires a real SQL
-- statement (UPDATE ... WHERE id IN (SELECT ... FOR UPDATE SKIP LOCKED)
-- LIMIT p_limit ... RETURNING *), not a PostgREST filter/patch. Exposing it
-- as an RPC lets the dispatcher call it via the supabase-js service client's
-- .rpc('claim_push_batch', { p_limit: 100 }) — one round trip, no lost
-- updates or duplicate claims when Task 7's scheduled drain and a manual
-- invocation happen to overlap.
CREATE OR REPLACE FUNCTION public.claim_push_batch(p_limit int DEFAULT 100)
RETURNS SETOF public.push_queue
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.push_queue
  SET attempts = attempts + 1
  WHERE id IN (
    SELECT id FROM public.push_queue
    WHERE sent_at IS NULL AND attempts < 5
    ORDER BY id
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
$$;

-- Same convention as enqueue_push / enqueue_scheduled_pushes / push_drain_dispatch
-- (20260716000002_push_hardening.sql, 20260716000003_push_cron.sql): newly
-- created functions get PUBLIC EXECUTE by default, which anon/authenticated
-- inherit. REVOKE first, then GRANT back only to service_role — the REVOKE
-- applies to service_role too (it is not exempt), so the explicit GRANT is
-- required or push-dispatcher's own service-role RPC call would 42501.
REVOKE EXECUTE ON FUNCTION public.claim_push_batch(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_push_batch(int) TO service_role;
