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
