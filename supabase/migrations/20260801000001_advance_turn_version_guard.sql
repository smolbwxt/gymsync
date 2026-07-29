-- ============================================================
-- Rotation guard: make advance_turn REPLAYABLE (idempotent).
-- ============================================================
-- THE PROBLEM (documented in GroupSessionLiveView.swift ~2526-2555):
-- when `logSet` fails with `.network` in a group session the client queues
-- the set locally and deliberately SKIPS `advanceTurn` — calling it would
-- throw its own `.network`, surface a false "Set didn't save" banner, and
-- every retry tap would mint a DISTINCT duplicate row that the 23505 dedupe
-- cannot catch. The accepted consequence was that the rotation stays stuck
-- until someone advances it by hand: one lifter's dead signal freezes
-- everyone.
--
-- That trade was tolerable for lifting (one person, in a gym, briefly
-- offline). It is not tolerable for anything where being offline is the
-- NORMAL case — phone in a pocket, outdoors, watch out of Bluetooth range.
--
-- THE FIX: give the turn a monotonic version so a queued advance can be
-- replayed later without risk. The client records the version it observed
-- when it logged; on replay it passes that version back. If the rotation
-- has moved on in the meantime — someone else logged, the organizer
-- advanced, a no-show was marked — the call is a NO-OP instead of shoving
-- the rotation forward a second time.
--
-- Why a monotonic counter and not "did current_turn_user_id change":
-- rotations WRAP. In a two-person session A -> B -> A, a stale advance
-- replayed one full cycle later would find `current_turn_user_id` back at A
-- and wrongly fire. A version that only ever increases cannot be fooled by
-- a wrap.

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS turn_version integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.sessions.turn_version IS
  'Monotonic rotation counter, bumped by advance_turn(). Clients pass the '
  'version they observed so a replayed/queued advance is a no-op once the '
  'rotation has already moved on.';

-- The old single-argument function is DROPPED rather than left in place:
-- keeping it alongside a two-argument version with a defaulted second
-- parameter makes `advance_turn(p_session_id => ...)` ambiguous and
-- PostgREST would fail to resolve the RPC. Nothing in SQL calls this
-- function (verified: only client RPC + pgTAP), and existing positional
-- callers — `advance_turn('<uuid>')`, which the shipped session_engine and
-- live_plumbing test suites use — bind to the new function unchanged.
DROP FUNCTION IF EXISTS public.advance_turn(uuid);

CREATE FUNCTION public.advance_turn(
  p_session_id       uuid,
  p_expected_version integer DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id    uuid;
  v_state           text;
  v_current_user    uuid;
  v_turn_version    integer;
  v_current_order   integer;
  v_next_user       uuid;
  v_next_order      integer;
BEGIN
  -- Lock the session row to serialize concurrent advances.
  SELECT organizer_id, state, current_turn_user_id, turn_version
    INTO v_organizer_id, v_state, v_current_user, v_turn_version
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

  -- ── IDEMPOTENCY GUARD ────────────────────────────────────────────────
  -- Checked BEFORE authorization on purpose. A replayed advance is sent by
  -- whoever was the current lifter when they logged; by the time it drains
  -- the turn may belong to someone else, so the authorization check below
  -- would reject it with 'not your turn' — turning a stale no-op into a
  -- user-visible error. A version mismatch means "already handled", which
  -- is success, not a failure: return the CURRENT holder and change
  -- nothing.
  --
  -- p_expected_version IS NULL preserves the original unconditional
  -- behaviour for live (online) calls, which have no version to assert.
  IF p_expected_version IS NOT NULL AND p_expected_version <> v_turn_version THEN
    RETURN v_current_user;
  END IF;

  -- Authorization: must be current lifter OR organizer.
  IF auth.uid() IS DISTINCT FROM v_current_user AND
     auth.uid() IS DISTINCT FROM v_organizer_id THEN
    RAISE EXCEPTION 'not your turn' USING ERRCODE = 'P0001';
  END IF;

  IF v_state <> 'in_progress' THEN
    RAISE EXCEPTION 'session is not in progress' USING ERRCODE = 'P0001';
  END IF;

  -- Resolve current turn_order.
  SELECT turn_order INTO v_current_order
    FROM public.session_participants
   WHERE session_id = p_session_id AND user_id = v_current_user;

  -- Find the next active (non-no_show) participant wrapping around.
  -- Try orders higher than current first, then wrap from 1.
  SELECT user_id, turn_order
    INTO v_next_user, v_next_order
    FROM public.session_participants
   WHERE session_id = p_session_id
     AND check_in_state <> 'no_show'
     AND turn_order > v_current_order
   ORDER BY turn_order ASC
   LIMIT 1;

  -- Wrap if nothing found after current.
  IF v_next_user IS NULL THEN
    SELECT user_id, turn_order
      INTO v_next_user, v_next_order
      FROM public.session_participants
     WHERE session_id = p_session_id
       AND check_in_state <> 'no_show'
       AND turn_order <= v_current_order
     ORDER BY turn_order ASC
     LIMIT 1;
  END IF;

  -- Liveness guard: ensure at least one active participant remains.
  IF v_next_user IS NULL THEN
    RAISE EXCEPTION 'no active participants remain' USING ERRCODE = 'P0001';
  END IF;

  -- Update session's current turn, bumping the version so any advance
  -- queued against the PREVIOUS version can no longer take effect.
  UPDATE public.sessions
  SET current_turn_user_id    = v_next_user,
      current_turn_started_at = now(),
      turn_version            = turn_version + 1
  WHERE id = p_session_id;

  RETURN v_next_user;
END;
$$;
