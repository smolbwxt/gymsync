# Phase U — Unbuilt Design Frames — Design

**Status:** approved scope (roadmap Phase U); frames verified against rendered proofs 2026-07-16.

## Recap adjudication (controller, 2026-07-16 — closes the roadmap's open question)

Frames 8, 17, 34 are THREE distinct intended screens, not alternatives:
- **Frame 8 "Session Complete"** — GROUP end-of-session moment: navy hero (crew·routine, duration, date·lifters, totals), per-session volume leaderboard with kudos counts, "Your PR this session", kudos-send emoji row, Share Recap. **Depends on the kudos backend (schema + realtime), a known backend gap → MOVED to Phase F** (social finishers) where kudos lands; recorded there.
- **Frame 17 "Workout Complete"** — SOLO end-of-workout moment: navy hero (routine, duration, date·solo, TOTAL LBS / SETS / PR), New-PR card, BY EXERCISE breakdown (sets · top), "Synced to Apple Health" row. Buildable NOW except the Health row (Phase H) — rendered absent until H ships. **In scope here (U-T3).**
- **Frame 34 "Session Detail"** — from-history detail. BUILT (CompletedSessionView). No action.

## Scope

1. **Stat-tile states (frame 41)** — the Home stat-tile row gains real states:
   - LOADED (current), LOADING·SKELETON (redacted blocks), FIRST-SESSION·ZERO (dashed-border card "No lifts logged yet / Your first workout unlocks these stats." + Start button wired to the existing solo-start action), OFFLINE·STALE-CACHE (last-synced values with the superscript-dot marker, em-dash where nothing cached; caption per frame).
   - Stale cache = a lightweight last-snapshot store (UserDefaults-level; NOT the Phase O SwiftData store) + the existing ConnectivityMonitor for offline detection.
   - The catalog's `stattile-loading/error/empty` screens re-point to the REAL states (reproductions deleted); frame-map maps them to 41.
2. **Activity Feed (frame 45)** — pushed "Activity" screen: month section headers, rows = date block (day + weekday), Solo/Group chip, name (group name for group sessions, routine name for solo), meta `duration · volume · sets`, right-aligned "N PR" chip. Reached from Stats (replace/augment the existing "View sessions" row per the frame's back-chevron-from-Stats). One aggregate query (RPC following the Burpee-Ledger RPC precedent, RLS-honoring, user-scoped: completed sessions + the user's per-session volume/set counts + PR counts). Capture + `activity-feed → 45` map entry.
3. **Solo recap alignment (frame 17)** — restructure `WorkoutSessionView`'s recap to the frame: navy hero card, New-PR card (existing `prCelebrationCard` restyled/aligned), BY EXERCISE list (existing breakdown aligned), Done. Health row omitted until Phase H. Capture (`recap-solo → 17`).
4. **Reconciliation** — `docs/design/unbuilt-frames/` README updated (41/45 built; 42 built earlier; 26 reclassified; frame-8 dependency recorded → Phase F); backend-gap re-inventory note (countdown/expiry, presence/last-active, swap proposals, lobby voice card, countdown hero — each: buildable-now or prerequisite recorded) appended to the roadmap by the controller at phase close.

## Acceptance
- Parity rows: `stattile-* → 41`, `activity-feed → 45`, `recap-solo → 17` all in the structural-noise band.
- Zero-state + skeleton reachable in catalog captures; offline-stale at least catalog-forced (live offline capture is not CI-feasible).
- Feed shows correct month grouping/meta against the seeded fixture world.

## Non-goals
Kudos/frame 8 (Phase F); Apple Health row (Phase H); SwiftData offline store (Phase O); redesigning CompletedSessionView (frame 34 — built).
