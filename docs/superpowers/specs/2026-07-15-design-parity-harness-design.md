# Design-Parity Verification Harness — Design

**Status:** approved (design), 2026-07-15
**Goal:** Every build, produce a real render of every app screen placed side-by-side with its authoritative design proof, plus a coarse mechanical divergence score — so a proof-vs-implementation discrepancy (like the gym-setup search flow that shipped as a map-pan) can't slip through unseen again.

## Motivation

The prior "full frame QA" failed in three ways: (1) the app side was only ever captured for 6 of ~50 screens — the rest were code-read, not rendered; (2) an existing-screen divergence (the gym setup) was mis-filed as an unbuilt feature; (3) reliance on human eyeballing let a plainly-visible issue (top dead space) slip. The fix is to remove the missing-app-renders gap and the eyeballing dependency: capture *every* screen and diff it mechanically.

## Load-bearing constraint

The proofs render in Chrome (web fonts/layout); the app renders in iOS (UIKit rasterization, real device chrome). **They can never pixel-match** even with a perfect implementation. Therefore:
- The diff is **coarse/structural** (downscale-and-compare so sub-pixel font noise doesn't dominate). It reliably flags the impactful class — missing sections, wrong layout, wrong component (map vs search), a floating empty state — and does NOT attempt pixel-exact gating.
- The primary deliverable is a **complete side-by-side gallery** (proof | app | diff-heatmap) for every screen, sorted worst-divergence-first. Coverage + attention-drawing is the value.
- **Report-only**, not a build gate. Legitimate diffs exist (recorded deviations, dynamic data, render engine); a hard gate would be noise. A curated accepted-deviations list silences known-OK diffs. A gate can come later once a clean baseline exists.
- It does not catch pure **behavior** (scroll, gestures) — that remains device QA.

## Components

### 1. Fixture seed — `scripts/seed_qa_fixtures.js`
Idempotently seeds the CI test account (`ci_test_user`) with a deterministic world so the app's real internal fetches return known, screenshot-stable data:
- a group (with the test user as member), 
- sessions in each state (scheduled/lobby_open/voting/locked/in_progress + one completed for recap),
- a chat thread with a few messages (text + soundboard echo + a voice-note row),
- friends (accepted + pending), routines (2-3 with exercises), personal records, a published featured routine.
Idempotent: keyed on stable fixture IDs / names, re-runnable without duplication. Uses the service-role key (same pattern as `seed_routines.js`).

### 2. Debug screen catalog — `#if DEBUG`, launch-arg gated
A hidden route (`UITEST_CATALOG=<screen-id>` launch arg, read in `AuthService.bootstrap()`-adjacent startup, same gating idiom as the autologin) that force-presents states navigation + seeding cannot reach:
- PR-celebration overlay, the four voice-dock states (idle/connecting/transmitting/mic-denied/unavailable), error/loading/empty states, the onboarding flow (Sign In / Username / Home Gym / You're set / priming / denied).
- Renders the target view with hand-built fixture state. Compiled out of release entirely.

### 3. App capture — extend `GymSyncUITests/ScreenshotTests.swift`
Walks every reachable screen (seeded data makes them populated) + every catalog state, attaching one `XCTAttachment` screenshot per screen with a stable name (`app-<screen-id>.png`). Reuses the existing autologin + screenshot-export pipeline. Runs in the `screenshots` CI job.

### 4. Proof render — `scripts/render_proofs.js`
Formalizes the working dc-runtime method: serve `docs/design/` (canvas + `support.js` + `ios-frame.jsx` + `_ds`), Chrome-headless with `--virtual-time-budget`, render each frame in the **Ink** palette (matching the CI test user), one PNG per frame (`proof-<frame-id>.png`), cropped to the content region (below drawn status bar, above home indicator). A frame→screen-id mapping table lives alongside (some canvas frames are superseded; the map points each app screen at its authoritative frame).

### 5. Diff + report — `scripts/parity_diff.js`
For each `app-<id>` ↔ `proof-<id>` pair:
- **Align:** crop both to the content region, normalize to a common width.
- **Score:** downscale both (e.g. to ~64px wide) and compute a perceptual difference (per-pixel delta on the downscaled images, or SSIM) — a coarse structural score in [0,1].
- **Heatmap:** a full-res difference visualization for the report.
- **Report:** one self-contained HTML (`parity-report.html`): a row per screen — proof | app | heatmap | score — sorted worst-first, with the `accepted-deviations.json` entries visually flagged/collapsed. Uploaded as a CI artifact.

## CI integration
- App capture: the existing `screenshots` job (already produces `app-screenshots`), extended to cover all screens/states.
- New `parity` job (needs: screenshots): installs Chrome, runs `render_proofs.js` then `parity_diff.js` against the downloaded `app-screenshots`, uploads `parity-report` artifact. `continue-on-error` (report-only).
- Seed runs as a step before the app-capture test (or a scheduled pre-seed), so the account is populated.

## Accepted-deviations mechanism — `docs/design/accepted-deviations.json`
A checked-in list of `{ screen-id, reason }` for legitimately-divergent screens (recorded deviations like the You-tab stat tiles, dynamic-data screens, screens intentionally ahead of/behind a superseded frame). The report flags these separately so they don't read as failures.

## Build phases (for the plan)
1. Proof render script + frame→screen map (formalize the working method; no app changes) — produces the proof half standalone.
2. Diff + report engine (against the 6 existing app screenshots first, to prove the pipeline end-to-end).
3. Fixture seed script.
4. Debug catalog + launch hooks (app `#if DEBUG`).
5. Extend the UITest capture to all screens/states.
6. CI wiring (parity job) + accepted-deviations baseline.

## Success criteria
- Every app screen has a real render paired with its proof in one report, each build.
- The report would have surfaced all four device-QA findings (gym search, Library scroll, Social void, dead space) at the top of the divergence-sorted list.
- No app-architecture refactor; all additive (fixtures, debug-only catalog, test/CI/script code).
- Runs in CI, report-only, with an accepted-deviations baseline to keep signal high.

## Non-goals
- Pixel-exact matching (impossible across render engines).
- Behavioral verification (scroll/gesture/interaction) — stays device QA.
- A hard build gate (deferred until a clean baseline exists).
