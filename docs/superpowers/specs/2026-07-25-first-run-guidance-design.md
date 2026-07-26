# First-Run Guidance — Discovery Dots + Just-In-Time Spotlights

**Date:** 2026-07-25
**Origin:** User feedback 2026-07-25: "we basically welcome a new user into an app with a
ton of features, and no direction." Refined across three rounds into TWO mechanisms that
ship together (user: "I want this along with my idea"):

1. **Discovery highlights** — the video-game pattern: when something becomes newly
   relevant, its nav item is marked so the user knows there's something to look at. The
   user chooses when to go.
2. **Just-in-time spotlights** — a semi-transparent overlay with a cutout around the key
   control, fired the FIRST time you land on a screen. Never in one blast at launch.

The dot is wayfinding; the spotlight is teaching. They hand off to each other.

---

## Non-negotiable design rules

**1. A discovery highlight must never look like a notification.** The app already uses
accent-filled indicators for *something is waiting for you*: a 9pt accent `Circle` for
unread group messages (`SocialTabView.swift:429`) and an accent `GSTag` ("3 new") for
pending friend requests (`:132`). If discovery reuses that language, users learn dots are
noise and start ignoring real friend requests — trading a real regression for a
nice-to-have.

| Signal | Look | Clears |
|---|---|---|
| Activity (existing) | **filled** accent circle / accent pill, often with a count | when you deal with it |
| Discovery (new) | **stroked ring**, `theme.text` (never accent), soft slow pulse, no count | permanently, on first visit |

Accent-filled versus white-stroked is a difference in kind, not degree, and it survives
every user accent color.

**2. Highlight progressively; hide nothing.** Games hard-lock features; a fitness app must
not. Every screen stays reachable from launch — the glow is guidance, not gating. A user
who wants to build a routine in the first ten seconds is never blocked, only un-nudged.

**3. Nothing fires twice.** Every key is one-shot and permanent. No nagging, no re-arming,
plus a global off switch.

**4. One spotlight per screen appearance.** Never stack or queue two overlays.

---

## Mechanism 1: discovery dots

A key becomes **eligible** when its milestone fires, and stays eligible until seen. Dots
roll up: an unseen key belonging to Library also lights the Library tab icon, so the user
can find it from anywhere.

### Unlock ladder (staged so day one shows exactly one thing)

| Key | Eligible when | Lights |
|---|---|---|
| `library.start` | immediately at first launch | Library tab |
| `home.schedule` | the user has ≥1 routine | Home tab |
| `stats.firstData` | the user has ≥1 completed session | Stats tab |
| `social.start` | the user has ≥1 completed session | Social tab |

Milestones come from state the app already loads (routines, session history) — **this
feature adds no backend at all: no migration, no RLS, no new queries.**

## Mechanism 2: just-in-time spotlights

On a screen's first appearance (and only if its key is unseen and tips are on), a
semi-transparent scrim covers the screen with a **cutout** around the control being
taught, plus a short copy card and a "Got it" button. Dismissal marks the key seen
forever.

| Key | Screen | Points at | Copy |
|---|---|---|---|
| `spot.home` | Home | Start-solo widget | "Start a workout any time — or schedule one below and check in when you arrive." |
| `spot.library` | Library ▸ Routines | "+ New" | "Build a routine here, or tap Discover for a ready-made one you can add in a tap." |
| `spot.builder` | Routine builder | Add-exercise row | "Add exercises, then set target sets, reps and rest. Save it and it's yours to run." |
| `spot.workout` | Live session | "Log Set" | "Log each set as you go. Beat your best on any lift and we'll call out the PR." |
| `spot.stats` | Stats | Volume card | "Everything you log lands here — volume, PRs, and per-exercise history." |
| `spot.social` | Social | Create-group control | "Start a group to train with friends: shared sessions, live turns, and a crew leaderboard." |

Together these cover the user's list: creating a routine (or using a prebuilt one),
scheduling, starting a session, logging, reading logs, and starting a group.

### Anchoring

The target view marks itself with `.gsSpotlightTarget("key")`, which publishes its frame
through a SwiftUI `anchorPreference`. The screen root carries `.gsSpotlight("key", …)`,
which reads that anchor and cuts the scrim. **The spotlight never drives navigation and
never knows about other screens** — each one is self-contained, which is what keeps this
from rotting into a cross-screen state machine. If a target is missing (layout changed,
data absent), the overlay degrades to a plain centered card rather than pointing at
nothing.

### The lifecycle gotcha

The five tab roots are mounted and unmounted on every tab switch (`RootView`'s
`MainTabView` uses a bare `ZStack`/`switch`, not a `TabView`), so `.onAppear` fires on
*every* re-selection. First-visit-ness therefore comes from the seen-store, never from
the view lifecycle.

---

## Storage

`GuidanceStore` — an `@Observable` singleton over `UserDefaults`, holding a JSON
`Set<String>` of seen keys plus the milestone flags. Device-local, matching the
`VoiceCoachMarkStore` / `hasSeenWalkthroughV1` precedent: this is per-device UI state, not
user data. Deliberately NOT `user_settings` — that table's full-row upsert discipline and
memberwise-init trap are real costs, and a re-install replaying the tips is an acceptable
(arguably correct) outcome.

The "Show tips" preference is `@AppStorage` for the same reason, with a "Reset tips"
action beside it so the whole system can be replayed for QA or curiosity.

## Relationship to the existing walkthrough

`WalkthroughView` (4-page pager, `hasSeenWalkthroughV1`) stays, with its job narrowed to
orientation — "here's what GymSync is" — and hands off to the guidance system for
instruction. No behavior change is required to it in this round.

## Testing

- `GuidanceStoreTests` (pure, no network): seen-key round-trip; a seen key never
  re-fires; eligibility gating by milestone; tab rollup returns the right tab for a key;
  tips-off suppresses everything; reset re-arms.
- Catalog screens `guidance-spotlight` and `guidance-dot` for CI capture.

## Non-goals

No server sync of seen state; no re-engagement or "you haven't tried X in a while"
nudges; no gating of any feature; no more than one spotlight per screen appearance; no
changes to existing activity badges.
