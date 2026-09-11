-- 20260911000001_crew_consistency_honor.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §3 — the
-- Crews card gains FREQUENCY honor, not performance: "who showed up most this
-- month", a crown that decays when they stop (rolling 30 days, ties to the
-- earlier achiever). Plan: docs/superpowers/plans/2026-09-11-social-cards
-- -plan.md, task S1.1.
--
-- THE THIRD SIBLING of group_stats / group_member_stats
-- (20260720000003_group_stats_rpc.sql), and written in that file's shape
-- deliberately: gate FIRST with is_group_member, LEFT JOIN LATERAL per member
-- so two unrelated cardinalities cannot multiply, REVOKE then GRANT.
--
-- ONE DEVIATION FROM THE SIBLING'S ORIGINAL TEXT, forced by history: the gate
-- calls `private.is_group_member`, not `public.is_group_member`.
-- 20260725000002_is_group_member_private_schema.sql:394 executed
-- `DROP FUNCTION public.is_group_member(uuid, uuid);` and re-created the
-- helper in the unreachable `private` schema (that same migration rewrote
-- group_stats / group_member_stats / group_burpee_ledger to match — see its
-- §9). A `public.` call here would raise 42883 undefined_function on the
-- first invocation instead of this function's own P0001, which is exactly
-- what the pgTAP gate assertion would then catch. Verified against the
-- current live definition of group_member_stats
-- (20260725000002_is_group_member_private_schema.sql:352).
--
-- WHY THIS IS NOT A CLIENT-SIDE COUNT. `sessions` SELECT RLS is
-- organizer-or-participant (20260709000006_create_sessions.sql:50-56, still
-- the live shape after 20260726000001_is_session_participant_dual_schema
-- .sql:164-171 swapped the helper into `private`), so the read the card
-- already makes returns only the sessions the VIEWER was in. Counting
-- per-member from that answers "who did I lift with most", under a label that
-- says "who showed up most". SECURITY DEFINER is what makes the label true.
--
-- WHO SHOWED UP = session_participants, not organizer_id. A crew's sessions
-- are scheduled by one person and attended by several; crediting the
-- organizer would make the crown a scheduling award.
--
-- THE TIE-BREAK IS `reached_at ASC` — the LATEST qualifying session of each
-- member, which is the moment they reached the count they now hold. Spec §3:
-- "ties to the earlier achiever". Spec §9.2 leaves the tie-break's WORDING
-- open; this decides only the ORDER, which a card that prints one name has to
-- have.
CREATE OR REPLACE FUNCTION public.group_consistency_honor(p_group_id uuid)
RETURNS TABLE (
  user_id    uuid,
  username   text,
  sessions   int,
  reached_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT gm.user_id,
         p.username,
         COALESCE(agg.session_count, 0)::int AS sessions,
         agg.last_completed_at               AS reached_at
    FROM public.group_members gm
    JOIN public.profiles p ON p.id = gm.user_id
    LEFT JOIN LATERAL (
      SELECT count(DISTINCT s.id) AS session_count,
             max(s.completed_at)  AS last_completed_at
        FROM public.sessions s
        JOIN public.session_participants sp
          ON sp.session_id = s.id AND sp.user_id = gm.user_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND s.completed_at IS NOT NULL
         AND s.completed_at >= now() - interval '30 days'
    ) agg ON true
   WHERE gm.group_id = p_group_id
     -- A member who has not trained in the window is ABSENT, not a zero row:
     -- the crown decays by the row disappearing, and an empty result is the
     -- card's "no honor line" state.
     AND COALESCE(agg.session_count, 0) > 0
   ORDER BY COALESCE(agg.session_count, 0) DESC, agg.last_completed_at ASC;
END;
$$;

-- Self-gated by the is_group_member check above — the same revoke-then-grant
-- idiom as group_stats / group_member_stats. Newly created functions get
-- PUBLIC EXECUTE by default, which anon inherits.
REVOKE EXECUTE ON FUNCTION public.group_consistency_honor(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_consistency_honor(uuid) TO authenticated;
