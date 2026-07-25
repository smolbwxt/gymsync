-- ============================================================
-- Venue Hubs (Local Hub) H1 — venues, membership, server-verified check-in.
-- ============================================================
-- Design: docs/superpowers/specs/2026-07-25-venue-hubs-design.md
-- Source spec: 2026-06-28-gymsync-design.md §3:513-551 (column sets, quoted
-- verbatim in the design doc), §3:663-666 (RLS narrative), Flow 9:886-925.
--
-- SCOPING (design doc "Scoping decisions", user-directed): SMS phone
-- verification is NOT built — the user benched Twilio (cost + legal review)
-- on 2026-07-20. `profiles.phone_verified_at` is created here anyway so
-- switching it on later is a gate check, not a migration. Every other
-- mandatory safety measure IS enforced below: age gate, block exclusion,
-- opt-in-only visibility, and the 3/hour check-in rate limit.
--
-- QR entry is H2: `qr_code_token` is generated per venue now, but v1's door
-- is the server-verified GPS geofence in check_in_to_venue() below.

-- ── 1. profiles: age gate + the phone-verification switch-on point ───────
-- Spec :186-188. Both nullable, both stamped by their own flows (age by the
-- client gate; phone by nothing in v1 — see SCOPING above).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS age_verified_18plus_at timestamptz,
  ADD COLUMN IF NOT EXISTS phone_verified_at      timestamptz;

-- The existing profiles guard trigger blocks client writes to is_curator;
-- age_verified_18plus_at is deliberately NOT added to that guard — it is
-- self-attestation by design (spec §6.7: "honor-system self-attestation"),
-- so the user's own client stamping it IS the intended mechanism.

-- ── 2. venues ────────────────────────────────────────────────────────────
-- Tightenings beyond the spec's column list (the documented
-- "spec is the column list, not the DDL" precedent):
--   * lat/lng NOT NULL + range CHECKs — a venue with no location cannot be
--     geofenced, and the whole entry path is the geofence.
--   * radius_meters CHECK between 20 and 2000: below 20m GPS jitter alone
--     fails honest users; above 2km it stops being "at the gym" (the gyms
--     table's own 200m default is the shape being followed).
--   * qr_code_token DEFAULT encode(gen_random_bytes(16),'hex') — opaque,
--     unguessable, generated now even though scanning is H2 (a token minted
--     later for old rows would need a backfill).
--   * created_by NOT NULL: every v1 venue is user-claimed. (Partner venues
--     would be service-role inserts, which bypass RLS anyway.)
CREATE TABLE public.venues (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL CHECK (length(btrim(name)) > 0),
  latitude       double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude      double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  radius_meters  integer NOT NULL DEFAULT 200 CHECK (radius_meters BETWEEN 20 AND 2000),
  qr_code_token  text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
  created_by     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_verified    boolean NOT NULL DEFAULT false,
  claimed_at     timestamptz NOT NULL DEFAULT now(),
  banner_url     text
);

ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;

-- ── 3. venue_users ───────────────────────────────────────────────────────
CREATE TABLE public.venue_users (
  venue_id          uuid NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_visible_on_hub boolean NOT NULL DEFAULT false,
  joined_at         timestamptz NOT NULL DEFAULT now(),
  last_seen_at      timestamptz,
  PRIMARY KEY (venue_id, user_id)
);

CREATE INDEX venue_users_user_id_idx ON public.venue_users(user_id);

ALTER TABLE public.venue_users ENABLE ROW LEVEL SECURITY;

-- ── 4. venue_checkins (rate-limit ledger) ────────────────────────────────
-- `last_seen_at` is a single mutable column and therefore cannot answer
-- "how many check-ins in the trailing hour" (spec's 3/hr limit). This
-- append-only ledger can. Deliberately NOT readable by clients at all (no
-- SELECT policy): it is a per-user location-time history, exactly the
-- "no persistent where-is-X surface" the spec's location-privacy rule
-- forbids exposing. Only the SECURITY DEFINER RPC below reads it.
CREATE TABLE public.venue_checkins (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id   uuid NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX venue_checkins_user_time_idx ON public.venue_checkins(user_id, created_at DESC);

ALTER TABLE public.venue_checkins ENABLE ROW LEVEL SECURITY;
-- No policies at all: fails closed for every client role.

-- ── 5. private helpers ───────────────────────────────────────────────────
-- Created directly in `private` per the established posture (every public
-- DEFINER helper since 20260722000001 has needed relocation; these are
-- RLS-quals-only, never client RPC targets). venue_users' own SELECT policy
-- must ask "is the reader a member of this row's venue", which re-enters
-- venue_users — the same self-reference is_group_member solves.
CREATE FUNCTION private.is_venue_member(p_venue_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.venue_users
    WHERE venue_id = p_venue_id AND user_id = p_user_id
  );
$$;

-- Great-circle metres between two WGS84 points. Plain SQL haversine —
-- deliberately NOT PostGIS/earthdistance: adding an extension for one
-- distance check is a heavier dependency than 6 lines of trigonometry, and
-- the client (CLLocation.distance) computes the same quantity, so the two
-- must agree by formula, not by extension version.
CREATE FUNCTION private.venue_distance_meters(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 6371000.0 * 2 * asin(sqrt(
      power(sin(radians(p_lat2 - p_lat1) / 2), 2)
    + cos(radians(p_lat1)) * cos(radians(p_lat2))
    * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
  ));
$$;

-- ── 6. RLS: venues ───────────────────────────────────────────────────────
-- "Global read (anyone can see a venue exists)" (spec :664).
CREATE POLICY "venues are globally readable"
  ON public.venues FOR SELECT TO authenticated
  USING (true);

-- "Writable by creator" — and NEVER with is_verified set. The partnership
-- flag is admin/service-role only, the same RLS-gated-column shape as
-- routines.is_featured (20260728000008).
CREATE POLICY "user claims a venue as themselves"
  ON public.venues FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND NOT is_verified);

-- "Verified venues (gym partnerships) can only be edited by app_admin"
-- (spec :665) — so the creator's UPDATE is gated on NOT is_verified in
-- BOTH directions: they cannot edit a venue that has been verified, and
-- cannot verify their own.
CREATE POLICY "creator edits own unverified venue"
  ON public.venues FOR UPDATE TO authenticated
  USING (created_by = auth.uid() AND NOT is_verified)
  WITH CHECK (created_by = auth.uid() AND NOT is_verified);

-- No DELETE policy: venues are shared context (other users' venue_users
-- rows hang off them); removal is a service-role operation.

-- ── 7. RLS: venue_users ──────────────────────────────────────────────────
-- Spec :665-666 — "readable by other users at the same venue ONLY IF
-- is_visible_on_hub = true", plus :663's "venue hub views exclude blocked
-- users' presence". Own row is always readable (you can always see your own
-- membership/toggle state).
CREATE POLICY "read own venue membership, or visible co-members"
  ON public.venue_users FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      is_visible_on_hub
      AND private.is_venue_member(venue_users.venue_id, auth.uid())
      AND NOT private.is_blocked(auth.uid(), venue_users.user_id)
      AND NOT private.is_blocked(venue_users.user_id, auth.uid())
    )
  );

-- "Writable only by the row's owner" (spec :666). INSERT is normally the
-- RPC's job (it enforces geofence/age/rate limit), but an owner-scoped
-- INSERT policy costs nothing and keeps the table's ownership story whole;
-- the RPC is SECURITY DEFINER and bypasses these anyway.
CREATE POLICY "user manages own venue membership"
  ON public.venue_users FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user updates own venue membership"
  ON public.venue_users FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user leaves a venue"
  ON public.venue_users FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ── 8. check_in_to_venue — the authoritative gate ────────────────────────
-- Flow 9's door. Gate-first (group_stats idiom): every rejection happens
-- before any row is written. This is the codebase's FIRST server-side
-- geofence — session check-in evaluates distance client-side only
-- (CheckInService.distanceCheck), which is spoofable; a venue hub discloses
-- your physical presence to strangers, so its distance claim must be
-- checked where the user cannot edit it.
--
-- Order is deliberate: age gate (cheapest, most categorical) -> rate limit
-- (cheap, protects the rest) -> geofence (needs the venue row).
CREATE OR REPLACE FUNCTION public.check_in_to_venue(
  p_venue_id uuid,
  p_lat      double precision,
  p_lng      double precision
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_venue   public.venues%ROWTYPE;
  v_recent  integer;
  v_dist    double precision;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;

  -- 1. Age gate (spec §6.7 — self-attested 18+).
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND age_verified_18plus_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'age verification required' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Rate limit: 3 check-ins per trailing hour (spec :1376).
  SELECT count(*) INTO v_recent
  FROM public.venue_checkins
  WHERE user_id = auth.uid() AND created_at > now() - interval '1 hour';
  IF v_recent >= 3 THEN
    RAISE EXCEPTION 'too many check-ins, try again later' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_venue FROM public.venues WHERE id = p_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'venue not found' USING ERRCODE = 'P0001';
  END IF;

  -- 3. Geofence.
  v_dist := private.venue_distance_meters(p_lat, p_lng, v_venue.latitude, v_venue.longitude);
  IF v_dist > v_venue.radius_meters THEN
    RAISE EXCEPTION 'you need to be at % to check in', v_venue.name
      USING ERRCODE = 'P0001';
  END IF;

  -- Passed. `is_visible_on_hub` is INSERTed false and never overwritten on
  -- re-check-in — walking back into the gym must not silently re-expose
  -- someone who toggled themselves off (opt-in is the user's, not the
  -- building's).
  INSERT INTO public.venue_users (venue_id, user_id, is_visible_on_hub, last_seen_at)
  VALUES (p_venue_id, auth.uid(), false, now())
  ON CONFLICT (venue_id, user_id) DO UPDATE SET last_seen_at = now();

  INSERT INTO public.venue_checkins (venue_id, user_id) VALUES (p_venue_id, auth.uid());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_in_to_venue(uuid, double precision, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_in_to_venue(uuid, double precision, double precision) TO authenticated;

-- ── 9. venue_month_leaderboard — opt-in-only local leaderboard ───────────
-- Flow 9: "top total-volume lifters at this venue this month (only counts
-- opted-in users)". A client-side join can't express this: set_logs are
-- readable per that table's own (block-aware) policy, but "who is visible
-- at this venue" is venue_users' gate — the honest aggregate spans both,
-- so it lives in one DEFINER function, gate-first, exactly like
-- campaign_community_progress.
--
-- Volume mirrors StatMath/weeklyVolumes exclusions EXACTLY (not failed, not
-- penalty, reps and weight both present) so a hub number never disagrees
-- with the same lifter's Stats tab.
CREATE OR REPLACE FUNCTION public.venue_month_leaderboard(p_venue_id uuid)
RETURNS TABLE (user_id uuid, username text, volume numeric)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public AS $$
BEGIN
  -- Gate: you must be a member of the venue to read its leaderboard.
  IF NOT private.is_venue_member(p_venue_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this venue' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT p.id, p.username, COALESCE(SUM(sl.reps * sl.weight), 0)::numeric
  FROM public.venue_users vu
  JOIN public.profiles p ON p.id = vu.user_id
  LEFT JOIN public.set_logs sl
    ON sl.user_id = vu.user_id
   AND sl.logged_at >= date_trunc('month', now())
   AND NOT sl.is_failed AND NOT sl.is_penalty
   AND sl.reps IS NOT NULL AND sl.weight IS NOT NULL
  WHERE vu.venue_id = p_venue_id
    AND vu.is_visible_on_hub
    -- Block exclusion, both directions (spec :663).
    AND NOT private.is_blocked(auth.uid(), vu.user_id)
    AND NOT private.is_blocked(vu.user_id, auth.uid())
  GROUP BY p.id, p.username
  ORDER BY 3 DESC, p.username ASC
  LIMIT 25;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.venue_month_leaderboard(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.venue_month_leaderboard(uuid) TO authenticated;
