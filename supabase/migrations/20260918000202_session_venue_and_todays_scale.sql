-- The session's venue, and today's scale (owner decisions round,
-- 2026-09-18, decisions 2 and 3). Two additive nullable columns and one
-- function, each under its own header block below.

-- ── sessions.venue_id ────────────────────────────────────────────────────
-- Decision 2, corrected against master: the brief's premise -- that
-- sessions.venue_id could be set from CheckInService.primaryGym()/the
-- existing session check-in path -- does not hold. primaryGym() reads
-- `gyms`, a private per-user geofence row (20260709000004); a gyms.id is
-- not a venues.id and nothing joins the two. SessionRepository.checkIn()
-- (session check-in) writes only check_in_state/check_in_at/check_in_method
-- and never names a venue. The venue flow is separate and already correct:
-- VenueRepository.checkIn -> check_in_to_venue -> a venue_checkins row.
--
-- So the claim below reads the caller's most recent venue_checkins row
-- within the last 12 hours -- the same presence rule 20260918000201 uses
-- for rack counts -- written best-effort AFTER the existing session
-- check-in succeeds, and only while venue_id IS NULL: first check-in wins.
--
-- claim_session_venue() is SECURITY DEFINER because venue_checkins has no
-- policies at all (only a DEFINER function can read it); the sessions
-- UPDATE it performs would have been legal WITHOUT DEFINER on its own --
-- "organizer or participant can update session" (20260709000006:61-67)
-- already admits any participant with no column list -- but the read of
-- venue_checkins is what forces the whole function to run as DEFINER.
-- `WHERE ... AND venue_id IS NULL` in the UPDATE is what makes first-write-
-- wins a database property rather than a client race: two participants
-- calling this within the same window cannot both win.
--
-- ON DELETE SET NULL: a deleted venue costs the session its cap (S6 passes
-- nil to StationSplit.count when the venue is unknown) and nothing else --
-- exactly today's behaviour for a crew that never checked into a hub.
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS venue_id uuid REFERENCES public.venues(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.sessions.venue_id IS
  'The venue this session is training at, if any (decision 2, owner-decisions round 2026-09-18). Claimed from the caller''s most recent venue_checkins row within the last 12 hours by public.claim_session_venue(), written best-effort after session check-in succeeds, only while NULL (first check-in wins). NULL means the crew never checked into a venue hub -- the shipped default: no cap, ceil(n/3) stations. ON DELETE SET NULL: a deleted venue costs the session its cap, nothing else.';

CREATE OR REPLACE FUNCTION public.claim_session_venue(p_session_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_venue uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  SELECT venue_id INTO v_venue
    FROM public.venue_checkins
   WHERE user_id = auth.uid() AND created_at > now() - interval '12 hours'
   ORDER BY created_at DESC LIMIT 1;

  IF v_venue IS NULL THEN RETURN NULL; END IF;

  UPDATE public.sessions SET venue_id = v_venue
   WHERE id = p_session_id AND venue_id IS NULL;

  SELECT venue_id INTO v_venue FROM public.sessions WHERE id = p_session_id;
  RETURN v_venue;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_session_venue(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_session_venue(uuid) TO authenticated;

-- ── session_participants.todays_scale ───────────────────────────────────
-- Decision 3. Phase A's energy-column reasoning applies verbatim, in its
-- own words (20260912000101_session_participant_energy.sql): "participant
-- updates own check-in" (20260712000001_sessions_phase3_columns.sql:22-25)
-- is USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid()) with
-- NO COLUMN LIST, so a lifter can already write their own row; "participants
-- readable by other participants" (20260726000001:182-187) is row-level, so
-- the crew can already read it. NO NEW POLICY, ON PURPOSE -- a third policy
-- here would be permissive-ORed with those and would grant nothing while
-- looking like it granted something.
--
-- Both BEFORE UPDATE triggers on session_participants were read, not
-- assumed:
--   * engine_guard (20260714000001:45-70) raises only when late_minutes,
--     burpees_owed or turn_order change. A todays_scale write changes none
--     of them. PASSES.
--   * checkin_window_guard (20260715000003:13-46) returns NEW immediately
--     when NEW.check_in_state IS DISTINCT FROM 'ready' -- which is not an
--     early return for our write: the row is already 'ready' by warm-up
--     time and a todays_scale-only UPDATE leaves check_in_state alone, so
--     NEW.check_in_state = OLD.check_in_state = 'ready', not DISTINCT FROM
--     'ready'. It then checks now() < scheduled_for - interval '20
--     minutes'; a warm-up Accept happens after check-in opened, so this is
--     false and the trigger returns NEW. PASSES. Identical to what `energy`
--     already does in production; D4 pins this with an assertion so a
--     future guard change cannot break it silently.
--
-- Shape: {"exercise_id": "<uuid>", "sets_instead": <int>}. Written on
-- Accept (SessionRunnerView.swift), best-effort -- a failed write leaves
-- the in-memory value in place. Cleared by nothing: the session ends and
-- the row stops being read. Crew visibility is unchanged -- this rides the
-- existing own-row-write / crew-read policies, adding no new surface.
ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS todays_scale jsonb;

COMMENT ON COLUMN public.session_participants.todays_scale IS
  'Shape {"exercise_id": uuid, "sets_instead": int} (decision 3, owner-decisions round 2026-09-18). NULL until the lifter accepts a Coach-suggested set reduction for this session. Written by the lifter from SessionRunnerView on Accept, best-effort, through the existing "participant updates own check-in" policy -- no new policy. Read by RoutineLayering.apply() as the last of three layers (squad swaps, then self-scale, then today''s scale). Not cleared; the session ending is what stops it being read.';
