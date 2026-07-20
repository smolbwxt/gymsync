-- ============================================================
-- Phase C Task 1 fix-forward, continued: 20260728000003 (APPLIED LIVE
-- minutes before this migration, in the same fix wave, therefore already
-- immutable under the same append-only doctrine as every other applied
-- migration) shipped a WITH CHECK fix for IMPORTANT-1 that was ITSELF
-- silently self-defeating. Caught by this task's own verification step
-- (pgTAP + a manual rollback-wrapped live probe run BEFORE claiming the
-- fix done) -- not by a reviewer, and not silently patched over: recorded
-- here in full per this repo's own "acknowledged, not silently patched
-- over" convention (task-7-report.md's own Fix wave 1 language). No table/
-- column changes; one new SECURITY DEFINER helper, one policy replaced.
-- ============================================================

-- ============================================================
-- ── Why 20260728000003's fix didn't actually work ───────────────────────
-- ============================================================
-- 20260728000003's policy read:
--   WITH CHECK (
--     user_id = auth.uid()
--     AND NOT EXISTS (
--       SELECT 1 FROM public.campaigns c
--       WHERE c.id = campaign_id AND c.is_draft
--     )
--   );
-- This LOOKS correct and matches the shape campaign_community_progress()'s
-- own gate uses -- but campaign_community_progress() is SECURITY DEFINER,
-- so ITS internal SELECT against public.campaigns runs with the function
-- owner's privileges, bypassing campaigns' own RLS. A policy's WITH CHECK
-- expression carries NO such elevation -- it runs as the INVOKING role
-- (the authenticated attacker themselves), so the embedded `SELECT 1 FROM
-- public.campaigns c WHERE c.id = campaign_id AND c.is_draft` subquery is
-- itself filtered by campaigns' own SELECT policy, "campaigns are globally
-- readable unless draft" (`USING (NOT is_draft OR
-- private.is_campaign_participant(campaigns.id, auth.uid()))`,
-- 20260728000001_campaigns_schema.sql:243-248).
--
-- For the EXACT attacker scenario the fix exists to close -- a stranger,
-- not yet a participant, targeting a draft campaign -- that USING clause
-- evaluates to `NOT true OR false` = false, so the campaigns SELECT policy
-- HIDES the row from the subquery entirely. `SELECT 1 FROM campaigns c
-- WHERE c.id = campaign_id AND c.is_draft` therefore returns ZERO rows
-- (not because is_draft is false, but because the row is invisible to this
-- caller at all), so `EXISTS(...)` is false, `NOT EXISTS(...)` is TRUE,
-- and the WITH CHECK silently PASSES -- reproducing the identical
-- live-exploitable bypass IMPORTANT-1 was opened to close, just moved one
-- level down into the fix's own gate. Confirmed empirically (rollback-
-- wrapped probe, 8/8 and then a further 5/5 reproductions against the live
-- DB after 20260728000003 was pushed) before writing this correction --
-- not inferred from reading the SQL alone.
--
-- This is exactly the failure mode `private.is_campaign_participant` and
-- `campaign_community_progress()` were ALREADY built to avoid --
-- 20260728000001's own item 8 header says so explicitly: "necessary
-- because this function is SECURITY DEFINER and therefore bypasses
-- campaigns' RLS entirely; without re-deriving the same predicate inside
-- the function body, a caller who knows (or guesses) a draft campaign's id
-- could read its aggregate totals even though the campaign row itself is
-- invisible to them." The SAME reasoning applies to ANY gate that needs to
-- answer "is this row I can't otherwise see currently in state X" -- a raw
-- inline subquery inherits the very RLS restriction the gate exists to
-- see past; only a SECURITY DEFINER function genuinely bypasses it. My own
-- 003 fix missed this the first time by reaching for a NOT EXISTS subquery
-- (the natural WITH-CHECK-shaped idiom, since WITH CHECK has no FROM list
-- to attach a JOIN or a DEFINER function's pre-elevated read to) instead of
-- routing through a DEFINER helper the way the RPC already had to.
-- ============================================================

-- ── New helper: private.is_campaign_draft() ─────────────────────────────
-- Same idiom/shape as private.is_campaign_participant
-- (20260728000001_campaigns_schema.sql item 4): SECURITY DEFINER STABLE,
-- lives directly in `private` (never `public` first), answers exactly one
-- narrow boolean question and nothing wider -- it does not leak any other
-- campaigns column, so it is not a new information-disclosure surface,
-- only a gate. COALESCE(..., false) makes a nonexistent p_campaign_id
-- resolve to "not a draft" rather than NULL -- irrelevant in practice
-- (campaign_participants.campaign_id's own FK to campaigns(id) rejects a
-- dangling reference regardless of what this predicate says), but keeps
-- the function's own return value deterministic and total rather than
-- leaning on the FK to paper over a NULL falling out of WITH CHECK's
-- three-valued logic.
CREATE FUNCTION private.is_campaign_draft(p_campaign_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT is_draft FROM public.campaigns WHERE id = p_campaign_id),
    false
  );
$$;
-- No REVOKE/GRANT issued -- same posture as private.is_campaign_participant
-- itself (20260728000001's own item 4: no REVOKE/GRANT there either),
-- which the task-1 report's own "Concerns" section already documents as
-- carrying default PUBLIC EXECUTE while remaining unreachable BY NAME from
-- a client query because the `private` schema's own USAGE grant is
-- revoked from anon/authenticated (20260722000001_is_blocked_private_
-- schema.sql) -- a client cannot look up `private.is_campaign_draft` to
-- call it directly, but the pre-resolved function-OID reference baked into
-- this policy's own WITH CHECK expression (created below, by the migration
-- role) does not need that lookup at each row's evaluation time, only
-- EXECUTE privilege on the function itself, which PUBLIC already carries.
-- Identical asymmetry, deliberately not re-litigated here.

-- ── Policy: replace 20260728000003's fix with the working version ──────
DROP POLICY "user joins a campaign as themselves" ON public.campaign_participants;

CREATE POLICY "user joins a campaign as themselves"
  ON public.campaign_participants FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT private.is_campaign_draft(campaign_id)
  );
-- The "OR participant" half of the SELECT policy's/RPC's own predicate is
-- still deliberately not carried over here -- 20260728000003's own header
-- already gives the reason (campaign_participants' PRIMARY KEY makes a
-- pre-existing participant's re-INSERT of the same (campaign_id, user_id)
-- pair impossible; that reasoning is untouched by this correction and is
-- not repeated in full here).
-- ============================================================
