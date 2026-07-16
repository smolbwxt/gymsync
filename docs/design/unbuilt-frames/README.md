# Unbuilt design frames — resolution record

The full-frame design-parity QA (2026-07-15) originally found four canvas frames
with no implementation. **As of Phase U (2026-07-16), every frame in this
directory is resolved** — the directory is retained as the historical record of
the finding and the authoritative proof renders.

| Proof | Canvas frame | What it is | Status |
|-------|-------------|------------|--------|
| `26-rich-states.png` | 26 · Rich states | Chat rich states (images / reactions / typing indicator) | **Built** (Phase 2.5) — was miscatalogued here as Home stat-tile states |
| `41-stat-tiles-states.png` | 41 · Stat Tiles states | Loaded / skeleton / first-session-zero / offline-stale stat tiles | **Built** (Phase U — `StatTilesRow`); parity-guarded via `stattile-* → 41` |
| `42-gym-setup-searching.png` | 42 · Gym Setup · searching | Live search-results state while picking a home gym | **Built** (MKLocalSearch); parity-guarded via `onboarding-homegym-searching → 42` |
| `45-activity-feed.png` | 45 · Activity Feed | Dedicated scrollable activity feed | **Built** (Phase U — `ActivityFeedView` + `activity_feed` RPC); parity-guarded via `activity-feed → 45` |

Related frames adjudicated during Phase U (proofs render on demand via
`scripts/render_proofs.js`; not stored here):

- **Frame 17 · Workout Complete** — solo recap. **Built** (Phase U — `SoloRecapView`,
  parity `recap-solo → 17`). The frame's "Synced to Apple Health" card is
  deliberately omitted until Phase H restores it.
- **Frame 8 · Session Complete** — group end-of-session celebration (leaderboard,
  kudos). **Queued for Phase F** — depends on the kudos backend, per the
  remaining-build roadmap.
- **Frame 34 · Session Detail** — from-history detail. Built (`CompletedSessionView`,
  parity `session-recap → 34`).

These PNGs are authoritative renders (canvas → dc-runtime, Ink palette). The live
source of truth is the canvas itself — `docs/design/Gym Sync App Designs.dc.html` —
re-render with `scripts/render_proofs.js`.
