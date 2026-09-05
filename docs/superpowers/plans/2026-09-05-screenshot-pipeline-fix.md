# Screenshot pipeline fix — plan

Owner ask (2026-09-05): "fix the screenshot pipeline; we had one built, but it broke somehow."
Evidence and root causes: `.superpowers/sdd/2026-09-05-screenshot-pipeline/investigation.md` (sections A–F).
Worktree: `G:/Projects/GymSync-wt/screenshot-pipeline`, branch `fix/screenshot-pipeline` off `origin/master` (028602c).

## Why it broke (short)

1. `ScreenshotTests.settle()` is `Thread.sleep(1.0)`; the launch overlay lives ≥ 1.65 s (1300 ms brand moment
   + 350 ms fade) and up to 4.15 s. The Home capture can never be clean as written. (§A.2, §B.2, §F.1)
2. Signed-in captures take the CI account's palette because `ThemeStore.load()` overwrites the onyx+sky seed
   from the network; catalog captures hard-pin onyx+sky and look right. (§C.2, §C.4)
3. The fixture world grows one orphaned `scheduled` session per `build-test` run
   (`ProposalRepositoryTests.swift:159-233` never reaches its cleanup), and `SessionRepository.upcoming()`
   has no date floor or limit, so Home's launch fetch gets heavier every run. (§F.2)
4. The QA seed has never run: `SUPABASE_SECRET_KEY` / `CI_TEST_USERNAME` are not in repo secrets and the
   fork-PR guard skips silently. (§E.1, §E.3)

## Global constraints

- Swift compiles ONLY in GitHub Actions CI. The implementer cannot build locally: mirror existing patterns
  exactly, keep every change small, and prefer additive code. One commit per task.
- Do NOT change product timing: `brandMoment = 1300 ms`, the 2.5 s cap, the 350 ms fade stay. The test waits;
  the product does not hurry. (§A.7)
- Launch-argument flags are read from `UserDefaults.argumentDomain` only (the `OneShotFlags` seam), never from
  persisted defaults, and are ungated (no `#if DEBUG`) — same convention as `-hasSeenWalkthroughV1`. State this
  in the commit message.
- A new catalog id ships as a four-part contract in ONE commit: `CatalogScreen` case + builder, the
  `CatalogScreenTests` documented-id list and count assertion, a `ScreenshotTests.testCatalog…` capture, and a
  `docs/design/frame-map.json` entry. (Lesson from the P2 plan.)
- Attribution trailer on every commit:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni`.

## Tasks

### Task 1 — Wait for the overlay, don't sleep past it
Files: `GymSyncApp/GymSync/App/LaunchLoadingOverlay.swift` (root ZStack :38-56), `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` (`waitForTabBar` :91-102, `settle` :109).
- Add `.accessibilityIdentifier("launch-overlay")` and `.accessibilityElement(children: .contain)` to the overlay's root ZStack. First a11y identifier in the app; note in a comment that this is the convention for test-visible chrome.
- Add `private func waitForLaunchOverlay(_ app: XCUIApplication)` that asserts
  `app.otherElements["launch-overlay"].waitForNonExistence(timeout: 15)`; call it from `waitForTabBar` after the tab bar exists, so all 16 signed-in tests inherit it.
- Reduce `settle()` to 0.3 s (it now follows a real synchronization point). Do not remove it.
- Register `ThemeStore.shared.load()` with `beginLaunchFetch`/`endLaunchFetch` at `RootView.swift:381-388` (one line each side) so the palette pop is hidden by the overlay for real users.

### Task 2 — Palette and accent launch arguments
Files: `GymSyncApp/GymSync/DesignSystem/ThemeStore.swift` (init :17-18, `load()` ~:133, `select`, `selectAccent`), `GymSyncApp/GymSyncTests/` (new `ThemeStoreLaunchPinTests.swift`), `ScreenshotTests.swift` (`launchApp` :52-63).
- In `ThemeStore.init()`, read `gsPalette` and `gsAccent` from `UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)` through a testable static seam `ThemeStore.launchPin(from: [String: Any]) -> (palette: String?, accent: String?)`; resolve with `GSPalettes.theme(for:)` / `GSAccents.accent(for:)`; unknown names are ignored (log once, keep the seed).
- `private let isPinned: Bool`. When pinned: `load()` returns early, `select(_:)` / `selectAccent(_:)` return early, and `restampAppearance()` runs from `init()` so UIKit chrome starts on the pinned palette.
- Unit tests for the seam: both keys present → both pinned; one missing → only that one; unknown name → nil for that key; empty dictionary → no pin. (Same shape as `OneShotFlagsTests`.)
- `launchApp()` adds `["-gsPalette", "onyx", "-gsAccent", "sky"]` alongside the two existing flags.

### Task 3 — Workflow hardening
File: `.github/workflows/ios.yml` (seed guard :196-205, simulator :220-228, export fallback :246-252).
- Seed guard: on fork PRs keep the current skip message. On non-fork refs, when either secret is missing, emit `::warning::` AND append a line to `$GITHUB_STEP_SUMMARY` naming the two secrets, then continue (do not fail the job yet — a hard fail would stop every capture until the secrets exist). Leave a `# TODO(owner): flip to exit 1 once secrets are set` comment.
- Pin the simulator by name: prefer `iPhone 16 Pro`; fall back to the first iPhone only if absent, and print which was chosen.
- After export, count `app-*.png` under `$RUNNER_TEMP/screens` and fail the step if fewer than 70; print the count either way.

### Task 4 — Stop the fixture leak
File: `GymSyncApp/GymSyncTests/ProposalRepositoryTests.swift` (:159-233).
- Ensure the session created at :159-203 is deleted (or completed) on every path, including the guaranteed FK failure on the random-UUID participant: move cleanup into a `defer` / `addTeardownBlock` so `twoParticipantSessionID` being nil no longer skips it. Keep the test's assertions unchanged.

### Task 5 — Bound the upcoming query (product fix, separate commit)
File: `GymSyncApp/GymSync/Models/SessionRepository.swift` (`upcoming()` :443-461; sibling `upcomingScheduled(_:limit:)` :326-340).
- Add the same date floor the sibling uses (`scheduled_for >= now − grace`, use the sibling's exact expression) and a `limit` (default 200) mirroring its signature. Update the doc comment at :448-451 to say why. Callers unchanged.

### Task 6 — Catalog capture of the solo set page
Files: `GymSyncApp/GymSync/App/CatalogHostView.swift` (enum :16-71 + new `content_soloLiveSet`), `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` (:50-58), `ScreenshotTests.swift` (:271-327), `docs/design/frame-map.json`.
- `case soloLiveSet = "solo-live-set"`. Builder returns `NavigationStack { WorkoutSessionView(routine:routineExercises:allExercises:) }` with a fixture `Routine` "Push A" and three `RoutineExercise`s (Bench Press 4×5 barbell, Incline DB Press 3×10 dumbbell, Dips 3×12 bodyweight) plus matching `[Exercise]`, built the way existing `content_*` builders build fixtures. Per §D.2 no app code changes are needed and no network call fires with `currentProfile == nil`.
- Registry assertion + `func testCatalogSoloLiveSet() { captureCatalog("solo-live-set") }` + frame-map entry in the same commit.

## Verification (controller)
- Push the branch, watch the `iOS` workflow, download `app-screenshots`, and check: `app-tab-home` mean luminance in the dark range and no "LOADING THE BAR" text; all 16 signed-in captures dark (onyx); `solo-live-set` present; capture count ≥ 71; job runtime vs 24 m 56 s baseline.
- Then re-check Home's "UPCOMING" count on the next two runs: it must stop growing.

## Not in this plan (need the owner)
- Add `SUPABASE_SECRET_KEY` and `CI_TEST_USERNAME` to repo secrets; then flip the seed guard to a hard fail.
- One-off cleanup of ~680 orphaned `scheduled` sessions on `ci_test_user_2` (a production-DB delete).
- Tier 1 snapshot tests (swift-snapshot-testing) as the primary renderer — proposed 2026-09-05, awaiting a yes.
- Group my-turn catalog fixture (L, §D.4).
