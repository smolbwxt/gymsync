-- ============================================================
-- Phase O / Task 1, fix-wave 2: close the is_session_participant()
-- PostgREST oracle — dual-function design.
-- ============================================================
-- BACKGROUND (task-1-report.md, "Concerns for the controller" #1):
-- fix-wave 1 (commit 7309db5) relocated 6 of 7 flagged helpers to `private`
-- but deliberately left public.is_session_participant(p_session_id uuid,
-- p_user_id uuid) untouched: supabase/functions/livekit-token/index.ts:42
-- calls it via `this.client.rpc("is_session_participant", {...})`, and
-- PostgREST route generation is schema-based (supabase/config.toml [api]
-- schemas = ["public", "graphql_public"]) — a plain relocation to `private`
-- would 404 every voice-token mint regardless of caller role, since
-- PostgREST never introspects an unlisted schema. Re-verified here: the
-- Edge Function's client is constructed with SUPABASE_SERVICE_ROLE_KEY
-- (index.ts:179-180), so that RPC call executes as Postgres role
-- `service_role`, not `authenticated`.
--
-- FIX: dual-function design, same shape this task brief specified.
--   (a) private.is_session_participant() — identical contract, unreachable
--       via PostgREST (schema not API-exposed, `private` already exists:
--       CREATE SCHEMA IF NOT EXISTS + REVOKE ALL FROM PUBLIC,
--       20260722000001_is_blocked_private_schema.sql — not recreated here).
--   (b) every dependent policy repointed to the private copy.
--   (c) public.is_session_participant's body replaced with a thin
--       SECURITY DEFINER delegation to private.is_session_participant —
--       single source of truth, and it stays DEFINER so it keeps running
--       with owner privileges (needs no additional grant to read
--       session_participants; only its OWN EXECUTE grant is narrowed
--       below).
--   (d) REVOKE EXECUTE ON public.is_session_participant FROM PUBLIC,
--       authenticated, anon; GRANT TO service_role only. Safe at this
--       point because (b) already means no policy anywhere still resolves
--       to public.is_session_participant's OID — the only remaining
--       caller is livekit-token's service-role RPC.
--
-- WHY NOT A BARE REVOKE ON THE EXISTING PUBLIC FUNCTION (the thing that was
-- explicitly rejected before this task started): EXECUTE-on-function is
-- re-checked at EVERY call site, including a call embedded in an RLS
-- policy's USING/WITH CHECK expression evaluated for role `authenticated` —
-- unlike SCHEMA USAGE, which is a name-resolution privilege checked once,
-- at CREATE POLICY time, not re-checked when the already-resolved qual is
-- later evaluated per-query. This exact asymmetry (and why it's what makes
-- the private-schema pattern work at all) is documented in
-- 20260722000001_is_blocked_private_schema.sql's header, lines 58-75 —
-- NOT 20260721000001 (that migration only carries the short "REVOKE first,
-- GRANT back" idiom note, not the full asymmetry explanation; citation
-- corrected here after actually reading both files side by side). A bare
-- `REVOKE EXECUTE ... FROM authenticated` on the STILL-public function
-- while 13 live policies and 6 SQL-function bodies still call it by that
-- name would fail-closed every one of those policies for every
-- authenticated caller in production — exactly the fate this migration's
-- ordering avoids by relocating first, repointing second, narrowing last.
--
-- VERIFIED (not assumed) CREATE-OR-REPLACE / grant-preservation semantics:
-- per Postgres's own documented behavior ("When CREATE OR REPLACE FUNCTION
-- is used to replace an existing function, the ownership and permissions of
-- the function do not change") and this repo's own established precedent
-- (task-1-report.md: "CREATE OR REPLACE preserves a function's grant set
-- when signature/return type are unchanged"), a same-signature CREATE OR
-- REPLACE on public.is_session_participant does NOT reset its grants back
-- to Supabase's default. This was re-confirmed empirically in this fix wave
-- with a disposable rollback-wrapped probe function (REVOKE FROM PUBLIC,
-- authenticated, anon; GRANT TO service_role; CREATE OR REPLACE; re-checked
-- information_schema.routine_privileges — identical grantee set before and
-- after the replace, in both a first probe that only revoked FROM PUBLIC
-- and a second that matched this project's full REVOKE ... FROM PUBLIC,
-- authenticated, anon pattern). That second probe run also surfaced WHY
-- this codebase's established pattern always lists `anon, authenticated`
-- explicitly instead of relying on `FROM PUBLIC` alone: Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE directly to anon/authenticated/
-- service_role at object-creation time (not merely via PUBLIC membership),
-- so a REVOKE naming only PUBLIC leaves those three roles' DIRECT grants
-- untouched — REVOKE must name them explicitly, which this migration does
-- below, matching precedent (e.g. 20260716000005_claim_push_batch.sql).
-- THE ACTUAL TRAP for a future reader: it is not "any CREATE OR REPLACE
-- reopens this" (verified false) — it is that a DROP + fresh CREATE
-- FUNCTION (as opposed to CREATE OR REPLACE), or any signature change
-- (which Postgres treats as a distinct, brand-new function object), WOULD
-- pick up Supabase's default grants again and silently reopen the oracle.
-- Any future edit to public.is_session_participant should stay a same-
-- signature CREATE OR REPLACE; if the signature ever needs to change, the
-- REVOKE/GRANT pair below must be restated for the new object.
--
-- Full inventory (grep-verified against every migration; cross-checked
-- each named policy/function against every later migration for
-- redefinition, transplanting only the CURRENT live version):
--
-- Dependent POLICIES repointed to private.is_session_participant (13):
--   1-2. sessions SELECT/UPDATE ("users can select sessions they
--        participate in", "organizer or participant can update session")
--        — 20260709000006, never redefined.
--   3.   session_participants SELECT ("participants readable by other
--        participants") — 20260709000006, never redefined.
--   4.   set_logs SELECT ("set_logs read: owner, participant, or opted-in
--        friend") — latest 20260725000004_is_solo_session_private_schema.
--        sql (already calling private.is_friend/is_solo_session/is_blocked
--        from prior relocations in this same sweep).
--   5-6. routine_proposals SELECT/INSERT ("session participants read
--        proposals", "session participants propose as themselves") —
--        20260712000003, never redefined.
--   7-8. routine_proposal_votes SELECT/INSERT ("session participants read
--        votes", "session participants vote as themselves") —
--        20260712000003, never redefined. Both wrap the call in
--        public.proposal_session_id(...) — that helper itself does not
--        call is_session_participant and is out of this task's scope,
--        left untouched.
--   9-10. session_duration_edits SELECT/INSERT ("session participants can
--        read/insert duration edits") — latest
--        20260725000005_is_session_organizer_private_schema.sql (already
--        OR'd with private.is_session_organizer).
--   11-12. session_kudos SELECT/INSERT ("session participants read kudos",
--        "session participants send kudos to session participants") —
--        20260720000001, never redefined. The INSERT policy calls
--        is_session_participant TWICE (sender leg + recipient leg) — both
--        repointed.
--   13.  chat_messages SELECT ("group members read messages") — latest
--        20260725000002_is_group_member_private_schema.sql (already using
--        private.is_group_member + private.is_blocked).
--
-- Dependent SQL-FUNCTION-BODY callers, CREATE OR REPLACE'd to call
-- private.is_session_participant (6): touch_session_activity(uuid),
-- wrap_up_session(uuid), still_going(uuid) — latest bodies
-- 20260725000005 (already calling private.is_session_organizer);
-- session_pr_counts(uuid) — 20260720000002, never redefined;
-- start_attempt(uuid,uuid,boolean) — latest 20260723000003 (Finding-1-fixed
-- body); private.can_access_message(uuid,uuid) — latest/only
-- 20260725000003 (already private, already calling private.is_group_member
-- internally). NOTE: every one of these is itself SECURITY DEFINER, owned
-- by the same migration role that owns is_session_participant, so — per
-- Postgres's "object owner bypasses that object's own ACL" rule — they
-- would technically keep working even left pointed at
-- public.is_session_participant after step (d)'s REVOKE. Repointed anyway,
-- for two reasons: (1) matches this sweep's own established precedent
-- everywhere else (is_group_member's migration updated
-- group_burpee_ledger/group_stats/group_member_stats; is_session_
-- organizer's updated these exact same three heartbeat RPCs for its own
-- operand); (2) not relying on an unstated ownership-bypass invariant that
-- would silently break if a future migration ever ran under a different
-- owning role.
--
-- No non-SQL callers other than livekit-token (grepped supabase/
-- functions/**/*.ts, GymSyncApp/**/*.swift for both `is_session_
-- participant` and generic `.rpc(` call sites): only livekit-token/
-- index.ts:42 found, service-role-authenticated as established above.
-- ============================================================

-- ── 1. private.is_session_participant() — same contract, unreachable schema
CREATE FUNCTION private.is_session_participant(p_session_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.session_participants
    WHERE session_id = p_session_id AND user_id = p_user_id
  );
$$;

-- ── 2. Repoint the 13 dependent policies ─────────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE, this repo's
-- established idiom throughout. Full USING/WITH CHECK text transplanted
-- verbatim from each policy's current live version cited above, changing
-- only public.is_session_participant -> private.is_session_participant.

-- 2a. sessions
DROP POLICY "users can select sessions they participate in" ON public.sessions;
CREATE POLICY "users can select sessions they participate in"
  ON public.sessions FOR SELECT TO authenticated
  USING (
    organizer_id = auth.uid()
    OR private.is_session_participant(sessions.id, auth.uid())
  );

DROP POLICY "organizer or participant can update session" ON public.sessions;
CREATE POLICY "organizer or participant can update session"
  ON public.sessions FOR UPDATE TO authenticated
  USING (
    organizer_id = auth.uid()
    OR private.is_session_participant(sessions.id, auth.uid())
  );

-- 2b. session_participants
DROP POLICY "participants readable by other participants" ON public.session_participants;
CREATE POLICY "participants readable by other participants"
  ON public.session_participants FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR private.is_session_participant(session_participants.session_id, auth.uid())
  );

-- 2c. set_logs (latest version 20260725000004)
DROP POLICY "set_logs read: owner, participant, or opted-in friend" ON public.set_logs;
CREATE POLICY "set_logs read: owner, participant, or opted-in friend"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR private.is_session_participant(set_logs.session_id, auth.uid())
    OR (
      private.is_solo_session(set_logs.session_id)
      AND private.is_friend(set_logs.user_id, auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = set_logs.user_id AND p.show_solo_workouts = true
      )
      AND NOT private.is_blocked(set_logs.user_id, auth.uid())
      AND NOT private.is_blocked(auth.uid(), set_logs.user_id)
    )
  );

-- 2d. routine_proposals / routine_proposal_votes
DROP POLICY "session participants read proposals" ON public.routine_proposals;
CREATE POLICY "session participants read proposals"
  ON public.routine_proposals FOR SELECT TO authenticated
  USING (private.is_session_participant(routine_proposals.session_id, auth.uid()));

DROP POLICY "session participants propose as themselves" ON public.routine_proposals;
CREATE POLICY "session participants propose as themselves"
  ON public.routine_proposals FOR INSERT TO authenticated
  WITH CHECK (proposer_id = auth.uid()
              AND private.is_session_participant(routine_proposals.session_id, auth.uid()));

DROP POLICY "session participants read votes" ON public.routine_proposal_votes;
CREATE POLICY "session participants read votes"
  ON public.routine_proposal_votes FOR SELECT TO authenticated
  USING (private.is_session_participant(
           public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

DROP POLICY "session participants vote as themselves" ON public.routine_proposal_votes;
CREATE POLICY "session participants vote as themselves"
  ON public.routine_proposal_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND private.is_session_participant(
                    public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

-- 2e. session_duration_edits (latest version 20260725000005)
DROP POLICY "session participants can read duration edits" ON public.session_duration_edits;
CREATE POLICY "session participants can read duration edits"
  ON public.session_duration_edits FOR SELECT TO authenticated
  USING (private.is_session_participant(session_id, auth.uid())
         OR private.is_session_organizer(session_id, auth.uid()));

DROP POLICY "session participants can insert duration edits" ON public.session_duration_edits;
CREATE POLICY "session participants can insert duration edits"
  ON public.session_duration_edits FOR INSERT TO authenticated
  WITH CHECK (
    edited_by = auth.uid()
    AND (
      private.is_session_participant(session_id, auth.uid())
      OR private.is_session_organizer(session_id, auth.uid())
    )
  );

-- 2f. session_kudos
DROP POLICY "session participants read kudos" ON public.session_kudos;
CREATE POLICY "session participants read kudos"
  ON public.session_kudos FOR SELECT TO authenticated
  USING (private.is_session_participant(session_kudos.session_id, auth.uid()));

DROP POLICY "session participants send kudos to session participants" ON public.session_kudos;
CREATE POLICY "session participants send kudos to session participants"
  ON public.session_kudos FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND private.is_session_participant(session_kudos.session_id, auth.uid())
    AND private.is_session_participant(session_kudos.session_id, recipient_id)
  );

-- 2g. chat_messages (latest version 20260725000002)
DROP POLICY "group members read messages" ON public.chat_messages;
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (
      (chat_messages.session_id IS NULL
       AND private.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND private.is_session_participant(chat_messages.session_id, auth.uid()))
    )
    AND NOT private.is_blocked(auth.uid(), chat_messages.author_id)
  );

-- ── 3. Repoint the 6 SQL-function-body callers (CREATE OR REPLACE,
--    body-only changes; each function's own ACL is untouched/preserved —
--    see header for the verified CREATE-OR-REPLACE grant-preservation
--    semantics) ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.touch_session_activity(p_session uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (private.is_session_participant(p_session, auth.uid())
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
  IF NOT (private.is_session_participant(p_session, auth.uid())
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
  IF NOT (private.is_session_participant(p_session, auth.uid())
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

CREATE OR REPLACE FUNCTION public.session_pr_counts(p_session_id uuid)
RETURNS TABLE (
  user_id   uuid,
  pr_count  int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT pr.user_id, COUNT(*)::int AS pr_count
    FROM public.personal_records pr
   WHERE pr.session_id = p_session_id
   GROUP BY pr.user_id;
END;
$$;
-- REVOKE/GRANT (FROM PUBLIC, anon / TO authenticated) stand from
-- 20260720000002_session_pr_counts_and_kudos_guard.sql — same signature,
-- ACL preserved by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.start_attempt(p_routine_id uuid, p_session_id uuid, p_opt_in boolean)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_visibility          text;
  v_session_routine_id  uuid;
  v_id                  uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'must be a participant of the session to start an attempt' USING ERRCODE = 'P0001';
  END IF;

  SELECT routine_id INTO v_session_routine_id FROM public.sessions WHERE id = p_session_id;
  IF v_session_routine_id IS DISTINCT FROM p_routine_id THEN
    RAISE EXCEPTION 'session must be running the attempted routine' USING ERRCODE = 'P0001';
  END IF;

  SELECT visibility INTO v_visibility FROM public.routines WHERE id = p_routine_id;
  IF v_visibility IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'routine must be public to attempt from Discover' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.workout_attempts
    (routine_id, user_id, session_id, is_opt_in_leaderboard, started_at, is_complete)
  VALUES
    (p_routine_id, auth.uid(), p_session_id, COALESCE(p_opt_in, false), now(), false)
  ON CONFLICT (session_id, user_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.workout_attempts
      WHERE session_id = p_session_id AND user_id = auth.uid();
  END IF;

  RETURN v_id;
END;
$$;
-- REVOKE/GRANT (FROM PUBLIC, anon / TO authenticated) stand from
-- 20260723000002_attempt_plumbing.sql — ACL preserved by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION private.can_access_message(p_message_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_messages m
    WHERE m.id = p_message_id
      AND (
        (m.session_id IS NULL AND private.is_group_member(m.group_id, p_user_id))
        OR (m.session_id IS NOT NULL AND private.is_session_participant(m.session_id, p_user_id))
      )
  );
$$;

-- ── 4. public.is_session_participant() — thin DEFINER delegation ────────
-- Single source of truth stays in private.is_session_participant; this
-- keeps existing (post-narrowing) callers working via the same public name
-- livekit-token already calls, with zero logic duplication. Still
-- SECURITY DEFINER (required — see header) though it no longer needs table
-- access itself; search_path pinned per this repo's blanket convention even
-- though the delegated call is fully schema-qualified.
CREATE OR REPLACE FUNCTION public.is_session_participant(p_session_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT private.is_session_participant(p_session_id, p_user_id);
$$;

-- ── 5. Close the RPC oracle ───────────────────────────────────────────────
-- Safe now: step 2 repointed every dependent policy and step 3 repointed
-- every SQL-function-body caller away from public.is_session_participant,
-- so no in-production query path still resolves an authenticated-context
-- call to this function's OID. The only remaining caller is livekit-token's
-- service-role RPC (verified above), so REVOKE from PUBLIC, authenticated,
-- anon (matching this repo's explicit-list convention — see header on why
-- `FROM PUBLIC` alone is insufficient) and GRANT to service_role only.
REVOKE EXECUTE ON FUNCTION public.is_session_participant(uuid, uuid) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_session_participant(uuid, uuid) TO service_role;
