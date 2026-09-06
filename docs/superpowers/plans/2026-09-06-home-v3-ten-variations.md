# Home v3 — ten variations to play with, built in the catalog

Owner (2026-09-05, after seeing Home v2 A/B rendered): "there's goodness in both … the tile version of
the start workout and check-in wins over the striped version … strip the detail sessions from the bottom
of the training calendar and have those exposed on the page that is brought up whenever you click
anywhere within the training calendar … give me like 10 different mock ups."

Same method as Home v2 (`docs/superpowers/plans/2026-09-05-home-v2-catalog.md`): catalog-only compositions
from shared pieces in `Features/Home/V2/`, rendered by CI, no production wiring. Base: master (PR #29).

## Fixed decisions (do not vary)

- **Top row is A's**: `HomeOneButton` full width; when the state is a crew state, the quiet
  `START SOLO WORKOUT` pill with the burpee widget beside it. B's today card is retired.
- **Calendar card loses its folded rows.** Add `showsAppointments: Bool = true` to `HomeCalendarCard`;
  every v3 composition passes `false`. The header keeps `TRAINING CALENDAR`, the `{n} UPCOMING` pill and the
  `+`; add a chevron at the header's trailing edge so the whole card reads as a door (tap anywhere → the
  calendar & scheduling page, where the itinerary is written out). Production untouched.
- Greeting header and join-with-code card as in v2. Every composition ends with join-with-code unless
  noted.
- Five compositions render the crew-night world, five the solo-day world, alternating, so both button
  states appear across the set.

## New pieces (Task 1) — `Features/Home/V2/`, fixture values verbatim

| Piece | Form | Copy |
|---|---|---|
| `HomeUpNextStrip` | strip (surface, 14 pt) | kicker `NEXT · SAT 9:00 AM` · `Lower B with Legs Crew` · chevron |
| `HomeLastLiftTile` | tile (extruded) | kicker `LAST LIFT` · `Push A` 22 pt · `Wed · 7,240 lb · 1 PR` |
| `HomePRWatchTile` | tile | kicker `PR WATCH` · `Bench 205` 22 pt · accent line `210 is within reach` (an invitation, so accent is allowed) |
| `HomeRecoveryStrip` | strip | two chips `BACK · LEGS` (green, `FRESH`) and `CHEST` (muted, `TENDER`) · line `Back and legs are fresh. Chest is still tender.` |
| `HomeMilestoneTile` | tile | kicker `LIFETIME` · `1.31M lb` 22 pt · `29% of Mount Fuji` · a 3-segment progress bar at 29% in the plate blue `#2F6FD0` |
| `HomeBodyWeightTile` | tile | kicker `BODY WEIGHT` · `180.4 lb` 22 pt · `−5.8 since July` |
| `HomeCrewPulseStrip` | strip | avatar `DA` with a green presence ring · `Dana is lifting now` · `Push Crew · tonight 5:00 PM` · chevron |
| `HomeWeekPlanStrip` | strip | kicker `THIS WEEK` · three chips `TUE PUSH ✓` (done, text) · `THU PULL ✓` (done) · `SAT LEGS` (next, accent ring) |

Tiles are 12 pt inner padding, min height 104 pt, paired in a two-column row with 10 pt gap (the v2
`tiles2` row). Strips are `surface`-filled, 14 pt radius, 10 pt top margin (rule 1: strips are not
cards). Default text everywhere; green only for FRESH / done; gold only on the streak number.

## The ten compositions (Task 2) — catalog ids and order, top to bottom

Top row (fixed) is implied at the start of each.

| id | world | below the top row |
|---|---|---|
| `home-v3-01-tiles` | crew | `[HomeStreakTile \| HomeCoachTile]` · calendar · `[HomeLastLiftTile \| HomePRWatchTile]` · join code |
| `home-v3-02-strips` | solo | `HomeWeekStrip` · `HomeCoachLine` · `HomeUpNextStrip` · calendar · join code |
| `home-v3-03-week-tiles` | crew | `HomeWeekStrip` · `[HomeCoachTile \| HomeLastLiftTile]` · calendar · join code |
| `home-v3-04-tile-line` | solo | `[HomeStreakTile \| HomePRWatchTile]` · `HomeCoachLine` · calendar · `HomeUpNextStrip` |
| `home-v3-05-recovery` | crew | `HomeWeekStrip` · `HomeRecoveryStrip` · `HomeCoachLine` · calendar · join code |
| `home-v3-06-milestone` | solo | `[HomeStreakTile \| HomeMilestoneTile]` · `HomeCoachLine` · calendar · join code |
| `home-v3-07-body` | crew | `HomeWeekStrip` · `[HomeBodyWeightTile \| HomePRWatchTile]` · `HomeCoachLine` · calendar |
| `home-v3-08-crew` | crew | `[HomeStreakTile \| HomeCoachTile]` · `HomeCrewPulseStrip` · calendar · join code |
| `home-v3-09-plan` | solo | `HomeWeekPlanStrip` · `[HomeStreakTile \| HomeCoachTile]` · calendar · join code |
| `home-v3-10-minimal` | solo | `HomeWeekStrip` · `HomeCoachLine` · calendar · `HomeUpNextStrip` |

One SwiftUI file `HomeV3Variations.swift` holding ten small composition views is fine (they are
assemblies, not logic); or one file per view if the implementer prefers. Each is a `ScrollView` with the
v2 spacing.

## Task 3 — Catalog contract

Ten `CatalogScreen` cases with the ids above, ten builders, ten `testCatalog…` captures, ten
`frame-map.json` entries (point at the same unclaimed proof-frame range the v2 ids used, sequentially),
registry list + count, `FLOOR` 75 → 85. One commit.

## Global constraints

As Home v2: Swift compiles only in CI; production `HomeView.swift` / `TrainingCalendarWidget.swift`
untouched; fixtures only; four-part contract per id; one commit per task; the attribution trailer
(`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
`Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni`).

## Verification (controller)

CI artifact → all ten present and dark, count 85 → five two-up cards (01|02, 03|04, 05|06, 07|08, 09|10)
→ owner.
