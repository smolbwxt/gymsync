# Phase U — Unbuilt Design Frames — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** build the two genuinely-unbuilt design frames (41 stat-tile states, 45 Activity Feed), align the solo recap to frame 17, and reconcile the design-debt records — each proven by a parity row in the noise band.

**Architecture:** SwiftUI feature work on `feature/design-frames`, one aggregate RPC (Burpee-Ledger precedent) for the feed, a lightweight stats snapshot cache for offline-stale, catalog re-points for the stattile states. CI-only Swift compilation; the harness is the acceptance instrument.

**Tech Stack:** SwiftUI, Supabase RPC + RLS, pgTAP for the RPC, XCUITest captures, parity harness.

## Global Constraints

- Swift compiles ONLY in CI; implementers commit, never push; cite real declarations (file:line) for every call. Memberwise-init trap: no new plain `private` stored properties on cross-file-constructed View structs.
- Migrations append-only via `db push` (pooler URL, creds in `.env.local`); every RPC ships pgTAP tests (positive + negative RLS) run via `node scripts/run_pgtap.js`.
- Canvas frames are authoritative: 41 (four states verbatim, incl. copy strings "No lifts logged yet", "Your first workout unlocks these stats.", the `·` last-synced marker + caption), 45 (month headers, date block, Solo/Group chip, `duration · volume · sets`, right "N PR" chip), 17 (navy hero: routine, MM:SS, "Friday, July 11 · solo", TOTAL LBS/SETS/PR; New-PR card; BY EXERCISE rows "N sets · top W × R" with PR chip; Done bar). Render any proof on demand: `.superpowers/parity/proofs/proof-frame-<NN>.png`.
- Offline-stale cache = lightweight snapshot (UserDefaults via the repo's settings idiom), NOT SwiftData (Phase O). Use the existing ConnectivityMonitor for offline state.
- The catalog `stattile-*` screens must render the REAL state views after this phase (delete reproductions).
- Never `git add -A`.

## Task 1: Stat-tile states (frame 41)

**Files:** Home stat-tile row (locate in `Features/Home/HomeView.swift` — read first), a small `StatTilesSnapshot` cache helper, `CatalogHostView.swift` re-points, `frame-map.json`.
- [ ] Read HomeView's stat-tile loading flow (what loads, when, current empty behavior) + GSStatTile API + ConnectivityMonitor API (cite lines).
- [ ] Implement the four states per frame 41: skeleton while loading (`.redacted` on placeholder tiles); zero-state dashed card with Start wired to the EXISTING solo-start action (cite it); offline-stale rendering cached snapshot values with the `·` marker + em-dash for absent + the caption line; loaded = current. Snapshot saved on every successful load.
- [ ] Catalog: `stattile-loading/error/empty` render the REAL row in forced states (loading/offline-stale/zero — note: rename semantics, "error" id now renders offline-stale; keep ids stable, document in the catalog comment). frame-map: all three → 41.
- [ ] Commit `feat(frames): Home stat-tile states (frame 41) + catalog re-point`.

## Task 2: Activity Feed RPC (backend)

**Files:** new migration `supabase/migrations/<next>_activity_feed_rpc.sql`, pgTAP test.
- [ ] Read the Burpee-Ledger RPC precedent (`20260717000002_burpee_ledger_rpc.sql`) for the idiom (SECURITY posture, membership gating).
- [ ] RPC `activity_feed(p_limit int default 50)`: for `auth.uid()` — completed sessions they participated in, returning per session: id, completed_at, started_at, is_group (group_id not null), display_name (group name else routine name), user's set count + volume (Σ reps×weight, excluding `is_penalty`/`is_failed`), user's PR count (personal_records by session), ordered completed_at desc. RLS-honoring (definer only if the precedent requires; prefer invoker + existing policies).
- [ ] pgTAP: positive (own sessions returned w/ correct aggregates from fixtures) + negative (other users' solo sessions absent). Run `node scripts/run_pgtap.js` green. `db push` applied.
- [ ] Commit `feat(frames): activity_feed RPC + pgTAP`.

## Task 3: Activity Feed view (frame 45)

**Files:** new `Features/Stats/ActivityFeedView.swift`, Stats entry-point edit, `ScreenshotTests.swift` capture, `frame-map.json`.
- [ ] Read StatsTabView's existing "Recent Activity / View sessions" row (cite) — the feed replaces its destination (or the row becomes "Activity"). Month-section grouping client-side from `completed_at`.
- [ ] Build per frame 45 (date block, chips, meta, PR chip, month headers). Repository call to the Task 2 RPC (add to the relevant repo enum following its idiom).
- [ ] Capture `app-activity-feed.png` (Stats → Activity row, defensive) + map `activity-feed → 45`.
- [ ] Commit `feat(frames): Activity Feed (frame 45) + capture`.

## Task 4: Solo recap alignment (frame 17)

**Files:** `Features/Workout/WorkoutSessionView.swift` recap section, `ScreenshotTests.swift`, `frame-map.json`.
- [ ] Read the current recap (hero-less summary + `prCelebrationCard` + breakdown). Restructure to frame 17: navy hero card (accent bg: kicker routine name, huge MM:SS duration, "date · solo", TOTAL LBS / SETS / PR columns), New-PR card, BY EXERCISE rows ("N sets · top W × R", PR chip on PR exercises), Done. NO Apple Health row (Phase H). Preserve all data sources; this is layout alignment.
- [ ] Capture: catalog is the reliable route — add a `recap-solo` catalog screen rendering the recap with fixture data (same seam discipline as prior catalog states) OR navigate a real quick workout if trivially scriptable; catalog preferred. Map `recap-solo → 17`.
- [ ] Commit `feat(frames): solo recap aligned to frame 17 + capture`.

## Task 5 (controller): CI gate + reconciliation + close
- [ ] Push once after T4; watch build-test/screenshots/parity; verify the three new/changed rows in the noise band; fix waves as needed.
- [ ] Update `docs/design/unbuilt-frames/README.md` (41/45/17 built; 8 → Phase F with kudos; inventory note). Whole-branch review → merge.

## Self-Review
Spec §1→T1, §2→T2+T3, §3→T4, §4→T5; acceptance→T5. Frame copy strings embedded in Global Constraints; RPC contract fully specified in T2; catalog id-stability decision documented in T1.
