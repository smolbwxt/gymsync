-- ============================================================
-- Phase C Task 1 fix-forward: 1 review finding (IMPORTANT) against
-- campaign_participants' INSERT policy, live in
-- 20260728000001_campaigns_schema.sql:267-269 (APPLIED LIVE, therefore
-- immutable) — plus a citation-misattribution correction (MINOR) in
-- 20260728000002_campaign_progress_trigger.sql's own header (also
-- APPLIED LIVE, also immutable). This migration DROP+CREATEs the one
-- affected policy in place; no table/column changes. Review report:
-- review-2346214..b24b6f9.diff / this task's controller-relayed findings.
-- ============================================================

-- ============================================================
-- ── IMPORTANT-1 (live-proven exploitable) — draft-visibility bypass via
--    campaign_participants' INSERT policy ───────────────────────────────
-- ============================================================
-- Confirmed exactly as the reviewer traced it: the original policy,
--   CREATE POLICY "user joins a campaign as themselves"
--     ON public.campaign_participants FOR INSERT TO authenticated
--     WITH CHECK (user_id = auth.uid());
-- only ever checked "is this row mine" — it never re-derived the same
-- draft-visibility predicate the campaigns SELECT policy and the
-- campaign_community_progress() aggregate RPC both already re-derive for
-- exactly this reason (20260728000001_campaigns_schema.sql's own
-- Adjudication 3 / item 8 header: "a caller who knows (or guesses) a
-- draft campaign's id could read its aggregate totals even though the
-- campaign row itself is invisible to them"). campaign_participants'
-- INSERT policy was the one write surface that adjudication's own gate-
-- first discipline never reached.
--
-- Live-proof summary (rollback-wrapped probe against the running
-- production DB, reviewer's shape, reproduced again below after this
-- migration is pushed): an authenticated stranger who has never seen a
-- draft campaign anywhere in the UI (its SELECT policy makes it globally
-- invisible to non-participants) can still INSERT a campaign_participants
-- row for it IF they somehow learn or guess its UUID — the INSERT policy
-- never checked is_draft at all. Once that row exists,
-- private.is_campaign_participant(campaign_id, auth.uid()) returns true
-- for that stranger, which flips BOTH the campaigns SELECT policy
-- ("NOT is_draft OR participant") and campaign_community_progress()'s own
-- gate open for them — the exact "test-campaign isolation" boundary
-- Adjudication 3 exists to hold (the "Murph de-leak" precedent named in
-- that adjudication) is defeated by a single self-join. This is a real,
-- exploitable gap against a live table, not a theoretical one — hence
-- IMPORTANT, not MINOR.
--
-- Fix: re-derive the identical "NOT is_draft" half of the same predicate
-- the SELECT policy and the aggregate RPC already use, inline in the
-- INSERT policy's own WITH CHECK, via NOT EXISTS rather than a join (a
-- WITH CHECK clause has no FROM list to join against — NOT EXISTS against
-- the row's own campaign_id column, the same shape
-- campaign_community_progress()'s gate already uses, is the correct
-- idiom here). The "OR participant" half of the SELECT/RPC predicate is
-- deliberately NOT carried over: at INSERT time there is by definition no
-- pre-existing campaign_participants row for this (campaign_id, user_id)
-- pair to make that OR-branch true in the first place (the table's own
-- PRIMARY KEY (campaign_id, user_id) rejects any duplicate insert outright
-- with a 23505 unique-violation, independent of RLS) — so the OR-branch
-- can never fire here and including it would only add dead code.
--
-- Considered and rejected: does a participant of a draft campaign (seeded
-- via service role/direct SQL, e.g. Task 3's fixture below) ever need to
-- re-INSERT their own row through this ordinary client path — e.g. after
-- a leave/rejoin? No: the campaign_participants PRIMARY KEY means a
-- SEEDED row already existing for that (campaign_id, user_id) pair is
-- never re-inserted (it either already exists — nothing to do — or the
-- user genuinely left first, via the unchanged owner-scoped DELETE
-- policy, in which case rejoining a STILL-draft campaign through the
-- ordinary client path is exactly the isolation-defeating behavior this
-- fix exists to close, so correctly rejecting it is the intended outcome,
-- not a regression). Consequence, documented rather than silently
-- discovered later: Task 3's seeded test-campaign participant row(s) MUST
-- be inserted via service-role/direct SQL (the same path Adjudication 3's
-- own header already named as one of the two legitimate routes — "via
-- direct SQL fixture setup or the ordinary join path" — this fix removes
-- the second of those two routes for DRAFT campaigns specifically; direct
-- SQL fixture setup remains the one path for seeding a draft campaign's
-- participants, exactly as Task 3's own report already documents it doing).
DROP POLICY "user joins a campaign as themselves" ON public.campaign_participants;

CREATE POLICY "user joins a campaign as themselves"
  ON public.campaign_participants FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = campaign_id AND c.is_draft
    )
  );

-- ============================================================
-- ── MINOR-1 — citation correction: streak_milestone was never a §6.3
--    push-table row ───────────────────────────────────────────────────
-- ============================================================
-- 20260728000002_campaign_progress_trigger.sql's own header (its "Push
-- notification: NONE named, therefore none built" section) reads: "Master
-- spec §6.3's push table (:1165-1177) is the exhaustive, named list of
-- push events wired through push-dispatcher -- no campaign-related row
-- exists in it (contrast `leaderboard_passed`, `streak_milestone`, both
-- of which DO have rows, per 20260723000002's own header:24-27, 'reserved
-- in 3d')." That parenthetical is wrong about `streak_milestone`
-- specifically: read directly, §6.3's push table
-- (docs/superpowers/specs/2026-06-28-gymsync-design.md:1165-1177) lists
-- 11 events -- friend_request, session_invite, session_reminder_15min,
-- session_lobby_open, your_turn, partner_pr, lateness_chirp,
-- session_idle_30min, session_idle_60min, leaderboard_passed,
-- chat_mention -- and `streak_milestone` is NOT one of them.
-- `leaderboard_passed` genuinely IS a row there (line 1176) -- that half
-- of the parenthetical is correct, and 20260723000002's own header:24-27
-- correctly cites it as "reserved in 3d" ahead of that migration actually
-- wiring it up. `streak_milestone` is a DIFFERENT case entirely, and this
-- repo's own prior migration already says so in so many words:
-- 20260719000008_streak_pushes.sql:52-53 -- "notification_prefs.category
-- has a CHECK constraint listing exactly the 10 designer categories from
-- the 3d push event matrix (design doc §6.3) -- streak_milestone/
-- streak_at_risk are new event kinds Flow 7 introduces that the original
-- matrix never listed." `streak_milestone` is named exactly once in the
-- design doc, in Flow 7's own narrative prose (spec :856-860, specifically
-- :859, "On streak milestone (7, 14, 30, 90, 365): celebratory push..."),
-- never in §6.3's table. The campaign trigger migration's underlying
-- POINT still stands correctly (no campaign-related row exists in §6.3's
-- table, and Flow 8's own text -- unlike Flow 7's -- names no push at
-- all, so building none was still the right call) -- only the supporting
-- citation was wrong, conflating "named somewhere in the spec" with
-- "has a row in the §6.3 table." Corrected here, in this new migration's
-- header, per the append-only doctrine -- 20260728000002 itself is
-- APPLIED LIVE and stays byte-for-byte as shipped.
-- ============================================================
