# Phase D Designer Brief — Watch

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Watch — all 5 watch surfaces (whose-turn / log-set / soundboard / ledger / idle),
HR pill zone colors + boundaries sign-off, the voice mixer sheet's coming-soon toggles
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md`.

---

## Correction to the roadmap before you start

`docs/superpowers/plans/2026-07-16-remaining-build-roadmap.md` (written 2026-07-16) lists "the
ENTIRE Watch app" among Phase D's undesigned, **not-yet-built** surfaces. That was accurate when
written. It is no longer accurate: **Phase W shipped and merged** (`.superpowers/sdd/progress.md`,
"PHASE W MERGED: master 3b8a433..f9b215c — build 229 deploying... ELEVENTH PHASE"; the watch
build debuted on build 230, turn-advance behavior on build 231). The watchOS target exists, is in
the App Store Connect pipeline, and all 4 core watch screens are real, running, merged Swift code
today:

- `GymSyncApp/GymSyncWatch/WhoseTurnView.swift`
- `GymSyncApp/GymSyncWatch/LogSetView.swift`
- `GymSyncApp/GymSyncWatch/SoundboardView.swift`
- `GymSyncApp/GymSyncWatch/LedgerView.swift`

Your job on this family is the **same shape as every other Phase D family** — bless or redraw
already-built, system-designed screens — not a from-scratch design problem. The one genuine gap
is that **none of these four screens (or the idle state) ever got an `accepted-deviations.json`
entry** when they shipped, unlike every other system-designed screen in this backlog. That's a
process gap worth naming to whoever owns the ledger (see the overview doc's concerns) — this
brief documents their current state directly from source so your session isn't blocked on it.

---

## (a) Screens — current state

### Navigation shape (applies to all 4 screens)
`ContentView.swift` (the watch app's root) is a `TabView` with `.tabViewStyle(.verticalPage)` —
Apple's watchOS 10 vertically-paging tab idiom for a small set of **peer** screens, explicitly
chosen over `NavigationStack` because these are 4 siblings a lifter flips between mid-set, not a
parent/child drill-down (see the file's own header comment for the WWDC23 citation). Order:
whose-turn (root) → log-set → soundboard → ledger. None of the 4 screens scroll — each is kept to
a handful of short lines by design ("tiny-screen honesty," the codebase's own term for it), since
`ScrollView` inside a `.verticalPage` TabView competes with the page-swipe gesture.

### 1. Whose-turn (`WhoseTurnView.swift`) — the root, and where "idle" lives
Renders exactly one of three states, each distinct (never inferred from another):
- **Live** — session name, current exercise, current lifter (initials badge + name), "Your turn" /
  "{name}'s turn" in accent/text, plus a "Phone unreachable" (wifi.slash) indicator when the
  phone-side push has gone stale.
- **Ended** — "Session ended" checkmark, session name, last exercise — rendered immediately, no
  staleness timeout.
- **Idle** — this IS the 5th surface your family scope names separately. Shows the next scheduled
  session's name + relative time ("NEXT SESSION"), or a plain "No session" if none is scheduled.
  It's a state within this view, not a separate tab — your frame set should treat it as a state
  of WhoseTurnView, matching how the code models it.

### 2. Log-set (`LogSetView.swift`)
Reps stepper (+/- watchOS idiom), weight adjustable via Digital Crown rotation, a log button.
Sends through `WatchSessionStore.logSet(...)` → the phone's existing submit path. Has a "No active
set to log" empty state when there's nothing to log against. Digital Crown routing has a real
interaction constraint worth knowing about: `.focusable(true)` must precede
`.digitalCrownRotation(...)` in the modifier chain or the crown drives the page-swipe instead of
the weight field — this is an implementation detail, not a design one, but it means your frame's
weight-adjustment affordance needs to visually read as crown-adjustable (some kind of crown
affordance/cue), not just a static number.

### 3. Soundboard (`SoundboardView.swift`)
Up to 4 favorite sounds, synced from the phone's `SoundboardFavoritesRepository` (the same source
`GroupSessionLiveView`'s own dock ribbon reads). Tap → local play + broadcast via the phone. Each
tile shows a label (not a raw slug — a fix-wave addition specifically because a raw slug like
"crowd-cheer" read worse at watch scale than a proper name) with transient per-tile
checkmark/error feedback after a tap.

### 4. Ledger glance (`LedgerView.swift`)
Read-only. Two stacked stats: OWED and PAID burpee counts for the current session, sourced from
the same numbers the phone's own penalty banner shows ("YOU OWE N burpees"). No write path at
all — logging a burpee only ever happens phone-side. Falls back to "No active session" when idle.

### Theming — Midnight only, by deliberate scope-trim
`GSWatchTheme.swift` ports only 5 semantic tokens (bg/surface/text/accent/divider) from the full
`GSTheme` token bag, and **only the Midnight palette** — the file's own header comment records
this as a deliberate YAGNI trim at Task 1 review: *"No theme picker or dark/light chrome switching
exists on the Watch... 'Watch UI polish beyond system idioms' is explicitly deferred to Phase D.
If/when a palette choice syncs from the phone... re-port GSPalettes' id->theme lookup... (trimmed
here as YAGNI)."* **This is a decision Phase D needs to make explicitly**, not inherit by
default: should the Watch app support all 4 palettes (requiring phone→watch palette sync over
WatchConnectivity, currently unbuilt) or stay Midnight-only permanently? See sign-offs below.

### HR pill zone colors + boundaries (`hr-pill-zone-color`)
**Deviation:** `hr-pill-zone-color` — *"two REAL canvas frames exist for the HR pill's shape/
placement (frame 2A 'Live — Spotlight', frame 2B 'Live — Roster') but both render exactly ONE
static bpm reading each, so neither demonstrates the zone-COLOR behavior the spec requires.
System-designed color mapping only: a standard 4-color effort-intensity ramp — warmup=blue,
moderate=green, hard=orange, max=red — plain SwiftUI system colors rather than a GSTheme token,
since GSTheme's accent ramp is a single brand hue per palette with no intensity-spectrum
equivalent... Zone numeric boundaries (<60%/60-75%/75-90%/>=90% of max-HR) are ALSO a recorded
assumption... Awaiting designer sign-off on both the color choices and the boundaries."*

This is filed once but is relevant to **two** surfaces: the phone-side roster pill (owned by the
Voice/Live brief — see `heart-rate-pill` there) and, prospectively, any future Watch-side HR
display. **Today, the Watch app displays no heart-rate reading anywhere** — `HeartRateSampler.swift`
only samples and broadcasts FROM the watch; none of the 4 screens above render bpm back to the
wearer. If your zone-color/boundary sign-off is meant to also govern a Watch-side HR glance, that
glance doesn't exist yet and would be new scope for this family, not a redraw.

### Voice mixer sheet's coming-soon toggles — cross-reference only
Your family scope note calls out "the mixer sheet's coming-soon toggles." The voice mixer sheet
itself (`voice-mixer-sheet`) is owned by the Voice/Live brief, not this one — it's a phone-side,
in-session sheet, unrelated to the watchOS target. It's referenced here only as a **design
precedent**: the mixer sheet's two non-functional toggles ("Noise suppression," "Hear my own
voice") are `.disabled(true)` with a "Coming soon" caption and `.opacity(0.6)` dimming specifically
so an operator can tell at a glance they're inert. If any Watch surface needs to show
not-yet-backed functionality (e.g., a future feature placeholder), that's the established idiom to
reuse. See the Voice/Live brief for the full entry; do not treat this as a second copy of that
deviation.

---

## (b) Captures available

**None.** This is the one family where the capture story is a flat no: there is no `#if DEBUG`
catalog seam on watchOS (`CatalogHostView.swift` lives in the iOS target only), no
`ScreenshotTests`-equivalent for the Watch target, and no "watch" reference anywhere in
`.github/workflows/ios.yml`'s screenshot/parity jobs — confirmed by grep before writing this
brief. None of the 4 watch screens has an `app-*.png` file anywhere in the repo, and none has a
`frame-map.json` entry (there's nothing to map to).

Two ways to actually see current state before drawing:
1. **Read the source directly** — all 4 files are short (well under 150 lines each); the
   descriptions in (a) above are drawn straight from them.
2. **Run the watchOS simulator target** locally (`xcodegen` embed, per Task 1's setup) and drive it
   through Xcode Previews — every view file ends in a `#Preview { ... }` block, so each screen is
   individually previewable without a full session.

**This is a prerequisite gap worth raising, not just absorbing**: if Phase D wants the parity
harness to eventually measure Watch screens the way it measures iOS ones, a watchOS capture
mechanism needs to be built first (a new, small infrastructure task, not a design task) — flag
this in your response so it can be scoped alongside your frames rather than discovered later.

---

## (c) Sign-offs pending

1. **All 4 screens + idle state need their first frames** — real, but starting from working code,
   not a blank page. This is this family's primary deliverable.
2. **HR pill zone colors + boundaries** (`hr-pill-zone-color`) — confirm the 4-color ramp
   (blue/green/orange/red) and the %-of-max-HR boundaries (60/75/90), and clarify whether this
   sign-off is meant to extend to a future Watch-side HR display (new scope) or stays phone-only
   (no Watch action needed).
3. **Midnight-only vs. 4-palette Watch theming** — an explicit product/design decision, not an
   engineering default to leave alone. If 4-palette is wanted, phone→watch palette sync
   (WatchConnectivity `applicationContext`) becomes a new build item, not a Phase D design item —
   flag it forward if so.
4. **Watch capture-harness gap** — not a sign-off exactly, but needs acknowledgment: nothing here
   is measurable by the parity harness until a capture mechanism exists.

---

## (d) Constraints

- **Tiny-screen laws.** No project-specific "tiny-screen constraints" document exists yet — this
  family is the first to need one. The codebase's own working term for its current discipline is
  "tiny-screen honesty": every screen fits without scrolling, `VStack`/`Group` only (never
  `ScrollView`, since it fights the page-swipe gesture), 2-4 lines of real content per screen,
  short caption-weight type throughout. Apple Watch case sizes in the current device lineup are
  41mm/45mm (and the Ultra's 49mm) — your frames should account for the smaller size as the
  binding constraint, same as the app already does (nothing here assumes the larger case).
- **GSWatchTheme, not GSTheme.** The Watch target intentionally does NOT import the full iOS
  `GSTheme.swift` (different platform SDK — watchOS has no UIKit-adjacent dependencies the full
  token bag drags in). It has its own trimmed 5-token `GSWatchTheme`. If your sign-off (c.3) adds
  palettes, that's an addition to `GSWatchTheme`, transcribed from `GSTheme`'s existing hex values
  — not a new token system.
- **`.verticalPage` TabView, 4 peer screens.** Don't design a navigation model that implies
  parent/child hierarchy (e.g., a "back" affordance) — the existing shape is deliberately flat.
- **The parity harness cannot measure your frames yet** (see (b) above) — your frames are still
  authoritative and still worth producing to spec, but won't score in a report until the capture
  gap is closed.
- **Frame format:** `dc-runtime`/`ios-frame.jsx` (`docs/design/ios-frame.jsx`) is the iOS phone
  frame component — it does not model a Watch case. Confirm with whoever owns the canvas pipeline
  whether a Watch-shaped frame wrapper needs to be built, or whether your Watch frames should ship
  as a different format entirely (this is a real open question, not a constraint to assume away).

---

## (e) Priority order

There is no phase/task chronology to rank by within this family the way other briefs have —
`hr-pill-zone-color` is the only formally-recorded deviation (Phase W Task 5), and the 4 core
screens have no recorded entries at all (the process gap named above). Recommended order:

1. **Whose-turn** (root screen, most-viewed, and the one with the most states — live/ended/idle —
   to get right)
2. **Log-set** (has the one nontrivial interaction question — how to visually cue Digital Crown
   adjustability)
3. **Soundboard** and **Ledger** (simplest, most self-contained — the two 4th-and-5th-priority
   screens across all six families' combined backlog would be reasonable to batch together)
4. **HR pill zone colors + boundaries sign-off** — can run in parallel with the above; it doesn't
   block any of the 4 screen redraws (no HR display exists to gate on it), but should not be
   deferred past this family's sprint since the Voice/Live family is also waiting on it for the
   phone-side roster pill.

Per the overview doc's family-sequencing rationale, Watch is one of the two families
recommended to run **last** (with Campaigns/Venues) — the roadmap's "design once, not twice"
logic still holds even though the app itself is already built: nothing here is expected to change
shape before then, but sequencing it after the smaller families lets the designer's system
vocabulary mature first, so the Watch frames inherit settled patterns rather than setting new ones
that later families would need to retrofit.
