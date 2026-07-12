-- ============================================================
-- Phase 3b Task 1: Session engine RPCs + penalty-field guard
-- ============================================================

-- ── 1. Fix-forward: re-declare evaluate_lateness with engine GUC ──────────────
--    Identical body to 20260712000001 with one added line (set_config).
CREATE OR REPLACE FUNCTION public.evaluate_lateness(p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scheduled timestamptz;
  v_per_minute integer;
BEGIN
  SELECT scheduled_for, COALESCE((late_penalty->>'per_minute')::int, 5)
    INTO v_scheduled, v_per_minute
    FROM public.sessions
    WHERE id = p_session_id AND organizer_id = auth.uid();
  IF v_scheduled IS NULL THEN
    RAISE EXCEPTION 'only the session organizer may evaluate lateness';
  END IF;

  -- Allow the UPDATE below to bypass the penalty-field guard trigger.
  PERFORM set_config('gymsync.engine', 'on', true);

  UPDATE public.session_participants sp
  SET late_minutes = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int,
      burpees_owed = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int * v_per_minute,
      check_in_state = CASE
        WHEN sp.check_in_at IS NOT NULL AND sp.check_in_at > v_scheduled THEN 'late'
        ELSE sp.check_in_state END
  WHERE sp.session_id = p_session_id
    AND (sp.check_in_at IS NULL OR sp.check_in_at > v_scheduled);

  -- Reset the bypass GUC so subsequent non-engine code in the same transaction
  -- (e.g. pgTAP tests running in BEGIN/ROLLBACK) cannot accidentally skip the guard.
  PERFORM set_config('gymsync.engine', '', true);
END;
$$;


-- ── 2. Penalty-field guard: BEFORE UPDATE trigger on session_participants ──────
--    Blocks direct client writes to late_minutes / burpees_owed / turn_order
--    for the row-owner unless the engine GUC is set.
CREATE OR REPLACE FUNCTION public.engine_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Only fire when the caller is the row's own user (self-update path).
  IF current_setting('request.jwt.claim.sub', true) IS DISTINCT FROM OLD.user_id::text THEN
    RETURN NEW;  -- Organizer / service role / other user: not guarded here.
  END IF;

  -- If the engine has set its bypass GUC, allow everything.
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  -- Guard: raise if any penalty field changed.
  IF NEW.late_minutes  IS DISTINCT FROM OLD.late_minutes  OR
     NEW.burpees_owed  IS DISTINCT FROM OLD.burpees_owed  OR
     NEW.turn_order    IS DISTINCT FROM OLD.turn_order    THEN
    RAISE EXCEPTION 'penalty fields are read-only' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS engine_guard ON public.session_participants;
CREATE TRIGGER engine_guard
  BEFORE UPDATE ON public.session_participants
  FOR EACH ROW EXECUTE FUNCTION public.engine_guard();


-- ── 3. start_session ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.start_session(p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id uuid;
  v_state        text;
  v_first_user   uuid;
BEGIN
  -- Load session; verify organizer.
  SELECT organizer_id, state
    INTO v_organizer_id, v_state
    FROM public.sessions
    WHERE id = p_session_id;

  IF v_organizer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'only the organizer may start the session' USING ERRCODE = 'P0001';
  END IF;

  IF v_state NOT IN ('scheduled', 'lobby_open') THEN
    RAISE EXCEPTION 'session cannot be started' USING ERRCODE = 'P0001';
  END IF;

  -- Engine GUC: let evaluate_lateness (and our turn_order UPDATE below) bypass the guard.
  PERFORM set_config('gymsync.engine', 'on', true);

  -- Evaluate lateness (auth.uid() is preserved inside this definer call).
  -- Note: evaluate_lateness resets the GUC at its end; we re-assert it here
  -- so the turn_order UPDATE below is also guarded correctly.
  PERFORM public.evaluate_lateness(p_session_id);

  -- Re-assert engine bypass for the turn_order assignment below.
  PERFORM set_config('gymsync.engine', 'on', true);

  -- Assign turn_order by check-in time (on-time first, then unchecked, then by user_id).
  UPDATE public.session_participants sp
  SET turn_order = ord.rn
  FROM (
    SELECT user_id,
           ROW_NUMBER() OVER (ORDER BY check_in_at ASC NULLS LAST, user_id ASC) AS rn
      FROM public.session_participants
     WHERE session_id = p_session_id
  ) ord
  WHERE sp.session_id = p_session_id
    AND sp.user_id = ord.user_id;

  -- Reset bypass GUC so the rest of the caller's transaction sees no engine privilege.
  PERFORM set_config('gymsync.engine', '', true);

  -- Find the participant with turn_order = 1.
  SELECT user_id INTO v_first_user
    FROM public.session_participants
   WHERE session_id = p_session_id AND turn_order = 1;

  -- Flip session to in_progress.
  UPDATE public.sessions
  SET state                  = 'in_progress',
      started_at             = now(),
      current_turn_user_id   = v_first_user,
      current_turn_started_at = now()
  WHERE id = p_session_id;
END;
$$;


-- ── 4. advance_turn ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.advance_turn(p_session_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id    uuid;
  v_state           text;
  v_current_user    uuid;
  v_current_order   integer;
  v_max_order       integer;
  v_next_user       uuid;
  v_next_order      integer;
BEGIN
  -- Lock the session row to serialize concurrent advances.
  SELECT organizer_id, state, current_turn_user_id
    INTO v_organizer_id, v_state, v_current_user
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

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

  SELECT MAX(turn_order) INTO v_max_order
    FROM public.session_participants
   WHERE session_id = p_session_id;

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

  -- Update session's current turn.
  UPDATE public.sessions
  SET current_turn_user_id    = v_next_user,
      current_turn_started_at = now()
  WHERE id = p_session_id;

  RETURN v_next_user;
END;
$$;
