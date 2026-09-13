-- 20260913000107_advance_round_force_for_the_crews_skip.sql
--
-- Controller ruling R-B13, from Stream S's S7 finding: the crew's skip (the
-- client-side control that lets the room move on from a lifter who is
-- stuck) had no server escape -- nothing stopped a client from SKIPPING
-- the round in its own UI while advance_round's predicate still silently
-- waited on the unlogged lifter forever. Spec 9a: any participant may
-- force the round closed once it has been open at least
-- RoundHold.floorSeconds (90 s); nothing is recorded against the skipped
-- lifter -- this is a close, not a penalty.
--
-- REVISED FROM THIS MIGRATION'S FIRST DRAFT, which added a NEW
-- three-argument overload alongside the existing two-argument function,
-- reasoning that a shipped client might already hold that signature. That
-- premise was wrong: advance_round is new in Phase B1 (D3,
-- 20260913000102) and has no shipped caller yet -- the Swift wrapper is on
-- Stream S's unmerged app branch, and will pass p_force explicitly, or
-- reach it through its default, via PostgREST's named-parameter request
-- body. With no caller to protect, keeping both signatures is actively
-- harmful, not merely redundant: a function accepting MORE default
-- arguments than a same-named sibling makes every call short enough to
-- admit both -- via each one's own defaults -- ambiguous. PostgreSQL has
-- no "prefer fewer defaults" tiebreak for this and raises
-- ambiguous_function (SQLSTATE 42725) instead. Concretely, the first
-- draft would have broken every ONE-argument call already in
-- session_round_engine_test.sql (assertions 5, 6, 9, 14, 17, and one bare
-- call) the moment it applied.
--
-- So: DROP the two-argument function outright, then CREATE the
-- three-argument one as the single remaining definition. D4's one- and
-- two-argument calls are left exactly as they are -- with only one
-- advance_round left, they resolve uniquely to it, filling one or two
-- defaults respectively, no ambiguity possible with a single candidate.
--
-- The function body below is unchanged from the first draft: after the
-- lifting_started_at no-op, when p_force is true, close the round
-- (skipping the per-lifter predicate entirely) once the open round has
-- been open >= 90 seconds; younger than that, a forced call is a no-op
-- returning the current round, same as an unforced one that isn't over
-- yet. p_force defaults to false, so every call that omits it keeps
-- today's exact behavior.
--
-- REVOKE/GRANT and COMMENT ON FUNCTION target the three-argument
-- signature only -- the dropped function's grants go with it.
DROP FUNCTION public.advance_round(uuid, integer);

-- ── (b) public.advance_round(uuid, integer, boolean) ─────────────────────
-- The server-owned close. Returns the round the session is in AFTER the
-- call -- unchanged when the round is not over, incremented when it is --
-- so a client never has to guess whether its call did anything.
CREATE FUNCTION public.advance_round(
  p_session_id     uuid,
  p_expected_round integer DEFAULT NULL,
  p_force          boolean DEFAULT false
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_state               text;
  v_round               integer;
  v_round_started_at    timestamptz;
  v_lifting_started_at  timestamptz;
  v_round_is_over       boolean;
BEGIN
  -- Lock the session row to serialise concurrent closes (advance_turn's
  -- FOR UPDATE, same reason).
  SELECT state, round, round_started_at, lifting_started_at
    INTO v_state, v_round, v_round_started_at, v_lifting_started_at
    FROM public.sessions
   WHERE id = p_session_id
   FOR UPDATE;

  -- ── IDEMPOTENCY GUARD, BEFORE AUTHORIZATION ──────────────────────────
  -- advance_turn's guard (20260801000001_advance_turn_version_guard.sql),
  -- adapted: a replayed close is sent by whoever logged last, and by the
  -- time it drains the round may already have moved -- someone else's
  -- client closed it, or a queued call arrived twice. A mismatch means
  -- "already handled", which is SUCCESS, not a failure: return the current
  -- round and change nothing. Checked before the participant check for the
  -- same reason advance_turn checks before its own: a stale replay must not
  -- surface as a user-visible error to someone who did nothing wrong.
  --
  -- And, verbatim from that migration's reasoning: only a MONOTONIC number
  -- is safe here. Rotations wrap, so "did the current lifter change" cannot
  -- distinguish a stale replay from a fresh call one full cycle later; a
  -- counter that only ever increases cannot be fooled by a wrap. `round`
  -- is that counter for the round the way turn_version is for the turn.
  --
  -- p_expected_round IS NULL preserves the unconditional behaviour for live
  -- (online) calls, which have no round to assert.
  IF p_expected_round IS NOT NULL AND p_expected_round <> v_round THEN
    RETURN v_round;
  END IF;

  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  IF v_state <> 'in_progress' THEN
    RAISE EXCEPTION 'session is not in progress' USING ERRCODE = 'P0001';
  END IF;

  -- A close attempted before lifting has started is a no-op, never an
  -- evaluation of the open-ended window: round 1 has not begun yet, so
  -- there is nothing to close (queued concern from fix round 1, ruled;
  -- fix-forward 20260913000106).
  IF v_lifting_started_at IS NULL THEN
    RETURN v_round;
  END IF;

  -- The crew's skip (spec 9a, ruling R-B13, S7's finding that the skip had
  -- no server escape): any participant may force the round closed without
  -- every present lifter having logged, once the open round has been open
  -- at least RoundHold.floorSeconds (90 s, spec 9a's floor). Nothing is
  -- recorded against the skipped lifter -- this is a close like any other,
  -- not a penalty. Younger than the floor, a forced call is a no-op: the
  -- crew cannot skip the instant the round opens. lifting_started_at is
  -- guaranteed non-NULL here (the check above already returned if not),
  -- so the two-argument COALESCE below never needs a third fallback.
  IF p_force THEN
    IF now() - COALESCE(v_round_started_at, v_lifting_started_at) >= interval '90 seconds' THEN
      PERFORM set_config('gymsync.engine', 'on', true);
      UPDATE public.sessions
         SET round            = round + 1,
             round_started_at = now()
       WHERE id = p_session_id;
      PERFORM set_config('gymsync.engine', '', true);

      RETURN v_round + 1;
    ELSE
      RETURN v_round;
    END IF;
  END IF;

  -- ── THE ROUND-CLOSE PREDICATE ────────────────────────────────────────
  -- Every present lifter has logged a non-penalty set since the round
  -- opened. This is the whole point of the RPC: a client cannot push the
  -- round forward early, and a client that crashes cannot hold it back --
  -- anyone's replay closes it once the condition is true.
  --
  -- `check_in_state IN ('online','ready','late')` is advance_turn's own
  -- present-set (20260802000001_rotation_presence.sql), character for
  -- character, and the agreement is the whole point: a lifter the ROTATION
  -- skips must never be a lifter the ROUND waits for. Ruling R-B7, and the
  -- header says why an invited lifter who never arrived would otherwise
  -- hang every round.
  --
  -- is_penalty = false: burpee rows are excluded on purpose. A penalty is
  -- not a set of the round -- paying one off must not close the round for
  -- the crew, and owing one must not be a way to log out of it either.
  --
  -- COALESCE(..., v_lifting_started_at, '-infinity'): round_started_at is
  -- NULL until the first close stamps it (D1); before that, round 1's
  -- window opens at lifting_started_at, not at session start (fix-forward
  -- 20260913000105, review finding 2 -- set_logs_reject_prelive_session
  -- gates only on session state, so a set logged during warm-up is
  -- loggable and must not count toward round 1's close; it won't, once
  -- lifting_started_at is itself set to a later time). '-infinity' remains
  -- the fallback only while lifting_started_at is ALSO still NULL --
  -- mid-warm-up, a state this RPC does not otherwise gate on.
  SELECT NOT EXISTS (
    SELECT 1 FROM public.session_participants sp
     WHERE sp.session_id = p_session_id
       AND sp.check_in_state IN ('online', 'ready', 'late')
       AND NOT EXISTS (
         SELECT 1 FROM public.set_logs sl
          WHERE sl.session_id = p_session_id
            AND sl.user_id    = sp.user_id
            AND sl.is_penalty = false
            AND sl.logged_at >= COALESCE(v_round_started_at, v_lifting_started_at, '-infinity'::timestamptz)))
    INTO v_round_is_over;

  IF NOT v_round_is_over THEN
    RETURN v_round;
  END IF;

  -- set / UPDATE / reset, evaluate_lateness's shape: the reset is inside
  -- the same transaction so a pgTAP BEGIN/ROLLBACK -- or any caller -- can
  -- never inherit the bypass.
  PERFORM set_config('gymsync.engine', 'on', true);
  UPDATE public.sessions
     SET round            = round + 1,
         round_started_at = now()
   WHERE id = p_session_id;
  PERFORM set_config('gymsync.engine', '', true);

  RETURN v_round + 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.advance_round(uuid, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.advance_round(uuid, integer, boolean) TO authenticated;

COMMENT ON FUNCTION public.advance_round(uuid, integer, boolean) IS
  'Closes the current round and returns the round the session is in after the call. No-ops (returns the current round) when p_expected_round is stale, or when any PRESENT participant -- check_in_state IN (online, ready, late), advance_turn''s own rotation set -- has not logged a non-penalty set since round_started_at. Participant-gated, SECURITY DEFINER; the only writer of sessions.round and sessions.round_started_at. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D3, ruling R-B7. Before round_started_at is ever stamped, round 1''s window opens at lifting_started_at rather than at session creation, so a set logged during warm-up never counts toward its close (fix-forward 20260913000105). A close attempted before lifting_started_at is set is a no-op, returning the current round unchanged (fix-forward 20260913000106). p_force = true lets any participant close the round without every present lifter having logged -- the crew''s skip, spec 9a -- once the open round has been open at least 90 seconds; nothing is recorded against the skipped lifter (fix-forward 20260913000107, ruling R-B13).';
