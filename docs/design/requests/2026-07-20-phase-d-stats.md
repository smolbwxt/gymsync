# Phase D Designer Brief — Stats

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Stats (streak card, body-weight card + log sheet, trend charts, activity feed, stat
tiles)
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md`.

---

## Read this first

This family contains the **oldest unresolved items in the entire Phase D backlog.** The three
`stattile-*` deviations were recorded in Phase U (the "Unbuilt design frames" phase), which ran
before every other phase whose deviations appear in this set of briefs — before Streaks, before
Social finishers, before Moderation, before Discover, before everything. They've been sitting
since before this project's fourth phase of eight. Prioritize accordingly.

---

## (a) Screens — current state

### Stat Tiles states (`stattile-loading`, `stattile-error`, `stattile-empty`)
**Deviations** (all three share the same reason, condensed):
*"Catalog capture shows ONE forced state; canvas frame 41 is a four-state sheet — a constant
structural offset is expected. Per-state fidelity verified in review (copy byte-exact)."*

Canvas frame 41 ("Stat Tiles states") already exists and depicts all four states (loaded/loading/
error/empty) on one sheet. The app captures each state as a separate screenshot (three catalog
ids, one per non-happy-path state — loaded is the default/happy path and isn't in this deviation
set at all). This is **not** an undesigned screen — frame 41 exists and copy has already been
verified byte-exact against it. What's flagged is a structural offset: comparing ONE app state
against a FOUR-state sheet always produces a nonzero score, by construction, no matter how
faithful the app is. This is closer to a **harness methodology gap** than a design gap — read it
that way, and consider whether frame 41 should be split into four separate single-state frames
(one per `stattile-*` catalog id) so the comparison is apples-to-apples. That's a legitimate thing
to propose back to engineering, not something you need to solve by redrawing.

### Stats tab (`tab-stats`) — streak card + body-weight card, two separate extensions
**Deviation:** `tab-stats` — condensed across two extensions:
- *Phase S Task 5 adds: current + longest streak tiles (`user_streaks`) — "a system-designed
  addition (GSCard/GSSectionHeader/GSStatTile idiom, matching the weekly-volume/recent-PRs card
  rhythm already on this screen; flame glyph for a live streak) with no canvas frame of its own
  yet. Awaiting a designer frame."*
- *Phase H Task 3 adds: a "Body Weight" card below Recent PRs — "a GSSectionHeader + '+ Log'
  button (mirrors RoutinesListView.yourRoutinesHeader's '+ New' shape) above the reused
  TrendChartView (same component ExerciseHistoryView's Est. 1RM trend already uses) — extends this
  entry rather than opening a new one."*

So the Stats tab, top to bottom, now has (in addition to whatever the original canvas frame 3
showed): a streak card (current + longest, flame glyph, GSCard/GSStatTile shape) and a Body Weight
card (GSSectionHeader + "+ Log" button + a `TrendChartView` — the same trend-chart component
already used elsewhere for Est. 1RM). Both additions reuse existing component idioms; neither has
ever had a canvas frame.

**This screen is also where the "trend charts" and "stat tiles" parts of your family scope live
structurally** — the Body Weight card's chart IS the trend-chart surface (reused, not new), and
the streak/PR/volume tiles on this screen ARE the stat-tile surface referenced above.

### Body-weight log sheet (`body-weight-log`)
**Deviation:** `body-weight-log` — *"the Stats 'Body Weight' card's log-entry sheet
(body_weight_logs)... System-designed: sheet shape mirrors ReportSheet's self-contained
NavigationStack + toolbar Cancel/Save, the weight field itself reuses LogSetSheet's shared bordered
stepper-cell component verbatim... so it matches every other weight entry already in the app. Unit
is a fixed 'lbs' default in v1 — no unit-preference setting exists anywhere in profiles/
user_settings (confirmed by grep before this task). Awaiting a designer frame."*

Note the unit question is real and unresolved: this app has **no kg/lbs preference anywhere**. If
your frame introduces or implies a unit toggle, that's a scope expansion worth flagging back,
not something to silently design around.

### Activity Feed (`activity-feed`)
Frame-mapped already: `frame-map.json` → `"activity-feed": { "frame": 45, "title": "Activity
Feed" }`. This was Phase U's own scope (item 2: *"a reverse-chronological list of completed
sessions (own history), reached from Stats... New view reachable from Stats (and/or Home), fed by
existing tables"*) — a frame already exists (45) and is mapped. This is **not** an open
`accepted-deviations.json` entry (it isn't in the 31-entry list at all), which most likely means
either (a) it's already landed in-band with frame 45 and needs no further action, or (b) it simply
hasn't been re-measured since. Confirm its current parity status before assuming it's done —
don't let a mapped-but-unverified frame hide inside a backlog focused on the unmapped ones.

### Streaks group-abandoned rule (behavior note, not a screen)
**Deviation:** `_streaks-group-abandoned-rule` (underscore prefix = BEHAVIOR, not visual) —
*"migration 20260719000007 breaks the GROUP streak on a bare abandoned transition with an absent
member — beyond Flow 7 literal text (group rule lists only no_show) but converging to product
intent; removes an unenforced config-ordering dependency. Whole-branch review recommended
recording it here for traceability."*

No visual deliverable — this is a rules-engine note about when a group streak breaks, recorded
here only for completeness. Nothing for you to draw.

---

## (b) Captures available

Catalog ids (`CatalogHostView.swift`, `#if DEBUG`):

| Screen | Capture id |
|---|---|
| Stat tile loading state | `stattile-loading` |
| Stat tile error state | `stattile-error` |
| Stat tile empty state | `stattile-empty` |
| Body-weight log sheet | `body-weight-log` |

Frame-mapped, view via seeded navigation (no catalog fixture needed/available):
- `tab-stats` (frame 3 exists as the base; the streak card and Body Weight card additions are only
  visible on a seeded account with streak + body-weight history)
- `activity-feed` (frame 45 — reached from Stats; confirm reachability before assuming it needs
  fresh design attention)

Checked-in captures: `.superpowers/parity/app-ci/app-stattile-loading.png`,
`app-stattile-error.png`, `app-stattile-empty.png` exist and are likely still current (these
states don't depend on later phases). `app-tab-stats.png` exists at both
`.superpowers/parity/app/` and `.superpowers/parity/app-ci/` but **predates Phase S (streaks) and
Phase H (body weight) entirely** — it shows neither addition. Request a fresh capture before
using it as your working reference. No capture exists yet for `body-weight-log` or `activity-feed`.

---

## (c) Sign-offs pending

1. **Stat Tiles four-in-one frame structure** — propose splitting frame 41 into four
   single-state frames, or bless the current constant-offset scoring as acceptable. This is a
   harness-methodology sign-off as much as a visual one.
2. **Streak card + Body Weight card** — both need their first frame; no prior sign-off exists for
   either.
3. **Body-weight unit** — confirm lbs-only is correct for v1, or flag the missing unit-preference
   setting as a scope gap.
4. **Activity Feed status** — confirm frame 45 is still in-band; if it's drifted, it needs to
   re-enter this backlog formally (currently it's invisible to the `accepted-deviations.json`
   count precisely because nothing flagged it as deviating).

---

## (d) Constraints

- **GSTheme token system**, four palettes — see `GymSyncApp/GymSync/DesignSystem/GSTheme.swift`.
- **Reuse the existing rhythm on this screen.** The Stats tab already establishes a
  card-per-metric-group rhythm (weekly-volume, recent-PRs) that the streak card and Body Weight
  card were both built to match — your frames should extend that rhythm, not introduce a
  competing one. `GSStatTile`, `GSSectionHeader`, `GSCard`, and the shared `TrendChartView`
  component are all already load-bearing here.
- **`TrendChartView` is a single shared component** (also used by `ExerciseHistoryView`'s Est.
  1RM trend) — any redesign of trend-chart visuals affects both call sites. Design it once.
- **Frame format:** `dc-runtime`/`ios-frame.jsx` (`docs/design/ios-frame.jsx`).

---

## (e) Priority order

By recorded age — the `stattile-*` trio is the oldest surviving "awaiting designer frame" cluster
in the whole Phase D backlog (Phase U, before every phase covered by the other five briefs), even
though its frame already exists and the fix here is more structural than visual:

1. **`stattile-loading`/`error`/`empty`** — oldest, and the fix (frame-splitting proposal) is fast
   to resolve once you've looked at it; don't let "already has a frame" make this seem lower
   priority than it is.
2. **`tab-stats`** (streak card, Phase S — older of its two extensions)
3. **`tab-stats`** (Body Weight card, Phase H — newer extension) / **`body-weight-log`** — draw
   together, same feature.
4. **`activity-feed`** — verify status before treating as a fresh design task; may already be done.
5. **`_streaks-group-abandoned-rule`** — no visual work, lowest priority by construction.
