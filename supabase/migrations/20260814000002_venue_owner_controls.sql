-- Venue owner controls (owner 2026-08-13: "I can't relinquish ownership
-- or delete my hub. There are no real controls.")
--
-- created_by becomes NULLABLE: NULL = community-owned. Relinquishing
-- hands the hub to the community — the venue, its members, and their
-- check-in history all survive; only the creator's edit rights end.
ALTER TABLE public.venues ALTER COLUMN created_by DROP NOT NULL;

-- Relinquish — SECURITY DEFINER because the creator-edit UPDATE policy's
-- WITH CHECK (created_by = auth.uid()) would reject the very row this
-- writes (created_by NULL), so the ownership check lives here instead.
CREATE OR REPLACE FUNCTION public.relinquish_venue(p_venue_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.venues
     SET created_by = NULL
   WHERE id = p_venue_id AND created_by = auth.uid() AND is_verified = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not your venue' USING ERRCODE = 'P0001';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.relinquish_venue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relinquish_venue(uuid) TO authenticated;

-- Delete — creator-only, unverified-only, and ONLY while nobody else has
-- ever joined. The original no-DELETE-policy rationale ("venues are
-- shared context") still stands the moment a second member exists: then
-- the path is relinquish, and removal stays a service-role operation.
-- SECURITY DEFINER on purpose: venue_users' SELECT policy hides
-- opted-out members from the creator, so an RLS-visible EXISTS check
-- could miss them and delete a hub someone quietly trains at.
-- Returns false (rather than raising) for the "others train here" case
-- so the client can offer relinquish as the alternative.
CREATE OR REPLACE FUNCTION public.delete_own_venue(p_venue_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.venues
    WHERE id = p_venue_id AND created_by = auth.uid() AND is_verified = false
  ) THEN
    RAISE EXCEPTION 'not your venue' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.venue_users
    WHERE venue_id = p_venue_id AND user_id <> auth.uid()
  ) THEN
    RETURN false;
  END IF;
  DELETE FROM public.venues WHERE id = p_venue_id;
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_own_venue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_own_venue(uuid) TO authenticated;
