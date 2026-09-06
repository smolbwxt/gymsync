# Home v3 addendum — Coach's targets strip on variation 08

Owner (2026-09-06): "variation 8 of the Home Screen is great. Maybe above the join with code, we display
the weekly muscle group goals, or whatever goal the coach is tracking as a strip?" Controller's take:
yes; make it "Coach's target this week" (renders whatever the current block tracks — per-muscle sets by
default), and render it in TWO placements so the fold decides: (a) above the calendar, under the crew
pulse; (b) above join-with-code, as the owner phrased it.

Same method and constraints as `2026-09-06-home-v3-ten-variations.md` (catalog-only, fixtures only,
production untouched, four-part contract, trailer). Base: master after PR #31.

## New piece — `HomeCoachTargetsStrip` (`Features/Home/V2/`)

Strip form (`surface` fill, 14 pt radius, the v3 strip spacing). Content:

- Kicker row: `THIS WEEK · COACH'S TARGETS` on the left; on the right a small muted `1 SESSION LEFT`.
- One row of four **target chips**, equal width, 8 pt gap. Each chip: group name as a 9 pt caps kicker
  (`CHEST`), a 4 pt-tall meter (track `surface2`, fill `text`; fill = done ÷ target, capped at 1), and a
  fraction `8/12` in 12 pt tabular numerals. States:
  - **met** (done ≥ target): fraction and meter fill in green (`Color.gsSuccess` if it exists on this
    branch, else the canonical `0x2FA45C`), the name stays default text.
  - **next** (the group furthest behind, exactly one): the chip carries a 1.5 pt accent ring (the same
    "next" idiom as the week strip's today chip). The owner trains by "what's fresh, what's next".
  - default: text/muted.
- The strip is tappable (chevron at the trailing edge of the kicker row); destination = the per-muscle
  week on Stats (comment only — catalog has no navigation).

Fixture (`HomeV2Fixtures`), one value per world, both the same targets: chest 8/12, back 10/12,
legs 6/12 (**next**), arms 8/8 (**met**). The sessions-left read is that world's
`weeklyGoal - daysDone` and nothing else: `1 SESSION LEFT` on the crew night (3 of 4 in the bank),
`0 SESSIONS LEFT` on the solo day (4 of 4, met).

> Corrected 2026-09-06, during implementation, from the drafted `2 SESSIONS LEFT` / `1 SESSION LEFT`.
> Both compositions below put this strip on the same page as `HomeStreakTile`, which states the same
> week as a fraction; a drafted `2` beside a tile reading 3/4 would have made the frame tell two
> stories about one week — the defect round 1 caught on UP NEXT. `GOAL MET` was considered for the
> solo value and rejected: that is `HomeWeekStrip`'s tail and means the SESSION goal, whereas the goal
> in view on this strip is Coach's targets, three of which are unmet on the same row.

## Two compositions

Both are variation 08 with the strip inserted:

| id | world | below the top row |
|---|---|---|
| `home-v3-08a-targets-above-calendar` | crew | `[streak tile \| coach tile]` · crew pulse strip · **targets strip** · calendar · join code |
| `home-v3-08b-targets-above-join` | crew | `[streak tile \| coach tile]` · crew pulse strip · calendar · **targets strip** · join code |

## Contract

Two ids, two builders, two captures, two frame-map entries, registry list + count (71),
`FLOOR` 85 → 87. One commit for the piece + fixtures + plan file, one for compositions + contract.
