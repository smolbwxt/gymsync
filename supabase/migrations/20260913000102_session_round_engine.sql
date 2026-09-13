-- 20260913000102_session_round_engine.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md
-- §6 -- "the server-owned round counter ... so every client agrees when a
-- round closes." Plan: docs/superpowers/plans/2026-09-13-group-session
-- -phase-b-plan.md, task D3, which is "the five data decisions," decision 4
-- made real. Builds on D1 (20260913000101_session_style_stations_round.sql),
-- which added the four columns and deliberately added no policy.
--
-- ── WHY A POLICY IS NOT ENOUGH ───────────────────────────────────────────
-- "organizer or participant can update session" (20260709000006_create_
-- sessions.sql, repointed at private.is_session_participant by
-- 20260726000001_is_session_participant_dual_schema.sql) is
--   USING (organizer_id = auth.uid() OR private.is_session_participant(...))
-- with NO COLUMN LIST -- and it cannot have one. An RLS policy is a ROW
-- predicate; Postgres has no per-column RLS. So from the moment D1 added
-- `round`, every participant of a session could write any integer into it,
-- and any jsonb into `stations`. That is the exact opposite of what §6 asks
-- for.
--
-- Column privileges (GRANT UPDATE (col) ...) are the other instrument, and
-- they are the wrong one here: making them bite would mean REVOKEing the
-- table-wide UPDATE that the app depends on for state / started_at /
-- completed_at / current_turn_user_id / lifting_started_at / style / ...
-- and re-granting it column by column -- a list every future migration that
-- adds a session column would silently have to remember to extend, failing
-- closed and mysteriously when it forgot.
--
-- A BEFORE UPDATE trigger is the narrow instrument. It names three columns
-- and says "not by hand." It leaves the policy, and therefore every other
-- column, exactly as it was. It is also the only one of the three that can
-- express the OTHER rule §1 needs -- style is "changeable in the lobby
-- until Start" -- because that rule is not about who you are, it is about
-- what the row already says (OLD.lifting_started_at).
--
-- ── WHY THE GUC IDIOM, COPIED RATHER THAN INVENTED ───────────────────────
-- public.engine_guard (20260714000001_session_engine_rpcs.sql) already
-- guards session_participants' penalty fields exactly this way: the trigger
-- stands down when current_setting('gymsync.engine', true) = 'on', and the
-- RPCs that legitimately write those fields set the GUC with is_local =
-- true and RESET IT IMMEDIATELY AFTER THEIR OWN UPDATE (evaluate_lateness,
-- same file, whose reset carries the reason verbatim: so a pgTAP
-- transaction -- or any caller's transaction -- cannot inherit the bypass).
-- Both RPCs below follow that set/UPDATE/reset shape line for line.
-- Copying the idiom means there is ONE thing to know about engine-owned
-- columns in this schema, not two.
--
-- ── WHY advance_turn IS NOT MODIFIED ─────────────────────────────────────
-- The rotation and the round are different clocks. advance_turn moves the
-- pointer to the next lifter, many times per round; advance_round closes
-- the round for everyone, once. The client that logs a set calls
-- advance_turn exactly as it does today and THEN calls advance_round -- the
-- second call is cheap, safe to repeat, and safe to lose, because it
-- no-ops unless the round is genuinely over. advance_turn's contract does
-- not change: it is shipped, three pgTAP suites cover it (session_engine,
-- live_plumbing, advance_turn_version_guard), and the phase plan freezes it
-- (constraint 20). This migration adds beside it; it does not edit it.
--
-- ── WHO THE ROUND WAITS FOR (controller ruling R-B7) ─────────────────────
-- The close predicate below, and the station roster after it, count the
-- PRESENT crew -- check_in_state IN ('online','ready','late') -- not
-- "everyone who is not a no_show". That is not a paraphrase: it is the
-- presence trio 20260802000001_rotation_presence.sql defines, and that
-- migration exists because of this exact failure one clock down. Its own
-- words: advance_turn's next-picker "excluded only 'no_show'", so "a
-- participant who never opened the session ('invited', or NULL) was a full
-- member of the rotation -- the turn could land on a ghost and the whole
-- room waited." A round that waits on an invited lifter who never arrived
-- is the same ghost: every round would hang until the crew skipped them,
-- and there is no skip. So the round waits for exactly the people the
-- rotation deals turns to, and the stations cover exactly that same roster.
-- One definition of "here", used in all three places.
--
-- The states outside it are 'invited', 'left', 'no_show' and NULL --
-- session_participants_check_in_state_check (20260709000006_create_
-- sessions.sql:22, widened by 20260803000003_routine_visibility_left_
-- state.sql to add 'left') admits exactly ('invited','online','ready',
-- 'late','no_show','left'), no others. A leaver is excluded from the round
-- and the roster exactly like an invited or no-show lifter -- no extra
-- case needed, since the positive list IN ('online','ready','late')
-- already excludes all four. NULL falls out for free: IN () is false for
-- NULL, exactly as it is in advance_turn.


-- ── (a) private.session_round_guard() ────────────────────────────────────
-- In `private`, not `public`, like every other non-client-callable helper
-- in this schema (private.touch_weekly_goals_updated_at, 20260906000001) --
-- a trigger function should not also mint a PostgREST RPC endpoint.
--
-- NOT SECURITY DEFINER, and not an authorization layer. It answers one
-- question -- "did this UPDATE arrive through an engine RPC?" -- and, for
-- style, one more: "has lifting already started?" WHO may update the row
-- remains entirely the policy's business. Adding anything else here would
-- make the guard a second, invisible authorization layer that no reader of
-- the policies could see.
CREATE OR REPLACE FUNCTION private.session_round_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- The engine's own writes pass straight through. is_local = true at the
  -- setter, so this can only be on inside the RPC's own transaction.
  IF current_setting('gymsync.engine', true) = 'on' THEN
    RETURN NEW;
  END IF;

  -- The three engine-owned columns (decision 4). IS DISTINCT FROM, not <>,
  -- so a NULL -> value change on stations / round_started_at is caught too.
  IF NEW.round            IS DISTINCT FROM OLD.round
     OR NEW.round_started_at IS DISTINCT FROM OLD.round_started_at
     OR NEW.stations         IS DISTINCT FROM OLD.stations THEN
    RAISE EXCEPTION 'round, round_started_at and stations are engine-owned'
      USING ERRCODE = 'P0001';
  END IF;

  -- Spec §1: the style is "changeable in the lobby until Start". Start is
  -- lifting_started_at (20260803000004_session_warmup_phase.sql), and it is
  -- OLD.lifting_started_at that decides -- the UPDATE that sets it is
  -- start_lifting's own, and it does not touch style, so a crew re-styling
  -- in the same instant Start lands still loses the race honestly rather
  -- than being judged against a value this statement is itself writing.
  IF NEW.style IS DISTINCT FROM OLD.style AND OLD.lifting_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'the style is fixed once lifting has started'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS session_round_guard ON public.sessions;
CREATE TRIGGER session_round_guard
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION private.session_round_guard();


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
  v_state            text;
  v_round            integer;
  v_round_started_at timestamptz;
  v_round_is_over    boolean;
BEGIN
  -- Lock the session row to serialise concurrent closes (advance_turn's
  -- FOR UPDATE, same reason).
  SELECT state, round, round_started_at
    INTO v_state, v_round, v_round_started_at
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
  -- COALESCE(..., '-infinity'): round_started_at is NULL until the first
  -- close stamps it (D1), so on the FIRST round every set logged in the
  -- session counts, which is exactly right -- the first round opened when
  -- the session did.
  SELECT NOT EXISTS (
    SELECT 1 FROM public.session_participants sp
     WHERE sp.session_id = p_session_id
       AND sp.check_in_state IN ('online', 'ready', 'late')
       AND NOT EXISTS (
         SELECT 1 FROM public.set_logs sl
          WHERE sl.session_id = p_session_id
            AND sl.user_id    = sp.user_id
            AND sl.is_penalty = false
            AND sl.logged_at >= COALESCE(v_round_started_at, '-infinity'::timestamptz)))
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


-- ── (c) public.set_session_stations(uuid, integer, jsonb) ────────────────
-- The station assignment for the CURRENT exercise, validated where it is
-- written. Returns the stored value -- the caller never has to re-read the
-- row to learn what the crew agreed on.
CREATE OR REPLACE FUNCTION public.set_session_stations(
  p_session_id        uuid,
  p_exercise_position integer,
  p_stations          jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_stored         jsonb;
  v_next           jsonb;
  v_roster_matches boolean;
BEGIN
  SELECT stations INTO v_stored
    FROM public.sessions
   WHERE id = p_session_id
   FOR UPDATE;

  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  -- ── IDEMPOTENT ON p_exercise_position ────────────────────────────────
  -- The re-mix is replayable: if the stored assignment already names this
  -- exercise position, return it unchanged. Two clients re-mixing at the
  -- same exercise change therefore CANNOT disagree -- the first write wins
  -- and the second learns what it was, rather than the crew's cards
  -- reshuffling under them because two phones raced. `stations` holds the
  -- current exercise only (D1: transient by design), so a later position
  -- overwrites, which is the next exercise's re-mix and is meant to.
  IF v_stored IS NOT NULL
     AND (v_stored ->> 'exercise_position')::integer IS NOT DISTINCT FROM p_exercise_position THEN
    RETURN v_stored;
  END IF;

  -- ── SHAPE ────────────────────────────────────────────────────────────
  -- p_stations is the "stations" array of D1's documented shape:
  -- {"exercise_position": int,
  --  "stations": [{"name": text, "lifter_ids": [uuid], "turn_order": [uuid]}]}
  -- The wrapper object is built here, not passed in, so exercise_position
  -- cannot disagree with the argument the idempotency check reads.
  IF p_stations IS NULL OR jsonb_typeof(p_stations) <> 'array' THEN
    RAISE EXCEPTION 'stations must be a json array' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_stations) AS station
     WHERE jsonb_typeof(station)                 IS DISTINCT FROM 'object'
        OR jsonb_typeof(station -> 'name')       IS DISTINCT FROM 'string'
        OR jsonb_typeof(station -> 'lifter_ids') IS DISTINCT FROM 'array'
        OR jsonb_typeof(station -> 'turn_order') IS DISTINCT FROM 'array'
  ) THEN
    RAISE EXCEPTION 'every station needs a name, lifter_ids and turn_order'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── DEPTH, CHECKED BEFORE THE ROSTER ─────────────────────────────────
  -- Spec §2: no station is deeper than three. Checked first so a four-deep
  -- station reports the depth -- the thing the crew can act on -- rather
  -- than the roster mismatch that a four-deep station in a three-lifter
  -- crew would also, confusingly, be.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_stations) AS station
     WHERE jsonb_array_length(station -> 'lifter_ids') > 3
  ) THEN
    RAISE EXCEPTION 'a station may not be deeper than three' USING ERRCODE = 'P0001';
  END IF;

  -- ── THE ROSTER ───────────────────────────────────────────────────────
  -- The union of every station's lifter_ids is exactly the present crew,
  -- each lifter once: nobody assigned twice, nobody left off, nobody who
  -- is not in this session. Equal counts plus equal sets is what makes it
  -- "exactly once" -- a duplicate would push the count above the set size.
  -- The present set is `check_in_state IN ('online','ready','late')`:
  -- advance_round's above and advance_turn's, deliberately identical in all
  -- three places (ruling R-B7). An invited lifter who never arrived
  -- therefore neither blocks a round close nor has to be given a station --
  -- if they had to, every assignment in a crew with one absent invitee
  -- would fail validation, and the re-mix would be unusable.
  -- A lifter_ids entry that is not a uuid string fails its cast (22P02)
  -- rather than reaching this test; that is a rejection either way.
  WITH assigned AS (
    SELECT (lifter #>> '{}')::uuid AS user_id
      FROM jsonb_array_elements(p_stations) AS station,
           jsonb_array_elements(station -> 'lifter_ids') AS lifter
  ),
  present AS (
    SELECT sp.user_id
      FROM public.session_participants sp
     WHERE sp.session_id = p_session_id
       AND sp.check_in_state IN ('online', 'ready', 'late')
  )
  SELECT (SELECT count(*) FROM assigned) = (SELECT count(*) FROM present)
     AND NOT EXISTS (SELECT user_id FROM assigned EXCEPT SELECT user_id FROM present)
     AND NOT EXISTS (SELECT user_id FROM present  EXCEPT SELECT user_id FROM assigned)
    INTO v_roster_matches;

  IF NOT v_roster_matches THEN
    RAISE EXCEPTION 'every present lifter belongs to exactly one station'
      USING ERRCODE = 'P0001';
  END IF;

  v_next := jsonb_build_object('exercise_position', p_exercise_position,
                               'stations',          p_stations);

  PERFORM set_config('gymsync.engine', 'on', true);
  UPDATE public.sessions SET stations = v_next WHERE id = p_session_id;
  PERFORM set_config('gymsync.engine', '', true);

  RETURN v_next;
END;
$$;


-- Both are client RPCs: the crew calls them, nobody else. REVOKE-then-GRANT
-- rather than a bare GRANT, matching this program's own most recent
-- precedent (20260912000102_session_coach_thread.sql, Phase A's D3) -- the
-- plan's line names only the GRANT, and the REVOKE is added deliberately so
-- `anon` cannot reach a session-mutating RPC.
REVOKE EXECUTE ON FUNCTION public.advance_round(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_session_stations(uuid, integer, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.advance_round(uuid, integer),
                          public.set_session_stations(uuid, integer, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.advance_round(uuid, integer) IS
  'Closes the current round and returns the round the session is in after the call. No-ops (returns the current round) when p_expected_round is stale, or when any PRESENT participant -- check_in_state IN (online, ready, late), advance_turn''s own rotation set -- has not logged a non-penalty set since round_started_at. Participant-gated, SECURITY DEFINER; the only writer of sessions.round and sessions.round_started_at. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D3, ruling R-B7.';

COMMENT ON FUNCTION public.set_session_stations(uuid, integer, jsonb) IS
  'Writes the current exercise''s station assignment and returns the stored value. Idempotent on p_exercise_position: if the stored assignment already names that position it is returned unchanged. Validates that no station is deeper than three and that every PRESENT lifter -- check_in_state IN (online, ready, late), the same roster advance_round waits for -- appears in exactly one station. Participant-gated, SECURITY DEFINER; the only writer of sessions.stations. Spec 2026-09-12-group-session-and-lobby-design.md section 6, plan task D3, ruling R-B7.';
