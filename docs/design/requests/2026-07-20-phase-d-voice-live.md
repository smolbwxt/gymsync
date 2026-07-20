# Phase D Designer Brief — Voice/Live

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Voice/Live (coach mark, connected toast, mixer sheet, transmit hero/80pt dock, HR
pills on roster, plate-math disclosure, offline syncing chip + replay-failure notice)
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md`.

---

## Read this first

This family is unusual among the six: **five of its eight deviations already have real designer
frames** — not system-designed placeholders. They're just not integrated into the canvas pipeline
yet. The designer delivered a follow-up canvas section (`docs/design/sections/
2026-07-live-voice.dc.html`, 2026-07, "PTT polish") with real frames for the coach mark, connected
toast, mixer sheet, and both transmit-hero variants — but that file was never pulled into
`docs/design/frame-map.json` the way every other `voice-*` entry (frames 47-50) was. Your first
job on this family may be **DesignSync integration**, not fresh drawing. The remaining three
items (plate-math, offline-syncing chip + replay-failure notice, HR pills on roster) genuinely
have no frame and need one from scratch.

---

## (a) Screens — current state

### Voice coach mark (`voice-coach-mark`)
**Deviation:** *"designer follow-up frame, docs/design/sections/2026-07-live-voice.dc.html frame 3
('FIRST-RUN COACH MARK') — a real authoritative frame, not system-designed, but this section file
is a separate follow-up canvas... not yet merged/numbered into the master canvas frame-map.json
uses for every other voice-* entry (frames 47-50); pending DesignSync integration to get its own
numbered frame-map entry. Catalog capture shows the coach mark bubble alone (GSVoiceCoachMark)
stacked above a forced-.connected(.muted) PTTDockRow — the frame's own dimmed live-session
background chrome... is that screen's own content, not this component's concern."*

### Voice connected toast (`voice-connected-toast`)
**Deviation:** *"same designer follow-up frame as voice-coach-mark above (frame 3's top banner) —
real frame, pending the same DesignSync/frame-map integration. Catalog capture shows
GSVoiceConnectedToast alone with a fixture group name."*

### Voice mixer sheet (`voice-mixer-sheet`)
**Deviation:** *"designer follow-up frame, frame 4 ('VOICE MIXER SHEET') — real frame, pending the
same DesignSync/frame-map integration. Per-participant volume/mute IS real (VoiceRoomService.
setLocalMute, wired through LiveKit's client-side per-participant playback volume). The mic-level
meter and both toggles ('Noise suppression', 'Hear my own voice') are honestly NOT backed by
anything real: no input-level metering API exists, no noise-suppression/monitor-toggle control
exists anywhere — rendered per the frame but chrome-only pending a real backing API... fix wave 1
(Finding F5): a code comment alone wasn't a strong enough signal — the two toggles read as
indistinguishable from real controls. Both are now .disabled(true) with a 'Coming soon' caption
under each title... and the whole toggle block is dimmed (.opacity(0.6)) — a deviation from the
frame's literal fully-opaque toggle rows, deliberately, so an operator can tell at a glance these
two are inert without reading source."*

This is the **"mixer sheet's coming-soon toggles"** your family scope names explicitly (and which
the Watch brief cross-references as a reuse precedent). The disabled/dimmed/captioned treatment is
a deliberate honesty deviation from the frame as drawn — confirm whether you want to bless that
deviation permanently, or whether a real mic-level-metering API should be built so the frame can
ship as originally drawn.

### Voice mixer entry point (`voice-mixer-entry-point`)
**Deviation:** *"no canvas frame depicts WHERE the voice mixer sheet opens from (the frames show
only its own content) — system-designed: a bordered icon-button (slider.horizontal.3) in
LobbyView's toolbar / GroupSessionLiveView's headerBar, styled after each screen's own existing
chatButton icon-button, shown only while voice is connected."*

Unlike its four siblings above, this one is genuinely undesigned (no frame anywhere shows the
entry point) — same headerBar crowding concern as `session-chat` in the Social brief (this icon,
the new session-chat icon, the soundboard toggle, and PTT controls are all competing for the same
real estate). Coordinate your redraw with the Social brief's header-crowding question rather than
solving it twice, independently, for two different icons in the same bar.

### Voice transmit hero (`voice-transmit-hero`)
**Deviation:** *"designer follow-up frames 1 ('Talking · hold') and 2 ('Mic open · tap'),
docs/design/sections/2026-07-live-voice.dc.html — real frames, pending the same DesignSync/
frame-map integration. PTTDockRow's transmitHero renders the reusable core only... Waveform reuses
GSTalkingBars (3 bars) rather than matching the frames' fuller 11-bar waveform exactly — same
component, larger sizing, not a second bespoke waveform view. The voice-transmitting catalog id
(existing) captures the toggled-open/hands-free variant (frame 2); the held/'YOU'RE LIVE' variant
(frame 1) needs a live press to reach and has no separate catalog id."*

This is your family's **"transmit hero/80pt dock"** item. Two things to resolve: (1) the
GSTalkingBars 3-bar vs. frame's 11-bar waveform gap — bless the simplified 3-bar version, or
request the fuller waveform be built; (2) frame 1 (the held/"YOU'RE LIVE" variant) has no catalog
capture id today — request one from engineering if you need a static reference to design against,
since it currently requires a live press-and-hold to reach.

### HR pills on roster (`heart-rate-pill`)
**Deviation:** *"catalog capture for GSHeartRatePill — component-alone capture, same idiom as
voice-coach-mark/voice-connected-toast above (the pill's real embedding context,
GroupSessionLiveView's roster grid + spotlight hero, has no catalog-fixture seam)... Also
generalizes BEYOND frame 2B: that frame shows the HR pill only on the one 'LIFTING NOW' roster
card... nothing in the design restricts HR broadcast to whoever currently holds the turn (any
participant with share_heart_rate on broadcasts continuously), so GroupSessionLiveView.rosterCard
renders this pill for ANY roster card with live data... The catalog capture itself is a small
gallery (all 4 zone colors + the nil-zone fallback + both caption variants) in one screenshot...
BEHAVIOR (not visual), gate M-3: master spec :1217 specs a disconnect state ('—' + small
unpaired-watch icon) for a sharer whose watch drops; the T5 brief specified fade/remove instead,
which is what's implemented (HeartRateFreshness.isFresh gate, >15s purge). No dash/icon
placeholder state exists. Phase D decides which to keep."*

Two distinct decisions bundled in this one entry: (1) the visual zone-color mapping itself is
owned jointly with the Watch brief's `hr-pill-zone-color` — see that entry there, don't duplicate
the sign-off; (2) **gate M-3, a genuine behavior fork** — spec says a disconnected watch should
show a dash + unpaired icon, the build instead fades/removes the pill after 15 seconds of
staleness. This is explicitly logged as "Phase D decides which to keep" — a real product decision
this brief is asking you to make, not just a visual redraw.

### Plate-math disclosure (`plate-math`)
**Deviation:** *"the log-set sheet's plate-loading disclosure — master spec names 'Plate math
(target weight + bar weight → plate stack)' explicitly but no canvas frame depicts a plate-math
affordance anywhere... System-designed: a compact icon+label+chevron 'Plates' toggle button...
sits directly below the existing Reps/Weight stepper row inside LogSetSheet, one shared
implementation reused by both the solo and group-penalty presentations. The expanded disclosure
renders the per-side plate breakdown as GSTag(style: .outline) chips plus a remainder caption when
the target isn't exactly reachable. Hidden entirely for empty/invalid weight... Fix wave 1
(inline-card extension) promoted the expanded disclosure body itself out of LogSetSheet into the
free-standing PlateStackDisclosure view specifically so GroupSessionLiveView's inline 'LOG THIS
SET' card could render the SAME disclosure directly inline — a THIRD presentation... same
component, same hidden/inert-for-empty/invalid/non-positive-weight gate, same deviation."*

This is your family's **"plate-math disclosure"** item — note it now has **three** presentations
(solo LogSetSheet, group-penalty LogSetSheet, and GroupSessionLiveView's inline "LOG THIS SET"
card), all sharing one `PlateStackDisclosure` component. Your frame needs to work in all three
contexts, not just one.

### Offline syncing chip + replay-failure notice (`offline-syncing-indicator`)
**Deviation:** *"a queued-but-not-yet-confirmed set log needs a small visual signal... no canvas
frame depicts an offline/syncing state on either [surface]. System-designed: reuses the exact
GSTag(style: .outline) chip idiom... for the group feed row ('syncing' tag alongside penalty/
failed); the solo table's checkmark-column instead swaps to a small rotate-arrows glyph (SF Symbol
arrow.triangle.2.circlepath)... Fix wave 1 adds a second, related-but-distinct visible state:
[a] new sibling component, GSInlineNoticeBanner... rendered with copy 'Saved on this phone. Your
turn will pass once you're back online.' ... Debt-zero sprint item 2 adds a THIRD, distinct
surface reusing the SAME GSInlineNoticeBanner: OfflineSetLogQueue.lastPermanentFailure... HomeView
now renders a dismissible notice... copy 'A set couldn't sync and was removed — check your session
history.', exclamationmark.circle... Dismissing calls OfflineSetLogQueue.clearLastPermanentFailure()."*

This is your family's **"offline syncing chip + replay-failure notice"** item, and it's actually
**three** distinct visual states layered into one deviation entry over three separate work
sessions:
1. The **syncing chip** itself — a `GSTag(style: .outline)` "syncing" tag (group feed row) / a
   rotating-arrows glyph (solo table checkmark column).
2. The **"saved locally, will sync" notice** — `GSInlineNoticeBanner`, checkmark glyph, no retry
   CTA, shown in the live group session when a queued set skips the normal turn-advance.
3. The **replay-failure notice** (the "+ replay-failure notice" your scope explicitly names) —
   same `GSInlineNoticeBanner` component, different icon (`exclamationmark.circle`) and dismiss
   affordance, shown on HomeView when a queued set is permanently dropped (RLS denial, validation
   failure, exhausted retry).

None of the three has ever been fixture-captured (see (b) below) — all three depend on a live
`SwiftData`-backed offline queue that the debug catalog has no seam for.

---

## (b) Captures available

Catalog ids (`CatalogHostView.swift`, `#if DEBUG`) — component-alone captures, matching the idiom
this family established:

| Screen | Capture id |
|---|---|
| Voice idle/connecting/transmitting/mic-denied/unavailable (baseline states, frames 47-50, already mapped) | `voice-idle`, `voice-connecting`, `voice-transmitting`, `voice-mic-denied`, `voice-unavailable` |
| Voice coach mark | `voice-coach-mark` |
| Voice connected toast | `voice-connected-toast` |
| Voice mixer sheet | `voice-mixer-sheet` |
| HR pill (gallery: all 4 zone colors + nil fallback + both caption variants in one shot) | `heart-rate-pill` |
| Plate-math disclosure | `plate-math` |

**Not capturable via the debug catalog at all:**
- `voice-mixer-entry-point` — it's a toolbar icon on real screens (LobbyView/GroupSessionLiveView),
  not an isolated component; view via seeded navigation with voice connected.
- The held/"YOU'RE LIVE" transmit-hero variant (frame 1) — `voice-transmitting` only captures the
  toggled-open variant (frame 2); the held variant needs a live press-and-hold, unreachable by a
  static harness capture today.
- `offline-syncing-indicator`'s all three states — explicitly judged disproportionate to fixture
  (each depends on a live `SwiftData` queue inside a full session flow); covered by hermetic tests
  (`GymSyncTests/OfflineSetLogQueueTests.swift`) and device QA instead. Request device-QA
  screenshots if you need a visual reference, not a catalog capture.

Checked-in `app-*.png` files exist for the five baseline voice states
(`.superpowers/parity/app-ci/app-voice-{idle,connecting,transmitting,mic-denied,unavailable}.png`)
— these are current and frame-mapped (47-50). None of this family's other seven capture ids has a
checked-in `app-*.png` yet (they all postdate every capture currently in the repo) — request a
fresh CI screenshot run.

---

## (c) Sign-offs pending

1. **DesignSync integration for the five real frames** (coach mark, connected toast, mixer sheet,
   both transmit-hero variants) — pull `docs/design/sections/2026-07-live-voice.dc.html` into the
   main canvas pipeline and number it into `frame-map.json` alongside frames 47-50. This may be
   the fastest win in the entire Phase D backlog: the design work is done, only integration
   remains.
2. **Mixer sheet toggles** — bless the disabled/dimmed/"Coming soon" treatment permanently, or
   scope a real mic-level-metering + noise-suppression API to back the frame as originally drawn.
3. **Transmit hero waveform** — bless GSTalkingBars' 3-bar simplification vs. the frame's 11-bar
   waveform, or request the fuller version be built.
4. **HR pill disconnect behavior (gate M-3)** — spec'd dash+icon vs. built fade/remove-after-15s;
   pick one. Joint with the Watch brief's zone-color/boundary sign-off but this specific fork is
   owned here.
5. **Plate-math disclosure** — first frame, must account for all three presentation contexts.
6. **Offline syncing + replay-failure notices** — first frame for all three states; also decide
   whether any deserve a catalog capture id despite the fixture-cost judgment call recorded three
   times now (Phase O Task 3, fix wave 1, debt-zero sprint) — if Phase D repeatedly needs to
   reference these states, that judgment call may be worth revisiting.
7. **Voice mixer entry point** — coordinate with the Social brief's session-chat header-crowding
   question; both icons compete for the same `headerBar` real estate.

---

## (d) Constraints

- **GSTheme token system**, four palettes — see `GymSyncApp/GymSync/DesignSystem/GSTheme.swift`.
  Note `hr-pill-zone-color`'s ramp deliberately uses plain SwiftUI system colors, not GSTheme
  tokens, because no palette has an intensity-spectrum equivalent to a single accent hue — the
  same precedent `YouTabView.deleteAccountRow` already set for non-themed color use. If you want a
  themed zone ramp instead, that's a new token-system decision, not a redraw.
- **Reuse `GSTag(style: .outline)`, `GSInlineErrorBanner`/`GSInlineNoticeBanner`, `GSTalkingBars`,
  `GSExpandingRing`** — all already established in this family's own screens; extend, don't
  duplicate.
- **`PlateStackDisclosure` and `GSInlineNoticeBanner` are shared components** across multiple call
  sites (three and three, respectively) — design once, applies everywhere.
- **Frame format:** `dc-runtime`/`ios-frame.jsx` (`docs/design/ios-frame.jsx`) for anything new.
  The five already-drawn frames in `2026-07-live-voice.dc.html` need verification that they're
  already in this format before integration — if they predate the dc-runtime convention, they may
  need re-authoring, not just re-numbering (this bit the team once: the 2026-07-13 canvas
  truncation/render-limitation incident, `.superpowers/sdd/progress.md`).

---

## (e) Priority order

By build-task chronology, oldest first:

1. **`plate-math`** (Phase H Task 4) — oldest, and its own report already resolved a fix-wave
   extension (three presentations); ready for a frame today.
2. **`offline-syncing-indicator`** (Phase O Task 3, its earliest of three layered additions) —
   second-oldest; the replay-failure notice (its newest layer, debt-zero sprint) is the most
   recently added but shares the same underlying component, so design all three together anyway.
3. **`voice-coach-mark`, `voice-connected-toast`, `voice-mixer-sheet`, `voice-mixer-entry-point`,
   `voice-transmit-hero`** (Phase O Task 5, the 3e follow-up queue) — the DesignSync-integration
   items. Despite being "newer" by task number than plate-math/offline, these should likely move
   **first in execution** even though they rank lower here by strict chronology, since four of
   the five need no new drawing at all — see sign-off (c.1). Sequence by effort, not just age.
4. **`heart-rate-pill`** (Phase W Task 5) — newest; blocked on the Watch brief's joint zone-color
   sign-off before it can fully close, but the gate-M-3 disconnect-behavior decision can proceed
   independently.

This family sits in the middle of the overview's recommended family order — not first (unlike
Stats' oldest-of-all `stattile-*` cluster), not last (unlike Watch/Campaigns) — but its DesignSync
integration item (c.1) is arguably the single fastest win across all six briefs and could be
pulled forward opportunistically regardless of where this family lands in the overall sequence.
