-- Trainer enrollment rails (owner 2026-08-16, design:
-- docs/superpowers/specs/2026-08-16-trainer-enrollment-design.md):
-- capacity-based individual subscription + gym-sponsored seats. DORMANT —
-- nothing reads these until the trainer paywall flips; shipping the
-- schema first keeps migrations ahead of builds (house rule).

-- ── Entitlements: why this user may carry clients beyond the free taste ──
CREATE TABLE public.trainer_entitlements (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  source       text NOT NULL CHECK (source IN ('individual_sub', 'gym_seat')),
  -- Set for gym seats: the sponsoring venue. SET NULL on venue deletion —
  -- the entitlement survives until revoked (data never hostage; the
  -- portal owns cleanup).
  venue_id     uuid REFERENCES public.venues(id) ON DELETE SET NULL,
  -- NULL = the unlimited band.
  client_cap   integer,
  -- NULL = active until revoked (gym seats); subscriptions carry a window.
  active_until timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz
);

CREATE INDEX trainer_entitlements_user_idx ON public.trainer_entitlements(user_id);

ALTER TABLE public.trainer_entitlements ENABLE ROW LEVEL SECURITY;

-- Owner reads their own; a venue creator reads the seats their gym
-- sponsors (the admin surface). WRITES are service-role only — the
-- verify-entitlement edge fn and the web portal are the sole writers,
-- the M1 one-writer trust model.
CREATE POLICY "trainer reads own entitlements"
  ON public.trainer_entitlements FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.venues v
               WHERE v.id = venue_id AND v.created_by = auth.uid())
  );

-- ── Gym seat keys: provisioned off-app, redeemed in the Shop ──
CREATE TABLE public.gym_seat_keys (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id    uuid NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  code        text UNIQUE NOT NULL,
  client_cap  integer,
  redeemed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  redeemed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz
);

CREATE INDEX gym_seat_keys_venue_idx ON public.gym_seat_keys(venue_id);

ALTER TABLE public.gym_seat_keys ENABLE ROW LEVEL SECURITY;

-- The venue creator sees their block (administration); a redeemer sees
-- the key they hold. Provisioning is service-role only; redemption goes
-- through the RPC below (never a raw client write).
CREATE POLICY "seat keys readable by gym owner or redeemer"
  ON public.gym_seat_keys FOR SELECT TO authenticated
  USING (
    redeemed_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.venues v
               WHERE v.id = venue_id AND v.created_by = auth.uid())
  );

-- ── Redemption: acceptance + entitlement in one act (the trainer_clients
-- redeem-RPC shape). P0001 messages are user-facing copy.
CREATE FUNCTION public.redeem_gym_seat_key(p_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_key  public.gym_seat_keys%ROWTYPE;
  v_user uuid := auth.uid();
  v_ent  uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to redeem a gym key.';
  END IF;

  SELECT * INTO v_key FROM public.gym_seat_keys
    WHERE code = p_code
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That key does not exist — check the code with your gym.';
  END IF;
  IF v_key.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'That key was revoked by the gym.';
  END IF;
  IF v_key.redeemed_by IS NOT NULL AND v_key.redeemed_by <> v_user THEN
    RAISE EXCEPTION 'That key was already redeemed.';
  END IF;
  IF v_key.redeemed_by = v_user THEN
    -- Idempotent: re-redeeming your own key returns the entitlement.
    SELECT id INTO v_ent FROM public.trainer_entitlements
      WHERE user_id = v_user AND source = 'gym_seat'
        AND venue_id = v_key.venue_id AND revoked_at IS NULL
      LIMIT 1;
    IF FOUND THEN RETURN v_ent; END IF;
  END IF;

  UPDATE public.gym_seat_keys
    SET redeemed_by = v_user, redeemed_at = now()
    WHERE id = v_key.id;

  INSERT INTO public.trainer_entitlements (user_id, source, venue_id, client_cap)
    VALUES (v_user, 'gym_seat', v_key.venue_id, v_key.client_cap)
    RETURNING id INTO v_ent;

  RETURN v_ent;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.redeem_gym_seat_key(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_gym_seat_key(text) TO authenticated;
