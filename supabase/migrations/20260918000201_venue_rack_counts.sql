-- Rack counts live on the venue (owner decisions round, 2026-09-18,
-- decision 1: "who maintains rack counts?" -> "make an informed decision
-- that makes sense"). Decision 2 (the session's venue claim) rides in the
-- same story below, but its function ships in the next migration -- see
-- the comment block after this one.
--
-- THE NUMBER BELONGS TO THE BUILDING, NOT TO A SESSION. A venue that hosts
-- four squat racks hosts them for every crew that trains there, on every
-- day. Asking a session's organizer at scheduling time asks the one person
-- not at the gym yet, about a room they will walk into hours later, onto a
-- row nobody else's session reads. Asking the crew again every session asks
-- people who have no way to know whether their answer matches the last
-- crew's. Both re-derive a number the building already has, from scratch,
-- every time.
--
-- THE GATE IS venue_checkins, NOT venue_users, ON PURPOSE. venue_users
-- records membership -- a lifter who joined a hub in March is still a
-- member today, whether or not they have ever been back. venue_checkins
-- records a server-verified geofenced presence (check_in_to_venue,
-- 20260729000002, is this app's only server-side geofence -- its own
-- header says so), which is exactly the claim "I can see the racks from
-- here". The table is RLS-enabled with no policies at all, so only a
-- SECURITY DEFINER function can read it -- which is why the gate lives
-- inside the RPC below rather than in a policy.
--
-- created_by IS NOT THE AUTHORITY. venues.created_by has been nullable
-- since 20260814000002_venue_owner_controls.sql: a community-owned hub has
-- no owner at all, relinquish_venue hands ownership to the community on
-- purpose, and the owner of a hub is not necessarily ever in the building.
-- A rack count maintained by an absent creator decays silently, and a
-- community hub could never get one.
--
-- AN UNKNOWN COUNT IS AN ABSENT KEY, NEVER A ZERO. "No racks here" is
-- venues.equipment not listing the class; a count of 0 would collide with
-- that meaning, so the RPC below rejects 0 rather than storing it, and a
-- class with no entry in rack_counts means "nobody has said yet", read by
-- the caller as "no cap" rather than "zero racks".
ALTER TABLE public.venues
  ADD COLUMN IF NOT EXISTS rack_counts jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS rack_counts_updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rack_counts_updated_at timestamptz;

-- set_venue_rack_count -- any lifter checked in there in the last 12 hours
-- may set or correct a class's count. Last write wins; rack_counts_updated_by
-- and rack_counts_updated_at record who and when, so a wrong number has an
-- author. Gate-first (the venue_hubs idiom): every rejection happens before
-- any row is touched. jsonb_set on a single key, never a full replace, so
-- two lifters correcting two different classes cannot clobber each other.
CREATE OR REPLACE FUNCTION public.set_venue_rack_count(
  p_venue_id uuid, p_equipment_class text, p_count int
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;

  IF p_equipment_class IS NULL
     OR p_equipment_class NOT IN ('barbell','dumbbell','machine','cable','bodyweight') THEN
    RAISE EXCEPTION 'unknown equipment class: %', p_equipment_class USING ERRCODE = 'P0001';
  END IF;

  IF p_count IS NULL OR p_count < 1 OR p_count > 99 THEN
    RAISE EXCEPTION 'a rack count is between 1 and 99' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.venue_checkins
     WHERE venue_id = p_venue_id AND user_id = auth.uid()
       AND created_at > now() - interval '12 hours'
  ) THEN
    RAISE EXCEPTION 'you need to be at this gym to set its rack count' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.venues
     SET rack_counts = jsonb_set(rack_counts, ARRAY[p_equipment_class], to_jsonb(p_count), true),
         rack_counts_updated_by = auth.uid(),
         rack_counts_updated_at = now()
   WHERE id = p_venue_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_venue_rack_count(uuid, text, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_venue_rack_count(uuid, text, int) TO authenticated;

-- Deliberately NOT in 20260918000202: this function's whole content is the
-- venue_checkins presence rule above, and splitting it from that rule would
-- put the rule in two files. The COLUMN it writes lands in the next migration,
-- so this function is created there instead — see 20260918000202.

COMMENT ON COLUMN public.venues.rack_counts IS
  'Equipment-class -> rack count for this venue (decision 1, owner-decisions round 2026-09-18). Keyed by the five classes venues.equipment already lists (barbell, dumbbell, machine, cable, bodyweight) -- a hard whitelist in set_venue_rack_count(). A missing key means unknown, never zero: a count of 0 is rejected by the RPC rather than stored. Written only by set_venue_rack_count(), gated on a venue_checkins row for the caller at this venue within the last 12 hours -- presence, not membership. rack_counts_updated_by/_at record the last author so a wrong number has one.';
