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
