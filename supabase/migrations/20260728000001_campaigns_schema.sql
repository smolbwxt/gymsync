-- ============================================================
-- Phase C / Task 1 (Part 1 of 2): campaigns / campaign_participants /
-- campaign_progress — tables, RLS, community-aggregate RPC.
-- ============================================================
-- Design doc citations:
--   Schema (verbatim column set) — docs/superpowers/specs/2026-06-28-
--     gymsync-design.md:581-614.
--   RLS narrative                — same file:669-671.
--   Flow 8 (all rules)           — same file:862-884.
--   Realtime wire shape          — same file:970, 1049-1051.
--   Phase spec §1                — docs/superpowers/specs/2026-07-19-
--     campaigns-design.md:7-8.
--
-- Quoted verbatim (spec :584-614):
--   campaigns (
--     id                  uuid PRIMARY KEY,
--     name                text NOT NULL,                   -- "Spring Break Prep 2026"
--     description         text,
--     starts_at           timestamptz NOT NULL,
--     ends_at             timestamptz NOT NULL,
--     banner_url          text,
--     global_target       jsonb,                           -- {"metric":"total_volume","target":100000000}
--     individual_target   jsonb,                           -- {"sessions":12} or {"workouts_completed":4}
--     curated_routine_ids uuid[],                          -- workouts featured in this campaign
--     is_featured         boolean DEFAULT false,
--     created_at          timestamptz DEFAULT now()
--   )
--   campaign_participants (
--     campaign_id         uuid REFERENCES campaigns(id) ON DELETE CASCADE,
--     user_id             uuid REFERENCES profiles(id),
--     joined_at           timestamptz DEFAULT now(),
--     PRIMARY KEY (campaign_id, user_id)
--   )
--   campaign_progress (
--     campaign_id         uuid REFERENCES campaigns(id) ON DELETE CASCADE,
--     user_id             uuid REFERENCES profiles(id),
--     sessions_completed  integer DEFAULT 0,
--     workouts_completed  integer DEFAULT 0,               -- from curated_routine_ids
--     volume_lifted       numeric(12,2) DEFAULT 0,
--     updated_at          timestamptz DEFAULT now(),
--     PRIMARY KEY (campaign_id, user_id)
--   )
--
-- Quoted verbatim (spec :669-671, RLS narrative):
--   "campaigns — global read. Writable by app_admin only (v1 team curation)."
--   "campaign_participants — readable by the campaign's participants +
--    app_admin (so leaderboards can render). Writable by user themselves
--    (join/leave)."
--   "campaign_progress — readable by the campaign's participants (needed
--    for the leaderboard). Writable only by trigger."
--
-- Quoted verbatim (Flow 8, spec :864-871, Discovery/Joining):
--   "Library -> Campaigns sub-tab shows all active campaigns + a countdown
--    to upcoming ones."
--   "Campaign detail page: description, dates, curated workout list,
--    current community progress bar, individual target, per-campaign
--    leaderboard."
--   "'Join Campaign' button -> creates campaign_participants row. No
--    commitment beyond opt-in -- you can leave anytime."
--
-- ── ADJUDICATION 1: app_admin has no RLS-visible claim — same posture as
--    every prior "+ app_admin" spec line in this repo ────────────────────
-- Confirmed precedent (20260721000001_moderation_block_report.sql:46-51,
-- reaffirmed 20260724000002_connected_accounts_calendar_sync.sql:187-190):
-- "app_admin is not an RLS-visible role/claim anywhere in this schema
-- today" -- every prior table with a spec line reading "+ app_admin" ships
-- with NO app_admin SELECT/INSERT/UPDATE/DELETE policy; admin reads/writes
-- happen out-of-band via service role / direct SQL. Followed identically
-- here: campaigns gets no client INSERT/UPDATE/DELETE policy at all (v1
-- team curation is a service-role/SQL operation, matching user_reports'
-- and session_calendar_syncs' own "no admin write policy" posture), and
-- campaign_participants' SELECT policy covers only the participant case
-- (the "+ app_admin" clause is the same non-implemented no-op as every
-- other occurrence of that phrase in this schema).
--
-- ── ADJUDICATION 2: join/leave is a direct INSERT/DELETE, not an RPC ────
-- The brief poses the choice explicitly (RPC vs direct insert). Flow 8's
-- own text: "'Join Campaign' button -> creates campaign_participants row.
-- No commitment beyond opt-in -- you can leave anytime." No capacity limit,
-- no window check, no server-side computation is named anywhere in Flow 8
-- for either joining or leaving (contrast Flow 9's venue check-in, which
-- DOES need a geofence RPC -- out of this phase's scope). Owner-scoped
-- INSERT/DELETE RLS (WITH CHECK/USING user_id = auth.uid()) is therefore
-- the honest minimal shape -- same idiom as soundboard_favorites' owner
-- INSERT/UPDATE policies (20260717000003_curation.sql) and blocked_users'
-- "blocker manages own blocks" ALL policy. No start_attempt-style RPC
-- (20260723000002_attempt_plumbing.sql) is needed because there is no
-- cross-table validation to perform at join time (contrast start_attempt,
-- which must check routine.visibility='public' before inserting).
--
-- ── ADJUDICATION 3: test-campaign isolation — new `is_draft` column ─────
-- Per the phase spec (2026-07-19-campaigns-design.md:14) and plan
-- (2026-07-19-campaigns.md:13), Task 1 owns the schema decision so Task 3's
-- seeded test campaign can exist without polluting real users' active-
-- campaign surfaces (the "Murph de-leak" cautionary precedent named in
-- 2026-07-18-reliability-debt-design.md:26 -- a CI seed workout that DID
-- leak into production visibility and is still an open cleanup item; this
-- migration exists specifically to not repeat that mistake for campaigns).
-- `is_draft boolean NOT NULL DEFAULT false` is added to `campaigns` (a
-- tightening beyond the spec's verbatim column list, per the brief's
-- explicit recommendation). Chosen over a "far-past date window" because a
-- date-window trick is fragile (an admin adjusting date fields for
-- unrelated reasons could accidentally un-hide it, and it does not read
-- as intentional in the data) and chosen over a hardcoded CI-account-id
-- check (brittle, and RLS has no clean way to reference "the CI account"
-- without a special-cased UUID literal baked into a policy). The SELECT
-- policy below reads: a draft campaign is invisible to everyone except
-- its own participants -- so Task 3's seed becomes visible ONLY to
-- whichever account(s) actually join it (via direct SQL fixture setup or
-- the ordinary join path), with zero risk of surfacing on a real user's
-- Library/Home carousel query, and with zero admin-claim dependency.
-- ============================================================

-- ── 1. campaigns ─────────────────────────────────────────────────────────
-- Tightenings beyond the spec's verbatim column list (documented per
-- body_weight_logs/user_reports precedent -- "spec is the column list, not
-- the DDL", 20260724000001_body_weight_logs.sql:22-41):
--   * id DEFAULT gen_random_uuid() (user_reports/body_weight_logs idiom).
--   * ends_at > starts_at CHECK -- a campaign with a backwards or
--     zero-width window is never valid; the trigger's window predicate
--     (starts_at <= completed_at <= ends_at) would otherwise silently
--     admit nothing for such a row, which is a data-entry bug, not a
--     legitimate campaign shape.
--   * curated_routine_ids NOT NULL DEFAULT '{}' -- same "always an
--     explicit, never-NULL array" idiom as soundboard_favorites.slugs
--     (20260717000003_curation.sql) -- a bare NULL array participates
--     awkwardly in `= ANY(...)` (always NULL, silently false) where an
--     empty array is the same outcome but unambiguous and indexable.
--   * is_featured/created_at gain NOT NULL to back their DEFAULTs (same
--     "spec says DEFAULT, codebase convention makes DEFAULT NOT NULL"
--     gap-fill as every prior table in this repo).
--   * is_draft -- see Adjudication 3 above. NOT a spec column.
-- NOT added: a composite/array FK from curated_routine_ids to
-- routines(id) -- Postgres cannot express per-element array FK integrity
-- declaratively, and enforcing it via a trigger would be inventing
-- referential integrity the spec never asks for (same reasoning
-- workout_attempts' own header gives for NOT enforcing routine.
-- visibility='public' via a constraint trigger,
-- 20260723000001_public_workout_repository.sql:60-68) -- campaigns are
-- service-role/SQL-curated content in v1, same trust boundary as
-- routines.is_featured/scoring_top_set_exercise_id.
CREATE TABLE public.campaigns (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                text NOT NULL,
  description         text,
  starts_at           timestamptz NOT NULL,
  ends_at             timestamptz NOT NULL,
  banner_url          text,
  global_target       jsonb,
  individual_target   jsonb,
  curated_routine_ids uuid[] NOT NULL DEFAULT '{}',
  is_featured         boolean NOT NULL DEFAULT false,
  is_draft            boolean NOT NULL DEFAULT false,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE INDEX campaigns_active_window_idx ON public.campaigns(starts_at, ends_at);

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

-- ── 2. campaign_participants ────────────────────────────────────────────
-- Tightenings: NOT NULL + ON DELETE CASCADE on both FK columns (matches
-- every user_id/campaign_id-shaped FK pair in this repo -- e.g.
-- group_members, blocked_users; a participation row can never legitimately
-- exist without either parent, and cascading on profile deletion matches
-- account-deletion-cascade's documented scope,
-- spec :1159, "friendships, gyms, ... " -- participation records are
-- exactly this class of per-user join-table row).
CREATE TABLE public.campaign_participants (
  campaign_id  uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, user_id)
);

CREATE INDEX campaign_participants_user_id_idx ON public.campaign_participants(user_id);

ALTER TABLE public.campaign_participants ENABLE ROW LEVEL SECURITY;

-- ── 3. campaign_progress ────────────────────────────────────────────────
-- Tightenings: NOT NULL + ON DELETE CASCADE on both FK columns (same
-- reasoning as campaign_participants above). NOT NULL on the three counter
-- columns to back their spec-stated DEFAULT 0 (same gap-fill idiom as
-- every other table). Non-negative CHECKs on all three counters -- same
-- "spec silent, codebase convention fills the gap" defensive-CHECK
-- reasoning as body_weight_logs' `weight > 0`
-- (20260724000001_body_weight_logs.sql:34-41): these are trigger-only
-- monotonic counters (see Part 2's trigger), so a negative value can only
-- ever mean a bug, never legitimate data.
-- No FK from (campaign_id, user_id) to campaign_participants: considered
-- and rejected. A composite ON DELETE CASCADE FK would silently erase a
-- user's accrued progress the moment they leave a campaign (DELETE FROM
-- campaign_participants), which is a real behavior invention Flow 8 never
-- states ("No commitment beyond opt-in -- you can leave anytime" describes
-- opting out of participation, not forfeiting progress already earned).
-- Leaving the tables uncoupled at the FK level means progress persists
-- across a leave/rejoin -- the more generous, honest-by-silence default
-- given the spec says nothing about progress forfeiture.
CREATE TABLE public.campaign_progress (
  campaign_id         uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sessions_completed  integer NOT NULL DEFAULT 0 CHECK (sessions_completed >= 0),
  workouts_completed  integer NOT NULL DEFAULT 0 CHECK (workouts_completed >= 0),
  volume_lifted       numeric(12,2) NOT NULL DEFAULT 0 CHECK (volume_lifted >= 0),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, user_id)
);

ALTER TABLE public.campaign_progress ENABLE ROW LEVEL SECURITY;

-- ── 4. private.is_campaign_participant() ────────────────────────────────
-- New RLS-recursion-safe helper, created directly in `private` from day
-- one -- NOT in `public` first -- per the now-established posture of every
-- helper created since 20260722000001 (is_blocked) onward; every OLDER
-- helper that started in `public` has since needed its own relocation
-- migration (20260725000001 through 20260727000004). campaign_participants
-- is self-referencing exactly like group_members (its own SELECT policy
-- must check "is auth.uid() a participant of this row's campaign", which
-- re-enters the same table RLS would otherwise recurse into) -- same
-- SECURITY DEFINER STABLE shape as private.is_group_member
-- (20260725000002_is_group_member_private_schema.sql:54-59). `private`
-- schema + its REVOKE ALL FROM PUBLIC already exist
-- (20260722000001_is_blocked_private_schema.sql) -- not recreated here.
CREATE FUNCTION private.is_campaign_participant(p_campaign_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.campaign_participants
    WHERE campaign_id = p_campaign_id AND user_id = p_user_id
  );
$$;

-- ── 5. RLS: campaigns ────────────────────────────────────────────────────
-- "Global read" (spec :669), tightened per Adjudication 3: a draft
-- campaign is visible only to its own participants. Every non-draft
-- campaign (real content) is unconditionally globally readable, matching
-- the spec's literal words with zero narrowing -- including campaigns
-- whose window has already ended (Flow 8 :884, "final community total is
-- displayed as historical fact" requires ended campaigns to stay
-- browsable, so this policy deliberately does NOT gate on the active
-- window).
CREATE POLICY "campaigns are globally readable unless draft"
  ON public.campaigns FOR SELECT TO authenticated
  USING (
    NOT is_draft
    OR private.is_campaign_participant(campaigns.id, auth.uid())
  );

-- No INSERT/UPDATE/DELETE policy for `authenticated` -- see Adjudication 1.
-- v1 team curation (including Task 3's seeded test campaign) is a
-- service-role/direct-SQL operation, same posture as user_reports'
-- status transitions and session_calendar_syncs' admin path.

-- ── 6. RLS: campaign_participants ───────────────────────────────────────
-- "Readable by the campaign's participants" (the "+ app_admin" clause is
-- the established no-op, Adjudication 1). A participant can see the full
-- roster of their own campaign's participants -- "so leaderboards can
-- render" (spec :670), same reasoning as group_members' own membership
-- read policy.
CREATE POLICY "participants can read their campaign roster"
  ON public.campaign_participants FOR SELECT TO authenticated
  USING (private.is_campaign_participant(campaign_participants.campaign_id, auth.uid()));

-- "Writable by user themselves (join/leave)" (spec :670) -- see
-- Adjudication 2. Direct INSERT/DELETE, owner-scoped, no RPC.
CREATE POLICY "user joins a campaign as themselves"
  ON public.campaign_participants FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user leaves a campaign they joined"
  ON public.campaign_participants FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- No UPDATE policy -- campaign_participants has nothing to update
-- (joined_at is set once at INSERT; the row's only lifecycle events are
-- create/delete, matching the spec's own "join/leave" framing exactly).

-- ── 7. RLS: campaign_progress ───────────────────────────────────────────
-- "Readable by the campaign's participants (needed for the leaderboard)"
-- (spec :671).
CREATE POLICY "participants can read campaign progress"
  ON public.campaign_progress FOR SELECT TO authenticated
  USING (private.is_campaign_participant(campaign_progress.campaign_id, auth.uid()));

-- "Writable only by trigger" (spec :671) -- no INSERT/UPDATE/DELETE policy
-- for `authenticated` at all, same "trigger-only writes" idiom as
-- user_streaks/group_streaks (20260719000006_streaks.sql) and
-- workout_attempts/leaderboard_entries
-- (20260723000001_public_workout_repository.sql:145-160): absence of a
-- write policy makes every client write fail closed with 42501; the real
-- writer is the SECURITY DEFINER trigger function added in Part 2 of this
-- task, owned by the migration role and therefore exempt from this
-- table's own RLS as table owner.

-- ============================================================
-- ── 8. campaign_community_progress(p_campaign_id) — the community bar ───
-- ============================================================
-- Flow 8 (spec :877-880): "Aggregate metric across all campaign_progress
-- rows... Updated live via a postgres_changes subscription on the
-- Campaigns detail page... 'Together we've moved 47.3M lbs of the 100M lb
-- goal.'" The campaign detail page is reachable from Discovery (spec :865,
-- "Library -> Campaigns sub-tab shows all active campaigns... a countdown
-- to upcoming ones") BEFORE a user has joined -- so the community total
-- must be visible to any authenticated user who can see the campaign at
-- all, not just current participants. That is a strictly WIDER audience
-- than campaign_progress's own row-level RLS ("readable by the campaign's
-- participants" -- policy 7 above), so a client query that just SUMs
-- campaign_progress rows directly would 404 the community bar for anyone
-- who hasn't joined yet. This is the same "row-level RLS can't express
-- the aggregate's honest audience" gap the phase spec itself names
-- (2026-07-19-campaigns-design.md:8, "design the honest aggregate
-- surface... a DEFINER aggregate RPC in the established pattern") --
-- solved the same way group_stats/group_member_stats solve the analogous
-- gap for group collective metrics (20260720000003_group_stats_rpc.sql).
--
-- Exposure-through reasoning (public, not private-with-wrapper): this
-- function IS the client-facing surface -- the Campaigns detail page's
-- community-bar fetch calls it directly, exactly like group_stats is
-- called directly by GroupStatsView. That is different from
-- private.is_campaign_participant above, which exists ONLY to be
-- referenced from inside RLS policy quals / other DEFINER function
-- bodies and is never meant to be a client RPC target at all -- putting a
-- "public thin caller" in front of a private helper is only warranted
-- when PostgREST needs to reach that exact logic and nothing wider is
-- appropriate; here PostgREST needs to reach exactly THIS logic (the
-- aggregate), so it belongs directly in `public`, narrowly granted, same
-- as group_stats/group_member_stats/start_attempt.
--
-- Gate-first (same idiom as group_stats :72-76, session_pr_counts, etc.):
-- reject before any campaign_progress row is touched. The gate re-checks
-- the EXACT same visibility predicate as the campaigns SELECT policy
-- above (NOT is_draft OR participant) -- necessary because this function
-- is SECURITY DEFINER and therefore bypasses campaigns' RLS entirely; without
-- re-deriving the same predicate inside the function body, a caller who
-- knows (or guesses) a draft campaign's id could read its aggregate
-- totals even though the campaign row itself is invisible to them --
-- exactly the oracle-shape private-schema/gate-first discipline exists to
-- prevent (20260722000001's own header). The gate is deliberately NOT
-- narrowed to "only while starts_at <= now() <= ends_at": Flow 8 (:884)
-- requires the community bar to keep displaying an ended campaign's frozen
-- final total as historical fact, matching the campaigns SELECT policy's
-- own choice not to hide ended (non-draft) campaigns.
CREATE OR REPLACE FUNCTION public.campaign_community_progress(p_campaign_id uuid)
RETURNS TABLE (
  sessions_completed bigint,
  workouts_completed bigint,
  volume_lifted       numeric
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.campaigns c
    WHERE c.id = p_campaign_id
      AND (NOT c.is_draft OR private.is_campaign_participant(c.id, auth.uid()))
  ) THEN
    RAISE EXCEPTION 'campaign not found' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(SUM(cp.sessions_completed), 0)::bigint,
    COALESCE(SUM(cp.workouts_completed), 0)::bigint,
    COALESCE(SUM(cp.volume_lifted), 0)::numeric
  FROM public.campaign_progress cp
  WHERE cp.campaign_id = p_campaign_id;
END;
$$;

-- Same revoke-then-grant idiom as group_stats/group_member_stats
-- (20260720000003_group_stats_rpc.sql:108-109,153-154): newly created
-- functions get PUBLIC EXECUTE by default, which anon inherits, so REVOKE
-- FROM PUBLIC, anon and GRANT back explicitly TO authenticated only.
REVOKE EXECUTE ON FUNCTION public.campaign_community_progress(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.campaign_community_progress(uuid) TO authenticated;
