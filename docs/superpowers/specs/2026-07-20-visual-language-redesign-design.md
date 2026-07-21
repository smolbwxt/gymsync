# GymSync Visual Language Redesign — Design

**Date:** 2026-07-20
**Status:** approved direction (owner, 2026-07-20). Ready for implementation planning.
**Proof artifacts (interactive):**
- All tabs — https://claude.ai/code/artifact/4cf82f59-e899-4375-9818-2be7997f2b3b
- Deeper screens — https://claude.ai/code/artifact/3bd9e8e0-3363-46c8-a592-86374ba00bb6

---

## 1. Goal

Replace GymSync's current flat "Modernist" look (light cream ground, navy ink, zero-radius sharp
slabs, dense lists) with a **near-black floating-widget language**: a near-black ground, rounded
elevated "widget" cards in lighter gray, big bold Archivo numerals, generous spacing, low noise,
and data-forward visualizations. The redesign also introduces two features and one cleanup that
fall out of the new language:

1. **User-selectable accent color** (default sky blue) — personalization.
2. **Per-group identity colors** on shared surfaces (calendar, social, leaderboards), drawn from a
   colorblind-safe palette, independent of the user's accent.
3. **Emoji → SF Symbols cleanup** for decorative/functional glyphs (reactions/kudos stay emoji).

**Explicit acknowledgment:** this re-bases the current Modernist look and the in-flight Phase D
designer frames + the 31 `accepted-deviations.json` parity entries. Those frames become "the old
look"; the design-parity baseline resets to the new language once Home ships. This is an accepted
cost, not an oversight.

## 2. Non-goals

- No backend/data/RLS changes. This is presentation only. (The separate functional-audit finding —
  the `chat_messages` block asymmetry — is unrelated and tracked elsewhere.)
- Not the app icon / pack art / exercise imagery — that art track runs through Recraft separately
  (`docs/design/RECRAFT-ART-PROMPTS.md`). This spec only reserves the *frames* those assets fill.
- Reactions and kudos remain emoji (see §7); only decorative/functional emoji are replaced.

**Coverage is NOT a non-goal — it is required.** Owner directive (2026-07-20): *every* feature we
have built, and *every* null/empty/first-run/loading state, must be redesigned in this language —
nothing is left in the old style and no state is left undesigned. §5–§6 define the reusable
components; §10 is the exhaustive feature inventory each must be applied to, with a defined empty
state per feature. "Inherits the components" is acceptable for a screen only when that screen's
layout + its empty state are explicitly confirmed against §10, not assumed.

## 3. Design tokens (the foundation)

The current `GSTheme` is a multi-palette struct (midnight/arena/ink/modernist) with **no radius or
elevation tokens** (Modernist is deliberately flat/zero-radius) and with the **accent baked into
each palette**. Two structural changes are required:

**A. Decouple accent from palette.** The palette supplies the near-black surface/neutral system;
the **accent is a separate, user-chosen dimension** layered on top. `GSTheme` gains an `accent`
group that is set independently of the surface palette.

**B. Add radius + elevation tokens.**

New default palette — **"Onyx"** (near-black), values verbatim for implementation:

| Role | Token | Value |
|---|---|---|
| Ground | `bg` | `#0A0B0D` |
| Elevated surface (widgets) | `surface` | `#16181D` |
| Nested / pressed surface | `surface2` | `#1E222A` |
| Hairline border | `hair` | `rgba(255,255,255,0.07)` |
| Primary text | `text` | `#F3F5F8` |
| Secondary text | `muted` | `#868B95` |
| Tertiary / disabled | `dim` | `#5C616B` |

Accent (user-chosen; default **Sky blue**), each preset carries three values — base, soft (tint),
on-accent (text/glyph on a filled accent):

| Preset | base | soft | on-accent |
|---|---|---|---|
| Sky blue (default) | `#38BDF8` | `rgba(56,189,248,.15)` | `#04222E` |
| Violet | `#A78BFA` | `rgba(167,139,250,.16)` | `#1C1233` |
| Amber | `#FFB020` | `rgba(255,176,32,.16)` | `#2A1C04` |
| Lime | `#B6F236` | `rgba(182,242,54,.15)` | `#1C2A06` |
| Coral | `#FF6B5E` | `rgba(255,107,94,.16)` | `#2E0F0B` |
| Rose | `#FB7BB5` | `rgba(251,123,181,.16)` | `#2E0F20` |
| Mono | `#F3F5F8` | `rgba(255,255,255,.12)` | `#0A0B0D` |
| Custom | user hex | `hex @ ~15%` | derived (dark or light for contrast) |

Radius: `sm 16`, `md 24` (default card), `pill 999`. **No more zero-radius.**
Elevation: `sm 0 2px 8px rgba(0,0,0,.35)`, `md 0 8px 24px rgba(0,0,0,.40)`, widget rest = hairline
border + `md`.
Type: **Archivo** (already bundled) — Bold 700 for headings/numerals (tight `-0.02em` to `-0.03em`
tracking), Regular 400 body; uppercase kickers at 10–11px, `+0.13em` tracking, `muted`.
Spacing scale: `4 / 8 / 11 / 16 / 24` (already close to today's `--space-*`).

## 4. The two color systems (core architecture)

The single most important rule: **personal accent and group identity are independent systems that
never resolve to the same token.**

**Personal accent** — one hue the *user* picks (default sky blue). Applies only to *the user's own*
UI: primary buttons, active tab, streak ring, PR flame, solo calendar markers, chart strokes, the
"you" row in leaderboards, selection/focus states. Persisted per user; changing it recolors the
whole app instantly (one token flip).

**Group identity colors** — one color (or profile photo) per *group*, applied only where a group
appears: group cards, group avatars, that group's calendar dots, group rows in feeds/leaderboards.
Never change with the accent.

- **Palette:** the **Okabe-Ito** colorblind-safe qualitative set —
  `#E69F00` orange, `#009E73` bluish-green, `#CC79A7` reddish-purple, `#0072B2` blue,
  `#D55E00` vermilion, `#F0E442` yellow, `#56B4E9` sky, `#000000`/gray. Distinguishable under
  deuteranopia/protanopia/tritanopia.
- **Assignment rule:** deterministic and **stable** per group — hash `group.id` → Okabe-Ito index.
  Group color is **independent of the user's accent and never changes when the accent changes**
  (a group's color is part of its identity). Because assignment is deterministic, no storage is
  required for the default; add a nullable `groups.color` override column for the power-user path.
- **Collision avoidance lives on the accent side, not the group side.** The Okabe-Ito group set and
  the accent presets are mutually distinct by construction, and role separation (accent on *your*
  controls, group color on *group* surfaces) disambiguates context. Only the custom-hex accent path
  can land near a group color; that is the user's deliberate choice, so we do not move group colors
  to compensate (the accent picker MAY show a soft "close to a group color" nudge, but never
  recolors a group).
- **Override:** a group admin may open a **color wheel / hex** picker to choose deliberately; once
  chosen, we stop guarding accent collisions (their choice wins).
- **Profile photo:** where a group has a photo and the surface is large enough (group cards,
  session rows), show the photo; the color remains the identity everywhere too small for a photo
  (calendar dots, tight avatars).

**Calendar treatment (resolved):** the dot-grid is **texture** (density of training) — do not ask
anyone to decode 6px group colors. Precise group attribution lives in the larger **upcoming-session
rows** with group avatars. A few recent dots may carry group color as flavor, but correctness never
depends on distinguishing them.

## 5. Component inventory

Built on the tokens above; each is a reusable SwiftUI view.

**Shared primitives:** `Widget` (surface + `md` radius + hairline + `md` elevation + 16 padding);
`StatTile`; `SectionKicker`; `PrimaryButton` / `SecondaryButton` (full-width, label + optional
leading/trailing SF Symbol — **fixes the current "text-rectangle-in-a-circle" bug**: the inner label
must inherit the button's fill, never a mismatched shade); `SegmentedControl`; `Chip`; `Avatar`
(photo or colored initials, square-rounded for groups, circle for people).

**Layout-correctness laws** (both surfaced as real bugs during proofing — encode them so SwiftUI
does not repeat them): (1) a label that must sit *below* a fixed-size circular container (avatar,
ring) is a **sibling of that container, never a centered child** — otherwise it overflows the
circle (the "Now lifting" bug). (2) a button's inner label inherits the button's own fill; it never
carries its own background shade (the "text-rectangle-in-a-circle" bug). Every widget must contain
its content within its own bounds at all Dynamic Type sizes.

**Home:** context-aware `PrimaryCTA` (smart primary + **persistent** "Start solo workout"
secondary); `PRCard`; `StreakRing` (ring = progress to next streak milestone, flame + count center);
`TrainingCalendar` (month dot-grid texture + legend + group-avatar upcoming rows); stat tiles.

**Stats:** `VolumeHero` (big number + trend delta); `AreaChart` (weekly volume); `PRList` (lift ·
weight · date · accent up-arrow); `Sparkline` (body weight).

**Social:** `HubHero` (cumulative crew volume this week + your share + stacked member avatars);
`GroupCard`; `ActivityFeedRow`.

**Library:** `SegmentedControl` (Routines/Exercises); `PackCard` (art frame + tag + title);
`RoutineCard` (bounded card, title/subtitle/tags/chevron — resolves the "left-justified feels
unpolished" note by anchoring content in a card).

**You:** `ProfileHeader` (avatar + name + handle + stat row); `AccentPicker` (presets + custom
wheel/hex — the accent's real home); `SettingsRow` (SF Symbol + label + value + chevron).

**Deep screens & nav:** top-level tabs use the bottom **tab bar**; pushed/deep views use
**back-nav + a fixed bottom action bar** carrying the screen's primary action.
- Live session: `NowLiftingHero` (current lifter, accent ring, set, chess-clock); `TurnStrip`
  (done ✓ / current / queued / no-show-dimmed); `ReactionPills` (**emoji retained**) + soundboard;
  state-driven bottom bar ("You're up next" → "Log set" on your turn).
- Solo workout: elapsed timer; `SetRow` list (logged ✓ / current); inline log; `RestTimer`; up-next.
- Exercise detail: art hero frame; muscle chips; best + est-1RM trend; how-to steps; two-part bottom
  bar (Add to routine / Log a set).
- Campaign: banner + tag; community progress bar; your contribution (accent); leaderboard with the
  **you-row highlighted**; join action.

## 6. Empty / first-run states (do not skip)

The redesign is won or lost here — premium dark dashboards collapse into sad boxes when empty.
Every empty state is **card-anchored and left-aligned inside a widget with an inviting action** —
never centered text floating on the ground (the current "No crew yet" failure).

- **Home:** no PR yet → a "Log your first lift" widget in the PR slot; streak 0 → ring empty with
  "Start a streak today"; no groups/upcoming → the calendar widget shows an invite/"find a crew"
  prompt inside its own frame; solo CTA always present.
- **Social:** no crew → a real hub-shaped card ("Start a crew or add a friend") with the action
  inside it, plus a preview of what the hub will show — not a centered icon.
- **Stats:** no data → the hero and chart render as labeled empty widgets with "Your first workout
  fills these in," not blank space.
- **Library:** no routines → a create-first-routine card beside the featured packs.

## 7. Emoji cleanup (folds into this visual pass)

Decorative/functional emoji clash with the app's SF Symbol chrome (116 `systemName:` uses already).
Replace, rendered in the accent or `muted` via tokens:

| Location | Now | → SF Symbol |
|---|---|---|
| Campaign "Completed" tag | 🌊 | `checkmark.circle.fill` |
| PR headers / streak values | 🔥 | `flame.fill` |
| PR-of-month | 🏆 | `trophy.fill` |
| Attachment labels | 📷 / 🎤 | `camera.fill` / `mic.fill` |
| Sound messages / soundboard fallback | 🔊 | `speaker.wave.2.fill` |

**Keep as emoji:** reaction pickers (`👍🔥💪😂`, `🔥💪😂👏`) and the kudos picker
(`💪🔥👏🏆⚡`) — reactions are conventionally emoji and read as friendly; the kudos set is also
server-`CHECK`-enforced, so it is a data contract, not decoration.

## 8. Implementation approach & rollout

**Foundation (Task group 1):** extend `GSTheme` to decouple accent from palette + add radius/
elevation tokens + the Onyx default palette; extend `ThemeStore` to hold and persist the user's
accent (default sky blue) and expose `setAccent`; add the deterministic group-color helper
(Okabe-Ito + accent-collision skip) + nullable `groups.color` override; update `GSComponents`
(rounded, elevated, button-label fill fix).

**Rollout order (owner-approved: Home first as proof):**
1. **Home** — foundation tokens + all Home widgets + the `AccentPicker` (even though it lives on
   You, it must exist to drive Home) + empty states. Ship, verify in CI screenshots.
2. **Stats**, **Social** (+ empty), **Library**, **You** — each a small independent merge inheriting
   the foundation.
3. **Deep screens** — live session, solo workout, exercise detail, campaign.
4. **Emoji cleanup** — swept per-screen as each screen is touched (not a separate branch).

Each screen merges independently, CI-gated; Swift compiles only in CI (macos-15), verified via the
screenshots job, not a local device.

**Parity harness:** once Home ships, the design-parity baseline (`frame-map.json`,
`accepted-deviations.json`) resets to the new language; the Phase D designer briefs are superseded
for redesigned screens and should be re-based rather than executed against the old frames.

## 9. Success criteria

- Every redesigned screen renders in Onyx with rounded, elevated widgets and Archivo numerals;
  no cream/navy/zero-radius surfaces remain on those screens.
- The accent picker (You + first-run) changes every accent-bound element app-wide instantly and
  persists across launches; group colors visibly do **not** move with it.
- Group colors are drawn from Okabe-Ito, deterministic per group, never colliding with the current
  accent (default path).
- Every redesigned screen has a defined, card-anchored empty state (no center-center floats).
- No decorative/functional emoji remain on redesigned screens; reactions/kudos remain emoji.
- The outlined-button "text-rectangle-in-a-circle" rendering bug is gone.
- **Every feature in §10 is redesigned in Onyx and has a defined, card-anchored null state.**

## 10. Full feature inventory (coverage checklist)

Every item below must ship in the new language with an explicit empty/null state (loading skeleton,
zero-data, error, and first-run where applicable). "Proof ✓" = a bespoke mockup exists; "proof —" =
still to be drawn (composed from §5 components, but its layout + null state must be explicitly
designed and confirmed, not assumed). No item may remain in the old Modernist style.

**Onboarding & auth** (proof —): sign in / sign up · home-gym setup (+ searching) · push-priming.

**Home** (proof ✓): + null: no PR, streak 0, no groups, no upcoming sessions, first-run.

**Library** (proof ✓ list/detail): Routines · Exercises · Exercise detail (proof ✓) · Routine
builder/editor (proof —) · Pack detail (proof —). Null: no routines, empty exercise search.

**Social** (proof ✓ hub/list/feed): Group detail (proof —) · Group stats (proof —) · Friends +
add-friend (proof —) · Chat, group + session (proof —). Null: no crew (proof — redesign of "No
crew yet"), no friends, empty chat, empty feed.

**Sessions / live** (proof ✓ live + solo): Schedule session (proof —) · Lobby / check-in (proof —)
· your-turn "Log set" state (proof —) · Session recap solo (proof —) · Group recap (proof —) ·
Completed session detail (proof —) · Recurring series (proof —) · PR celebration overlay (proof —)
· Burpee ledger (proof —) · Soundboard library (proof —) · Kudos send (proof —). Null: no upcoming.

**Stats** (proof ✓ overview): Activity/sessions list (proof —) · Per-exercise history (proof —) ·
Body-weight log (proof —). Null: no data on each.

**Campaigns / Discover** (proof ✓ campaign detail): Campaigns tab (proof —) · Ended campaign
(proof —) · Discover (proof —) · Top lifters (proof —) · Discover-workout detail (proof —). Null:
no campaigns, empty discover.

**You / Settings** (proof ✓ profile + appearance): Edit profile (proof —) · Notifications (proof —)
· Calendar sync (proof —) · Heart rate & health (proof —) · Privacy & blocking (proof —) · Blocked
users (proof —, null: none blocked) · Report sheet (proof —) · Delete account (proof —) · Account
(proof —).

**Watch (watchOS)** (proof —, round-scaled): whose-turn · log-set · soundboard · burpee ledger ·
HR pill/zones. Null: idle/waiting.

**Voice / live audio (PTT)** (proof —): coach mark · mixer sheet · transmit hero · HR pills ·
offline/syncing states.

**Cross-cutting states** — for every data surface above: loading skeleton, offline/stale, error,
and empty must each be styled in the new language (card-anchored, never center-center floats).

**Proof generation plan:** remaining bespoke proofs will be produced in grouped sheets
(onboarding · session lifecycle · campaigns/discover · settings/moderation · watch/voice · a
dedicated **null-states gallery**) before or alongside each rollout phase in §8, so no screen is
implemented without an approved target.
