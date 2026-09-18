-- 20260913000106_advance_round_noop_before_lifting.sql
--
-- Fix-forward from a concern raised alongside 20260913000105 (fix round 1,
-- d-leg3.md), ruled by the controller: 000105 closed the case where a
-- warm-up-phase set is evaluated AFTER lifting starts (COALESCE falls
-- through to lifting_started_at), but advance_round remained callable
-- DURING warm-up itself -- state 'in_progress', lifting_started_at still
-- NULL -- where COALESCE fell all the way through to '-infinity' and a
-- warm-up set would still have counted toward closing round 1 if the
-- round were evaluated for closure before lifting formally started.
--
-- CREATE OR REPLACE public.advance_round, one change: an early return
-- right after the state check -- IF v_lifting_started_at IS NULL THEN
-- RETURN v_round; END IF. A close attempted before lifting has started is
-- a no-op, never an evaluation of the open-ended window: round 1 has not
-- begun, so there is nothing to close. This makes the COALESCE's
-- '-infinity' branch unreachable in practice (by the time execution
-- reaches it, lifting_started_at is guaranteed non-NULL), though the
-- COALESCE and its explanatory comment are otherwise untouched here --
-- byte-identical to 20260913000105's definition apart from the new early
-- return and this header. REVOKE/GRANT are not reissued: CREATE OR
-- REPLACE preserves the existing ACL for an unchanged signature. The
-- COMMENT ON FUNCTION gains one appended sentence.

-- ── (b) public.advance_round(uuid, integer) ──────────────────────────────
-- The server-owned close. Returns the round the session is in AFTER the
-- call -- unchanged when the round is not over, incremented when it is --
-- so a client never has to guess whether its call did anything.
CREATE OR REPLACE FUNCTION public.advance_round(
  p_session_id     uuid,
  p_expected_round integer DEFAULT NULL
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

COMMENT ON FUNCTION public.advance_round(uuid, integer) IS
  'Closes the current round and returns the round the session is in after the call. No-ops (returns the current round) when p_expected_round is stale, or when any PRESENT participant -- check_in_state IN (online, ready, late), advance_turn''s own rotation set -- has not logged a non-penalty set since round_started_at. Participant-gated, SECURITY DEFINER; the only writer of sessions.round and sessions.round_started_at. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D3, ruling R-B7. Before round_started_at is ever stamped, round 1''s window opens at lifting_started_at rather than at session creation, so a set logged during warm-up never counts toward its close (fix-forward 20260913000105). A close attempted before lifting_started_at is set is a no-op, returning the current round unchanged (fix-forward 20260913000106).';
