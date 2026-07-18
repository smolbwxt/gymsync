# Phase H — Health & Calendar Integrations — Design

**Status:** approved scope (roadmap Phase H, rescoped after the audit correction: HealthKit EXPORT already exists — `Services/HealthKitBridge.swift`, wired since 3b).

## Components

### 1. HealthKit gaps (export exists — close the gaps)
- **Re-write on duration edit** (deferred 3b ticket): when a completed session's duration is edited, the exported HKWorkout must be replaced (delete+rewrite per HK API — the bridge needs a delete path keyed to the session; discover how the original export identifies the workout — metadata key? add one if absent, fix-forward for future exports, best-effort for past).
- **Restore the frame-17 "Synced to Apple Health" card** on SoloRecapView (deliberately omitted in Phase U; `estimatedCalories` + `healthSynced` are dormant awaiting exactly this — cite the dormancy comments).
- **E2E verify the permission flow** (You-tab row + requestPermission) — device-QA item; code path review + capture only.

### 2. iOS Calendar sync (EventKit — spec'd v1, never built)
Master spec §2 EventKitBridge + v1 list: scheduled sessions → calendar events; update on reschedule; delete on cancel/abandon. v1-honest scope: the ORGANIZER's device writes events for sessions they schedule (participant-side sync needs per-user opt-in surfaces — judge in plan; the spec's line is one-way sessions→calendar). Requires NSCalendarsUsageDescription (the ITMS-90683 lesson — Info.plist via project.yml) + graceful denied-permission state. A You-tab toggle gates it (default off — no surprise permission prompts).

### 3. Body weight log + trend (spec'd v1, never built)
`body_weight_logs` table per master spec (owner-only RLS) + migration + pgTAP. UI: log entry (You tab or Stats — judge placement per idioms), Stats trend chart via the existing TrendChartView idiom. Seed a fixture series for captures.

### 4. Plate-math helper (spec'd v1, never built)
Pure client feature per the spec's unit-test list: target weight + bar weight → plate stack per side (45/35/25/10/5/2.5 default plates). Surfaced from the live set UI (WorkoutSessionView/GroupSessionLiveView log sheet — smallest idiomatic affordance). Hermetic unit tests (the spec names this one explicitly).

### 5. Google Calendar (SUB-PHASE, gated on user's OAuth consent approval)
`connected_accounts` + `session_calendar_syncs` tables + Edge Function sync per spec Flow 10 — BUILD ONLY the schema + a stub-ready structure this phase IF the OAuth prerequisite isn't ready; the full flow lands when the user's Google Cloud verification completes. USER ACTION REQUIRED: create the Google Cloud project + OAuth consent screen submission. Record status; do not block the phase on it.

## Acceptance
pgTAP (body weight RLS, calendar-sync table RLS if built); hermetic plate-math + HK-edit-path unit tests; captures (body-weight UI, plate-math sheet, Health card restored on recap-solo — its parity row updates); EventKit flows device-QA (simulator has no real calendar grant in CI — capture the denied/off states).

## Non-goals
Two-way calendar sync (v2); Fitbit/Whoop/etc (v2); HR (Phase W); persistent HR storage (never, per spec).
