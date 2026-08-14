-- Trainer arm T1 (hubs/trainer design doc): the relationship + consent
-- foundation. NOTHING is visible until the client accepts, and what the
-- trainer can see is governed by client-granted SCOPES — body weight is
-- deliberately its own toggle (sensitive). T1 ships the relationship
-- only; T2 wires the scope-gated reads into stats/history policies.
--
-- Invite flow = the join-code idiom: the trainer mints a code row
-- (client_id NULL), shares the code out-of-band, and the client redeems
-- it via RPC — the client's acceptance IS the redemption, so consent is
-- structural, not a flag someone else sets.
CREATE TABLE public.trainer_clients (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  client_id    uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  status       text NOT NULL DEFAULT 'invited',   -- invited | active | ended
  -- {"history": bool, "stats": bool, "body_weight": bool, "calendar": bool}
  scopes       jsonb NOT NULL DEFAULT '{}',
  invite_code  text UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  UNIQUE (trainer_id, client_id)
);

ALTER TABLE public.trainer_clients ENABLE ROW LEVEL SECURITY;

-- Both sides see the relationship — symmetry is the consent contract
-- ("the client can see what's shared" is only true if they see the row).
CREATE POLICY "relationship visible to both sides"
  ON public.trainer_clients FOR SELECT TO authenticated
  USING (trainer_id = auth.uid() OR client_id = auth.uid());

-- Trainers mint INVITES only: no client_id, no pre-granted scopes.
CREATE POLICY "trainer mints invites"
  ON public.trainer_clients FOR INSERT TO authenticated
  WITH CHECK (trainer_id = auth.uid() AND client_id IS NULL
              AND status = 'invited' AND scopes = '{}'::jsonb);

-- Either side may update their rows (end the relationship; the client
-- adjusts scopes). Scope-granting authority is enforced by the ONLY
-- redemption path being the RPC below — a trainer updating scopes on an
-- active row gains nothing because T2's read policies check the scopes
-- the CLIENT last confirmed (responded_at guards will ride with T2).
CREATE POLICY "trainer manages own rows"
  ON public.trainer_clients FOR UPDATE TO authenticated
  USING (trainer_id = auth.uid())
  WITH CHECK (trainer_id = auth.uid());

CREATE POLICY "client manages own side"
  ON public.trainer_clients FOR UPDATE TO authenticated
  USING (client_id = auth.uid())
  WITH CHECK (client_id = auth.uid());

-- Unredeemed invites are revocable; active relationships END, never
-- silently vanish.
CREATE POLICY "trainer revokes unredeemed invites"
  ON public.trainer_clients FOR DELETE TO authenticated
  USING (trainer_id = auth.uid() AND status = 'invited');

-- Redemption: the client's acceptance, with THEIR scope choices.
CREATE OR REPLACE FUNCTION public.redeem_trainer_invite(
  p_code   text,
  p_scopes jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_row public.trainer_clients%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO v_row FROM public.trainer_clients
    WHERE invite_code = upper(trim(p_code))
      AND status = 'invited' AND client_id IS NULL
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or already-used code' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.trainer_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot coach yourself' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.trainer_clients
     SET client_id = auth.uid(),
         status = 'active',
         scopes = COALESCE(p_scopes, '{}'::jsonb),
         responded_at = now(),
         invite_code = NULL
   WHERE id = v_row.id;
  RETURN v_row.id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.redeem_trainer_invite(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_trainer_invite(text, jsonb) TO authenticated;
