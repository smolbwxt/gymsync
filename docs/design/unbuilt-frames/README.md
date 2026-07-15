# Unbuilt design frames — held for a future phase

The full-frame design-parity QA (2026-07-15) found that four canvas frames have
**no implementation yet**. They aren't parity bugs — they're features that were
always queued as the "brief-#1 leftovers" phase and never built. The user's call
(2026-07-15): **hold onto the proofs; build them out later if the features prove
desirable.**

These PNGs are authoritative renders (canvas → dc-runtime, Ink palette). The live
source of truth is the canvas itself — `docs/design/Gym Sync App Designs.dc.html`,
frames listed below — re-render with the method recorded in the project memory.

| Proof | Canvas frame | What it is | Where it would live |
|-------|-------------|------------|---------------------|
| `26-rich-states.png` | 26 · Rich states | Home stat-tile loading / error / empty states | `GSStatTile` variants consumed by `HomeView` |
| `41-stat-tiles-states.png` | 41 · Stat Tiles states | Redacted / loading / populated stat tiles | `GSStatTile` / `HomeView` |
| `42-gym-setup-searching.png` | 42 · Gym Setup · searching | Live search-results state while picking a home gym | `HomeGymSetupView` (MapKit search) |
| `45-activity-feed.png` | 45 · Activity Feed | Dedicated scrollable activity feed | new view; today Stats only has "Recent Activity → View sessions" |

The complete frame-by-frame QA matrix (built screens all verified faithful; two
systematic divergences fixed in PR #22) is summarized in the project memory and
was tracked in `.superpowers/qa/frame-parity.md` (git-ignored scratch).
