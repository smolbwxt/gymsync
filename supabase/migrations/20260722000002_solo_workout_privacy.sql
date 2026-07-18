-- ============================================================
-- Phase M / Task 4: solo-workout privacy — set_logs SELECT RLS
-- ============================================================
-- Master spec's set_logs RLS entry (docs/superpowers/specs/2026-06-28-
-- gymsync-design.md:657): "readable by the user who logged it, plus
-- participants of the session it belongs to. Solo workouts where
-- profiles.show_solo_workouts=false are owner-only; otherwise friends can
-- read." The "friends can read" half was never implemented in
-- 20260709000007_create_set_logs.sql — 20260719000006_streaks.sql's own
-- header (lines 79-87) already flagged this: "the design doc's own
-- set_logs RLS narrative...describes a 'friends can read' rule that was
-- never actually implemented... this is the first one, built to the same
-- idiom" (for user_streaks, not set_logs). This migration closes the gap
-- for set_logs itself.
--
-- ── CURRENT policy (verbatim; unchanged since creation) ──────────────────
-- Grepped every migration for `set_logs` + `FOR SELECT` — only
-- 20260709000007_create_set_logs.sql ever defined this policy; no later
-- migration touched it:
--   CREATE POLICY "users can select their own set logs OR shared session
--   logs" ON public.set_logs FOR SELECT TO authenticated USING (
--     user_id = auth.uid()
--     OR public.is_session_participant(set_logs.session_id, auth.uid())
--   );
--
-- ── "Solo" predicate ───────────────────────────────────────────────────
-- Every session gets a `sessions` row, solo included —
-- SessionRepository.startSolo() (GymSyncApp/GymSync/Models/
-- SessionRepository.swift:21-50) inserts the sessions row, THEN "Add[s]
-- self as sole participant (for RLS unification across phases)" into
-- session_participants. So "solo" is honestly expressed as:
-- session_participants has EXACTLY ONE row for that session_id (and by
-- construction that row's user_id is always the session's own
-- organizer/owner — no other code path inserts into session_participants
-- for a session with no group/invite context). Verified against schema:
-- session_participants (20260709000006_create_sessions.sql:18-24) carries
-- no `is_solo`/`kind` flag of its own — participant count is the only
-- honest signal available.
--
-- A direct `(SELECT count(*) FROM session_participants WHERE
-- session_id=…) = 1` subquery INSIDE the set_logs policy would be WRONG
-- for a friend (non-participant) caller: session_participants' own SELECT
-- policy ("participants readable by other participants",
-- 20260709000006_create_sessions.sql:68-73) restricts reads to
-- participants of that session, so a friend evaluating that subquery
-- directly would see 0 rows (not 1) even for a genuinely-solo session —
-- the exact RLS-recursion self-defeat create_sessions.sql's own header
-- (lines 29-31) already documents ("SECURITY DEFINER helpers break RLS
-- recursion... any direct cross-table subquery in a policy re-enters the
-- other table's RLS and cycles"). `is_solo_session()` below is a
-- SECURITY DEFINER STABLE helper in the exact same shape as
-- `is_session_participant`/`is_session_organizer` (same file) — it
-- bypasses that RLS exactly like its siblings do, so the count is always
-- evaluated against the true underlying data regardless of caller.
--
-- ── Friend helper: reuse `public.is_friend`, already public per Phase S ──
-- `public.is_friend(p_user_id, p_viewer_id)` already exists
-- (20260719000006_streaks.sql:127-136): accepted-pair friendship check
-- (either direction), SECURITY DEFINER STABLE, already backing a live RLS
-- policy ("owner and friends can read user streaks"). It already lives in
-- the PUBLIC schema (not `private`) — unlike `is_blocked`
-- (20260722000001_is_blocked_private_schema.sql), which was moved to
-- `private` specifically because it let an arbitrary caller resolve "did A
-- block B" for ANY pair, defeating blocked_users' owner-only SELECT policy
-- whose entire purpose is hiding that fact from everyone but the blocker.
-- `is_friend` carries the same shape of oracle risk in principle
-- (arbitrary-pair friendship-status enumeration), but that is a decision
-- already made and shipped in Phase S, not something this migration
-- re-litigates: reusing the existing public helper (rather than forking a
-- second, `private`-schema copy of the identical predicate for just this
-- one new caller, which would leave two inconsistent implementations of
-- "are these two users friends" in the schema) is the correct fix-forward
-- move. Flagged here, not fixed here — out of scope for a
-- set_logs-focused fix-forward (CLAUDE.md: "don't touch unrelated code").
--
-- `is_solo_session()` itself is kept in the `public` schema, matching the
-- established shape of its own siblings (is_session_participant/
-- is_session_organizer/is_group_member/is_friend — all public, all
-- SECURITY DEFINER STABLE, all left with Postgres's default
-- EXECUTE-to-PUBLIC grant on CREATE FUNCTION). It leaks strictly less than
-- is_blocked did: a boolean "does session X currently have exactly one
-- participant" carries no identity or relationship information for an
-- arbitrary caller to harvest (contrast is_blocked(A,B), which answers a
-- yes/no question ABOUT a specific pair of users' deliberately-hidden
-- relationship) — judged low-sensitivity, consistent with the existing
-- sibling helpers' posture, and NOT moved to `private`.
--
-- ── Fix-forward: DROP + CREATE (no CREATE OR REPLACE POLICY in Postgres) ──
-- USING clause transplants the current policy's two clauses verbatim, and
-- adds ONE new OR-branch: a set_log is also readable by an ACCEPTED FRIEND
-- of the owner, but ONLY when (a) the log's session resolves to a solo
-- session and (b) the owner has opted in
-- (`profiles.show_solo_workouts = true`). Gating on is_solo_session() is
-- what keeps this a strictly solo-sharing surface: for a MULTI-participant
-- (group) session, a non-participant friend of the organizer does NOT
-- gain access through this new clause — they still only read via the
-- pre-existing is_session_participant() branch, exactly as before this
-- migration. Without that gate, an organizer with show_solo_workouts=true
-- would leak ALL of their group-session set_logs to every accepted friend,
-- not just their solo ones — the master spec's rule is explicitly scoped
-- to solo workouts, not sharing in general.
--
-- `profiles` is read directly in the new clause (not through another
-- DEFINER helper): its own SELECT policy is `USING (true)` for any
-- authenticated user (20260709000001_create_profiles.sql), so there is no
-- RLS-recursion risk for that lookup — wrapping it in a helper would be
-- pure ceremony.
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_solo_session(p_session_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT (
    SELECT count(*) FROM public.session_participants
    WHERE session_id = p_session_id
  ) = 1;
$$;

DROP POLICY "users can select their own set logs OR shared session logs" ON public.set_logs;

-- Name kept under Postgres's 63-byte NAMEDATALEN identifier limit —
-- the original attempt ("...shared session logs OR friend solo logs", 82
-- bytes) was silently truncated by Postgres to 63 bytes on CREATE POLICY
-- (confirmed via pg_policies after `supabase db push`: identifier landed
-- as "...OR shared session logs OR f", not an error, just silent
-- truncation), which would have made the live policy name diverge from
-- what this file says it is. Renamed to a short, explicit name instead of
-- relying on that truncation.
CREATE POLICY "set_logs read: owner, participant, or opted-in friend"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_session_participant(set_logs.session_id, auth.uid())
    OR (
      public.is_solo_session(set_logs.session_id)
      AND public.is_friend(set_logs.user_id, auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = set_logs.user_id AND p.show_solo_workouts = true
      )
    )
  );
