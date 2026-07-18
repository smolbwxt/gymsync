-- ============================================================
-- Phase M whole-branch review, Finding 1 (Important): block doesn't sever
-- friendship or solo-workout access
-- ============================================================
-- Review finding, verbatim: blocking a friend today is (a) client-side row
-- removal only — FriendRepository.friends()
-- (GymSyncApp/GymSync/Models/Friendship.swift:109-126) has no block filter,
-- so the blocked friend REAPPEARS on the next refresh; (b) the accepted
-- `friendships` row persists, so `is_friend()` stays true and the blocked
-- friend STILL READS the blocker's solo `set_logs` when
-- `show_solo_workouts=true` (the friend-solo branch added by
-- 20260722000002 has no block check). Two independent fixes, both in this
-- migration:
--   1. set_logs SELECT policy — close the read hole directly (covers BOTH
--      newly-blocked pairs and any pair already blocked before this
--      migration ships, since a policy check is evaluated live on every
--      read, unlike a one-time data fix).
--   2. AFTER INSERT trigger on blocked_users — sever the friendships row so
--      is_friend() itself goes false going forward ("block = unfriend",
--      industry-standard; also closes the friend-request half of this
--      review's Finding 2 — a pending request is a friendships row too).
--   3. One-time backfill — pairs already blocked as of this migration (via
--      the pre-fix INSERT-only `ModerationRepository.block()`,
--      GymSyncApp/GymSync/Models/Moderation.swift:83-95) never had their
--      friendships row severed, since the trigger in (2) only fires on
--      INSERTs from this point forward. Without this, an already-blocked
--      pair would keep its stale accepted friendship until one of them
--      unblocks/re-blocks. (1) alone already hides the solo-workout leak
--      for these pairs, but the friendship row itself — and every OTHER
--      surface `is_friend()`/`friends()` feeds (the Friends list, any
--      future is_friend()-gated feature) — would stay wrong without this.

-- ── 1. set_logs SELECT policy — fix-forward, transplanted verbatim ────────
-- Current live policy (20260722000002_solo_workout_privacy.sql:129-142,
-- unchanged since — grepped every migration after it for `set_logs` +
-- `FOR SELECT`, none touched it):
--   CREATE POLICY "set_logs read: owner, participant, or opted-in friend"
--     ON public.set_logs FOR SELECT TO authenticated
--     USING (
--       user_id = auth.uid()
--       OR public.is_session_participant(set_logs.session_id, auth.uid())
--       OR (
--         public.is_solo_session(set_logs.session_id)
--         AND public.is_friend(set_logs.user_id, auth.uid())
--         AND EXISTS (
--           SELECT 1 FROM public.profiles p
--           WHERE p.id = set_logs.user_id AND p.show_solo_workouts = true
--         )
--       )
--     );
--
-- Adds exactly two clauses to the friend-solo OR-branch, both using
-- `private.is_blocked(p_blocker, p_blocked)` — TRUE iff p_blocker has
-- blocked p_blocked (20260722000001_is_blocked_private_schema.sql:76-83) —
-- fully qualified, same as the two existing callers (chat_messages SELECT,
-- friendships INSERT in that same migration). No GRANT needed here: EXECUTE
-- is PUBLIC-default and was never revoked for `private.is_blocked` itself
-- (only schema USAGE was revoked from anon/authenticated — see that
-- migration's ── 2 comment for why that asymmetry is safe), and this
-- policy's qual is resolved to the function's OID once, at CREATE POLICY
-- time, under the migration role's full privileges — same mechanism the
-- existing two callers already rely on.
--
-- Direction A — `private.is_blocked(set_logs.user_id, auth.uid())`: has the
-- OWNER (set_logs.user_id, the blocker in this framing) blocked the VIEWER
-- (auth.uid())? If so, the viewer is the blocked party and must not read
-- the blocker's solo workouts — this is "the blocked shouldn't see the
-- blocker's" from the finding.
--
-- Direction B — `private.is_blocked(auth.uid(), set_logs.user_id)`: has the
-- VIEWER blocked the OWNER? If so, the viewer is the one who did the
-- blocking and must not read the now-blocked owner's solo workouts either
-- — "the blocker shouldn't see the blocked's" from the finding.
--
-- Judgment call the finding asked for: is direction B already implied by
-- `is_friend()` alone, now that (2) below severs the friendships row the
-- moment EITHER direction blocks? NO, for two reasons: (a) the backfill in
-- (3) only runs once, at migration time — it cannot retroactively cover a
-- block/friendship pair created AFTER this migration ships if some future
-- change ever let a block coexist with a friendship again (defense in
-- depth against that class of regression, not a hypothetical this
-- migration itself reintroduces); (b) more importantly, RIGHT NOW, before
-- this migration's trigger has ever fired for a given pair, `is_friend()`
-- can still be true for a blocked pair (that is the entire bug this
-- migration fixes) — so a policy that only checked direction A would still
-- leak in direction B for every row read between "block inserted" and
-- "backfill/trigger has run", and would leak permanently for any DB where
-- the trigger is somehow bypassed (e.g. a service-role bulk insert into
-- blocked_users that a future script performs without going through normal
-- INSERT semantics — triggers still fire for service-role DML, but this is
-- the kind of edge a defense-in-depth check is for). Both directions
-- included, neither treated as redundant.
DROP POLICY "set_logs read: owner, participant, or opted-in friend" ON public.set_logs;
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
      AND NOT private.is_blocked(set_logs.user_id, auth.uid())
      AND NOT private.is_blocked(auth.uid(), set_logs.user_id)
    )
  );

-- ── 2. Server-side friendship sever on block ───────────────────────────────
-- "The cleanest honest mechanism" per the finding: a trigger that deletes
-- the friendships row(s) between the blocker and the blocked the instant a
-- block is recorded. Mirrors "block = unfriend", the industry-standard
-- behavior (Instagram/Twitter/etc. all sever the follow/friend graph on
-- block) — and it is a genuine server-side guarantee, not a client
-- convention the app can forget to apply consistently.
--
-- Alternative considered and REJECTED: client-side two-call (block, then a
-- second removeFriendship() call from the same Swift action). Rejected
-- because it is racy (a crash/network drop between the two calls leaves
-- the block recorded but the friendship intact — exactly today's bug,
-- just with smaller odds) and skippable via direct API access (anyone
-- calling `blocked_users` INSERT directly — e.g. from a future non-iOS
-- client, or a REST client — would reproduce the original hole, since
-- there is no server-side guarantee tying the two operations together).
-- A trigger makes the invariant hold no matter which client (or lack of
-- one) performs the INSERT.
--
-- friendships PK is (user_id, friend_id) with a canonical-pair UNIQUE index
-- on (LEAST(user_id,friend_id), GREATEST(user_id,friend_id))
-- (20260710000001_create_friendships.sql:7,12-13) — there is AT MOST ONE
-- friendships row for any two users regardless of who requested whom or
-- what status it's in (pending/accepted/blocked). Deleting both possible
-- orderings (blocker as user_id/blocked as friend_id, and vice versa) is
-- therefore not two separate real cases to reconcile — it is "delete the
-- one row if it exists, whichever direction it happens to be stored in".
-- Unconditional on status: this also deletes a PENDING row, not just an
-- ACCEPTED one — which is exactly what this review's Finding 2 needs (a
-- pending friend request from someone you just blocked should vanish, not
-- just stop being acceptable) and is confirmed in
-- supabase/tests/moderation_block_report_test.sql (extended by this task).
--
-- SECURITY DEFINER + pinned search_path: same idiom as every other
-- trigger function in this schema that writes to a table other than the
-- one it's attached to (public.increment_lifetime_volume(),
-- 20260709000008_lifetime_volume_trigger.sql:1-2;
-- public.invite_new_member_to_future_sessions(),
-- 20260713000003_late_joiner_invites.sql:1-2;
-- public.streak_on_no_show()/streak_on_session_state_change(),
-- 20260719000006_streaks.sql). Strictly speaking the caller (always the
-- blocker themselves — blocked_users' own INSERT/ALL policy,
-- "blocker manages own blocks", requires blocker_id = auth.uid()) already
-- satisfies friendships' "either party deletes" DELETE policy
-- (USING (user_id = auth.uid() OR friend_id = auth.uid())) for every row
-- this trigger ever targets, since the blocker is always one of the two
-- parties in any friendships row between the pair — so a SECURITY INVOKER
-- version would happen to work today. DEFINER is used anyway, matching
-- this codebase's established posture for any trigger performing a
-- cross-table write: the guarantee this trigger exists to provide
-- ("blocking always severs the friendship") should not silently depend on
-- friendships' DELETE policy staying exactly this permissive — a future
-- narrowing of that policy (e.g. an is_group_member-style added gate, the
-- shape recurring-sessions' own final-review follow-up already applied to
-- a different table) must not be able to quietly break block-severs-
-- friendship as a side effect.
--
-- No REVOKE/GRANT EXECUTE needed: trigger functions can only be invoked in
-- a trigger context (Postgres raises "trigger functions can only be
-- called as triggers" on any direct SELECT/CALL), so there is no
-- PostgREST-RPC-oracle shape here the way there was for is_blocked() —
-- nothing to lock down beyond what CREATE FUNCTION's default already
-- provides. Consistent with every sibling trigger function above, none of
-- which carry a REVOKE/GRANT block either.
CREATE OR REPLACE FUNCTION public.sever_friendship_on_block()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.friendships
  WHERE (user_id = NEW.blocker_id AND friend_id = NEW.blocked_id)
     OR (user_id = NEW.blocked_id AND friend_id = NEW.blocker_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS blocked_users_sever_friendship ON public.blocked_users;
CREATE TRIGGER blocked_users_sever_friendship
  AFTER INSERT ON public.blocked_users
  FOR EACH ROW EXECUTE FUNCTION public.sever_friendship_on_block();

-- Re-block idempotency, by construction: if a pair is unblocked then
-- blocked again, this trigger fires again on the second INSERT and simply
-- deletes zero rows (the friendship is already gone, and nothing
-- re-creates a friendships row on unblock) — no error, no special-casing
-- needed. Proven directly in pgTAP below rather than left as an inference.

-- ── 3. One-time backfill — pairs already blocked before this migration ───
-- Runs AFTER the trigger is created (though DELETE order relative to
-- trigger creation doesn't matter here — this statement doesn't touch
-- blocked_users, so it can't fire the new trigger) — placed last simply to
-- read top-to-bottom as "policy, mechanism, then catch-up the existing
-- data to match". Self-join blocked_users -> friendships on both possible
-- orderings, same shape as the trigger body above, one-shot rather than
-- per-row.
DELETE FROM public.friendships f
USING public.blocked_users b
WHERE (f.user_id = b.blocker_id AND f.friend_id = b.blocked_id)
   OR (f.user_id = b.blocked_id AND f.friend_id = b.blocker_id);
