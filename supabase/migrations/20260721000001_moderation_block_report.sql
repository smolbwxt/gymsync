-- ============================================================
-- Phase M / Task 1: block/report backend (App Store compliance gate)
-- ============================================================
-- Master spec (docs/superpowers/specs/2026-06-28-gymsync-design.md):
--   §Moderation (lines 491-511) — user_reports / blocked_users schema,
--   verbatim columns below.
--   §RLS list (lines 662-663) — user_reports: "writable by anyone [authenticated],
--   readable by reporter + app_admin (granted manually via SQL for v1, no
--   queue UI — see §8)"; blocked_users: "readable + writable only by the
--   blocker. Blocks are enforced at the query level: chat messages from
--   blocked users are filtered out; friend requests from blocked users are
--   rejected; venue hub views exclude blocked users' presence."
-- Phase spec (docs/superpowers/specs/2026-07-17-moderation-compliance-design.md,
-- §1) narrows the v1 RLS posture further: "admin reads via service/SQL — no
-- admin SELECT policy" and scopes block enforcement in this task to the two
-- named surfaces that exist today (chat content, friend requests); venue hub
-- is a Local Hub (Phase V) feature that doesn't exist yet, so there is no
-- venue_users policy to touch. Reactions/kudos are evaluated below and left
-- untouched (not named surfaces).

-- ── 1. user_reports ──────────────────────────────────────────────────────
CREATE TABLE public.user_reports (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id            uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reported_user_id       uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  reported_content_type  text,
  reported_content_id    uuid,
  reason                 text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  status                 text NOT NULL DEFAULT 'open'
                              CHECK (status IN ('open', 'dismissed', 'actioned'))
);
CREATE INDEX user_reports_reporter_id_idx ON public.user_reports(reporter_id);
CREATE INDEX user_reports_reported_user_id_idx ON public.user_reports(reported_user_id);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- Spec: "writable by anyone" means any authenticated caller may file a
-- report, as themselves only (reporter_id = auth.uid()) — same requester-
-- spoof guard idiom as friendships' "requester creates pending request"
-- (20260710000001_create_friendships.sql).
CREATE POLICY "authenticated user files report"
  ON public.user_reports FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- Spec: readable by reporter only in v1. No app_admin SELECT policy —
-- the phase spec is explicit that admin reads happen out-of-band via
-- service role / direct SQL (manually-granted role, no queue UI, §8 in
-- the master spec). Adding a role-based SELECT policy here would be
-- speculative: app_admin as an RLS-visible role/claim does not exist
-- anywhere else in the schema today.
CREATE POLICY "reporter reads own reports"
  ON public.user_reports FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

-- No UPDATE/DELETE policy: status transitions ('open' -> 'dismissed' /
-- 'actioned') are an admin action, performed via service role / SQL per
-- the v1 posture above — not a client-writable surface.

-- ── 2. blocked_users ─────────────────────────────────────────────────────
CREATE TABLE public.blocked_users (
  blocker_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  -- Mirrors friendships' self-reference guard (CHECK (user_id <> friend_id),
  -- 20260710000001_create_friendships.sql) — a user cannot block themselves.
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX blocked_users_blocked_id_idx ON public.blocked_users(blocked_id);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- Spec: "readable + writable only by the blocker" — all-ops single policy,
-- same idiom as push_devices' "owner manages own devices"
-- (20260716000001_push_schema.sql).
CREATE POLICY "blocker manages own blocks"
  ON public.blocked_users FOR ALL TO authenticated
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

-- ── 3. is_blocked() — SECURITY DEFINER helper ───────────────────────────
-- Idiom: is_group_member()/is_session_participant()
-- (20260710000002_create_groups.sql, 20260709000006_create_sessions.sql) —
-- SQL, SECURITY DEFINER, STABLE, search_path pinned, EXISTS against the
-- owning table.
--
-- DEFINER is required here, not just idiomatic: blocked_users RLS restricts
-- SELECT to blocker_id = auth.uid() (rows the caller owns as blocker). The
-- friend-request check below needs to answer "has the ADDRESSEE blocked the
-- CALLER" — a fact about a blocked_users row the caller does NOT own as
-- blocker (blocker_id = addressee, not auth.uid()). A SECURITY INVOKER
-- function would inherit the caller's RLS and always see zero rows for that
-- direction, silently defeating the check. SECURITY DEFINER bypasses RLS on
-- the underlying table, same as the two helpers above.
--
-- DIRECTION: is_blocked(p_blocker, p_blocked) is TRUE iff p_blocker has
-- blocked p_blocked. It is NOT symmetric — is_blocked(A, B) and
-- is_blocked(B, A) are independent facts.
CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker uuid, p_blocked uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE blocker_id = p_blocker AND blocked_id = p_blocked
  );
$$;

-- REVOKE/GRANT idiom (e.g. activity_feed(), 20260719000002_activity_feed_rpc.sql):
-- PUBLIC EXECUTE is the default (which anon inherits), so REVOKE FROM
-- PUBLIC, anon and GRANT back explicitly TO authenticated. is_blocked() is
-- called from RLS policies evaluated as `authenticated`, so that role must
-- retain EXECUTE. Do NOT include authenticated in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.is_blocked(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_blocked(uuid, uuid) TO authenticated;

-- ── 4. chat_messages SELECT — fix-forward replace ───────────────────────
-- Current live policy (20260719000010_session_chat_subthreads.sql, #3 —
-- "group members read messages"; NOT touched by 20260719000011, which only
-- replaced chat_message_reactions' policies and chat_messages' INSERT
-- policy). Transplanted verbatim below, wrapped in one outer AND clause
-- excluding rows authored by a user the caller has blocked.
--
-- NULL author_id semantics (system messages, chat_messages.author_id ON
-- DELETE SET NULL, 20260710000003_create_chat.sql: "NULL = system"):
-- is_blocked(auth.uid(), NULL) evaluates
--   EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = auth.uid()
--           AND blocked_id = NULL)
-- `blocked_id = NULL` is NULL (unknown) for every row per SQL three-valued
-- logic, not TRUE, so no row ever satisfies the WHERE clause and EXISTS is
-- FALSE regardless of the caller's block list. is_blocked() therefore
-- returns FALSE for a NULL author, and NOT FALSE = TRUE — system messages
-- remain visible to everyone, unaffected by any block. Verified against
-- Postgres's NULL comparison semantics, not assumed.
DROP POLICY "group members read messages" ON public.chat_messages;
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (
      (chat_messages.session_id IS NULL
       AND public.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid()))
    )
    AND NOT public.is_blocked(auth.uid(), chat_messages.author_id)
  );

-- Realtime (postgres_changes) finding — no publication migration needed:
-- chat_messages has been in the supabase_realtime publication since
-- 20260710000003_create_chat.sql; publication membership is table-level,
-- not row/policy-scoped. Postgres Changes (unlike Broadcast/Presence
-- channels) has always evaluated the subscriber's RLS SELECT policy per
-- change event — this is core Realtime behavior, not the newer
-- Broadcast-channel "Realtime Authorization" feature — and this exact
-- mechanism was the basis for 20260719000010's session sub-thread lockdown
-- ("RLS (WALRUS) is what scopes which postgres_changes events a given
-- subscriber actually receives", task-2-report.md). The SELECT policy
-- above is therefore sufficient for both fetch/refetch AND the live
-- postgres_changes stream: once a caller blocks an author, that author's
-- subsequent chat_messages INSERTs will not pass the caller's RLS
-- evaluation and will not be delivered to their subscription. No
-- client-side filter is required for v1.

-- ── 5. friendships INSERT — fix-forward replace ─────────────────────────
-- Real write path confirmed by inspection, not assumed: FriendRepository.
-- sendRequest() (GymSyncApp/GymSync/Models/Friendship.swift:23-40) does a
-- direct client `.insert()` on `friendships` — there is no RPC in this
-- path. The only gate is the RLS INSERT policy "requester creates pending
-- request" (20260710000001_create_friendships.sql), transplanted verbatim
-- below with two added clauses. Rejects when EITHER party has blocked the
-- other: is_blocked(friend_id, user_id) covers "addressee blocked the
-- requester" (the case a naive single-direction check would miss, since
-- the caller is always the requester and the friend_id side of a block
-- is invisible to a non-DEFINER check); is_blocked(user_id, friend_id)
-- covers "requester blocked the addressee" (mostly a self-consistency
-- guard — a user who has blocked someone would not normally friend-request
-- them, but nothing else prevented it before this).
DROP POLICY "requester creates pending request" ON public.friendships;
CREATE POLICY "requester creates pending request"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND NOT public.is_blocked(friend_id, user_id)
    AND NOT public.is_blocked(user_id, friend_id)
  );

-- ── 6. Deliberately untouched — documented, not silently dropped ───────
--
-- friendships UPDATE ("recipient accepts") is not touched: this task's
-- brief scopes block enforcement to the INSERT (request creation) path.
-- Edge case flagged, not implemented: if a block is created strictly AFTER
-- a pending request already exists (e.g. A requests B, then B blocks A),
-- the now-blocked pending row still exists and "recipient accepts" would
-- still permit B to accept it — the INSERT-time guard above only prevents
-- a block from stopping a *new* request, not from stopping acceptance of
-- one that predates the block. Follow-up, not in scope here.
--
-- chat_message_reactions and session_kudos are NOT extended with author-
-- block filtering. The spec's RLS list (line 663) names exactly two
-- enforcement surfaces — "chat messages from blocked users are filtered
-- out; friend requests from blocked users are rejected" — plus a third
-- (venue hub presence) for a Local Hub feature that does not exist in the
-- schema yet (no venues/venue_users tables). Reactions and kudos are not
-- named. Extending the block gate there was evaluated and deliberately
-- left alone to keep v1 honest to the spec's named surfaces, per the phase
-- spec's own hedge ("keep v1 honest: chat content + friend requests are the
-- spec's named surfaces").
--
-- venue hub views: no venues/venue_users tables exist yet (Local Hub is
-- Phase V, per the phase spec's non-goals list) — nothing to enforce
-- against today.
