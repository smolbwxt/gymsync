# Gym Sync — Designer Note #4: canvas file contract for automatic sync

Good news first: we received the full canvas via zip export — all nine new frames (the three
addendum screens, stat-tile states, gym-setup searching, rest timer, and the four PTT dock
states) are in hand and the engineering pipeline is building against them. Thank you.

To make handoffs fully automatic going forward (no zip exports, no human relay), two file
conventions on your side:

## 1. Split new work into separate files

`Gym Sync App Designs.dc.html` is now ~318 KB — beyond the 256 KiB per-file limit of the API
we use to pull your work. Anything appended to it is invisible to us until someone manually
exports a zip.

**Going forward: put each new section in its own file**, e.g.:
- `sections/2026-07-live-voice.dc.html`
- `sections/2026-08-streaks.dc.html`

Keep each file under ~200 KB (roughly 10-12 phone frames). The existing big canvas can stay
as-is — we have it complete; just don't grow it further.

## 2. Plain HTML frames (no ios-frame.jsx)

Frames built with `<x-import ... from="./ios-frame.jsx">` only render inside the design tool —
our render-and-screenshot pipeline (which we use to verify the app matches your proofs
pixel-by-pixel) executes plain HTML/CSS only. The older sections' hand-drawn phone chrome
rendered perfectly; the JSX-framed ones render as empty shells for us.

**Going forward: author frames the way the original sections were** (plain divs + your DS
classes/tokens, decorative phone chrome drawn in HTML). We read your markup as the exact
spec either way, but plain HTML additionally lets us render and diff it.

With both conventions in place, the loop becomes: you save → we pull, render, capture, and
build — automatically, every session.

## Still open from note #3 (no rush)
- Bless-or-redraw was answered by your redraws — thank you; all six new frames are built.
- Apple Health row placement in the Settings Hub (we kept it — only HealthKit entry point).
- Product gaps found during build, for your/product's list: burpee "settled" state has no
  schema backing (debts never decrement); the no-show state is currently unreachable in
  production; the "we'll retry when you're back online" copy implies an offline outbox that
  doesn't exist yet (we shipped behavior-truthful copy instead).
