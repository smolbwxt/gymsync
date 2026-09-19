-- D1 (Phase C1, plan section 2, decision 2): the durable swap layer. Two
-- homes, and the difference between them is who may write.
--
-- ── session_participants.self_swaps -- my own quiet swap, NO NEW POLICY ────
-- "participant updates own check-in" (20260712000001_sessions_phase3_
-- columns.sql:22-25) is USING (user_id = auth.uid()) WITH CHECK (user_id =
-- auth.uid()) with NO COLUMN LIST, so a lifter can already write their own
-- row, and "participants readable by other participants"
-- (20260726000001:182-187) is row-level, so the crew can already read it.
-- Verbatim, the same reasoning `todays_scale` shipped on a day earlier
-- (20260918000202:71-96): a third policy here would be permissive-ORed with
-- those and would grant nothing while looking like it granted something.
--
-- Both BEFORE UPDATE triggers on session_participants were read, not
-- assumed:
--   * engine_guard (20260714000001_session_engine_rpcs.sql:45-67) only
--     fires for the row-owner's own update, and even then only raises when
--     late_minutes, burpees_owed or turn_order change. A self_swaps write
--     changes none of them. PASSES.
--   * checkin_window_guard (20260715000003:13-46) returns NEW immediately
--     when NEW.check_in_state IS DISTINCT FROM 'ready'. When the row is
--     already 'ready' (the normal case for a swap made mid-session) a
--     self_swaps-only UPDATE leaves check_in_state alone, so NEW = OLD =
--     'ready', not DISTINCT FROM 'ready' -- it does not early-return there,
--     but it then checks `now() < scheduled_for - interval '20 minutes'`,
--     which fails open (returns NEW) whenever scheduled_for IS NULL, exactly
--     the ad-hoc/freestyle case D2's assertion 9 pins. PASSES either way.
--
-- ── sessions.squad_swaps -- the crew's agreed swap, RPC + guard clause ─────
-- "organizer or participant can update session" (20260709000006:61-66,
-- repointed at private.is_session_participant by 20260726000001) admits the
-- organizer AND every participant with no column list -- exactly the hole
-- `20260918000203_session_venue_guard.sql` closed for venue_id. Without a
-- guard clause here, one lifter could PATCH `squad_swaps` alone and the
-- consent card's unanimity would be decorative. So the write path is
-- `apply_squad_swap`, SECURITY DEFINER, gated the same way
-- `claim_session_venue` is gated (`private.is_session_participant`), and
-- `private.session_round_guard` gets one more clause, the same idiom one
-- clause longer, refusing a client write of squad_swaps directly.
--
-- ── keyed by routine-exercise ROW id, not exercise id ──────────────────────
-- RoutineLayering.apply keys squadSwaps/selfScale by re.exerciseID today
-- (RoutineLayering.swift:80-82); RoutineProgression.currentExercise counts
-- by completedSets(re.exerciseID) (:41-50). Both are wrong for a routine
-- that names one lift twice: swapping slot 3's bench would swap slot 7's
-- bench too, and slot 7's sets would count toward slot 3. Both columns here
-- are keyed by the routine_exercises row id (the SLOT), not the exercise id
-- -- the app-side re-key is S1.
--
-- ── no foreign key on either column, deliberately ──────────────────────────
-- routine_exercises rows are deleted when a routine is edited; the layer is
-- a recorded intent about a session, not a live reference to a routine that
-- may no longer exist in that shape. An FK with ON DELETE CASCADE would
-- silently erase the swap and one with RESTRICT would block the routine
-- edit -- neither is right, so there is no FK.
--
-- APPLIED: live 2026-09-19 as `session_swap_layer`, version 20260919001232 (controller, Supabase MCP; verified:
-- both new columns present (self_swaps, squad_swaps), the guard carries the venue AND the squad_swaps clauses, anon holds no EXECUTE).
-- The controller's gate review added the slot-membership check (R-C-4) before applying.

ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS self_swaps jsonb;

COMMENT ON COLUMN public.session_participants.self_swaps IS
  'My own quiet exercise swaps for this session (decision 2, Phase C1 D1). Shape {"<routine_exercise_id>": "<replacement_exercise_id>", ...}, keyed by the routine_exercises row id (the SLOT), not the exercise id -- a routine may name one lift twice. An absent key means no swap for that slot; NULL means no layer at all -- readers must treat NULL and {} identically, though the app never writes {} where NULL means the same thing. Written by a direct own-row UPDATE through the existing "participant updates own check-in" policy -- no new policy. Read by RoutineLayering.apply() ahead of squad_swaps and todays_scale.';

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS squad_swaps jsonb;

COMMENT ON COLUMN public.sessions.squad_swaps IS
  'The crew''s agreed exercise swaps for this session (decision 2, Phase C1 D1). Shape {"<routine_exercise_id>": "<replacement_exercise_id>", ...}, keyed by the routine_exercises row id (the SLOT), not the exercise id. An absent key means no swap for that slot; NULL means no layer at all. Written ONLY through public.apply_squad_swap() -- private.session_round_guard refuses a direct client write of a changed value, the same idiom that already guards round/round_started_at/stations/venue_id. Read by RoutineLayering.apply() as the first of three layers (squad swaps, then self-scale, then today''s scale).';

CREATE OR REPLACE FUNCTION public.apply_squad_swap(
  p_session_id     uuid,
  p_slot_id        uuid,
  p_replacement_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_merged jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;

  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.exercises WHERE id = p_replacement_id) THEN
    RAISE EXCEPTION 'replacement is not a known exercise' USING ERRCODE = 'P0001';
  END IF;

  -- Controller's gate review (R-C-4): the key must be a slot of THIS session's
  -- routine, or any participant could grow the object with keys that name
  -- nothing. A session with no routine has no slots and no crew swap.
  IF NOT EXISTS (
    SELECT 1
      FROM public.sessions s
      JOIN public.routine_exercises re ON re.routine_id = s.routine_id
     WHERE s.id = p_session_id AND re.id = p_slot_id
  ) THEN
    RAISE EXCEPTION 'slot is not part of this session''s routine' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('gymsync.engine', 'on', true);

  UPDATE public.sessions
     SET squad_swaps = coalesce(squad_swaps, '{}'::jsonb)
                        || jsonb_build_object(p_slot_id::text, p_replacement_id::text)
   WHERE id = p_session_id;

  PERFORM set_config('gymsync.engine', '', true);

  SELECT squad_swaps INTO v_merged FROM public.sessions WHERE id = p_session_id;
  RETURN v_merged;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.apply_squad_swap(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.apply_squad_swap(uuid, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.apply_squad_swap(uuid, uuid, uuid) IS
  'Merges {p_slot_id: p_replacement_id} into sessions.squad_swaps and returns the merged object. Participant-gated; raises P0001 ''sign-in required'', ''not a participant of this session'', ''replacement is not a known exercise'', ''slot is not part of this session''''s routine''. SECURITY DEFINER; the only writer of sessions.squad_swaps -- private.session_round_guard refuses every other write of it. Phase C1 D1.';

-- One more clause on private.session_round_guard: the whole function as it
-- stands at 20260918000203_session_venue_guard.sql, its three existing
-- clauses verbatim, plus the squad_swaps clause. Do NOT drop the venue_id
-- clause.
CREATE OR REPLACE FUNCTION private.session_round_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.round            IS DISTINCT FROM OLD.round
     OR NEW.round_started_at IS DISTINCT FROM OLD.round_started_at
     OR NEW.stations         IS DISTINCT FROM OLD.stations THEN
    RAISE EXCEPTION 'round, round_started_at and stations are engine-owned'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.style IS DISTINCT FROM OLD.style AND OLD.lifting_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'the style is fixed once lifting has started'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.venue_id IS NOT NULL AND NEW.venue_id IS DISTINCT FROM OLD.venue_id THEN
    RAISE EXCEPTION 'venue_id is claimed through claim_session_venue'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.squad_swaps IS DISTINCT FROM OLD.squad_swaps THEN
    RAISE EXCEPTION 'squad_swaps is written through apply_squad_swap'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;
