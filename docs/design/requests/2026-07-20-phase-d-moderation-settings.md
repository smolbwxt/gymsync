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
