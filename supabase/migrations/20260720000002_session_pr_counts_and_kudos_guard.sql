-- ============================================================
-- Phase F / Task 4 — Fix round 1 (task-4-report.md): crew PR counts
-- unreachable under RLS + self-kudos guard.
-- ============================================================
-- Finding 1 (Critical): GroupSessionLiveView.buildGroupRecapPayload
-- (~1857-1945) fetches session PRs via
-- `PersonalRecordRepository.bySession(sessionID:)` -> a direct
-- `personal_records` select. personal_records' SELECT RLS is SELF-ONLY
-- (20260715000002_personal_records.sql:23-25, "users can select their own
-- personal records" -> auth.uid() = user_id). For a real multi-lifter group
-- session, whichever teammate's device builds the recap only ever gets back
-- THEIR OWN pr rows for that session — every other participant's PRs are
-- silently dropped by RLS, not aggregated wrong. The recap then renders 0
-- PRs for every teammate (hero "PRS" stat = sessionPRs.count, and every
-- leaderboard row's "N PR" badge = sessionPRs.filter { $0.userID ==
-- participant }.count) except the one lifter whose own device happened to
-- render it. Only the catalog fixture (which hands the view pre-built
-- fixture data, bypassing the network call entirely) looked right.
--
-- Same shape as group_burpee_ledger (20260717000002_burpee_ledger_rpc.sql)
-- and activity_feed (20260719000002_activity_feed_rpc.sql): a client-side
-- aggregate computed from a single caller's RLS-filtered fetch silently
-- undercounts everyone but that caller. Same cure — a SECURITY DEFINER
-- aggregate RPC, gated on session participation (not row ownership) FIRST,
-- same idiom as group_burpee_ledger's membership gate / the burpee-ledger
-- "RAISE EXCEPTION ... USING ERRCODE = 'P0001'" pattern.
--
-- Scope note: `PersonalRecordRepository.bySession` itself is NOT removed —
-- its two other callers (CompletedSessionView.swift:380,
-- SessionRecapView.swift:197) are the solo/from-history recap path, driven
-- by the viewing user's own `.task` fetch for a session THEY were part of;
-- each user who opens their own history only ever needs (and today only
-- ever gets) rows self-scoped to their own participation in that render
-- pass. That is a materially different call shape from
-- buildGroupRecapPayload's "one fetch, rendered to every teammate's PR
-- count at once" — the only shape this migration's fix targets. Swift-side
-- (see commit 2) leaves those two call sites on `bySession` untouched and
-- cites this migration for why that's safe to leave as-is.
CREATE OR REPLACE FUNCTION public.session_pr_counts(p_session_id uuid)
RETURNS TABLE (
  user_id   uuid,
  pr_count  int
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  -- Gate FIRST, same idiom as group_burpee_ledger: reject before any row is
  -- touched. is_session_participant (defined
  -- 20260709000006_create_sessions.sql:32) is the correct check here —
  -- unlike group_burpee_ledger's CURRENT group-membership gate (which
  -- exists specifically to reach PRE-membership sessions), a session's PR
  -- count has no analogous "joined the session after the fact" case: only
  -- someone who was actually in the session (or the session organizer,
  -- also covered by is_session_participant via the session_participants
  -- row inserted at schedule time) should ever see who PR'd in it.
  IF NOT public.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  -- Small, single-session aggregate (a session has, at most, a handful of
  -- lifters) — plain GROUP BY, no LATERAL fan-out risk.
  RETURN QUERY
  SELECT pr.user_id, COUNT(*)::int AS pr_count
    FROM public.personal_records pr
   WHERE pr.session_id = p_session_id
   GROUP BY pr.user_id;
END;
$$;

-- Self-gated by the is_session_participant check above (same
-- revoke-then-grant idiom as group_burpee_ledger / activity_feed /
-- register_push_device). Newly created functions get PUBLIC EXECUTE by
-- default, which anon inherits, so REVOKE FROM PUBLIC, anon and GRANT back
-- explicitly TO authenticated. Do NOT include authenticated in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.session_pr_counts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_pr_counts(uuid) TO authenticated;

-- ============================================================
-- Finding 2 (Important): self-kudos unguarded server-side.
-- ============================================================
-- 20260720000001_session_kudos.sql's header (lines 22-26) documented a
-- deliberate decision to skip a sender<>recipient CHECK: "the UI's send row
-- is crew-wide ... so a self-targeted row is never produced by the client
-- ... not worth enforcing server-side for v1 (no spec requirement, no harm
-- if it ever happened)". That reasoning trusted client behavior as the only
-- gate — the review flags it as an unguarded server-side invariant instead:
-- any future or third-party authenticated caller of the INSERT policy
-- (which only checks sender = auth.uid() + both parties participate in the
-- session, and does not check sender <> recipient) can currently write a
-- self-kudos row directly, corrupting the recap's per-recipient kudos
-- totals for no legitimate product reason. That old file is an already
-- -applied migration and stays untouched (fix-forward); this table is
-- brand-new and tiny (added the same day, 20260720000001), so a follow-up
-- ADD CONSTRAINT here validates trivially against existing rows (confirmed
-- 0 self-kudos rows exist before this migration) and supersedes that
-- earlier no-CHECK rationale going forward.
ALTER TABLE public.session_kudos
  ADD CONSTRAINT session_kudos_no_self CHECK (sender_id <> recipient_id);
