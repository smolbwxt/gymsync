# design-sync notes — GymSync Onyx

- GymSync's real design system is **SwiftUI** (Onyx, in GymSyncApp/). There is no JS design-system
  repo, so this sync is **off-script generation**: the React/web edition of Onyx is authored by hand
  from the locked mocks (squad-home.html v7) and Swift token values, then validated and graded through
  the standard gates (package-validate + absolute rubric). "Ship what the customer built" here means:
  the web components mirror the shipped Swift components and locked mocks 1:1 — they ARE the first
  web build of Onyx, not a reimplementation of an existing JS library.
- First scope (2026-08-09): squad-room set — Onyx tokens + week's bar family (bar, plate, collar),
  crew card, pixel banners + rail, chat widget, iMessage bubbles, routine rows + tuning stepper,
  extruded button family, crew chips, tab bar.
- Authored source lives in `design-web/` (committed); build output in `ds-bundle/` (generated).
- Token source of truth: squad-home.html v7 `:root` block (Onyx dark) — bg #0A0B0D, sf #16181D,
  ac #3AB5F5, onac #04121F, gold #E8C33A, grn #2FA45C, lip #14171C, face #2A303A;
  lifter colors: you #3AB5F5, marcus #E8834A, dani #2FA45C, tess #C9A227.
- Key mechanic encoded in WeeksBar: collar clamps at declared goal; bare sleeve = remaining;
  flush = ironclad. NO ghost plates (design decision, Aug 9).

## Known render warns
- (none outstanding — all 8 GRID_OVERFLOW warns resolved via cfg.overrides cardMode:column, 2026-08-09)

## Re-sync risks
- `design-web/` is hand-authored to mirror SwiftUI Onyx + the locked squad-home v7 mock. Nothing
  detects drift between the Swift components and this web edition — when Swift Onyx changes
  (tokens, extrusion depths, new components), design-web must be updated BY HAND and re-synced.
- playwright pinned to 1.58.0 in .ds-sync to match the cached chromium build 1208
  (%LOCALAPPDATA%/ms-playwright, owned by the Playwright MCP plugin). If that cache updates,
  re-pin playwright to the version whose browsers.json matches (see §4.1 procedure).
- Lifter colors are inlined as hex in previews AND as tokens in tokens.css — change both together.
- Build assumes node 22 + esbuild/tsc from design-web devDependencies; converter deps live in
  .ds-sync (gitignored, reinstall on fresh clone: npm i esbuild ts-morph @types/react playwright@1.58.0).
- Preview scope 2026-08-09: ALL 17 components authored + graded good in one campaign; no floor cards.
