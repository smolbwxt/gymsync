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
