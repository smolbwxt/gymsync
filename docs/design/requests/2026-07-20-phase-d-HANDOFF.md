# GymSync — Phase D Designer Handoff (consolidated)

**Date:** 2026-07-20 · **From:** Engineering · **To:** Design counterpart

This single document consolidates the Phase D "design sharpening" package — an umbrella
overview plus six family briefs — into one send-ready handoff. It is a point-in-time
snapshot generated from the committed briefs in `docs/design/requests/2026-07-20-phase-d-*.md`
(commit 74774c4); those individual files remain the editable sources.

## How to use this document

1. **Read the Overview first.** It explains the backlog (31 open `accepted-deviations.json`
   entries), the parity-closed-loop workflow every family follows, the recommended family
   order, the parallel "art track," and the definition of done.
2. **Then work the family briefs** in the order below (the Overview's recommended execution
   sequence). Each brief's **§(b)** references the real app captures to redraw *from* — so
   frames start from what exists, not a blank canvas.
3. **Asset access:** the briefs reference repo assets — app captures (`docs/design/…app-*.png`),
   the master canvas (`Gym Sync App Designs.dc.html`), `frame-map.json`, and rendered proofs
   under `.superpowers/parity/proofs/`. The designer needs repo access (or a bundle of the
   referenced PNGs) to see them; this text document alone does not embed the images.

## Contents (in recommended execution order)

1. Overview (read first)
2. Stats — streak card, body weight, trend charts, activity feed, stat tiles
3. Social — chat sub-threads, kudos, group recap, group stats, edit profile
4. Moderation & Settings — report/block/delete, notification/calendar/HR toggles
5. Voice / Live — coach mark, mixer sheet, transmit hero, HR pills, plate math, offline states
6. Discover / Library — Discover, Top Lifters, publish fields, Campaigns, ended-campaigns gap
7. Watch — all 5 watch surfaces, HR pill zone colors, capture-harness gap

---



<div style="page-break-before: always"></div>

---

# Phase D — Design Sharpening: Overview

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Status:** Phase D is the final phase of the build roadmap (`docs/superpowers/plans/
2026-07-16-remaining-build-roadmap.md`), user-committed 2026-07-18. Thirteen development phases
have shipped to `master` (E, P, U, S, F, M, L, H, O, W, C, plus Phase 0's harness merge); only
**Phase V (venues)** remains outstanding, gated on Twilio Verify approval + legal review, running
in parallel rather than blocking Phase D. This document is the umbrella for six family briefs; read
it alongside them, not instead of them.

**The six family briefs:**
1. `2026-07-20-phase-d-social.md` — chat sub-threads, kudos, group recap, group stats, edit profile
2. `2026-07-20-phase-d-discover-library.md` — Discover, Top Lifters, publish fields, Campaigns
3. `2026-07-20-phase-d-moderation-settings.md` — report/block/delete, notification/calendar/HR
   toggles
4. `2026-07-20-phase-d-stats.md` — streak card, body weight, trend charts, activity feed, stat tiles
5. `2026-07-20-phase-d-watch.md` — all 5 watch surfaces, HR pill zone colors
6. `2026-07-20-phase-d-voice-live.md` — coach mark, mixer sheet, transmit hero, HR pills, plate
   math, offline states

---

## The design backlog, reconciled

`docs/design/accepted-deviations.json` is the canonical queue — **31 entries**, every one now
assigned to exactly one family brief:

| Family | Entries | Count |
|---|---|---|
| Social | `session-chat`, `group-stats`, `edit-profile` | 3 |
| Discover/Library | `tab-library`, `discover`, `discover-detail`, `top-lifters`, `campaigns-tab`, `campaign-detail`, `home-campaigns-carousel`, `exercise-detail` | 8 |
| Moderation/Settings | `tab-you`, `report-sheet`, `blocked-users`, `delete-account`, `_blocked-users-visible-on-boards` | 5 |
| Stats | `stattile-loading`, `stattile-error`, `stattile-empty`, `tab-stats`, `body-weight-log`, `_streaks-group-abandoned-rule` | 6 |
| Watch | `hr-pill-zone-color` | 1 |
| Voice/Live | `voice-coach-mark`, `voice-connected-toast`, `voice-mixer-sheet`, `voice-mixer-entry-point`, `voice-transmit-hero`, `heart-rate-pill`, `plate-math`, `offline-syncing-indicator` | 8 |
| **Total** | | **31** |

Two entries (`_streaks-group-abandoned-rule`, `_blocked-users-visible-on-boards`) are
underscore-prefixed BEHAVIOR notes, not visual deviations — they're included for traceability but
carry no drawing requirement. One entry (`exercise-detail`) is already closed (photographic
content vs. mock, verified faithful) and needs only a confirmation glance. The remaining 27 are
live design work.

Two items referenced in the roadmap's Phase D backlog prose are **not** in this 31-entry count
because they were never filed as formal deviations, only tracked informally:
- **Publish-fields UI** (`RoutineBuilderView`'s `is_featured`/`default_sort`/`scoring_metrics`
  extension) — tracked only in roadmap prose; covered in the Discover/Library brief with a note to
  get it a real ledger entry once framed.
- **Ended-campaigns surface** — tracked only in the Phase C merge-gate's ledger note (`PRE-GA
  LEDGER` / `V/D handoff` items in `.superpowers/sdd/progress.md`), not as a deviation entry; it's
  also a genuine **product** gap (no screen exists for what a user sees when a campaign has ended),
  covered in the Discover/Library brief and flagged as time-sensitive.

---

## Correction: the Watch app is already built

The roadmap document (written 2026-07-16) lists "the ENTIRE Watch app" among Phase D's
not-yet-built surfaces. **Phase W merged since then** (`.superpowers/sdd/progress.md`: "PHASE W
MERGED... ELEVENTH PHASE," watch build debuted as build 230). All 4 core watch screens
(whose-turn/log-set/soundboard/ledger, plus an idle state folded into whose-turn) are real,
running Swift code today. The Watch brief documents their current state directly from source.
This is Phase D's job on every other family too — bless or redraw what's built — not a unique
exception; the roadmap prose was simply stale by the time this brief was written. One real gap
persists: none of the 4 watch screens ever received a formal `accepted-deviations.json` entry when
they shipped (unlike every other system-designed screen in this backlog) — flag this process gap
to whoever owns the ledger so future built-but-undesigned screens don't silently skip the record.

---

## Family order recommendation

The roadmap's own method (`Phase D` section) already states the governing logic: *"Sequence D
LAST (after W/C/V) so Watch/Campaigns/Venues get designed once, not redesigned; but the ART track
... can run in parallel any time."* Applied to this backlog:

1. **Stats first** — contains the single oldest "awaiting designer frame" cluster in the entire
   backlog (`stattile-*`, recorded in Phase U, before every other phase represented here). The
   fastest genuine win is also here: the `stattile-*` fix is closer to a harness-methodology
   question (four-state sheet vs. one-state capture) than a fresh design problem.
2. **Social, Moderation/Settings, Voice/Live** — the three mid-sized families, roughly
   interchangeable in sequence, though Voice/Live's DesignSync-integration item (five frames
   already drawn, just never numbered into `frame-map.json`) is arguably the single fastest win
   across all six briefs and can be pulled forward opportunistically regardless of where its
   family lands.
3. **Discover/Library** — the largest family (8 entries) and the one carrying an actual product
   gap (ended-campaigns), not just a design gap. Its Campaigns sub-scope specifically should track
   with the "design once" logic below; its Discover sub-scope has no such dependency and could move
   earlier if capacity allows.
4. **Watch last** — per the roadmap's own "design once, not twice" logic. **Important caveat: the
   premise has partially changed.** The roadmap grouped Watch with Campaigns/Venues under the
   theory that all three were still unbuilt and might reshape before a designer should invest in
   them. Watch is now built and stable (Phase W merged, shipping in TestFlight); its "design once"
   risk is lower than the roadmap assumed. It's kept last here anyway, for two reasons that still
   hold: (a) it benefits from the designer's system vocabulary maturing on the other five families
   first, so Watch frames inherit settled patterns rather than setting new ones; (b) it needs a new
   piece of infrastructure (a watchOS capture mechanism, since none exists — see the Watch brief's
   §b) that can be scoped in parallel while the earlier families are in flight, rather than
   blocking on it up front.
5. **Venues — does not exist as a family in this backlog, deliberately.** The original "Campaigns/
   Venues" pairing in the roadmap's Phase D description bundles two features that are NOT at the
   same readiness level: Campaigns shipped (Phase C, merged) and has real screens to bless;
   **venues have not been built at all** (Phase V is still gated on Twilio Verify + legal review +
   a venue-seeding strategy, per the roadmap's Phase V prerequisites). There is nothing to design a
   frame against yet — no schema, no UI, no product surface. This is why this overview commissions
   six briefs, not seven: a "Venues" brief today would have zero real content, unlike Watch's
   (which has four real screens despite the roadmap's stale framing). Once Phase V ships, it should
   get its own brief, sequenced after Watch per the same "design once" logic — not folded into
   Discover/Library or any other family here.

---

## The art track — runs in parallel, not sequenced with the families above

Per the roadmap: *"the ART track (icon, pack artwork, exercise imagery style) can run in parallel
any time — it's asset production, not screen design."* Three items, none blocking and none blocked
by the family sequence above:

1. **App icon.** Still the PIL-generated placeholder dumbbell (`GymSyncApp/GymSync/Assets.xcassets/
   AppIcon.appiconset/` and the watchOS target's own `GymSyncApp/GymSyncWatch/Assets.xcassets/
   AppIcon.appiconset/` — both need real artwork, not just the phone target). This is the most
   visible unresolved placeholder in the entire app and has no dependency on any family brief above.
2. **Featured-pack artwork + an asset pipeline.** Packs (`LibraryTabView.featuredShelf`/
   `.packCard`) render placeholder blocks today — no image asset exists, and no pipeline exists to
   produce/deliver one. This is asset production infrastructure as much as it is art: someone needs
   to decide the pipeline (manual upload? generated? licensed stock?) before artwork can land.
3. **Exercise demonstration imagery style.** The `exercise-detail` deviation (Discover/Library
   brief) already names the tension: functional free-exercise-db photographs vs. the app's own
   design language (flat, zero-radius, midnight-palette-forward). This is a style decision with
   real product consequences (150-300 exercises' worth of imagery, per Phase E's library
   expansion) — worth deciding deliberately rather than defaulting to "whatever the import script
   downloaded."

A fourth, smaller item from the roadmap's content backlog belongs here too: **soundboard icons/
sounds curation** — the designer previously proposed 4 new sounds (Drumroll, Clap, Dig in,
Lightweight) via `scripts/add_sound.js`; catalog icons are meant to be emoji, not SF Symbols (per
the 2026-07 curation canvas notes) — confirm this is still the intended direction before the art
pass locks it in.

---

## The parity-closed-loop workflow (recap)

Per the roadmap's own method — this is how each family should actually execute, and it's already
proven (used for every phase through Campaigns):

1. **Designer draws frames** for the family's screens, in `dc-runtime`/`ios-frame.jsx` format
   (`docs/design/ios-frame.jsx`), embedding the real app captures referenced in each brief's §(b)
   so redraws start from what exists, not from a blank canvas.
2. **DesignSync pull** — the canvas gets pulled into the repo (`docs/design/` — either the master
   `Gym Sync App Designs.dc.html` or a numbered `sections/*.dc.html` follow-up, per the
   established split-file convention that keeps individual pulls under the API's 256KiB cap).
3. **`render_proofs.js`** renders each new/changed frame to a `proof-frame-NN.png` for visual
   inspection before anything is wired into the live parity pipeline.
4. **`frame-map.json` entries** — each screen id gets (or updates) its `{ "frame": N, "title":
   "..." }` mapping, connecting the app's `app-<id>.png` capture to its canvas frame number.
5. **A small implementation fix-wave per family** — engineering closes the structural gaps the new
   frame reveals (spacing, component substitutions, state handling) — never a monolithic redesign
   branch; each family merges independently, CI-gated like every other phase.
6. **Parity report shows the family land in-band** — `parity_diff.js --app <captures> --map
   frame-map.json` scores each mapped screen; the family is "done" once its screens score in the
   structural-noise band (see Definition of Done below).
7. **Prune deviations** — once a screen's frame lands and scores in-band, its
   `accepted-deviations.json` entry is removed (or, for permanent divergences like `exercise-
   detail`'s photographic content, kept and marked as intentionally permanent rather than pending).

---

## Definition of done

Per the roadmap, verbatim: *"every `app-*.png` capture maps to an authoritative frame and scores
in the structural-noise band; `accepted-deviations.json` contains only genuinely-permanent entries
(behavior notes, photo-vs-mock); the app icon and pack artwork are real."*

Concretely, for this backlog specifically:
- All 31 current `accepted-deviations.json` entries are either pruned (frame landed, scored
  in-band) or reclassified as permanent (the `_`-prefixed behavior notes; `exercise-detail`'s
  photo-vs-mock; any zone-color/boundary or toggle-honesty decision that's deliberately
  content-not-chrome).
- Every screen id in `CatalogHostView.swift`'s `CatalogScreen` enum (33 cases) has a
  `frame-map.json` entry — today several catalog ids exist with no mapping at all (e.g.
  `campaigns-tab`, `discover`, `body-weight-log` are catalog-capturable but unmapped; the Watch
  screens aren't in the catalog enum at all and have no capture mechanism yet, per the Watch
  brief).
- The two publish-fields/ended-campaigns items get proper `accepted-deviations.json` entries (or
  are resolved before ever needing one).
- The Watch capture-harness gap is closed (or explicitly deferred with a named owner and reason —
  not silently left absent).
- The three art-track items (icon, pack artwork, exercise imagery style) ship real assets,
  independent of the family sequence.
- The standing designer-note queue predating this backlog — three items the roadmap names
  explicitly (*"chat mic-icon adjudication, bell icon variant, offline-pill placement"*, Phase D
  backlog item 2) — is closed out:
  - **Bell icon variant**: appears resolved already — the designer delivered a bell redraw as
    canvas frame 36 (`onboarding-push-priming`, already mapped and shipped). Confirm during the
    Moderation/Settings family pass rather than treating as open.
  - **Offline-pill placement**: substantially resolved by the `offline-syncing-indicator` work
    (Voice/Live brief) — confirm the shipped chip/banner treatment satisfies the original note,
    or reopen if not.
  - **Chat mic-icon adjudication** (`docs/design/requests/2026-07-12-design-request-addendum.md`,
    item A.6): genuinely still open — the addendum asked the designer to confirm single
    context-sensitive arrow vs. the shipped separate mic/send icon swap, and no resolution is on
    record anywhere in the ledger or the canvas. This is real, outstanding work with no owner in
    the 31-entry count; the Social brief's chat/session surfaces are the natural place to close it,
    since the new session-chat sub-thread reuses the same `ChatView` input row.


<div style="page-break-before: always"></div>

---

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


<div style="page-break-before: always"></div>

---

# Phase D Designer Brief — Social

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Social (chat sub-threads, kudos, group recap, group stats, edit profile, session surfaces)
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md` for the cross-family sequencing and definition of done.

---

## Read this first

This brief packages three Phase F ("Social finishers") screens that shipped system-designed
(no canvas frame, built to existing GS component idioms) plus the session-chat entry points and
the still-open recap-celebration adjudication carried from Phase U. Everything below is real,
merged, running code — not a proposal. Your job is to draw the authoritative frame; engineering's
job (a small fix-wave per the parity-closed-loop) happens after your frames land.

---

## (a) Screens — current state

### 1. Session sub-thread chat (`session-chat`)
**Deviation:** `session-chat` — *"no canvas frame depicts a session sub-thread chat affordance —
proof-frame-05/06/07 (Lobby, Live Spotlight, Live Roster headers) show no chat button.
System-designed: a bordered icon-button (LobbyView toolbar / GroupSessionLiveView headerBar,
styled after each screen's own existing icon buttons) opening a sheet with the reused ChatView,
text-only send row. Awaiting a designer frame."*

This is a **new** per-session chat thread, distinct from the existing group-level chat (`chat`,
frame 21 — already designed, unaffected). It surfaces as an icon button in two places:
- `LobbyView` toolbar (pre-session)
- `GroupSessionLiveView` headerBar (both Spotlight and Roster layouts, in-session)

Both open a sheet wrapping the same `ChatView` component the group chat already uses, but scoped
to `chat_messages.session_id` instead of `chat_messages.group_id`. Text-only send row (no image/
voice-note affordances re-derived — those already exist on the group thread and are reused as-is
inside the sheet).

**Known crowding note (carry into your redraw):** Phase F's own task report flagged that
`GroupSessionLiveView.headerBar` is already busy (voice mixer entry point, soundboard toggle,
existing chat/roster controls) — a live-header crowding note is on record. Your frame should
either give the session-chat icon a clearly subordinate visual weight to the group's PTT/voice
controls, or propose a consolidated overflow affordance. This is a decision needed, not just a
visual redraw.

### 2. Group Stats sub-tab (`group-stats`)
**Deviation:** `group-stats` — *"GroupView's new Stats sub-tab (spec Flow 5, deferred from Phase
2) — collective SESSIONS/TOTAL LBS/PRS tiles, the group streak card (deferred from Phase S), and
a per-member volume leaderboard. proof-frame-22.png ('Members') and proof-frame-19.png (already
mapped to 'friends') were both rendered and inspected — neither depicts a collective-metrics/
leaderboard/streak surface. System-designed: GSStatTile collective-tiles row mirrors Home's
StatTilesRow 3-tile idiom; the streak card mirrors StatsTabView.streakCardView verbatim
(swapped to the group-scoped read); leaderboard rows mirror GroupRecapView.leaderboardRow's
shape minus rank/kudos (neither applies to an all-time aggregate outside a live session).
Awaiting a designer frame."*

This is a new sub-tab inside `GroupView`, alongside the existing Chat and Sessions sub-tabs.
Three stacked sections: (1) a 3-tile collective-metrics row (borrowed shape from Home's tiles),
(2) a group streak card (verbatim borrow of the Stats-tab streak card, group-scoped), (3) a
per-member volume leaderboard (borrowed row shape from `GroupRecapView.leaderboardRow`, with
rank/kudos chip dropped since this is an all-time aggregate, not a session-end moment).

**Scoping sign-off needed:** is a lifetime aggregate the right scope, or should this default to
a rolling window (30/90 days)? Engineering built lifetime because the spec (Flow 5) doesn't
specify a window — this is exactly the kind of product decision Phase D should adjudicate rather
than silently accept.

### 3. Edit Profile (`edit-profile`)
**Deviation:** `edit-profile` — *"Edit Profile (display name + avatar), deferred from Phase 2.5
— the You-tab Edit button was inert until this task. System-designed: avatar-picker row mirrors
GroupView.membersList's shape (56pt preview + accent 'Change Photo' link, upload-on-pick),
display-name field mirrors CreateGroupView's bordered-TextField shape with an explicit toolbar
Save. Awaiting a designer frame."*

Reached from the You tab's previously-inert "Edit" button. Avatar upload reuses the existing
Storage `avatars` bucket pattern (precedent: group avatars). Display-name field is a bordered
TextField with an explicit toolbar "Save" (not autosave).

**Known asymmetry, flagged but unresolved (Phase F Task 6 report):** the avatar picker
persists-on-pick (uploads immediately when you choose a photo, before you tap Save) — this
mirrors the group-avatar precedent, but it means "Cancel" after picking a new photo does NOT
revert the avatar. Product note queued for sign-off: is persist-on-pick the right UX for a
personal profile (as opposed to a group, where any admin might expect immediate effect)?

### 4. Group Recap adjudication (Phase U carryover — informational, not a fresh deviation)
Canvas frames 8 (`group-recap`, mapped) and 17 (`recap-solo`, mapped) depict full-screen
"Session Complete" celebrations (kudos, session leaderboard). The app currently renders the
quieter Session Detail (`session-recap`, frame 34) at group-session end. Phase U adjudicated this
as: celebration screen at session end (frames 8/17), Session Detail (frame 34) reachable from
history — both are already mapped in `frame-map.json` and both frames exist. This is **not an
open sign-off** — it's built and mapped — but it's the direct precedent for "kudos" in this
family's scope, and your review pass should confirm the live app's kudos-sending flow (fired from
`group-recap`) still matches frame 8's interaction exactly, since it hasn't been re-verified since
Phase U closed.

---

## (b) Captures available

The debug catalog (`GymSyncApp/GymSync/App/CatalogHostView.swift`, `#if DEBUG`) has fixture
entries for two of these three screens; the third and the recap screens are reached via seeded
navigation (no catalog fixture needed — they render from real/seeded data):

| Screen | Capture id | Source | Status |
|---|---|---|---|
| Session chat | `session-chat` | `CatalogScreen.sessionChat` | In frame-map.json (no frame yet — will 404 in parity report until you deliver one) |
| Group recap | `group-recap` | `CatalogScreen.groupRecap` | Mapped to frame 8 — capture exists, use for the kudos-flow re-verification above |
| Group stats | *(none)* | not in `CatalogScreen` enum | No catalog fixture exists yet — request one, or view via seeded navigation (`GroupView` → new Stats sub-tab, requires a seeded group with session history) |
| Edit profile | `edit-profile` | `CatalogScreen.editProfile` | In frame-map.json (no frame yet) |

Capture files land at `.superpowers/parity/app-ci/app-<id>.png` after the next CI screenshot run
(the naming convention is `app-<screenId>.png`, matching `frame-map.json` keys and
`CatalogScreen` raw values 1:1 — see `scripts/rename_app_shots.js`'s header comment for the
mechanism). The repo's checked-in captures under `.superpowers/parity/app-ci/` predate Phases
F/M/L/H/O/W/C and do **not** include `session-chat`, `group-recap`, or `edit-profile` yet — request
a fresh CI screenshot run before you start, or ask engineering to add a catalog id for group-stats
so it becomes capturable the same way. Do not expect binary images embedded in this doc — these
are paths to request/view, not attachments.

---

## (c) Sign-offs pending

1. **Session-chat entry-point placement** — icon button in an already-crowded `headerBar`
   (voice controls + soundboard + existing chat/roster icons). Needs your call: subordinate
   icon weight, or consolidate into an overflow menu.
2. **Group Stats scoping** — lifetime aggregate (as built) vs. a rolling window. Product decision,
   not a visual one, but it changes what the frame needs to show (a window-selector control or not).
3. **Edit-Profile avatar persist-on-pick asymmetry** — confirm intended behavior; if persist-on-pick
   is wrong for a personal profile, the frame needs a distinct "pending change, tap Save to
   commit" visual state that doesn't exist today.
4. **Group Recap kudos-flow re-verification** — not a new sign-off, but your pass should confirm
   frame 8's interaction still matches after everything that's shipped since Phase U.

---

## (d) Constraints

- **GSTheme token system.** Every color must resolve through a `GSTheme` semantic token
  (`bg`/`surface`/`text`/`accent` + the accent/neutral ramps) — never a literal hex baked into a
  frame. The four palettes are Midnight (`#13161c` bg / `#38bdf8` accent — the default and the
  only one currently canvas-complete in full detail), Arena (near-black / volt lime), Ink (warm
  bone / deep navy), Modernist (bone / signal red) — see `GymSyncApp/GymSync/DesignSystem/
  GSTheme.swift` for the full token bag per palette. A frame that only works in Midnight isn't
  done.
- **System idioms already in use for this family** (reuse, don't reinvent): `GSCard` zero-radius
  cards, flush-left labels/buttons, 2px dividers, `GSSectionHeader`, `GSStatTile`,
  `GSInitialsAvatar`, `GroupRecapView.leaderboardRow`'s rank+avatar+name+metric row shape.
- **Frame format.** Author frames in `dc-runtime`/`ios-frame.jsx` format (the established canvas
  pipeline — `docs/design/ios-frame.jsx`, `<IOSDevice>` wrapper) so `render_proofs.js` can render
  them and the parity harness can diff against real captures. Plain-HTML frames (the pre-Phase-3e
  convention) are **not** renderable by the current localhost+Playwright pipeline for anything
  using the dc-runtime template — confirm which template you're using before delivery (this bit
  the team once already: see the 2026-07-13 canvas-render-limitation incident in
  `.superpowers/sdd/progress.md`).
- **The parity harness will measure your frames.** Once a frame lands and gets a `frame-map.json`
  entry, `parity_diff.js` diffs it against the real app capture on every CI run. Structural
  fidelity (layout, spacing, type scale) is what's measured — not pixel-identical photographic
  content (see the `exercise-detail` precedent in the Discover/Library brief for how that
  distinction gets recorded).

---

## (e) Priority order

All three of this family's deviations were recorded in the same phase (Phase F, Tasks 3/5/6) —
there is no "worst divergence" percentage to rank by, because none of these three screens has a
frame yet (an un-mapped screen isn't scored by the harness at all; it's categorically behind
every *measured* divergence, including the harness's historical worst finding, `pr-celebration`
at 64%, now resolved). Use build-task order as the tie-break, since it reflects how long each has
sat in the backlog:

1. **`session-chat`** (Task 3, oldest of the three) — also the one with an unresolved layout
   question (header crowding), so it benefits most from getting drawn first and iterated.
2. **`group-stats`** (Task 5) — blocked on the scoping sign-off (c.2) before a frame can even be
   fully specified; raise that question with the frame request, don't wait for a separate round-trip.
3. **`edit-profile`** (Task 6, newest) — the persist-on-pick question (c.3) is a smaller, more
   contained decision; can proceed in parallel with the other two.

The Group Recap re-verification (item 4) is not blocking — it's a lightweight confirmation pass,
do it whenever convenient within this family's sprint.


<div style="page-break-before: always"></div>

---

# Phase D Designer Brief — Moderation/Settings

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Moderation/Settings (report sheet, blocked users, delete account, notification
prefs, calendar toggle, HR toggle + the §6.5 sharing-paused surface TO BE DESIGNED)
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md`.

---

## Read this first

Three of this family's screens (report sheet, blocked users, delete account) are App Store
compliance surfaces — Phase M shipped them functional specifically because no public submission
could happen without them, and the design ledger explicitly notes **no canvas frame exists or is
expected** for any of the three. They still deserve your polish pass, but they're not "missing
frames waiting to be drawn from a canvas gap" the way the rest of this backlog is — there was
never a spec for them. The You-tab (`tab-you`) entry is different: it's one long-running deviation
that four separate phases (design adoption, M, H, W) have each extended with one more row, and it
still hasn't been signed off even once.

---

## (a) Screens — current state

### The You tab / Settings Hub (`tab-you`) — the big one
**Deviation:** `tab-you` — condensed across four extensions:
- *Base: "You tab implements the newer Settings Hub with added stat tiles + Apple Health row — a
  recorded deviation ahead of the superseded canvas 'You' frame, awaiting design sign-off."*
- *Phase M Task 4 adds: a "Share Solo Workouts" toggle (with inline caption) inside the Settings
  group box, and a red "Delete Account" row below it.*
- *Phase H Task 2 adds: "Add my sessions to Calendar" (default off, same toggle-row-with-inline-
  caption shape; system-denied state collapses the row into a single open-Settings tap target per
  PTTDockRow.deniedRow's idiom) — no canvas frame depicts EventKit sync at all.*
- *Phase W Task 4 adds: "Share heart rate in live sessions" (default OFF, identical shape, footer
  copy states the ephemeral-broadcast privacy contract) — grepped frame-map.json and every
  .dc.html for "heart rate"/"bpm": the only hits are the Live-session BPM pills (a different
  screen, T5's display surface, not a Settings row) and lobby copy — extends this entry rather
  than opening a new one.*

Practically: the You tab's Settings group box now has, top to bottom, the original rows (Home
Gym, Appearance, Notifications, Apple Health) plus **three newer toggle rows** — Share Solo
Workouts, Add my sessions to Calendar, Share heart rate in live sessions — each using the same
"toggle + inline caption, denied-state collapses to a single Settings tap target" shape, plus a
red Delete Account row at the bottom. This entire screen has never had a single sign-off pass; it
has only ever grown. Your redraw is the first chance to actually resolve it instead of extending
it a fifth time.

### The §6.5 sharing-paused surface — TO BE DESIGNED, does not exist yet
This is **not** in `accepted-deviations.json` as a screen entry — it's a spec'd requirement that
was explicitly **deferred at build time**, tracked instead as a Phase W gate item:
*"T5 done... §6.5 sharing-paused surface deferred... Sec6.5 sharing-paused deferral RULED
acceptable (gate item)."* The spec itself (`docs/superpowers/specs/2026-06-28-gymsync-design.md`
§6.5, HealthKit heart rate authorization + Watch integration): *"First time a user enters a
session with `share_heart_rate = true`, iOS prompts for HealthKit read permission for heart rate.
If denied, we do NOT re-prompt — instead show a 'Heart rate sharing paused' state in Settings with
a deep-link to iOS Settings → Health."*

So: the toggle exists (see `tab-you` above), but the specific state where the user has the toggle
ON, HealthKit permission is denied, and the app needs to tell them sharing is silently not
happening — **that state has no UI at all today**. This needs an actual frame, from scratch, not
just a sign-off on something built. Treat it as this brief's one true "undesigned, not just
unblessed" item.

### Report sheet (`report-sheet`) — compliance surface, no frame expected
**Deviation:** `report-sheet` — *"the Report action's reason-picker + freeform-details sheet is
an App Store review requirement (Guidelines 1.2/5.1.1), not a designed screen — no canvas frame
exists or is expected. System-designed: fixed reason-category list (Harassment/Spam/Inappropriate
content/Other) with a checkmark-selection row shape borrowed from AppearanceView's palette rows,
freeform TextField + toolbar Cancel/Submit mirroring CreateGroupView's sheet shape."*

### Blocked Users list (`blocked-users`) — compliance surface, no frame expected
**Deviation:** `blocked-users` — *"the You-tab Blocked Users list is the same App Store compliance
surface as report-sheet above — no canvas frame exists or is expected. System-designed: pushed
List of Profile rows (GSInitialsAvatar + two-line name block, mirroring FriendsView's row shape)
with a per-row Unblock button; GSEmptyState/GSErrorCard for the no-blocks/load-failed cases."*

### Delete Account (`delete-account`) — compliance surface, no frame expected
**Deviation:** `delete-account` — *"the Delete Account typed-confirmation sheet is an App Store
5.1.1 compliance requirement, not a designed screen — no canvas frame exists or is expected.
System-designed: sheet shape mirrors report-sheet's self-contained NavigationStack + toolbar
Cancel; a red-accented warning card explains the irreversible cascade, a bordered TextField
requires typing the exact string 'DELETE' before the destructive confirm button... becomes
tappable. Catalog/screenshot capture only ever shows this pre-confirmation state — the actual
deletion is device-QA only."*

### Blocked-users-visible-on-boards (behavior note, not a screen)
**Deviation:** `_blocked-users-visible-on-boards` (underscore prefix marks it BEHAVIOR, not
visual) — *"Blocking someone hides them from chat and friend-request surfaces but NOT from public
leaderboards... A blocked/blocking pair can still see each other's rows on a routine's leaderboard
(e.g. 'The Murph') and the global Top Lifters board. Not a Guideline 1.2/5.1.1 compliance gap
(Phase M already closed the direct-contact surfaces block is required to cover)... but it is a
real, user-visible privacy gap worth naming. Candidate fix (deferred, not designed here): extend
the is_blocked-gated idiom already used for chat/friendships to leaderboard_entries/
workout_attempts RLS and topLifters()'s query."*

No visual work needed from you on this one — it's a backend/RLS fix candidate, not a design gap.
It's included here because it's about block enforcement (this family's subject), even though the
surfaces it actually affects (Top Lifters, Discover detail's leaderboard) live in the
Discover/Library brief. Read it before touching either family's leaderboard rows.

---

## (b) Captures available

Catalog ids (`CatalogHostView.swift`, `#if DEBUG`):

| Screen | Capture id |
|---|---|
| Report sheet | `report-sheet` |
| Blocked users | `blocked-users` |
| Delete account | `delete-account` (pre-confirmation state only — the confirm button's disabled guard makes the destructive state structurally unreachable from the capture harness by design) |
| You tab / Settings Hub | `tab-you` (frame-mapped, frame 35 "Settings Hub" — a REAL existing frame from an earlier phase; this is a re-draw of a mapped frame, not a from-scratch one) |

Not capturable at all today:
- The §6.5 sharing-paused surface — no UI exists, nothing to screenshot.

`tab-you` has a checked-in capture at `.superpowers/parity/app-ci/app-tab-you.png` and
`.superpowers/parity/app/app-tab-you.png`, but both predate the Phase H and Phase W row additions
(calendar toggle, HR toggle) — request a fresh capture before using either as your reference; what
you'd see today has three more rows than either checked-in file shows. `report-sheet`,
`blocked-users`, and `delete-account` have no checked-in `app-*.png` files yet at all (Phase M
postdates every capture currently in the repo) — request a fresh CI screenshot run.

---

## (c) Sign-offs pending

1. **`tab-you` — the whole screen, for the first time.** Four separate extensions across four
   phases, zero sign-off passes. This is the priority item in the family.
2. **§6.5 sharing-paused surface — needs an original frame**, not a sign-off (nothing to sign off
   on; it doesn't exist).
3. **Report sheet, Blocked Users, Delete Account — polish pass only.** No frame is expected or
   required (compliance surfaces), but your review should confirm the system-designed shapes read
   as intentional rather than utilitarian, since these are now permanent parts of the app, not
   placeholders.
4. **`_blocked-users-visible-on-boards`** — not yours to sign off (it's an engineering/RLS fix
   candidate), but flag if you think the product decision (leave leaderboards unfiltered) is
   wrong; that's a legitimate design/product objection even though the fix is backend-side.

---

## (d) Constraints

- **GSTheme token system**, four palettes — same as every family. The Delete Account destructive
  action already uses a plain red accent rather than a themed token (precedent set by
  `YouTabView.deleteAccountRow`, and reused for `hr-pill-zone-color`'s zone ramp in the Watch/
  Voice-Live families) — confirm whether that's the right call to keep making, or whether
  destructive-red deserves its own semantic token across all four palettes.
- **Reuse shapes already established in this family:** the toggle-row-with-inline-caption
  pattern (Share Solo Workouts / Add my sessions to Calendar / Share heart rate) should be your
  template for the §6.5 sharing-paused state too — it's a natural extension of a pattern that
  already exists three times on this exact screen, not a new idiom.
- **Frame format:** `dc-runtime`/`ios-frame.jsx` (`docs/design/ios-frame.jsx`) per the established
  pipeline.
- **This screen is measured by the parity harness on every CI run** once frame 35 gets a redraw —
  `tab-you` already has a frame-map entry (frame 35), so a new frame here immediately starts
  scoring, unlike the fully-undesigned screens elsewhere in this backlog.

---

## (e) Priority order

`tab-you` is the standout priority in this family — it's the only entry with a **frame that
already exists and is actively scored** (frame 35), meaning every day it goes un-redrawn, the
harness is comparing live app content (4 rows richer than build time) against a stale reference.
That's actively degrading signal, not just an absent frame.

1. **`tab-you`** — existing frame, actively stale, four accumulated extensions (Phase M → H → W).
   Highest-leverage single redraw in this entire Phase D backlog.
2. **§6.5 sharing-paused surface** — no frame exists, and it's the one truly novel design problem
   in this family (a permission-denied edge state, not a settings row).
3. **`report-sheet`**, **`blocked-users`**, **`delete-account`** — all shipped in the same phase
   (M), all compliance-driven, no canvas frame expected for any. Equal priority; batch them
   together as a single polish pass since they share the same sheet-chrome idiom.
4. **`_blocked-users-visible-on-boards`** — informational, no visual deliverable from this brief.


<div style="page-break-before: always"></div>

---

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


<div style="page-break-before: always"></div>

---

# Phase D Designer Brief — Discover/Library

**Date:** 2026-07-20
**From:** Engineering
**To:** Design counterpart
**Family:** Discover/Library (Discover grid/detail, Top Lifters, publish fields, campaigns
sub-tab + detail + carousel, curated lists, ended-campaigns surface)
**Part of:** Phase D (Design Sharpening, final phase) — see `2026-07-20-phase-d-overview.md`.

---

## Read this first

This is the largest family by deviation count (8 of 31) because two full product pillars —
Phase L (Discover + public workout leaderboards) and Phase C (seasonal campaigns) — shipped
back-to-back with **zero canvas coverage**. Every screen below was grepped against
`docs/design/frame-map.json` and every `.dc.html` canvas file before being marked
system-designed; none of these greps found anything. This family also carries one item that
is **not just a design gap — it's a product gap** (the ended-campaigns surface, see below), and
one older, already-resolved entry (`exercise-detail`) that only needs a confirmation glance.

---

## (a) Screens — current state

### Library tab structure
**Deviation:** `tab-library` — *"LibraryTabView's segmented sub-tab control widened from 2
segments (Routines/Exercises) to 3 (+ Discover)... Phase C Task 2 widens it again, 3 -> 4 segments
(+ Campaigns) — the master spec's four-sub-tab Library structure now completes (:690)... Awaiting
a designer frame that reflects the 4-segment control."*

The Library tab is now a 4-segment control: **Routines · Exercises · Discover · Campaigns**. Only
the top segmented-control row has changed from the original canvas frame; content below (Routines,
the default sub-tab) is unchanged. Your frame needs to show all 4 segments at the correct width.

### Discover grid (`discover`)
**Deviation:** `discover` — *"Library's new Discover sub-tab (public workout repository grid,
master spec Flow 4)... System-designed: 2-column grid (SoundLibrarySheet.catalogGrid's LazyVGrid
idiom) of cards mirroring LibraryTabView.packCard's bordered-card shape (image placeholder, name,
owner caption, FEATURED chip, scoring-metric chips, attempt-count caption when non-zero) —
is_featured-first ordering, plus a new Top Lifters entry row at the top... Awaiting a designer
frame."*

2-column LazyVGrid of public-workout cards, `is_featured` sorted first. A "Top Lifters" entry row
sits above the grid (see below). Seed content now exists ("The Murph" + 2 templates via
`scripts/seed_qa_fixtures.js`) so a live-data capture is possible, not just fixture-driven.

### Discover workout detail (`discover-detail`)
**Deviation:** `discover-detail` — *"the public workout detail screen reached from Discover...
System-designed: description + scoring-metric chips header, a read-only exercise list..., Attempt
Solo / Attempt with Friends CTAs, and a sortable leaderboard — segmented control... needs a
dynamic 2-4 [segments] depending on the routine's scoring_metrics, leaderboard rows mirror
GroupRecapView.leaderboardRow's shape with GSInitialsAvatar swapped in and a '✏️ edited' indicator
replacing the kudos chip. Report/Block toolbar reuses Phase M's RoutineModerationToolbar — this is
the first screen where that menu is ever live. Awaiting a designer frame."*

Note the **dynamic segmented control** (2-4 segments depending on which `scoring_metrics` a given
routine has) — your frame set needs at least two examples (a 2-metric and a 4-metric routine) so
engineering isn't guessing at how the control should reflow.

### Top Lifters (`top-lifters`)
**Deviation:** `top-lifters` — *"the global cumulative-volume leaderboard reached from Discover's
new 'Top Lifters' entry row... System-designed: bordered icon + title/subtitle + chevron entry row
on Discover mirrors ScheduleSessionView.whatSection's Menu-row shape; the board itself reuses
GroupRecapView.leaderboardRow's rank+avatar+name+metric idiom... and a 'You' row highlight... No
opt-in gate: profiles SELECT RLS is USING (true) for any authenticated user, so this board is a
plain ordered+LIMIT-ed read, not a new relationship oracle. Awaiting a designer frame."*

Flag for your awareness, not a design question: this board is **not** privacy-filtered by
block state (see `_blocked-users-visible-on-boards` in the Moderation/Settings brief) — a blocked
user's name can still appear here. That's a product/engineering decision already ruled acceptable
for now, not something your frame needs to solve, but worth knowing if you're designing any
row-level affordance (e.g., don't design a "block from here" action without checking that brief).

### Publish-fields UI (roadmap item, no formal deviation entry yet)
The roadmap (`docs/superpowers/plans/2026-07-16-remaining-build-roadmap.md`, Phase D backlog)
lists **"publish-fields UI (L-T4)"** as an undesigned surface. This is the routine-publish flow
extended with `is_featured`, `default_sort`, `scoring_metrics`, `scoring_top_set_exercise_id`
(`GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift`). It shipped functional but
undesigned in Phase L Task 4 (targeted 3-column UPDATE with explicit null-encode). **No
`accepted-deviations.json` entry exists for this screen specifically** — it was tracked only in
the roadmap prose, not the formal ledger. Treat it as in-scope for this brief; flag it to the
ledger owner so it gets a proper entry once you've drawn a frame for it.

### Campaigns sub-tab (`campaigns-tab`)
**Deviation:** `campaigns-tab` — *"Library's new Campaigns sub-tab (Flow 8: 'Library -> Campaigns
sub-tab shows all active campaigns + a countdown to upcoming ones')... System-designed: list rows
(not a grid — a campaign has no artwork upload path in this task's scope) borrow
HomeView.upcomingCard's bordered-GSCard kicker+title+meta-caption shape, grouped under 'Active'/
'Upcoming' GSSectionHeaders; upcoming rows show a day-count instead of the 'Active' tag.
GSEmptyState/GSErrorCard for the no-campaigns/load-failed cases... Awaiting a designer frame."*

### Campaign detail (`campaign-detail`)
**Deviation:** `campaign-detail` — *"the campaign detail screen (description, dates, curated
workout list, current community progress bar, individual target, per-campaign leaderboard)...
System-designed: community/individual progress bars are a small bespoke flat-rectangle fill
(CampaignProgressBar) — no existing progress-bar component was found in GSComponents.swift;
leaderboard rows mirror GroupRecapView.leaderboardRow... join/leave CTA reuses
GSPrimaryButtonStyle/GSSecondaryButtonStyle directly... Leaderboard is participants-only by RLS
construction — a non-participant sees community-total + my-progress-section omitted entirely,
plus the join CTA; captured by the campaign-detail-unjoined/campaign-detail-joined catalog case
pair. UPDATE (Task 3): the curated workout list... now built — curated_routine_ids resolves to
PublicWorkout rows, rendered as a compact tappable row list (name + owner + FEATURED tag), tapping
pushes DiscoverWorkoutDetailView. Awaiting a designer frame."*

This is the "curated lists" surface referenced in your family scope — the curated-workout-list
section within campaign detail, not a separate screen. It has **two states you must design**:
joined and unjoined (see captures below) — these are materially different layouts (unjoined omits
the community-total/my-progress sections and the leaderboard's own "You" row entirely), not just
a button-label swap.

### Home campaigns carousel (`home-campaigns-carousel`)
**Deviation:** `home-campaigns-carousel` — *"HomeView's new 'Campaigns you might like' carousel
card... System-designed: shelf shape borrows LibraryTabView.featuredShelf's kicker +
horizontal-scroll-of-cards idiom — single card full-width when only one active campaign,
ScrollView(.horizontal) for 2+. ONE card design covering both joined/unjoined states...
Deliberately NOT a nested Button-inside-NavigationLink-label... No catalog case added — HomeView
itself is not part of the debug catalog's reach set. Awaiting a designer frame."*

No catalog fixture exists for this one (HomeView has no `#if DEBUG` catalog seam at all — none of
its cards do). You'll need to review it via seeded live-app navigation, not a static capture.

### Ended-campaigns surface — ALSO a product gap, not just a design gap
This is **not** an `accepted-deviations.json` entry — it comes from the Phase C merge gate's
ledger note (`.superpowers/sdd/progress.md`, PHASE C GATE / RE-GATE entries): *"Gate Minors
ledgered for V/D handoff: ended-campaigns surface (BEFORE first real campaign ends)..."* No screen
exists today for what a user sees when they open a campaign that has already ended — the current
build only handles "Active" and "Upcoming" states (see `campaigns-tab` above). This needs product
adjudication (what does an ended campaign look like — final standings? an archive list?) as much
as it needs a frame, and it's time-sensitive: it must exist **before the first real campaign
scheduled on the content calendar ends**, not just before the next TestFlight build. Flag this to
product, not just design.

### Exercise Detail — informational, already resolved
**Deviation:** `exercise-detail` — *"Demo card shows a real mirrored photograph (free-exercise-db);
the canvas frame 14 mock uses placeholder art — photographic content can never pixel-match a mock.
Layout structure verified faithful (2026-07-16)."*

No action needed from you here — this is the precedent for how the parity harness handles
photographic content vs. a mock (it accepts permanent divergence on pixel content while still
verifying layout structure). It's included in this brief only so every `accepted-deviations.json`
entry is accounted for somewhere; treat it as closed unless you spot something new.

---

## (b) Captures available

Catalog ids (`CatalogHostView.swift`, `#if DEBUG`) — all fixture-driven since none of these
reach real backend state deterministically without live data:

| Screen | Capture id(s) |
|---|---|
| Discover grid | `discover` |
| Discover detail | `discover-detail` |
| Top Lifters | `top-lifters` |
| Campaigns tab | `campaigns-tab` |
| Campaign detail | `campaign-detail-unjoined`, `campaign-detail-joined` (two distinct catalog cases — request both) |

Not in the catalog (no `#if DEBUG` seam — view via seeded live-app navigation instead):
- `tab-library` (the 4-segment control itself — reached by opening the Library tab)
- Publish-fields UI (`RoutineBuilderView`'s publish extension — reached by publishing a routine)
- Home campaigns carousel (`home-campaigns-carousel` — reached from Home when a seeded campaign exists)
- Ended-campaigns surface — **does not exist to view**; nothing to capture until it's built

None of these have `app-*.png` captures checked in yet (`.superpowers/parity/app-ci/` predates
Phases L and C entirely). Request a fresh CI screenshot run, or generate the catalog captures
locally via the harness before your session. Reference `docs/design/frame-map.json` for the
naming convention (`app-<screenId>.png` maps 1:1 to each `CatalogScreen` raw value / frame-map key)
— do not expect embedded images in this doc, these are paths to pull, not attachments.

---

## (c) Sign-offs pending

1. **`discover-detail`'s dynamic segmented control** — needs frame examples at both 2- and
   4-segment widths.
2. **Ended-campaigns surface** — needs product adjudication (what a user sees) before it can be
   framed at all; time-sensitive (before the first real campaign ends).
3. **Publish-fields UI** — needs its first frame and a formal `accepted-deviations.json` entry
   (currently only roadmap-tracked).
4. **`_blocked-users-visible-on-boards` cross-reference** — this family's leaderboards (Top
   Lifters, Discover detail's board) are the actual surfaces that behavior-gap affects; no action
   needed here, but don't design a moderation affordance into these boards without reading that
   entry (owned by the Moderation/Settings brief).

---

## (d) Constraints

- **GSTheme token system**, four palettes (Midnight default/complete, Arena, Ink, Modernist) —
  same as every other family; see `GymSyncApp/GymSync/DesignSystem/GSTheme.swift`.
- **Reuse before inventing.** This family already borrows heavily from existing components
  (`LibraryTabView.packCard`, `.featuredShelf`, `.heroCard`; `GroupRecapView.leaderboardRow`;
  `GSPrimaryButtonStyle`/`GSSecondaryButtonStyle`; `HomeView.upcomingCard`). Your frames should
  extend this vocabulary, not introduce a parallel one — `CampaignProgressBar`'s bespoke
  flat-rectangle fill exists only because no progress-bar component was found anywhere in
  `GSComponents.swift`; if you want a real progress-bar token, that's a system-level addition
  worth flagging explicitly rather than a one-off.
- **Frame format:** `dc-runtime`/`ios-frame.jsx` (`docs/design/ios-frame.jsx`), not plain HTML —
  the plain-HTML convention only renders through the older pipeline and this family's frames need
  to run through `render_proofs.js` like everything else in Phase D.
- **The parity harness measures structural fidelity**, not photographic pixel-matching (see
  `exercise-detail` above for the precedent) — expect Discover's routine-card imagery and any
  campaign banner art to fall into the same "structural, not pixel" category once real imagery
  exists.

---

## (e) Priority order

By build-task chronology (oldest "awaiting designer frame" first — none of these are measured by
a parity percentage yet, since none has a frame):

1. **`discover`** and **`discover-detail`** (Phase L Task 3, oldest in this family)
2. **`top-lifters`** and publish-fields UI (Phase L Task 4)
3. **`tab-library`**'s 3-segment state technically predates campaigns but was superseded by its
   own 4-segment update — draw the current 4-segment state only, no need to draw the intermediate.
4. **`campaigns-tab`**, **`campaign-detail`**, **`home-campaigns-carousel`** (Phase C Task 2,
   newest of the undesigned-screen set — but time-pressured by the ended-campaigns product gap,
   which should be adjudicated in parallel with, not after, these three)
5. **`exercise-detail`** — lowest priority, already closed, included only for completeness.

This family and the Watch family are explicitly called out in the roadmap as candidates for
**last** in the family sequencing (see the overview doc) — but Discover/Library is far more
design-ready than Watch (8 real, fully-built, well-specified deviations vs. Watch's near-total
absence of formal entries) and does not carry Watch's "design once, not twice" risk. Campaigns'
sub-scope specifically should wait for venues (per the overview's rationale) but Discover proper
has no such dependency and could move earlier if capacity allows.


<div style="page-break-before: always"></div>

---

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
