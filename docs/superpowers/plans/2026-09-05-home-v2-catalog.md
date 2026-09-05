# Home v2 — both arrangements built as real SwiftUI in the catalog

Owner (2026-09-05): "give me mockups for both. I will assess when I see them implemented by themselves or a
mix of the two." So: build Home v2 **A (tiles)** and **B (strips)** as catalog-only screens with fixture
data, render them through the CI screenshot pipeline, and hand the owner real frames. Nothing is wired
into production `HomeView` until the owner picks (A, B, or a mix — the pieces are shared so a mix is a
third composition, not a rewrite).

Design authority, in order: the owner's round-9 direction (docket "Owner round 9"), the v7 proof
(`Home A · tiles`, `Home B · strips`, the calendar & scheduling page — artifact
https://claude.ai/code/artifact/33a36a70-aff4-4413-98c4-4eb1768fb50f, section "Home, v2"), the design
language (`docs/superpowers/specs/2026-09-05-design-language.md`, rules 1–5, 7), and the page audit B5.

Worktree: `G:/Projects/GymSync-wt/home-v2`, branch `feat/home-v2-catalog` off master.

## Global constraints

- Swift compiles ONLY in CI. Read every file you touch in full; mirror `HomeView.swift` and
  `TrainingCalendarWidget.swift` idioms; keep production files untouched except where a task says so.
- **Production Home is not changed.** New views live in `Features/Home/V2/` and are reachable only through
  `CatalogHostView`. No `HomeView.swift` edits.
- Reuse, don't redraw: the extruded card idiom (`.gs3DCard` / `.gs3DCardStyle`), `GSSectionHeader`, the
  existing streak slot grid, `TrainingCalendarWidget`'s month dot field (extract it if it is `private`, by
  the smallest change that keeps production behaviour identical), the join-code card, the burpee widget.
- Fixture data only; no repository calls in the new views (they take plain value inputs).
- Every new catalog id ships the four-part contract in ONE commit: enum case + builder, the
  `CatalogScreenTests` documented-id list and count, a `ScreenshotTests.testCatalog…` capture, a
  `docs/design/frame-map.json` entry. Raise the ios.yml `FLOOR` by the number of new captures.
- One commit per task. Trailer on every commit:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni`.

## The one button — shared component, both variants

`HomeOneButton(state:)` with these states and exact copy (rule 5). It never starts a workout itself;
each state names the tap's destination in a comment (the destination is out of scope for the catalog).

| State | Face | Line 1 | Line 2 (small caps) |
|---|---|---|---|
| `.startRoutine(name)` | accent | `START · PULL A` | `LOCKED AND LOADED · OPENS THE START SCREEN` |
| `.startWorkout` | accent | `START A WORKOUT` | `ROUTINES · FREESTYLE · BUILD ONE` |
| `.checkInOpens(time)` | raised face | `CHECK-IN OPENS 4:40` | `YOU'RE IN` |
| `.checkIn(crew, routine, time)` | gold gradient (`0xF6C945→0xDCA426`, ink `0x2A1D02`) | `CHECK IN` | `PUSH CREW · PUSH A · 5:00 PM · OPEN NOW` |
| `.joinSession` | accent | `JOIN THE SESSION` | `STARTED 4:52 · YOU'RE LATE` |

Height 57 pt, lip 7 pt, caps, tabular numerals. When the state is a crew state, the quiet
`START SOLO WORKOUT` pill (48 pt, raised face) sits under it, with the burpee widget beside the pill when
debt exists — exactly production's current row.

## Shared pieces (Task 1)

`Features/Home/V2/`:
- `HomeOneButton.swift` (above).
- `HomeCoachTile.swift` — the word `Coach` at 24 pt, one state sentence at 12 pt, an accent count badge in
  the corner when something waits. Extruded card, tappable.
- `HomeCoachLine.swift` — the strip form: `CO` glyph tile, `Coach:` + one sentence, chevron; `surface`
  fill, 14 pt radius (rule 1: strips are not cards).
- `HomeStreakTile.swift` — kicker `STREAK`, the number in **gold** at 40 pt (rule 2), the slot grid,
  `3/4 DAYS THIS WEEK`.
- `HomeWeekStrip.swift` — the strip form: gold streak number at the head, seven day chips (done = text,
  today = ring, planned = accent ring), `4/4 · GOAL MET` at the tail.
- `HomeCalendarCard.swift` — header `TRAINING CALENDAR` + `{n} UPCOMING` pill + a `+` circle; the three
  month dot fields; then the **folded appointments**: up to three compact rows (`Today 5:00 PM · PC · Push A ·
  Push Crew · IN ›`), each 44 pt; whole card tappable (rule "anything on a timeline"). Reuse
  `TrainingCalendarWidget`'s dot field.
- `HomeV2Fixtures.swift` — one fixture world: greeting `Smola`, Friday Sep 5, crew session tonight
  (Push Crew · Push A · 5:00 PM, Dana checked in, Sam on the way), streak 12, 3/4 this week, Coach line
  `bench stalled twice at 205. Take 185 × 8 today, then we climb.`, calendar dots for Aug/Sep/Oct, three
  upcoming rows, 12 burpees owed, and a second state for the solo day (Pull A from the block, week 2 of 6,
  no time set, 4/4 goal met).

## Task 2 — `HomeV2TilesView` (A)

Order: greeting header (reuse production's) → one button (crew state, gold CHECK IN) → `START SOLO
WORKOUT` pill + burpee widget → row of two tiles: `HomeStreakTile` | `HomeCoachTile` → `HomeCalendarCard`
→ join-with-code card. Fixture: the crew-tonight world.

## Task 3 — `HomeV2StripsView` (B)

Order: greeting → **today card** (kicker `TODAY · FROM YOUR BLOCK` + `WEEK 2 OF 6` pill, title `Pull A`,
line `5 exercises · about 50 min · no time set`, the one button in `.startRoutine("PULL A")`, small line
`Something else? Start solo workout ›`) → `HomeWeekStrip` → `HomeCoachLine` → `HomeCalendarCard` →
join-with-code. Fixture: the solo-day world.

## Task 4 — Catalog ids, captures, floor

`home-v2-tiles`, `home-v2-strips` (and, so the owner can compare states, `home-v2-tiles-solo-day` =
A with the solo-day fixture, `home-v2-strips-crew-night` = B with the crew fixture). Four ids, four
captures, four-part contract each, `FLOOR` 71 → 75. Register each under `CatalogScreen` next to
`soloLiveSet`.

## Verification (controller)

Push, CI, download the artifact, verify the four captures render dark with the gold button on the crew
states, compose a two-up card (A | B) and a two-up of the swapped states, send to the owner. The owner
picks A, B, or a mix; only then does a production wiring plan get written.
