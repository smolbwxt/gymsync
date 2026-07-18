# Phase H — Health & Calendar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** close the HealthKit gaps, add iOS calendar sync, body-weight log + trend, plate math; stage Google Calendar behind the user's OAuth prerequisite.

**Architecture:** four largely-independent tasks + a controller gate. Spec: `docs/superpowers/specs/2026-07-18-health-calendar-design.md`; product law: master spec §2 bridges / v1 list / Flow 10; the audit correction (HealthKit export EXISTS — gaps only).

**Tech Stack:** Swift (HealthKit/EventKit — CI-only compile; NO simulator grants for either, so CI proves compile + denied-states only), Postgres + pgTAP, hermetic XCTest.

## Global Constraints
- Info.plist keys via `GymSyncApp/project.yml` (the ITMS-90683 lesson): NSCalendarsUsageDescription (and full-access variant per iOS 17 EventKit API — discover which API level the codebase targets and the right key/API pairing: `EKEventStore.requestFullAccessToEvents`).
- Permission prompts NEVER fire on launch — only behind explicit user toggles/actions; denied states graceful.
- HealthKit changes preserve the existing export behavior for the normal path (the bridge is live production code — read fully, cite, minimal diffs).
- Migrations append-only + pgTAP; Swift citations; memberwise traps; commit-don't-push; catalog cases + deviations for new surfaces.
- Never `git add -A`.

## Task 1: HealthKit gaps
- [ ] Read `HealthKitBridge.swift` fully + its callers (endSession paths, the duration-edit path `SessionRepository.editDuration` + its callers) + SoloRecapView's dormant `healthSynced`/Health-card omission comments + `estimatedCalories`'s dormancy note. Cite all.
- [ ] Re-write-on-edit: export marks workouts with a metadata key (`HKMetadataKeyExternalUUID` = session id — verify the API; fix-forward the export to stamp it), and the duration-edit path deletes-by-predicate + re-exports (best-effort, logged, never blocks the edit; old exports without the key: skip with a log — honest limitation).
- [ ] Restore the frame-17 Health card on SoloRecapView (the omitted card: "Synced to Apple Health · 42 min · 318 kcal" shape per `proof-frame-17.png` — render it), driven by `healthSynced` + `estimatedCalories` (their dormancy ends — update those comments). The recap-solo parity row will shift: the frame INCLUDES the card, so the score should IMPROVE — note expected direction.
- [ ] Hermetic tests where possible (metadata-stamping pure logic); device-QA note for the rest. Commit.

## Task 2: EventKit sync
- [ ] Read: ScheduleSessionView/SessionRepository schedule+reschedule+cancel paths (cite); the series flows (occurrences materialized — events per occurrence; judge volume: cap at the series' materialized set); project.yml Info.plist idiom.
- [ ] `EventKitBridge` service (mirror HealthKitBridge's shape): requestAccess (iOS17 full-access API), addEvent(session) → store identifier mapping (LOCAL mapping: a lightweight store keyed session_id→eventIdentifier — UserDefaults per the StatTilesSnapshot precedent; server table NOT needed for one-way local sync — cite the reasoning vs the spec's session_calendar_syncs which exists for GOOGLE'S server-side sync), update/delete on reschedule/cancel.
- [ ] You-tab toggle ("Add my sessions to Calendar", default off) gating all writes; on enable: request permission + backfill upcoming organized sessions; on disable: best-effort remove mapped events. Denied state → row shows "enable in Settings" per the notification-prefs idiom.
- [ ] Wire the schedule/reschedule/cancel call sites (organizer-side only, v1 per spec). project.yml key. Captures (toggle row rides tab-you; deviation note). Commit.

## Task 3: Body weight + trend
- [ ] Migration: `body_weight_logs` per master spec (owner-only RLS both directions) + pgTAP. `db push`.
- [ ] UI: log sheet (weight + unit per profile conventions — discover if a unit preference exists; default lbs) reachable from Stats ("Body Weight" card with trend via TrendChartView + a log button — cite the TrendChartView init from U). Repository per idiom. Seed fixture series (idempotent). Captures + deviation. Commit.

## Task 4: Plate math
- [ ] `PlateMath` pure helper (target, bar=45 default → per-side stack, greedy descending [45,35,25,10,5,2.5]; unreachable weights → nearest-below + remainder note) + hermetic XCTests (the spec's named case).
- [ ] Surface: a small button in the log-set sheet(s) (read LogSetSheet/GroupSessionLiveView's set entry — cite; one shared sheet component) showing the stack for the current target weight. Captures via catalog (`plate-math`) + deviation. Commit.

## Task 5: Google Calendar staging (conditional)
- [ ] Check with the controller whether the user's OAuth consent is approved. If NOT (expected): migration for `connected_accounts` + `session_calendar_syncs` per spec (Vault-encrypted token columns — read how existing secrets/vault patterns work; if Vault unavailable, document the encryption posture honestly) + pgTAP + a stub note in the roadmap; NO OAuth client code. If YES: full Flow 10 (unlikely this pass). Commit.

## Task 6 (controller): gate + merge.

## Self-Review
Spec §1→T1, §2→T2, §3→T3, §4→T4, §5→T5. The EventKit local-mapping vs server-table decision is pre-adjudicated with reasoning (T2). Permission-prompt discipline in constraints. Parity expectations for recap-solo noted (score improves).
