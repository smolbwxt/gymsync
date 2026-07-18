-- ============================================================
-- Phase O / Task 1: DEFINER-helper sweep — is_session_organizer()
-- (Phase H review add-on: "confirm is_session_organizer's exposure class
-- while in there" — session_calendar_syncs' RLS, 20260724000002, is the
-- trigger for the review flag)
-- ============================================================
-- CLASSIFICATION (per the task brief's question — answered here, not
-- assumed): is_session_organizer(p_session_id uuid, p_user_id uuid) is
-- SECURITY DEFINER STABLE, lives in the exposed `public` schema, and (per
-- grep of every migration) carries no REVOKE/GRANT EXECUTE statements
-- anywhere — default PUBLIC EXECUTE, exactly like the six queue helpers.
-- It is therefore auto-minted as POST /rest/v1/rpc/is_session_organizer,
-- callable by any authenticated caller with two arbitrary uuids. The fact
-- it answers ("is p_user_id the organizer of p_session_id?") is not
-- otherwise visible to a non-participant: sessions' own SELECT policy
-- ("users can select sessions they participate in",
-- 20260709000006_create_sessions.sql) restricts reads of the
-- organizer_id column to the organizer or a current participant, so a
-- non-participant cannot learn organizer identity by reading the table —
-- but they CAN learn it today by calling this RPC with a guessed/known
-- session_id and a candidate user_id, sweeping candidates the same way
-- is_blocked let a caller sweep "who has blocked me." Same oracle SHAPE as
-- is_blocked/is_friend/the rest of this sweep: a DEFINER function,
-- callable via PostgREST RPC, over arbitrary inputs, answering a
-- relationship question the table's own RLS does not otherwise expose to
-- that caller. DECISION: same exposure class — relocate.
--
-- Defined once, 20260709000006_create_sessions.sql:41-48, never
-- redefined.
--
-- Live POLICY dependents (grep-confirmed, none redefined since their
-- listed migration):
--   1-3. session_participants INSERT/UPDATE/DELETE ("participants
--        insertable/updatable/deletable only by session organizer") —
--        20260709000006_create_sessions.sql
--   4-5. session_duration_edits SELECT/INSERT ("session participants can
--        read/insert duration edits") — 20260714000003
--   6.   session_calendar_syncs SELECT ("organizer reads own session's
--        calendar syncs") — 20260724000002
--
-- Live SQL-FUNCTION-BODY callers (same plpgsql-SPI-reresolves-by-name
-- reasoning as is_group_member's migration — these must be updated via
-- CREATE OR REPLACE or they break at the next cold call once
-- public.is_session_organizer is dropped): touch_session_activity(uuid)
-- (20260716000003_push_cron.sql), wrap_up_session(uuid) and
-- still_going(uuid) (both 20260716000006_idle_rpcs.sql). All three also
-- call is_session_participant, which stays `public.is_session_participant`
-- unchanged (blocked from relocation — see task report).
--
-- No non-SQL callers (grepped supabase/functions/**/*.ts and the whole
-- repo for direct `.rpc("is_session_organizer", ...)` calls: none found).
-- ============================================================

-- ── 1. private.is_session_organizer() — same contract, unreachable schema ─
CREATE FUNCTION private.is_session_organizer(p_session_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE id = p_session_id AND organizer_id = p_user_id
  );
$$;

-- ── 2. session_participants (write policies only — no FOR ALL, matching
--    the deliberate SELECT exclusion documented in 20260709000006) ──────
DROP POLICY "participants insertable only by session organizer" ON public.session_participants;
CREATE POLICY "participants insertable only by session organizer"
  ON public.session_participants FOR INSERT TO authenticated
  WITH CHECK (private.is_session_organizer(session_participants.session_id, auth.uid()));

DROP POLICY "participants updatable only by session organizer" ON public.session_participants;
CREATE POLICY "participants updatable only by session organizer"
  ON public.session_participants FOR UPDATE TO authenticated
  USING (private.is_session_organizer(session_participants.session_id, auth.uid()))
  WITH CHECK (private.is_session_organizer(session_participants.session_id, auth.uid()));

DROP POLICY "participants deletable only by session organizer" ON public.session_participants;
CREATE POLICY "participants deletable only by session organizer"
  ON public.session_participants FOR DELETE TO authenticated
  USING (private.is_session_organizer(session_participants.session_id, auth.uid()));

-- ── 3. session_duration_edits ────────────────────────────────────────────
DROP POLICY "session participants can read duration edits" ON public.session_duration_edits;
CREATE POLICY "session participants can read duration edits"
  ON public.session_duration_edits FOR SELECT TO authenticated
  USING (public.is_session_participant(session_id, auth.uid())
         OR private.is_session_organizer(session_id, auth.uid()));

DROP POLICY "session participants can insert duration edits" ON public.session_duration_edits;
CREATE POLICY "session participants can insert duration edits"
  ON public.session_duration_edits FOR INSERT TO authenticated
  WITH CHECK (
    edited_by = auth.uid()
    AND (
      public.is_session_participant(session_id, auth.uid())
      OR private.is_session_organizer(session_id, auth.uid())
    )
  );

-- ── 4. session_calendar_syncs ─────────────────────────────────────────────
DROP POLICY "organizer reads own session's calendar syncs" ON public.session_calendar_syncs;
CREATE POLICY "organizer reads own session's calendar syncs"
  ON public.session_calendar_syncs FOR SELECT TO authenticated
  USING (private.is_session_organizer(session_calendar_syncs.session_id, auth.uid()));

-- ── 5. SQL-function-body callers — CREATE OR REPLACE, body-only change.
--    CREATE OR REPLACE preserves each function's existing grant posture
--    (all three are "No REVOKE" intended-client-callable RPCs, unchanged
--    signature/return type here). is_session_participant calls in all
--    three stay `public.is_session_participant`, unchanged. ─────────────
CREATE OR REPLACE FUNCTION public.touch_session_activity(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR private.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may send an activity heartbeat' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.sessions
  SET last_activity_at = now()
  WHERE id = p_session AND state = 'in_progress';
END;
$$;

CREATE OR REPLACE FUNCTION public.wrap_up_session(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR private.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may wrap up the session' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('gymsync.engine', 'on', true);

  UPDATE public.sessions
  SET state        = 'completed',
      completed_at = COALESCE(last_activity_at, started_at)
  WHERE id = p_session AND state = 'in_progress';

  PERFORM set_config('gymsync.engine', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.still_going(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_session_participant(p_session, auth.uid())
          OR private.is_session_organizer(p_session, auth.uid())) THEN
    RAISE EXCEPTION 'only session participants may confirm the session is still going' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.sessions
  SET last_activity_at    = now(),
      idle_30_notified_at = NULL,
      idle_60_notified_at = NULL
  WHERE id = p_session AND state = 'in_progress';
END;
$$;

-- ── 6. Drop the oracle ────────────────────────────────────────────────────
DROP FUNCTION public.is_session_organizer(uuid, uuid);
