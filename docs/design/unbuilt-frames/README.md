# Unbuilt design frames — held for a future phase

The full-frame design-parity QA (2026-07-15) originally found four canvas frames
with no implementation. Two have since shipped: frame 42 (MKLocalSearch home-gym
search) is built and now regression-guarded by the parity harness
(`onboarding-homegym-searching → 42` in `docs/design/frame-map.json`), and frame 26
turned out to be chat rich states (images/reactions/typing indicator), not Home
stat-tile states — those shipped in Phase 2.5. Frames 41 and 45 remain genuinely
unbuilt; they were always queued as "brief-#1 leftovers" and never built. The
user's call (2026-07-15) for what's left: **hold onto the proofs; build them out
later if the features prove desirable.**

These PNGs are authoritative renders (canvas → dc-runtime, Ink palette). The live
source of truth is the canvas itself — `docs/design/Gym Sync App Designs.dc.html`,
frames listed below — re-render with the method recorded in the project memory.

| Proof | Canvas frame | What it is | Status |
|-------|-------------|------------|--------|
| `26-rich-states.png` | 26 · Rich states | Chat rich states (images / reactions / typing indicator) | **Built** (Phase 2.5) — not a Home stat-tile state as previously miscatalogued here |
| `41-stat-tiles-states.png` | 41 · Stat Tiles states | Redacted / loading / populated stat tiles | Unbuilt — `GSStatTile` / `HomeView` |
| `42-gym-setup-searching.png` | 42 · Gym Setup · searching | Live search-results state while picking a home gym | **Built** (MKLocalSearch) — regression-guarded by `onboarding-homegym-searching → 42` in the parity harness |
| `45-activity-feed.png` | 45 · Activity Feed | Dedicated scrollable activity feed | Unbuilt — new view; today Stats only has "Recent Activity → View sessions" |

The complete frame-by-frame QA matrix (built screens all verified faithful; two
systematic divergences fixed in PR #22) is summarized in the project memory and
was tracked in `.superpowers/qa/frame-parity.md` (git-ignored scratch).
