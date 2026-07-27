-- ============================================================
-- Monetization plumbing: profiles.pro_until (server-written entitlement).
-- ============================================================
-- Direction (2026-07-27): freemium Pro tier — social layer free forever,
-- Pro gates the personal-depth layer (programs, deep history, unlimited
-- routines). SHIPPED DORMANT: nothing is gated until the client-side
-- Monetization.paywallEnabled flag flips, but the entitlement must exist
-- first because retrofitting it under live users is far worse.
--
-- THE SECURITY SHAPE, same as is_curator: `pro_until` is written ONLY by
-- server-side receipt validation (App Store Server webhook -> edge
-- function, service role) — a client-writable is_pro would be spoofable in
-- an afternoon. The guard trigger below extends the exact
-- guard_is_curator posture (20260717000004): column-level REVOKE alone is
-- a no-op against this project's table-wide UPDATE grant.
--
-- Timestamp, not boolean: subscriptions expire, and "Pro until <date>"
-- also expresses launch grandfathering (everyone pre-paywall granted a
-- year) with zero extra machinery. NULL = never entitled.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS pro_until timestamptz;

CREATE OR REPLACE FUNCTION public.guard_pro_until()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('role', true) IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.pro_until IS NOT NULL THEN
        RAISE EXCEPTION 'pro_until is not client-writable'
          USING ERRCODE = '42501';
      END IF;
    ELSIF NEW.pro_until IS DISTINCT FROM OLD.pro_until THEN
      RAISE EXCEPTION 'pro_until is not client-writable'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_pro_until ON public.profiles;
CREATE TRIGGER profiles_guard_pro_until
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_pro_until();
