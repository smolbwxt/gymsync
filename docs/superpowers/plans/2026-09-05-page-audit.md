# Every page vs the design rules — audit checklist (2026-09-05)

Source of truth for "flag to change". Judged from the REAL rendered screens of the first seeded CI
screenshot artifact (run 33991668722, 71 captures, Onyx + sky), by two visual reviewers working from
`docs/superpowers/specs/2026-09-05-design-language.md`, cross-referenced against the earlier code
sweep (`.superpowers/sdd/2026-09-04-investigations/design-love-sweep.md`). Per-screen tables with
every finding: `visual-audit-A.md` (sheets 1–6) and `visual-audit-B.md` (sheets 7–12), same directory.

## Scoreboard

| | Screens |
|---|---|
| Captured | 71 |
| Follow the rules | 11 |
| Deviate | 48 |
| Cannot judge | 12 (8 captures land on the wrong screen, 2 mid-load, 2 debug harness) |

Nothing here is a regression from the pipeline fix; this is the first time the app has been looked at
whole, in its own palette, against written rules.

## The fixes, as batches (cross-screen patterns first — one fix, many screens)

Ranked by screens healed per change. Each batch is one implementation plan.

### B1. Accent discipline (≈20 screens)
- **Escape hatches go neutral.** Cancel, Skip, "Not now", the report sheet's Cancel: `muted` text, never accent. The accent moves to the act (Save, Set home gym, Turn on notifications, Submit). Screens: body-weight log, delete account, create group, both home-gym steps, both push screens, report sheet.
- **No decorative accent on readouts.** Leaderboard rank-1 numbers and per-row "≈ k lbs/wk", the "you"-row tint (use `neutral400@0.2`), `Active` / `FEATURED` tags (Active → green), campaigns-tab meta lines, the paywall's feature title, Top Lifters avatar tiles, venue-hub equipment chip outlines, the connected toast (presence → green). Build ONE shared leaderboard-row component instead of four call-site edits.
- **Full-bleed accent heroes become a raised face**, leaving the screen's one button as the only accent: group recap, solo recap, completed session, the paywall's "Coming soon" slab (becomes a line of copy).
- **Two primaries → one.** Create Group has a toolbar Create and a body Create Group; Schedule has Next + Schedule; the paywall has Monthly + Yearly. Keep the act, demote the twin.

### B2. Gold discipline (6 screens)
- Gold ON: the week-streak number on Home (`174` renders white today) — the crew room's "weeks strong" already has it right.
- Gold OFF: Shop's Pro title and rack countdown, My Rack's countdown, Stats' Pro gate line, Block calendar's "block ends" fill/label/legend.

### B3. Surfaces (≈10 screens)
- Flat-on-page bodies onto raised cards: campaign detail (both states), paywall feature block, exercise detail's stat tiles (its HOW TO card already does it right), Discover's tappable exercise rows, Routine Builder's per-exercise card (the busiest edit surface in the app, zero gs3D today), the legacy Group screen behind MANAGE.
- Radii to the two canonical sizes: the six Coach consult screens (12–18 today), Burpee ledger (20).
- The stat-tile empty state's dashed outline is a third surface idiom; make it the raised face.
- Two clipping bugs: Discover cards sized to content; Routines & Programming list gets a tab-bar bottom inset; venue-hub chip row no longer clips at the edge.

### B4. The talk control (component, 4 captures)
Today it is two objects (accent mic circle + pill), sentence case, no waveform, and while transmitting the pill stays neutral while the circle goes accent — the inverse of the rule. Rebuild as ONE neutral raised pill, `HOLD TO TALK` with the small accent waveform at rest, solid accent `TALKING · RELEASE TO STOP` while transmitting, in its own home above the primary. Also: the voice coach mark is a white system popover on the Onyx app — re-skin on the raised face; the voice mixer ships two disabled "Coming soon" toggles — remove; `Voice unavailable` says nothing actionable while its sibling `Mic access off — turn on in Settings` is the model — match it.

### B5. Home (the approved direction, awaiting the owner's tiles-vs-strips pick)
No primary today (the only button is the neutral quiet-pill string), no gold, no Coach line. Implement the one state-reading button that never auto-starts, the gold streak, the Coach line one tap from Home, and the calendar that folds its appointments and opens the scheduling page.

### B6. PR splash (1 screen)
Order is inverted: an accent flame lands first and the headline is a small muted kicker. Rule: headline first, big, in accent; line sweeps under; then the number and ring. No kudos row.

### B7. Green means done (token + 6 screens)
`GSTag` has no success style, so "completed / live / applied / present" fall back to accent or to the wrong green. Add one green style on the canonical hex (`0x2FA45C`), then use it: program ledger COMPLETED, coach rules LIVE, proposal Approved, lobby presence dot, crew presence dot (accent today; the crew avatar tile is orange, a colour outside the language), connected toast, `Active` tag.

### B8. Copy (≈12 screens)
- Weight convention on every entry surface: derive the kicker from equipment (`TOTAL INCL. BAR` / `PER HAND` / `TOTAL ADDED`) on the live set card AND the plate-math sheet (it shows `Weight (lbs)`, so a string-keyed fix misses it). This is field-report item #2.
- ~~Button case sweep~~ — **dropped by owner ruling 2026-09-05**: buttons are not required to be caps; existing labels stay as they are.
- `Abandon program` is red; red is for errors — use the raised face with default text.
- Notifications-denied: the capture is byte-identical to the priming screen and still offers "Turn on notifications". First verify whether the catalog's forced `.denied` status is being overwritten (PushPrimingView reads `pushReceiver.authorizationStatus`; the fixture passes `catalogAuthorizationStatus: .denied`) — if the app's real denied branch works, fix the fixture; if not, the screen needs "Notifications are off" + OPEN SETTINGS.
- Empty states invite (Blocked Users row rebuild: fixed-width right-aligned UNBLOCK, list surface, back button).

### B9. No decorative emoji (2 screens)
Group screen's ✅ / 🌫️ session-state glyphs → SF Symbols; the crew room's chat preview prefixes system PR lines with a literal 🔥 (reactions stay; this is chrome).

### B10. You tab (1 screen, the v5 proof)
Widget words are right; the lines under them are contents lists, not state sentences, and the milestone hero is absent. This is the approved You v5 design — implement it.

### B11. Questions above the fold (1 screen)
Program template detail buries its two required FOCUS pickers below an eight-row readout with the primary disabled until answered. Move the pickers above THE PLAN.

## Test-fidelity fixes (so the next audit can see every screen)

- **8 mis-navigated captures**: `app-lobby`, `app-chat`, `app-burpee-ledger`, `app-group-stats`, `app-session-recap` land on the crew room; `app-exercise-detail`, `app-library-exercises` land on the Routines hub. Cause: the tests tap a `Sessions` sub-tab that the crew-room redesign moved behind MANAGE, and the walk falls through to whatever is on screen. Update the navigation in `ScreenshotTests.swift` (MANAGE → Sessions sub-tab → row by state caption).
- `app-routine-detail` captured mid-load (spinner) and highlights the You tab while showing a Library screen — wait for content; check the tab-selection bug.
- `app-onboarding-push-denied` fixture (see B8).
- Four stale `ci_test_user_2` comments (ScreenshotTests:420,427; ios.yml:147; CatalogHostView:1476).
- The seed emits "0 lbs PR" chat lines for bodyweight Murph sets — cosmetic, seed-side.
- Streak inflation on the CI account (~6 per run from residue check-ins, now stopped by the leak fix) — reset after the residue cleanup.

## Retire or downgrade from the code sweep (pixels disagree)

- `CreateGroupView` "both toolbar buttons accent": Create renders disabled grey; the real defect is the duplicate Create (B1).
- "Clean" verdicts contradicted by pixels: the Onboarding subtree, `FriendsView`, `BlockedUsersView`, `GroupRecapView`, `NotificationPreferencesView`, `HeartRateMonitorView`, `CoachingView`, `EditProfileView`, `SoloRecapView`, `HomeView`.
- Downgrade: `StatsTabView` gold gate (not rendered in this state); the literal `"WEIGHT · LBS"` string fix (covers half the surface — see B8).
- Confirmed from pixels: rank-1 accent in campaign detail and Discover detail; the `accent100` me-row; the flat paywall block; Top Lifters rank accent; the weight-convention gap.

## Owner rulings (2026-09-05)

1. Sign-in splash keeps its full-bleed accent — the one allowed exception. **Answered: yes.**
2. Heart-rate zone ramp is data colour, exempt like plate colours. **Answered: yes.**
3. Buttons are not required to be caps; existing labels stay. **Answered** — the caps sweep is dropped.
4. Home: both arrangements are being built as real SwiftUI in the catalog (`docs/superpowers/plans/2026-09-05-home-v2-catalog.md`); the owner picks A, B, or a mix from the rendered frames.

## Suggested order

B4 talk control and B7 green token first (components: many screens, no product decisions). Then B1 + B2 + B9 as one "colour discipline" plan. Then B3 surfaces. Then B8 copy. Home (B5), PR (B6), You (B10) ride with the approved proofs. Test-fidelity fixes go with the snapshot-tests work so the next audit sees all 71.
