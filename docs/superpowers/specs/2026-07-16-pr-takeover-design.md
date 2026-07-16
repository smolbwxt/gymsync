# Phase P — PR Celebration Takeover — Design

**Status:** approved scope (roadmap Phase P); ground-truth revision 2026-07-16.
**Goal:** retire the harness's #1 divergence (`pr-celebration` 64% vs canvas frame 29) and close the solo-session gap in the PR moment.

## Ground truth (discovered 2026-07-16, supersedes the roadmap's framing)

The full-screen, user-dismissed PR celebration (frame 29 / p29) ALREADY EXISTS in `GroupSessionLiveView` (built in visual-parity-1, proof-matched: see its header comment "PR Celebration: full-screen, USER-DISMISSED moment (p29)"). The 64% parity divergence has two real causes:
1. The debug catalog's `pr-celebration` screen is a hand-built reproduction of the SOLO RECAP's inline `prCelebrationCard` (`WorkoutSessionView.swift:449`) — a different design element — diffed against the takeover frame.
2. Solo sessions have NO live PR moment (only the recap card afterward), while the master spec's Flow 3 says "PR detection works identically" solo vs group.

## Components

### 1. Extract the takeover into a shared view
Lift `GroupSessionLiveView`'s full-screen PR overlay into a reusable `PRCelebrationOverlay` (DesignSystem or Features/Sessions — match repo convention), parameterized by what it actually renders (exercise name, weight/reps if shown, dismiss action). `GroupSessionLiveView` adopts it with byte-identical visual output — this is a refactor; the existing group-session behavior (trigger conditions, user-dismissed, no auto-timeout) must not change.

### 2. Solo adoption
`WorkoutSessionView` (solo live session) presents the same overlay when a set resolves as a PR mid-session (the existing PR detection path at set-log time — the shared detect/record helper). The recap's inline `prCelebrationCard` stays (it summarizes the session's heaviest PR — a different job).

### 3. Catalog re-point
`CatalogHostView`'s `pr-celebration` screen renders the REAL `PRCelebrationOverlay` with fixture data, deleting the visual reproduction (and its drift risk, flagged since Task 4 of the harness).

## Acceptance
- Parity: `pr-celebration` score drops from 64% into the structural-noise band (≤ ~25%) — the mechanical proof the real view matches frame 29.
- Group-session captures/behavior unchanged (existing parity rows stay in band; no trigger-logic diffs beyond the extraction).
- Solo: a PR set during a solo session presents the takeover; dismissing returns to the session (device QA item — not CI-verifiable).

## Non-goals
Recap redesign (frames 8/17 adjudication is Phase U); changing PR detection/server triggers; animations beyond what the existing overlay already does.
