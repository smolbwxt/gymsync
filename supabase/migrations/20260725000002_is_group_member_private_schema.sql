-- ============================================================
-- Phase O / Task 1: DEFINER-helper sweep, item 3 of 6 — is_group_member()
-- ============================================================
-- public.is_group_member(p_group_id uuid, p_user_id uuid) — defined once,
-- 20260710000002_create_groups.sql:25-30, never redefined. SECURITY
-- DEFINER STABLE, search_path pinned to public, default PUBLIC EXECUTE
-- grant (no REVOKE/GRANT statements anywhere for it).
--
-- Exposure: answers "is p_user_id a member of p_group_id?" for ANY
-- arbitrary (group, user) pair, via the auto-minted POST
-- /rest/v1/rpc/is_group_member — a membership oracle over every group in
-- the system, same shape as is_blocked/is_friend.
--
-- This is the highest-fanout helper in the queue: grep of every migration
-- for `is_group_member` turns up every live dependent below, cross-checked
-- against DROP POLICY/CREATE OR REPLACE history so only the CURRENT
-- (latest) definition of each named policy is transplanted — most were
-- redefined at least once for unrelated reasons (kind lists, block checks,
-- membership-gating rewrites) after their original creation.
--
-- Batching rationale: one migration for the whole helper (matching
-- is_blocked's own precedent of one migration per helper, and the task
-- brief's explicit guidance to batch by dependency overlap) — every
-- dependent below shares the same single change (public.is_group_member ->
-- private.is_group_member; nothing else in any of these policies/functions
-- is touched), so splitting by table would just fragment one mechanical
-- change across many files for no isolation benefit. can_access_message
-- and message_group_id are deliberately NOT included here even though they
-- also touch chat surfaces — they are separate queue items (5 and 4) with
-- their own body/grant considerations, handled in their own migration
-- after this one (their bodies reference private.is_group_member once it
-- exists, per queue order).
--
-- is_session_participant is NOT relocated (separate, currently-blocked
-- queue item — see task report) — every policy/function below that ORs
-- is_group_member with is_session_participant keeps the is_session_
-- participant call as `public.is_session_participant`, unchanged.
--
-- Non-obvious-caller check: grep of supabase/functions/**/*.ts and the
-- whole repo for direct `.rpc("is_group_member", ...)` calls: none found.
-- No triggers or views call it directly (checked: zero `CREATE VIEW`
-- statements exist anywhere in supabase/migrations). Three SECURITY
-- DEFINER PL/pgSQL functions call it from their own body (not via a
-- cached policy qual — plpgsql SPI re-resolves embedded SQL by name at
-- each fresh compile, so leaving these as `public.is_group_member(...)`
-- after DROP FUNCTION public.is_group_member would break them at the next
-- cold call): group_burpee_ledger(uuid), group_stats(uuid),
-- group_member_stats(uuid). All three are updated below via CREATE OR
-- REPLACE (same signature, same grants preserved automatically — see each
-- section) to call private.is_group_member instead.
-- ============================================================

-- ── 1. private.is_group_member() — same contract, unreachable schema ────
CREATE FUNCTION private.is_group_member(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id);
$$;

-- ── 2. groups / group_members ────────────────────────────────────────────
DROP POLICY "members and creator can read group" ON public.groups;
CREATE POLICY "members and creator can read group"
  ON public.groups FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR private.is_group_member(groups.id, auth.uid()));

DROP POLICY "members can read membership" ON public.group_members;
CREATE POLICY "members can read membership"
  ON public.group_members FOR SELECT TO authenticated
  USING (user_id = auth.uid()
         OR private.is_group_member(group_members.group_id, auth.uid()));

-- ── 3. chat_messages (SELECT last defined 20260722000001; INSERT last
--    defined 20260719000011; UPDATE last defined 20260715000001) ────────
DROP POLICY "group members read messages" ON public.chat_messages;
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (
      (chat_messages.session_id IS NULL
       AND private.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid()))
    )
    AND NOT private.is_blocked(auth.uid(), chat_messages.author_id)
  );

DROP POLICY "members send client messages as themselves" ON public.chat_messages;
CREATE POLICY "members send client messages as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND (kind NOT IN ('image', 'audio') OR storage_path IS NOT NULL)
    AND (kind <> 'soundboard_echo' OR payload IS NOT NULL)
    AND (
      (chat_messages.session_id IS NULL
       AND private.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid())
          AND chat_messages.group_id IS NOT DISTINCT FROM (
                SELECT s.group_id FROM public.sessions s
                WHERE s.id = chat_messages.session_id))
    )
  );

DROP POLICY "author edits own messages" ON public.chat_messages;
CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (
    author_id = auth.uid()
    AND private.is_group_member(chat_messages.group_id, auth.uid())
  )
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND private.is_group_member(chat_messages.group_id, auth.uid())
  );

-- ── 4. chat_read_state (SELECT/INSERT last defined 20260710000003;
--    UPDATE last defined 20260711000001) ─────────────────────────────────
DROP POLICY "group members read read-state" ON public.chat_read_state;
CREATE POLICY "group members read read-state"
  ON public.chat_read_state FOR SELECT TO authenticated
  USING (private.is_group_member(chat_read_state.group_id, auth.uid()));

DROP POLICY "user inserts own read-state" ON public.chat_read_state;
CREATE POLICY "user inserts own read-state"
  ON public.chat_read_state FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND private.is_group_member(chat_read_state.group_id, auth.uid()));

DROP POLICY "user updates own read-state" ON public.chat_read_state;
CREATE POLICY "user updates own read-state"
  ON public.chat_read_state FOR UPDATE TO authenticated
  USING (user_id = auth.uid()
         AND private.is_group_member(chat_read_state.group_id, auth.uid()))
  WITH CHECK (user_id = auth.uid()
              AND private.is_group_member(chat_read_state.group_id, auth.uid()));

-- ── 5. storage.objects: chat-images, chat-audio (both pairs last defined
--    20260711000002 / 20260715000001, never redefined) ──────────────────
DROP POLICY "group members upload chat images" ON storage.objects;
CREATE POLICY "group members upload chat images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-images'
    AND private.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

DROP POLICY "group members read chat images" ON storage.objects;
CREATE POLICY "group members read chat images"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND private.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

DROP POLICY "group members upload chat audio" ON storage.objects;
CREATE POLICY "group members upload chat audio"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-audio'
    AND private.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

DROP POLICY "group members read chat audio" ON storage.objects;
CREATE POLICY "group members read chat audio"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-audio'
    AND private.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- ── 6. session_series / session_series_days (SELECT/INSERT on
--    session_series last defined 20260713000001; UPDATE/DELETE on
--    session_series last defined 20260713000002; session_series_days
--    SELECT last defined 20260713000001, INSERT/UPDATE/DELETE last defined
--    20260713000002). series_group_id() stays public — not in this sweep's
--    queue — only its caller (is_group_member) is repointed. ────────────
DROP POLICY "group members read series" ON public.session_series;
CREATE POLICY "group members read series"
  ON public.session_series FOR SELECT TO authenticated
  USING (private.is_group_member(session_series.group_id, auth.uid()));

DROP POLICY "organizer creates series in own group" ON public.session_series;
CREATE POLICY "organizer creates series in own group"
  ON public.session_series FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid()
              AND private.is_group_member(session_series.group_id, auth.uid()));

DROP POLICY "organizer updates series" ON public.session_series;
CREATE POLICY "organizer updates series"
  ON public.session_series FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid()
         AND private.is_group_member(session_series.group_id, auth.uid()))
  WITH CHECK (organizer_id = auth.uid()
              AND private.is_group_member(session_series.group_id, auth.uid()));

DROP POLICY "organizer deletes series" ON public.session_series;
CREATE POLICY "organizer deletes series"
  ON public.session_series FOR DELETE TO authenticated
  USING (organizer_id = auth.uid()
         AND private.is_group_member(session_series.group_id, auth.uid()));

DROP POLICY "group members read series days" ON public.session_series_days;
CREATE POLICY "group members read series days"
  ON public.session_series_days FOR SELECT TO authenticated
  USING (private.is_group_member(
           public.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer writes series days" ON public.session_series_days;
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    public.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer updates series days" ON public.session_series_days;
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               public.series_group_id(session_series_days.series_id), auth.uid()))
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND private.is_group_member(
                    public.series_group_id(session_series_days.series_id), auth.uid()));

DROP POLICY "organizer deletes series days" ON public.session_series_days;
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND private.is_group_member(
               public.series_group_id(session_series_days.series_id), auth.uid()));

-- ── 7. sessions DELETE (last defined 20260714000004) ────────────────────
DROP POLICY "organizer deletes own scheduled sessions" ON public.sessions;
CREATE POLICY "organizer deletes own scheduled sessions"
  ON public.sessions FOR DELETE TO authenticated
  USING (organizer_id = auth.uid() AND state = 'scheduled'
         AND (sessions.group_id IS NULL
              OR private.is_group_member(sessions.group_id, auth.uid())));

-- ── 8. group_streaks SELECT (20260719000006, never redefined) ───────────
DROP POLICY "members can read group streaks" ON public.group_streaks;
CREATE POLICY "members can read group streaks"
  ON public.group_streaks FOR SELECT TO authenticated
  USING (private.is_group_member(group_streaks.group_id, auth.uid()));

-- ── 9. SQL-function-body callers — CREATE OR REPLACE, body-only change ──
-- CREATE OR REPLACE preserves each function's existing REVOKE EXECUTE FROM
-- PUBLIC, anon / GRANT EXECUTE TO authenticated set (signature and return
-- type both unchanged here) — same idiom this codebase already relies on
-- (20260720000004's own header: "No REVOKE re-run needed... signature and
-- return type are both unchanged here, only the body"). Not restated.

-- group_burpee_ledger: current live definition is the DROP FUNCTION +
-- CREATE FUNCTION in 20260719000005_burpee_ledger_paid.sql (added
-- paid/settled columns) — CREATE OR REPLACE is valid here since this
-- migration does not change the return type again.
CREATE OR REPLACE FUNCTION public.group_burpee_ledger(p_group uuid)
RETURNS TABLE (
  user_id       uuid,
  total_owed    int,
  paid          int,
  settled       boolean,
  late_count    int,
  no_show_count int,
  last_late_at  timestamptz
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_group_member(p_group, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT owed.user_id,
         owed.total_owed,
         COALESCE(paid_agg.paid, 0)::int AS paid,
         COALESCE(paid_agg.paid, 0) >= owed.total_owed AS settled,
         owed.late_count,
         owed.no_show_count,
         owed.last_late_at
    FROM (
      SELECT sp.user_id,
             SUM(sp.burpees_owed)::int AS total_owed,
             COUNT(*) FILTER (WHERE sp.check_in_state = 'late')::int AS late_count,
             COUNT(*) FILTER (WHERE sp.check_in_state = 'no_show')::int AS no_show_count,
             MAX(COALESCE(s.scheduled_for, s.started_at))
               FILTER (WHERE sp.burpees_owed > 0) AS last_late_at
        FROM public.session_participants sp
        JOIN public.sessions s ON s.id = sp.session_id
       WHERE s.group_id = p_group
       GROUP BY sp.user_id
    ) owed
    LEFT JOIN LATERAL (
      SELECT SUM(COALESCE(sl.reps, 0))::int AS paid
        FROM public.set_logs sl
        JOIN public.sessions ps ON ps.id = sl.session_id
       WHERE ps.group_id = p_group
         AND sl.user_id = owed.user_id
         AND sl.is_penalty
    ) paid_agg ON true;
END;
$$;

-- group_stats: current live definition is the CREATE OR REPLACE in
-- 20260720000004_group_stats_scalars_all_time.sql (all-time volume/PRs).
CREATE OR REPLACE FUNCTION public.group_stats(p_group_id uuid)
RETURNS TABLE (
  session_count int,
  total_volume  numeric,
  total_prs     int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*)::int
       FROM public.sessions s
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS session_count,
    (SELECT COALESCE(SUM(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)), 0)
       FROM public.set_logs sl
       JOIN public.sessions s ON s.id = sl.session_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed'
        AND NOT sl.is_penalty
        AND NOT sl.is_failed) AS total_volume,
    (SELECT count(*)::int
       FROM public.personal_records pr
       JOIN public.sessions s ON s.id = pr.session_id
      WHERE s.group_id = p_group_id
        AND s.state = 'completed') AS total_prs;
END;
$$;

-- group_member_stats: current live definition is unchanged since
-- 20260720000003_group_stats_rpc.sql (20260720000004 explicitly left it
-- untouched — current-roster scoping is deliberate there).
CREATE OR REPLACE FUNCTION public.group_member_stats(p_group_id uuid)
RETURNS TABLE (
  user_id   uuid,
  username  text,
  volume    numeric,
  pr_count  int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT gm.user_id,
         p.username,
         COALESCE(vol_agg.volume, 0) AS volume,
         COALESCE(pr_agg.pr_count, 0)::int AS pr_count
    FROM public.group_members gm
    JOIN public.profiles p ON p.id = gm.user_id
    LEFT JOIN LATERAL (
      SELECT SUM(COALESCE(sl.reps, 0) * COALESCE(sl.weight, 0)) AS volume
        FROM public.set_logs sl
        JOIN public.sessions s ON s.id = sl.session_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND sl.user_id = gm.user_id
         AND NOT sl.is_penalty
         AND NOT sl.is_failed
    ) vol_agg ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS pr_count
        FROM public.personal_records pr
        JOIN public.sessions s ON s.id = pr.session_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND pr.user_id = gm.user_id
    ) pr_agg ON true
   WHERE gm.group_id = p_group_id
   ORDER BY volume DESC;
END;
$$;

-- ── 10. Drop the oracle ───────────────────────────────────────────────────
-- Must run AFTER every policy and function body above stops referencing
-- public.is_group_member: a policy or function dependency would otherwise
-- block this DROP (Postgres tracks function-in-policy dependencies; plain
-- SQL-text references inside plpgsql bodies are not tracked as catalog
-- dependencies, but the CREATE OR REPLACE statements above already ran, so
-- no live plpgsql body references the public name by the time this DROP
-- executes either way).
DROP FUNCTION public.is_group_member(uuid, uuid);
