# Phase C — Seasonal Campaigns — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the campaigns machinery per master spec Flow 8 — tables + progress trigger, Library sub-tab + Home carousel, live community progress, per-campaign leaderboard, completion badge + system message — with one seeded test campaign.

**Architecture:** backend-first (T1 schema/trigger/RPCs), then UI (T2), then content+live-proof (T3), gate (T4). Spec: `docs/superpowers/specs/2026-07-19-campaigns-design.md`; product law = master spec Flow 8 + campaigns schema — implementers read them verbatim. ALL handoff-doc laws bind (`docs/superpowers/HANDOFF-2026-07-19-fable-to-opus.md` §3).

**Tech Stack:** Postgres + pgTAP, SwiftUI (CI-only), Realtime postgres_changes (community bar), the 3d outbox if Flow 8 names a push, seed idioms.

## Global Constraints
- Handoff §3 in full (append-only migrations + live-pg_policies inventories + private-schema DEFINER discipline + NOT VALID/VALIDATE for grown-table CHECKs; Swift CI-only + citations + the isolation/memberwise traps; explicit staging; commit-don't-push).
- Test-campaign isolation: must not surface on real users' active-campaign UI (mechanism adjudicated in T3, seeded per the Murph de-leak precedent).
- Never `git add -A`.

## Task 1: Backend — tables, trigger, RPCs
- [ ] Read master spec Flow 8 + campaigns schema verbatim (quote in report). Migrations: `campaigns`/`campaign_participants`/`campaign_progress` per spec + the progress trigger (fires on the session-completion path — find the honest hook: the same transition streaks/leaderboards use; cite those precedents) + join/leave surface (RPC vs direct insert per spec — adjudicate w/ citation). RLS per spec; any aggregate helper for the community bar goes DEFINER-in-private or a narrowly-granted RPC per the established patterns.
- [ ] Chat kind: check whether `system_campaign` (or spec's name) needs the chat_messages CHECK extended — NOT VALID+VALIDATE doctrine if so. Push notification: check Flow 8 — if named, payloads.ts case + deno test per the 3d pattern.
- [ ] pgTAP: RLS both directions, trigger correctness (fixture session → progress increments; outside-window → no increment), join/leave. Full-suite TRUE totals; db push. Commit.

## Task 2: UI — sub-tab, carousel, detail
- [ ] Read LibraryTabView (sub-tab enum), HomeView (carousel/card idioms), the canvas for campaign frames (render if any exist; else system-design + deviations), GroupStats/Discover leaderboard row idioms, the Realtime subscription idioms (SessionLiveService for postgres_changes; the channel-guard doctrine from debt-zero binds any new channel work).
- [ ] Campaigns sub-tab (active + upcoming lists), Home carousel card (active campaigns only), campaign detail (description/dates/community progress bar live via postgres_changes on campaign_progress, per-campaign leaderboard, join/leave CTA, completion badge state). Repository per idiom.
- [ ] Captures + frame-map/deviations; catalog cases per the 4-part idiom. Hermetic tests for pure logic (progress %, date-window state machine). Commit.

## Task 3: Content + live proof
- [ ] Seeded test campaign (idempotent; isolation mechanism per spec §3 — adjudicate draft-flag vs past-window vs CI-only visibility; document). CI-account join + fixture-session completion → progress increment proven LIVE (the acceptance bar). Captures with the seeded data. Commit.

## Task 4 (controller): gate + merge.

## Self-Review
Spec §1→T1, §2→T2, §3→T3. Test-campaign isolation named with an adjudication owner. Real content explicitly the user's. Channel-guard doctrine carried into T2's Realtime work.
