-- 20260906000002_friends_live.sql
--
-- Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
-- -goal-design.md §A item 6 (the crew pulse strip) and its phase 3. Plan:
-- docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, Stream A
-- task A8.
--
-- "Who from your crew is in the gym RIGHT NOW." One row feeds
-- `HomeCrewPulseStrip`; the LIMIT 5 is headroom for the "and 2 more" the
-- strip does not show yet, and a bound on the scan.
--
-- SECURITY DEFINER IS NOT OPTIONAL. `20260709000006_create_sessions.sql:29-31`
-- documents why: the `sessions` and `session_participants` policies reference
-- each other, so any cross-table subquery evaluated under the caller's RLS
-- re-enters the other table's RLS and cycles. The same file's
-- `is_session_participant` / `is_session_organizer` are the precedent, and
-- `public.activity_feed()` (20260719000002) is the precedent for a DEFINER
-- RPC that RETURNS TABLE.
--
-- DEFINER is also what makes the read correct rather than merely possible.
-- Under INVOKER this query would see nothing at all: `sessions` SELECT is
-- "organizer or participant", and the caller is neither in a friend's
-- session; `groups` SELECT requires CURRENT membership, so a friend
-- training with a crew the caller does not belong to would render with a
-- NULL group name.
--
-- THE GATE IS AUTH.UID(), HARDWIRED. Every row this function can return is
-- reachable from `auth.uid()` through an accepted friendship. There is no
-- parameter, so there is no other entity to authorize against and no
-- IF/RAISE gate is needed — the same posture activity_feed's header states.

CREATE OR REPLACE FUNCTION public.friends_live()
RETURNS TABLE (
  user_id      uuid,
  username     text,
  display_name text,
  session_id   uuid,
  group_id     uuid,
  group_name   text,
  started_at   timestamptz
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  -- Friends in EITHER direction. `friendships` is directional with a
  -- canonical-pair unique index (20260710000001_create_friendships.sql:12-13),
  -- so the accepted row for a pair exists once, under whichever party sent
  -- the request — a one-sided read would silently miss half the crew.
  WITH friend_ids AS (
    SELECT CASE WHEN f.user_id = auth.uid() THEN f.friend_id ELSE f.user_id END AS id
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.user_id = auth.uid() OR f.friend_id = auth.uid())
  )
  SELECT
    p.id,
    p.username,
    p.display_name,
    s.id,
    s.group_id,
    g.name,
    s.started_at
  FROM friend_ids fi
  JOIN public.profiles p ON p.id = fi.id
  -- Organizer OR participant, as one row per (friend, session). The client
  -- always inserts the creator as a participant
  -- (`SessionRepository.startSolo`, "Add self as sole participant (for RLS
  -- unification across phases)"), so the organizer arm is belt-and-braces
  -- for any row that predates that idiom; EXISTS rather than a join keeps
  -- it from multiplying rows.
  JOIN public.sessions s
    ON s.state = 'in_progress'
   AND (
     s.organizer_id = fi.id
     OR EXISTS (
       SELECT 1 FROM public.session_participants sp
        WHERE sp.session_id = s.id AND sp.user_id = fi.id
     )
   )
  LEFT JOIN public.groups g ON g.id = s.group_id
  -- Blocks, both directions. `20260722000003_block_severs_friendship.sql`
  -- severs the friendships row on block, so for pairs blocked after that
  -- migration the CTE above already returns nothing — but that trigger only
  -- fires on INSERT into blocked_users, and the same migration's own
  -- reasoning for ALSO fixing the set_logs policy applies verbatim here: a
  -- predicate is evaluated live on every read and therefore covers pairs the
  -- trigger cannot. Both directions, matching the set_logs policy
  -- (20260725000004:56-57).
  WHERE NOT private.is_blocked(auth.uid(), fi.id)
    AND NOT private.is_blocked(fi.id, auth.uid())
    -- SOLO PRESENCE FOLLOWS THE SOLO-WORKOUT SETTING. Not named by the plan;
    -- added because omitting it would reopen, on a new surface, exactly the
    -- hole `20260722000002_solo_workout_privacy.sql` was written to close.
    -- `profiles.show_solo_workouts` DEFAULTS TO FALSE and means "friends may
    -- see my solo workouts"; a session with no `group_id` is precisely what
    -- the strip renders as `Solo`, so surfacing one to a friend who has not
    -- opted in would publish a solo workout in real time while the same
    -- user's solo `set_logs` stay hidden. A crew session (group_id NOT NULL)
    -- is not a solo workout and is unaffected.
    --
    -- Deliberately keyed on `group_id IS NULL` rather than
    -- `private.is_solo_session()` (participant count = 1, the set_logs
    -- policy's test): a crew session in its first minute has one participant
    -- and is not a solo workout, and hiding it would be the wrong error.
    AND (s.group_id IS NOT NULL OR p.show_solo_workouts)
  ORDER BY s.started_at DESC NULLS LAST
  LIMIT 5;
$$;

-- Newly created functions get PUBLIC EXECUTE by default, which `anon`
-- inherits, so REVOKE FROM PUBLIC, anon and GRANT back explicitly TO
-- authenticated — the repo's revoke-then-grant idiom (activity_feed,
-- group_burpee_ledger, register_push_device). Do NOT include `authenticated`
-- in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.friends_live() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.friends_live() TO authenticated;
