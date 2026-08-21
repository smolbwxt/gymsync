-- 20260821000006_client_body_context.sql
--
-- Trainer tab: body health statistics on the client page (owner
-- 2026-08-21). The training_profiles payload holds bodyweight/height/
-- bodyfat, but the row is own-only and MUST stay that way - the same
-- payload carries goals and injury history, which the body_weight scope
-- was never consent for. This RPC exposes EXACTLY the three body fields,
-- gated on an ACTIVE relationship with the body_weight scope granted.
CREATE OR REPLACE FUNCTION public.client_body_context(p_client_id uuid)
RETURNS TABLE (bodyweight_lbs numeric, height_inches numeric, body_fat_percent numeric)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (tp.payload->>'bodyweightLbs')::numeric,
    (tp.payload->>'heightInches')::numeric,
    (tp.payload->>'bodyFatPercent')::numeric
  FROM public.training_profiles tp
  WHERE tp.user_id = p_client_id
    AND EXISTS (
      SELECT 1 FROM public.trainer_clients tc
      WHERE tc.trainer_id = auth.uid()
        AND tc.client_id = p_client_id
        AND tc.status = 'active'
        AND COALESCE((tc.scopes->>'body_weight')::boolean, false)
    );
$$;

REVOKE ALL ON FUNCTION public.client_body_context(uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.client_body_context(uuid) TO authenticated;
