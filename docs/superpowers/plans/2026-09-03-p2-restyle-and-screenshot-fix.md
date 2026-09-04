# P2 Restyle Sweep + Screenshot-Pipeline Fix — Implementation Plan (2026-09-03)

> **For agentic workers:** executed via superpowers:subagent-driven-development. Each task is one
> dispatch. Swift compiles ONLY in GitHub Actions CI (macos-15, XcodeGen) — there is no local Xcode.

**Goal:** (1) Restore the CI screenshot pipeline, which has captured the first-run walkthrough
cover instead of the app in every signed-in test since 2026-08-29. (2) Finish the P2 gs3D restyle:
the Settings subtree, the Create Group friend picker, and the Venue hub's post-sweep cards, applied
with the same per-surface judgment the P1 rounds used (commits cb5edbc, 8f082f2, 77a6c28, 609bc7d).

**Owner approval (2026-09-03):** fix first, merged to master, then the restyle. Friends list and
GroupView lists stay flat per the 2026-08-13 decision (609bc7d).

**Design authority:** `docs/superpowers/specs/2026-07-20-visual-language-redesign-design.md` (tokens,
component inventory, emoji rule) + the gs3D vocabulary in `GymSyncApp/GymSync/DesignSystem/GS3DButton.swift`
(read its header comments in full before touching any view).

## File Map

| Task | Working directory | Branch | Files |
|---|---|---|---|
| 1 | `G:/Projects/GymSync` | `fix/screenshot-walkthrough-cover` | `GymSyncApp/GymSync/Services/OneShotFlags.swift`, `GymSyncApp/GymSyncTests/OneShotFlagsTests.swift`, comment only in `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` |
| 2 | `G:/Projects/GymSync-wt/p2-settings-a` | `feat/p2-restyle-settings-a` | `GymSyncApp/GymSync/Features/You/AppearanceView.swift`, `GymEquipmentView.swift`, `RestTimerSettingView.swift`, `NotificationPreferencesView.swift` |
| 3 | `G:/Projects/GymSync-wt/p2-settings-b` | `feat/p2-restyle-settings-b` | `GymSyncApp/GymSync/Features/You/HeartRateMonitorView.swift`, `EditProfileView.swift`, `CoachingView.swift`, `SettingsView.swift` |
| 4 | `G:/Projects/GymSync-wt/p2-create-group` | `feat/p2-restyle-create-group` | `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift` |
| 5 | `G:/Projects/GymSync-wt/p2-venue-hub` | `feat/p2-restyle-venue-hub` | `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift` |
| 6 | `G:/Projects/GymSync` | `feature/p2-restyle-sweep` (after 2–5 merge) | `GymSyncApp/GymSync/App/CatalogHostView.swift`, `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` |

Tasks 2–5 touch disjoint files and run in parallel, each in its own worktree. Task 6 runs after they
are merged into the feature branch and after Task 1 has landed on master.

## Global Constraints

1. **Swift compiles ONLY in CI.** You cannot build or run tests locally. For every project API you
   use, open the declaring file and cite `file:line` in your report. No guessed signatures. Keep
   view bodies layered (split large builders into private computed vars) — Release-config
   type-check timeouts pass Debug CI and kill only the archive job.
2. **View-layer only.** No logic changes, no new features, no navigation changes, no new strings
   beyond what a treatment swap needs. Existing screens only.
3. **The gs3D vocabulary** (all in `DesignSystem/GS3DButton.swift`; precedents in
   `Features/Library/RoutinesListView.swift`, `Features/Sessions/ScheduleSessionView.swift`,
   `Features/Library/ExercisesListView.swift`, `Features/Stats/StatsTabView.swift`):
   - Static widget container → `.gs3DCard(cornerRadius: GSMetrics.radiusMd)` (radiusSm for row-sized).
   - Tappable card or row → `.buttonStyle(.gs3DCardStyle(cornerRadius: …))`; the label sheds its own
     surface fill and stroke (the lip delineates). Selection reads as an accent ring overlay
     `RoundedRectangle(cornerRadius:).strokeBorder(theme.accent, lineWidth: 2)`; `accent100`
     selection fills retire.
   - Compact accent action button → `.buttonStyle(.gs3D(face: theme.accent, cornerRadius: 10, lipHeight: 5))`.
   - Neutral extruded CTA → `.buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: GSMetrics.radiusSm))`.
   - Selectable chips → accent face when selected, neutral raised pair otherwise; they sink.
   - NEVER `theme.surface` or `theme.bg` as a face. When converting, REMOVE the old
     `.background(theme.surface)` + `.overlay(RoundedRectangle(...).strokeBorder(theme.divider, ...))`
     chrome and any `.cornerRadius(...)` that only served it.
4. **Furniture stays flat:** text fields, search fields, segmented controls, DatePickers, steppers,
   toggle rows inside an already-extruded group box, and rows inside a SwiftUI `List`. When in
   doubt, classify by the question "is this a widget the user reads, a thing the user taps, or an
   input the user types into?" — only the first two get depth.
5. **Owner laws (2026-08-13):** default text color everywhere; gold is reserved for the week
   streak; accent tint on UI text retires (chart marks and other data ink may keep accent).
   Decorative or functional emoji become SF Symbols; reaction and kudos emoji stay.
6. **Footprint:** the lip lives INSIDE the composite's frame. A fixed-height element gets a face of
   (total − lipHeight) so layout never grows. Beside a 44pt field, pin like GroupView's Add button
   (`GSPrimaryButtonStyle(verticalPadding: 8)` → 37pt face + 7pt lip = 44).
7. **SwiftUI/Swift traps:** `let x = true` is omitted from the memberwise init (use `var` for an
   overridable default); plain `private var` stored properties on a View struct privatize its
   synthesized init (`@State private` is exempt).
8. **Git:** never `git add -A`. Stage explicit paths. Commit but NEVER push. Conventional
   commit subject + body. End every commit message with these two trailer lines exactly:
   `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
   `Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni`.
9. **Report contract for restyle tasks (2–5):** the report includes a per-surface table —
   `file:line | what it is | classification (widget / tappable / furniture) | treatment applied or "left flat"` —
   covering every `.background(theme.surface)`, `strokeBorder(theme.divider…)`, `GSCard`, and
   `accent700`/`theme.accent` text tint in the task's files. That table is the review surface.

---

### Task 1: Walkthrough launch-argument override survives the per-account key

**Why:** `ScreenshotTests.launchApp()` suppresses the first-run walkthrough with
`app.launchArguments += ["-hasSeenWalkthroughV1", "YES"]`. Commit cbbdfe7 (2026-08-28, O3) made
`OneShotFlags.walkthroughSeen(userID:)` read only the per-account key
`"hasSeenWalkthroughV1.<uuid>"`, so the launch argument no longer matches. Since then the
walkthrough `fullScreenCover` sits over the app in every signed-in UI test; Xcode 26 synthesizes the
taps anyway, they land on the cover, all fifteen tab captures show the "Lift together" page, and
`testYouAppearance` fails with "Appearance settings row not found in Settings" (runs 33233675472,
33421509875). The O3 product decision — the persisted legacy device-wide key is deliberately NOT
honored, so existing users see the skippable walkthrough once more — stands. Only the
launch-argument domain, which nothing ever persists, counts as an override.

**Files:**
- Modify: `GymSyncApp/GymSync/Services/OneShotFlags.swift` (`walkthroughSeen(userID:)`, currently ~line 42)
- Test: `GymSyncApp/GymSyncTests/OneShotFlagsTests.swift` (existing class; follow its snapshot/restore style)
- Comment only: `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` `launchApp()` — the comment above the
  `-hasSeenWalkthroughV1` line says RootView reads `@AppStorage`; refresh it to say the argument is
  honored by `OneShotFlags.walkthroughSeen(userID:)` through the launch-argument domain. No code change.

**TDD required.** Write the three tests first, confirm by reading that they would fail against the
current implementation (you cannot run them; say so and explain the expected failure), then implement.

- [ ] **Step 1: Tests** (add to `OneShotFlagsTests`):

```swift
/// O3 contract: the walkthrough is per-account.
func testWalkthroughSeenIsPerAccount() {
    let a = UUID(), b = UUID()
    XCTAssertFalse(OneShotFlags.walkthroughSeen(userID: a))
    OneShotFlags.setWalkthroughSeen(userID: a)
    XCTAssertTrue(OneShotFlags.walkthroughSeen(userID: a))
    XCTAssertFalse(OneShotFlags.walkthroughSeen(userID: b), "a second account must get its own first run")
}

/// The UI-test / QA contract: `-hasSeenWalkthroughV1 YES` on the launch line lands in the
/// argument domain (never persisted) and skips the walkthrough for ANY account.
func testLaunchArgumentOverrideSkipsWalkthroughForAnyAccount() {
    let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
    var args = previous
    args[OneShotFlags.walkthroughKey] = "YES"   // launch args arrive as the string "YES"
    UserDefaults.standard.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    XCTAssertTrue(OneShotFlags.walkthroughSeen(userID: UUID()))
}

/// O3 product decision (cbbdfe7): a PERSISTED legacy device-wide key is not an override.
func testPersistedLegacyKeyIsNotHonored() {
    UserDefaults.standard.set(true, forKey: OneShotFlags.walkthroughKey)
    XCTAssertFalse(OneShotFlags.walkthroughSeen(userID: UUID()))
}
```

The existing `tearDown` calls `OneShotFlags.resetAll()`, whose walkthrough flag clears every key
with the `hasSeenWalkthroughV1` prefix — that covers the per-account keys and the legacy key these
tests write. Verify that by reading the registry entry (~line 81–92) and cite it.

- [ ] **Step 2: Implement** in `OneShotFlags`:

```swift
static func walkthroughSeen(userID: UUID) -> Bool {
    if launchArgumentSkipsWalkthrough { return true }
    return UserDefaults.standard.bool(forKey: "\(walkthroughKey).\(userID.uuidString)")
}

/// UI-test / QA override: `-hasSeenWalkthroughV1 YES` on the launch line. Read from the
/// ARGUMENT domain only — the persisted legacy device-wide key is deliberately not honored
/// (O3, 2026-08-28: an existing user sees the skippable walkthrough once more, which is
/// cheaper than a second account on the same phone silently getting none).
/// `ScreenshotTests.launchApp()` relies on this.
private static var launchArgumentSkipsWalkthrough: Bool {
    let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    guard let raw = args[walkthroughKey] else { return false }
    if let flag = raw as? Bool { return flag }
    if let number = raw as? NSNumber { return number.boolValue }
    if let text = raw as? String { return ["YES", "yes", "TRUE", "true", "1"].contains(text) }
    return false
}
```

Update the O3 doc comment above `walkthroughSeen` so it states both halves: legacy persisted key
not honored; argument domain is the test/QA override.

- [ ] **Step 3: Commit** on branch `fix/screenshot-walkthrough-cover` (already checked out in
`G:/Projects/GymSync`). Stage exactly the three files. Subject:
`fix(ci): walkthrough launch-argument override survives the per-account key`. Body: the Why
paragraph above, condensed to 5–8 lines, naming cbbdfe7 and the two red run IDs.

---

### Task 2: Settings subtree A — Appearance, Gym equipment, Rest timer, Notification preferences

**Files (all under `GymSyncApp/GymSync/Features/You/`):** `AppearanceView.swift` (125 lines),
`GymEquipmentView.swift` (223), `RestTimerSettingView.swift` (192), `NotificationPreferencesView.swift` (239).
Work in `G:/Projects/GymSync-wt/p2-settings-a` on `feat/p2-restyle-settings-a`.

**Known flat surfaces (starting points, not the whole list — audit each file):**
- `AppearanceView.swift:37` accent card (`.background(theme.surface)` + `.cornerRadius`) → static
  widget → `.gs3DCard(cornerRadius: GSMetrics.radiusMd)`. `:82–88` palette rows are `Button`s with
  surface + `strokeBorder(isSelected ? accent : divider)` → tappable rows → `.gs3DCardStyle(cornerRadius:
  GSMetrics.radiusSm)`, label sheds fill/stroke, selection = accent ring overlay (2pt). Keep the
  `selectionIndicator` and the swatch strip (`:107`, `:120` borders are part of the swatch artwork, leave).
- `GymEquipmentView.swift:79`, `:120` surface boxes → classify (widget vs. input container).
  `:207` plate toggles with `strokeBorder(isOn ? clear : divider)` → selectable chips → accent face
  when on, raised pair when off, sinking (ExercisesListView filter-chip precedent).
- `RestTimerSettingView.swift:57`, `:136–137`, `:153` bordered tiles/inputs; `:98` surface box →
  classify each; preset choices that the user taps are chips; the numeric input is furniture.
- `NotificationPreferencesView.swift:137`, `:183` surface boxes; `:159` bordered input → classify.

Apply Global Constraints 3–6 and 9. Owner law: any accent-tinted UI text in these files goes default.

- [ ] Audit every surface in the four files; fill the per-surface table.
- [ ] Apply treatments; remove retired chrome; keep footprints.
- [ ] Self-review against the vocabulary: no `theme.surface` faces, every modifier cited file:line.
- [ ] Commit (one commit for the task): `style(p2): Appearance, Gym equipment, Rest timer, Notifications join the gs3D language`, body = the per-surface decisions in prose (what got depth, what stayed furniture and why).

---

### Task 3: Settings subtree B — Heart rate monitor, Edit profile, Coaching box, Settings leftovers

**Files (all under `GymSyncApp/GymSync/Features/You/`):** `HeartRateMonitorView.swift` (181),
`EditProfileView.swift` (155), `CoachingView.swift` (338, only the bordered box at `:185–186`),
`SettingsView.swift` (1108; only two surfaces). Work in `G:/Projects/GymSync-wt/p2-settings-b` on
`feat/p2-restyle-settings-b`.

**Known flat surfaces:**
- `HeartRateMonitorView.swift:93`, `:164` surface cards → classify (status/reading cards are widgets).
- `EditProfileView.swift:73–74` bordered text field → furniture, leave. Audit the rest (avatar block,
  save CTA) for anything card-class.
- `CoachingView.swift:185–186` one `strokeBorder(theme.divider)` box → classify; the file already
  uses gs3D elsewhere, match its siblings.
- `SettingsView.swift`: `qaToolsGroupBox` (~`:475–520`, surface + `strokeBorder`) → static
  `.gs3DCard(cornerRadius: GSMetrics.radiusMd)` matching `legalGroupBox` (`:1039`) and
  `settingsGroupBox` (`:591`). `deleteAccountRow` (~`:775–777`, surface + `strokeBorder`) → neutral
  extruded CTA per GroupView's "Leave Group" footer (`Features/Social/GroupView.swift:279–293`),
  destructive label color unchanged. Leave `unitsRow` (`:412`) and `showTipsRow` (`:464`) flat —
  they are rows inside the extruded group box. The one emoji in this file: decorative → SF Symbol;
  if it is content (a reaction or kudos), leave it and say so.

Apply Global Constraints 3–6 and 9.

- [ ] Audit; per-surface table.
- [ ] Apply treatments; remove retired chrome; keep footprints.
- [ ] Self-review; cite every modifier.
- [ ] Commit: `style(p2): Heart rate, Edit profile, Coaching box, and the Settings leftovers join the gs3D language`.

---

### Task 4: Create Group friend picker joins the gs3D language

**File:** `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift` (302 lines). Work in
`G:/Projects/GymSync-wt/p2-create-group` on `feat/p2-restyle-create-group`.

**Precedent to mirror exactly:** the friend multi-select rows in `ScheduleSessionView` from commit
77a6c28 (`git show 77a6c28 -- GymSyncApp/GymSync/Features/Sessions/ScheduleSessionView.swift`):
sinking `.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm)` rows, label sheds its fills, selection
reads as a 2pt accent ring overlay, `accent100` fill retired, `.contentShape(Rectangle())` kept.

**Surfaces:** `:95–115` friend rows (`Button` with `accent100`/clear background + conditional accent
stroke) → convert per precedent; keep `selectionCheckbox` (`:225–240`) as the row's trailing
indicator. The inter-row hairline `Rectangle().fill(theme.divider)` between flat rows no longer
belongs between extruded rows — replace with vertical spacing (8pt) between rows. `:44–51` group
name text field → furniture, leave. `:143` Create CTA already `GSPrimaryButtonStyle` (extruded) — leave.

- [ ] Audit; per-surface table.
- [ ] Apply; remove retired chrome.
- [ ] Self-review; cite every modifier.
- [ ] Commit: `style(p2): Create Group friend rows join the gs3D language`.

---

### Task 5: Venue hub — leaderboard card and equipment chips

**File:** `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift` (845 lines). Work in
`G:/Projects/GymSync-wt/p2-venue-hub` on `feat/p2-restyle-venue-hub`. The check-in card (`:479–520`)
and the hub list rows (`:174`) are already gs3D — match them.

**Surfaces:**
- `leaderboardSection` (`:555–585`): the ranked list's container (`.background(theme.surface)` +
  `.cornerRadius(GSMetrics.radiusSm)`) → static widget → `.gs3DCard(cornerRadius: GSMetrics.radiusMd)`;
  keep the `GSDivider()` hairlines between rows inside it. The volume text `foregroundStyle(theme.accent700)`
  → default text (`theme.text`) per the owner law; it is UI text, not chart ink.
- `equipmentChip` (`:640–650`): owner-tappable chips → selectable chips (accent face when on,
  raised pair when off, sinking `.gs3D(...)` on the Button). Non-owner chips are display-only:
  keep them flat and quiet exactly as they are, but drop the `opacity(on ? 1 : 0.6)` dimming only
  where it no longer applies. Capsule shape stays — `.gs3D(face:lip:cornerRadius:)` takes a
  cornerRadius; use the chip's height/2 or `GSMetrics.pill`.
- `whosHereSection` rows (`:524–552`) are plain rows → leave. `VenueClaimView` (`:795`) is a
  form → furniture, leave. `LocalHubsView` / `AgeGateView` / `VenueAdvisoryView` — out of scope.

- [ ] Audit; per-surface table.
- [ ] Apply; remove retired chrome.
- [ ] Self-review; cite every modifier.
- [ ] Commit: `style(p2): Venue hub leaderboard and equipment chips join the gs3D language`.

---

### Task 6: Catalog captures for the restyled Settings screens and Create Group

**Files:** `GymSyncApp/GymSync/App/CatalogHostView.swift`, `GymSyncApp/GymSyncUITests/ScreenshotTests.swift`.
Work in `G:/Projects/GymSync` on `feature/p2-restyle-sweep` after Tasks 2–5 are merged into it.

**Why:** there is no local Xcode; the CI `screenshots` job's artifact is the only way the owner sees
a restyle before TestFlight. `CatalogHostView` (`#if DEBUG`) renders one screen directly under
`UITEST_CATALOG=<id>` with no auth; `ScreenshotTests.captureCatalog(_:)` captures it. Edit profile,
Delete account, Paywall, and Venue hub already have catalog cases.

**Add catalog ids + one test method each** for: `gym-equipment`, `notification-preferences`,
`rest-timer-setting`, `heart-rate-monitor`, `coaching`, `create-group`, `appearance`. Follow the existing
`CatalogScreen` enum + `captureCatalog` pattern exactly (read both files first; the test ids must be
copied verbatim from the enum raw values — a typo silently renders nothing). Screens that need live
services (HealthKit authorization, Bluetooth) render their unauthorized/empty state — that is fine;
if a screen cannot be hosted without a service the catalog cannot fake, skip it and say which and why.

- [ ] Add the enum cases and host wiring.
- [ ] Add the test methods.
- [ ] Commit: `test(screenshots): catalog captures for the restyled Settings screens and Create Group`.

---

## Verification (controller)

- Task 1: push `fix/screenshot-walkthrough-cover`; `build-test` green; `screenshots` job green and
  its artifact shows the You tab, Settings, and the Appearance screen (not the walkthrough). Merge to
  master (auto-deploys TestFlight).
- Tasks 2–5: merge the four branches into `feature/p2-restyle-sweep` (off master after Task 1 lands);
  push; `build-test` green; `deploy` type-check not tripped. Task 6 lands on the same branch; the
  `screenshots` artifact shows each restyled screen. Whole-branch review, then merge to master.
