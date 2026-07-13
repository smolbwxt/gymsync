-- ============================================================
-- Phase 3d Task 5 fix round 1: register_push_device — same-device
-- cross-user re-registration.
-- ============================================================
-- PROBLEM: PushDeviceRepository.upsert (client-side `.upsert(onConflict:
-- "apns_token")`) silently fails RLS when a token is re-registered under a
-- different auth.uid() than the row's current owner. push_devices' "owner
-- manages own devices" policy (20260716000001_push_schema.sql) is FOR ALL,
-- gating every command — including the UPDATE half of an upsert — on
-- `user_id = auth.uid()`. On first insert that's the new user's own row, so
-- it passes; but on `ON CONFLICT (apns_token) DO UPDATE`, Postgres evaluates
-- the UPDATE's USING/WITH CHECK against the EXISTING (old-owner) row, which
-- fails RLS for the new user. PostgREST reports this as 0 rows
-- affected/returned rather than surfacing an error, so a physical device
-- reused across accounts (sign out, sign in as someone else) silently keeps
-- delivering push to the previous owner.
--
-- FIX: a SECURITY DEFINER function that pins auth.uid() into the row on
-- BOTH branches of the upsert (never trusts a client-supplied user_id), so
-- it can freely reassign ownership regardless of who currently holds the
-- row. Self-gated by the auth.uid() IS NOT NULL check below — a caller can
-- only ever register the token to THEMSELVES, so this is safe to leave
-- client-callable directly (no need to route it through a service-role edge
-- function).
CREATE OR REPLACE FUNCTION public.register_push_device(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'must be signed in to register a push device' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.push_devices (user_id, apns_token, last_seen_at)
  VALUES (auth.uid(), p_token, now())
  ON CONFLICT (apns_token) DO UPDATE
    SET user_id      = auth.uid(),
        last_seen_at = now();
END;
$$;

-- Client-callable — self-gated by the auth.uid() check above, and every
-- column write is pinned to auth.uid() rather than a client-supplied value,
-- so there's no way to reassign a token to someone else's account. Newly
-- created functions get PUBLIC EXECUTE by default, which anon inherits, so
-- REVOKE FROM PUBLIC, anon and then GRANT back explicitly TO authenticated
-- (same revoke-then-grant idiom as claim_push_batch in
-- 20260716000005_claim_push_batch.sql) — do NOT include authenticated in
-- the REVOKE.
REVOKE EXECUTE ON FUNCTION public.register_push_device(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device(text) TO authenticated;
