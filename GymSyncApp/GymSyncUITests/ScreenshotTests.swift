import XCTest

/// CI simulator-screenshot pipeline (infra/ci-screenshots).
///
/// Launches the app with the debug-only autologin path wired up in
/// `AuthService.bootstrap()` (reads `UITEST_EMAIL`/`UITEST_PASSWORD` from the
/// app process's environment and signs in with Supabase password auth
/// instead of waiting on Sign in with Apple, which isn't automatable against
/// a real Apple ID in CI), then walks each of the five tabs plus the
/// You -> Appearance destination, attaching a screenshot for each.
///
/// The account that signs in is the `TEST_USER_EMAIL`/`CI_TEST_USERNAME` one
/// (`ci_test_user`): `ios.yml` passes those same repo secrets in as
/// `UITEST_EMAIL`/`UITEST_PASSWORD`, and `scripts/seed_qa_fixtures.js
/// --username "$CI_TEST_USERNAME"` builds the fixture world for it.
/// `ci_test_user_2` is NOT that identity — it is the counterpart profile the
/// GymSyncTests unit target queries as a friend/block/kudos target and never
/// signs in as. This account is shared and its data mutates between runs;
/// these screenshots are for layout/visual verification only, not content
/// assertions. Deliberately no pixel-diffing here — that's a follow-up once
/// this pipeline is proven stable.
///
/// One test method per tab (rather than a single walk-through test) so a
/// failure partway through (e.g. a slow network call on the Social tab)
/// still lets every other tab's screenshot attach — `xcodebuild test`
/// continues running remaining test methods in the same target after one
/// fails.
final class ScreenshotTests: XCTestCase {

    // Generous: covers the autologin network round-trip (Supabase password
    // sign-in) plus the profile fetch that follows it before the tab bar's
    // "Home" button exists — see AuthService.bootstrap() / OnboardingCoordinator.
    private let launchTimeout: TimeInterval = 60

    /// Ceiling for the cold-launch brand overlay. The product's own worst
    /// case is 4.15 s (1300 ms brand moment + a hold capped at 2500 ms +
    /// a 350 ms fade — LaunchLoadingOverlay/RootView); 15 s is slack for a
    /// loaded CI runner, not a target.
    private let launchOverlayTimeout: TimeInterval = 15

    /// Render budget for a `captureCatalog` launch — see the comment at its
    /// only use site for why this is a constant of its own and not `settle()`.
    private let catalogRenderBudget: TimeInterval = 2.0

    override func setUp() {
        super.setUp()
        // Abort a test at its first failure: without this, XCTFail (e.g. the
        // missing-credentials guard in launchApp) records the failure but the
        // test keeps running into the 60s tab-bar wait it was meant to skip.
        continueAfterFailure = false
    }

    // MARK: - Launch

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Suppress the first-run walkthrough cover: RootView presents it when
        // OneShotFlags.walkthroughSeen(userID:) is false, and a fresh CI
        // simulator account has never seen it. The covered tab buttons still
        // EXIST in the AX hierarchy (so waitForTabBar passes) but aren't
        // hittable — every tab tap then dies in kAXErrorCannotComplete
        // scroll-to-visible. The flag itself is per-ACCOUNT
        // ("hasSeenWalkthroughV1.<uuid>"), so this argument does NOT match a
        // stored key: walkthroughSeen() honors it explicitly, reading the
        // NSArgumentDomain — which nothing ever persists — as the UI-test/QA
        // override. Nothing on disk is touched.
        app.launchArguments += ["-hasSeenWalkthroughV1", "YES"]
        // Same class of failure as the walkthrough cover: a first-visit
        // spotlight is a modal scrim, so every tab/segment tap underneath it
        // dies in kAXErrorCannotComplete scroll-to-visible. Turning tips off
        // for the suite keeps captures showing the SCREENS; the overlay
        // itself is reviewed through the `guidance-spotlight` catalog case,
        // which builds GSSpotlightOverlay directly and is unaffected.
        // (Literal, not GuidanceTip.tipsEnabledKey: the UI test target runs
        // out-of-process and links no app code. GuidanceTipTests, which DOES
        // `@testable import GymSync`, asserts the key's value so a rename
        // can't silently orphan this string.)
        app.launchArguments += ["-guidanceTipsEnabled", "NO"]
        // Pin the LOOK. Without this the 16 signed-in captures render the CI
        // account's persisted user_settings palette (a light one, lime accent)
        // while the 54 catalog captures hard-pin onyx+sky at GymSyncApp.swift
        // — the parity harness was comparing two different design languages,
        // and the owner's proofs are onyx. ThemeStore reads these from the
        // ARGUMENT domain in init() (before the first frame) and then ignores
        // load()/select(), so the network row can't repaint a capture.
        // Literals, not ThemeLaunchArgument.palette/.accent: this target runs
        // out-of-process and links no app code — same reason
        // -guidanceTipsEnabled is a literal above. ThemeStoreLaunchPinTests
        // (which DOES `@testable import GymSync`) asserts these key strings so
        // a rename can't silently orphan them.
        app.launchArguments += ["-gsPalette", "onyx", "-gsAccent", "sky"]
        var env = app.launchEnvironment
        // Sourced from the UI test *process's* environment — CI's
        // `xcodebuild test` step sets these via `env:`, which XCTest inherits
        // into ProcessInfo.processInfo.environment on the Mac running the
        // test bundle. We must explicitly forward them into
        // `launchEnvironment` for the simulated app process to see them.
        //
        // Fail FAST on missing/empty credentials: on fork PRs GitHub resolves
        // secrets to empty strings (not unset), which would otherwise send
        // every test into a doomed 60s wait at the sign-in screen.
        let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"] ?? ""
        let password = ProcessInfo.processInfo.environment["UITEST_PASSWORD"] ?? ""
        if email.isEmpty || password.isEmpty {
            XCTFail("UITEST_EMAIL/UITEST_PASSWORD not set or empty — repo secrets unavailable (fork PR?); screenshots require them")
        } else {
            env["UITEST_EMAIL"] = email
            env["UITEST_PASSWORD"] = password
        }
        app.launchEnvironment = env
        app.launch()
        return app
    }

    /// Waits for the tab bar's "Home" button (always present once auth +
    /// profile load resolve to MainTabView) as the readiness signal, then
    /// fails the calling test with a clear message if it never shows up.
    @discardableResult
    private func waitForTabBar(_ app: XCUIApplication) -> Bool {
        let homeTab = app.buttons["Home"]
        let appeared = homeTab.waitForExistence(timeout: launchTimeout)
        if !appeared {
            // Ship a PNG of whatever screen the app is stuck on — the first
            // pipeline failure was only diagnosable by frame-extracting the
            // failure .mp4s; this puts the answer straight in the artifact.
            attachScreenshot(app, named: "launch-failed.png")
        }
        XCTAssertTrue(appeared, "Tab bar did not appear within \(launchTimeout)s — autologin, profile load, or app launch may have failed")
        if appeared { waitForLaunchOverlay(app) }
        return appeared
    }

    /// Waits OUT the cold-launch brand overlay.
    ///
    /// Called from `waitForTabBar` (rather than from each test) so all 16
    /// signed-in walks inherit it. The overlay is an `.overlay` ON
    /// `MainTabView`, so the tab bar EXISTS from the same instant the
    /// overlay does — `waitForTabBar` alone is not a readiness signal, it
    /// is the signal that the overlay just appeared. The overlay then lives
    /// 1.65–4.15 s (1300 ms brand moment + a 0–2500 ms hold on
    /// `launchFetchesInFlight` + a 350 ms fade), i.e. always longer than
    /// `settle()`, which is why `app-tab-home` was captured dimmed or
    /// mid-fade on every run.
    ///
    /// `waitForNonExistence` is the right primitive precisely because
    /// SwiftUI keeps a view mounted (and its AX elements queryable) for the
    /// whole removal transition: this releases when the last pixel is gone,
    /// which no fixed sleep can promise.
    ///
    /// TWO SIGNALS, on purpose (fix round 1). The identifier wait is the
    /// PRIMARY one — it is the contract, and it is what blocks. But a query
    /// that matches NOTHING also returns "gone" instantly, so an identifier
    /// that stopped resolving would silently restore the old dim-Home bug
    /// with a green suite: the exact "checker that stops checking" failure
    /// the identifier was introduced to avoid. So:
    ///   - the query is type-agnostic (`descendants(matching: .any)`), since
    ///     the element type a SwiftUI a11y container surfaces as is not
    ///     something this suite should be betting on — the same lesson
    ///     `openYouWidget` already paid for below; and
    ///   - the caption is checked afterwards as an independent TRIPWIRE. It
    ///     is deliberately NOT the thing we wait on (it is marketing copy and
    ///     would rot), but if the overlay is genuinely still up while the
    ///     identifier wait reports success, this is what says so.
    private func waitForLaunchOverlay(_ app: XCUIApplication) {
        let gone = app.descendants(matching: .any)["launch-overlay"].firstMatch
            .waitForNonExistence(timeout: launchOverlayTimeout)
        let captionStillUp = app.staticTexts["LOADING THE BAR"].exists
        // Read both signals BEFORE asserting: `continueAfterFailure = false`
        // aborts at the first XCTFail, and a PNG of the screen that tripped
        // either one is the whole diagnosis.
        if !gone || captionStillUp {
            attachScreenshot(app, named: "launch-overlay-stuck.png")
        }
        XCTAssertTrue(gone, "Launch overlay still present after \(launchOverlayTimeout)s — every capture from this test would be taken under it")
        XCTAssertFalse(captionStillUp,
                       "launch overlay caption still on screen after the identifier wait — the launch-overlay query is probably not matching")
    }

    /// Brief settle for residual layout/animation once a REAL wait has
    /// already happened — after `waitForLaunchOverlay` (via `waitForTabBar`),
    /// after a `waitForExistence`, after a `swipeUp` whose result is checked
    /// with `isHittable`. That preceding wait is the synchronization point;
    /// this is only the tail of it, which is why it is 0.3 s and not the
    /// 1.0 s it used to be. Not removed: things still animate.
    ///
    /// If a tap changes what is about to be captured and nothing waits on the
    /// result, this is the WRONG helper — use `settleAfterNavigation()`.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// The budget after any tap that changes the captured content with no
    /// explicit wait on the result — a navigation push, a segmented-control
    /// sub-tab that swaps content (and, in `testGroupStats`, fetches it), or
    /// a tab switch captured immediately. None of those has a synchronization
    /// point of its own, so they keep the pre-2026-09-05 1.0 s rather than
    /// inheriting `settle()`'s post-wait 0.3 s. `testHomeTab` uses it for a
    /// different reason: to outlast the launch overlay's 350 ms fade in case
    /// SwiftUI releases the overlay's a11y container at the START of that
    /// removal transition rather than at the end.
    private func settleAfterNavigation() {
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(_ app: XCUIApplication, label: String) {
        let tab = app.buttons[label]
        guard tab.waitForExistence(timeout: 10) else {
            XCTFail("\(label) tab button not found")
            return
        }
        tab.tap()
    }

    /// Three-tab restructure (2026-08-12): the old Library/Stats/Shop tab
    /// destinations live behind You-grid widgets now — open one by its
    /// accessibility label ("Stats", "Routines and programming", "Coach",
    /// "Discover", "The Rack", "Settings"). Scrolls once if the widget sits
    /// below the fold.
    private func openYouWidget(_ app: XCUIApplication, label: String) {
        selectTab(app, label: "You")
        settle()
        // The widgets wrap in `.accessibilityElement(children: .ignore)`,
        // which drops the button TRAIT - `app.buttons[label]` never
        // matches them (every "widget not found" screenshot failure was
        // this one line). Query by identifier across all element types.
        let widget = app.descendants(matching: .any)[label].firstMatch
        guard widget.waitForExistence(timeout: 15) else {
            XCTFail("\(label) widget not found on You tab")
            return
        }
        if !widget.isHittable {
            app.swipeUp()
            settle()
        }
        widget.tap()
        settleAfterNavigation()
    }

    /// Routines hub → the EXERCISES row → `ExercisesListView`.
    ///
    /// Shared by `testLibraryExercisesList` and `testExerciseDetail`, which
    /// both used to do `app.buttons["Exercises"]` and both landed on the hub.
    /// `RoutinesHubView.exercisesRow` carries the SAME modifier pair as the
    /// You-grid widgets above — `.accessibilityElement(children: .ignore)`
    /// plus `.accessibilityLabel("Exercises")` — which drops the button
    /// TRAIT, so no `app.buttons[...]` query matches it, exact or predicate.
    /// The label itself is exact ("Exercises", not a composed string), so the
    /// fix is the query TYPE, not the match style: the same type-agnostic
    /// `descendants(matching: .any)` lookup `openYouWidget` already pays for.
    ///
    /// The row sits below PROGRAMS, the builder button and the routine
    /// collection, so it is usually below the fold — hence the two-swipe
    /// guard, mirroring `testActivityFeed`.
    private func openExercisesRow(_ app: XCUIApplication) {
        let exercisesRow = app.descendants(matching: .any)["Exercises"].firstMatch
        guard exercisesRow.waitForExistence(timeout: 10) else { return }
        if !exercisesRow.isHittable {
            app.swipeUp()
            settle()
            if !exercisesRow.isHittable {
                app.swipeUp()
                settle()
            }
        }
        exercisesRow.tap()
    }

    // MARK: - Tab screenshots

    func testHomeTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        settleAfterNavigation()
        attachScreenshot(app, named: "app-tab-home.png")
    }

    func testLibraryTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Routines and programming")
        attachScreenshot(app, named: "app-tab-library.png")
    }

    /// The exercises list (search + chips + list) — added 2026-07-24: this
    /// surface had no capture, which let the chips-row gap bug ship twice
    /// without CI review catching it. Reached via the You grid's EXERCISES
    /// widget since the restructure (no more Library segmented control).
    func testLibraryExercisesList() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        // EXERCISES moved into the Routines hub (owner 2026-08-16).
        openYouWidget(app, label: "Routines and programming")
        openExercisesRow(app)
        settleAfterNavigation()
        attachScreenshot(app, named: "app-library-exercises.png")
    }

    func testSocialTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settleAfterNavigation()
        // Wait for spec §3's honor line before the shutter. It is the last
        // thing the crew card learns — `SocialTabView.refresh()` reads groups,
        // friends and requests, then one task group per crew — and a fixed
        // 1.0 s settle caught it on one run and missed it on the next, which
        // made whether this capture proves the seeded crown a coin flip.
        // NOT an assertion: this file is continue-on-error by design (every
        // other wait here is a `guard … else { return }` or a bare
        // `waitForExistence`), so a crew with no crown still captures its
        // screen rather than failing the suite.
        _ = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'MOST CONSISTENT'"))
            .firstMatch
            .waitForExistence(timeout: 10)
        attachScreenshot(app, named: "app-tab-social.png")
    }

    // TWO captures from one walk, on the app-calendar-scheduling / -2
    // precedent below (:498-516). The Stats page is taller than a phone and
    // the streak card is the FIFTH block down (lifetime volume, weekly
    // volume, the LEDGER door, personal records, then streak), so the gold
    // current-streak number congruence T2.4 lands has no picture in the
    // viewport frame above. `-2` is a second ATTACHMENT, not a second
    // catalog id: no `CatalogScreen` case, no documented-id entry, no
    // frame-map id of its own. It IS a second exported file, so ios.yml's
    // FLOOR (which counts captures, not ids) moves with it.
    func testStatsTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Stats")
        attachScreenshot(app, named: "app-tab-stats.png")

        // Scroll to the streak card. GSSectionHeader renders its title
        // uppercased, so the header reads "STREAK" in the AX tree. Bounded
        // so a page that never reaches it still attaches a frame rather than
        // spinning out the test's time budget.
        let streakHeader = app.staticTexts["STREAK"]
        var swipes = 0
        while !streakHeader.isHittable && swipes < 6 {
            app.swipeUp()
            settle()
            swipes += 1
        }
        settleAfterNavigation()
        attachScreenshot(app, named: "app-tab-stats-2.png")
    }

    func testYouTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "You")
        settleAfterNavigation()
        attachScreenshot(app, named: "app-tab-you.png")
    }

    // MARK: - You -> Appearance

    func testYouAppearance() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        // Settings rows moved into SettingsView behind the You grid's
        // SETTINGS row (four-tab reorientation; the widget path is the
        // restructure's).
        openYouWidget(app, label: "Settings")

        // GSSettingsRow buttons carry a derived label of "{title}, {value}"
        // (e.g. "Appearance, Ink" — value = current palette, mutable), so an
        // exact buttons["Appearance"] never matches. Prefix-match instead.
        let appearanceRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Appearance'")
        ).firstMatch
        guard appearanceRow.waitForExistence(timeout: 15) else {
            XCTFail("Appearance settings row not found in Settings")
            return
        }
        appearanceRow.tap()
        settleAfterNavigation()
        attachScreenshot(app, named: "app-you-appearance.png")
    }

    // MARK: - Debug catalog captures
    //
    // `CatalogHostView` (Task 4, `#if DEBUG` only) presents a single target
    // view directly when `UITEST_CATALOG=<id>` is set, bypassing auth
    // entirely — no `launchApp()`/`waitForTabBar()` here, those are for the
    // real sign-in flow. One test method per catalog id (not a single
    // mega-walk) so one flaky/missing state doesn't swallow the rest, same
    // rationale as the per-tab methods above. The ids below are copied
    // verbatim from `CatalogScreen`'s raw values in
    // `GymSyncApp/GymSync/App/CatalogHostView.swift` — that enum is the
    // fixed contract; a typo'd id here silently renders nothing (the launch
    // hook only routes on `CatalogScreen(rawValue:)` success).

    /// Launches directly into a debug catalog screen and captures it.
    private func captureCatalog(_ id: String) {
        let app = XCUIApplication()
        // Kill tips and tours for catalog captures too. `launchApp()` has
        // always passed this; `captureCatalog()` passed no launch arguments
        // at all, so any catalog id whose view carries `.gsSpotlight(_:)` or
        // `.gsSpotlightTour(_:)` rendered its scrim instead of its screen —
        // `GSSpotlightTourModifier.presentIfNeeded()` and the single-tip
        // modifier both gate on `GuidanceTip.tipsEnabled`. `content_soloLiveSet`
        // worked around it per-tip with `GuidanceTip.workout.markSeen()` and
        // `crews-tab` briefly did the same with the crews tour; this one line
        // covers both, and covers every full-tab id added later (Home and You
        // carry tours as well). The overlay itself is still reviewed through
        // the `guidance-spotlight` catalog case, which builds
        // `GSSpotlightOverlay` directly and is unaffected.
        //
        // Literal rather than `GuidanceTip.tipsEnabledKey` for the reason
        // `launchApp()` gives: this target runs out-of-process and links no
        // app code, and `GuidanceTipTests` asserts the key string so a rename
        // cannot silently orphan it.
        app.launchArguments += ["-guidanceTipsEnabled", "NO"]
        var env = app.launchEnvironment
        env["UITEST_CATALOG"] = id
        app.launchEnvironment = env
        app.launch()
        // NOT `settle()`: a catalog launch bypasses `RootView` entirely, so
        // there is no launch overlay to wait OUT and nothing here is a
        // synchronization point — this sleep is the screen's whole render
        // budget. Pinned at the 2.0 s the two `settle()` calls added up to
        // before `settle()` dropped to 0.3 s. These 54 captures are the ones
        // that already look right; shrinking their only wait is not part of
        // the overlay fix.
        Thread.sleep(forTimeInterval: catalogRenderBudget)
        attachScreenshot(app, named: "app-\(id).png")
    }

    func testCatalogPRCelebration()      { captureCatalog("pr-celebration") }
    func testCatalogVoiceIdle()          { captureCatalog("voice-idle") }
    func testCatalogVoiceConnecting()    { captureCatalog("voice-connecting") }
    func testCatalogVoiceTransmitting()  { captureCatalog("voice-transmitting") }
    func testCatalogVoiceMicDenied()     { captureCatalog("voice-mic-denied") }
    func testCatalogVoiceUnavailable()   { captureCatalog("voice-unavailable") }
    func testCatalogVoiceCoachMark()     { captureCatalog("voice-coach-mark") }
    func testCatalogVoiceConnectedToast() { captureCatalog("voice-connected-toast") }
    func testCatalogVoiceMixerSheet()    { captureCatalog("voice-mixer-sheet") }
    func testCatalogOnboardingSignIn()   { captureCatalog("onboarding-signin") }
    func testCatalogOnboardingUsername() { captureCatalog("onboarding-username") }
    func testCatalogOnboardingHomeGym()  { captureCatalog("onboarding-homegym") }
    func testCatalogOnboardingHomeGymSearching() { captureCatalog("onboarding-homegym-searching") }
    func testCatalogOnboardingDone()     { captureCatalog("onboarding-done") }
    func testCatalogPushPriming()        { captureCatalog("onboarding-push-priming") }
    func testCatalogPushDenied()         { captureCatalog("onboarding-push-denied") }
    func testCatalogStatTileLoading()    { captureCatalog("stattile-loading") }
    func testCatalogStatTileError()      { captureCatalog("stattile-error") }
    func testCatalogStatTileEmpty()      { captureCatalog("stattile-empty") }
    func testCatalogRecapSolo()          { captureCatalog("recap-solo") }
    func testCatalogSessionChat()        { captureCatalog("session-chat") }
    func testCatalogGroupRecap()         { captureCatalog("group-recap") }
    func testCatalogEditProfile()        { captureCatalog("edit-profile") }
    func testCatalogReportSheet()        { captureCatalog("report-sheet") }
    func testCatalogBlockedUsers()       { captureCatalog("blocked-users") }
    func testCatalogDeleteAccount()      { captureCatalog("delete-account") }
    func testCatalogDiscover()           { captureCatalog("discover") }
    func testCatalogDiscoverDetail()     { captureCatalog("discover-detail") }
    func testCatalogTopLifters()         { captureCatalog("top-lifters") }
    func testCatalogBodyWeightLog()      { captureCatalog("body-weight-log") }
    func testCatalogPlateMath()          { captureCatalog("plate-math") }
    func testCatalogHeartRatePill()      { captureCatalog("heart-rate-pill") }
    func testCatalogCampaignsTab()          { captureCatalog("campaigns-tab") }
    func testCatalogCampaignDetailUnjoined() { captureCatalog("campaign-detail-unjoined") }
    func testCatalogCampaignDetailJoined()   { captureCatalog("campaign-detail-joined") }
    func testCatalogProgramActive()          { captureCatalog("program-active") }
    func testCatalogProgramDetail()          { captureCatalog("program-detail") }
    func testCatalogProgramTemplateDetail()  { captureCatalog("program-template-detail") }
    func testCatalogVenueLocalTab()          { captureCatalog("venue-local-tab") }
    func testCatalogVenueHub()               { captureCatalog("venue-hub") }
    func testCatalogVenueAgeGate()           { captureCatalog("venue-age-gate") }
    func testCatalogGuidanceSpotlight()      { captureCatalog("guidance-spotlight") }
    func testCatalogGuidanceDiscovery()      { captureCatalog("guidance-discovery") }
    func testCatalogBarLoader()              { captureCatalog("bar-loader") }
    func testCatalogPaywall()                { captureCatalog("paywall") }
    func testCatalogPumpComposer()           { captureCatalog("pump-composer") }
    func testCatalogPumpFeedPost()           { captureCatalog("pump-feed-post") }
    func testCatalogPumpComposerHighlight()  { captureCatalog("pump-composer-highlight") }

    // P2 restyle sweep (2026-09-03): the Settings subtree + Create Group.
    // `testYouAppearance` above is the only signed-in walk that reaches the
    // Settings subtree, and it stops at Appearance — every other restyled
    // screen sits one tap deeper, so the catalog is the only way the CI
    // artifact shows them. `appearance` duplicates `testYouAppearance`'s
    // screen deliberately: this one renders it hermetically (no auth, no
    // walkthrough cover, pinned Onyx + sky), so a restyle stays reviewable
    // even when the signed-in walk regresses — which is exactly what
    // happened between 2026-08-29 and Task 1 of this plan.
    func testCatalogAppearance()             { captureCatalog("appearance") }
    func testCatalogGymEquipment()           { captureCatalog("gym-equipment") }
    func testCatalogNotificationPreferences() { captureCatalog("notification-preferences") }
    func testCatalogRestTimerSetting()       { captureCatalog("rest-timer-setting") }
    func testCatalogHeartRateMonitor()       { captureCatalog("heart-rate-monitor") }
    func testCatalogCoaching()               { captureCatalog("coaching") }
    func testCatalogCreateGroup()            { captureCatalog("create-group") }

    // The live solo set page (screenshot-pipeline plan, Task 6). The app
    // spends more minutes on this screen than any other and it had no
    // capture at all: none of the 16 signed-in walks starts a workout,
    // because starting one writes a real session and real set logs to the
    // shared CI_TEST_USERNAME account. The catalog builds it from fixture
    // values instead (`content_soloLiveSet`), so the design round gets the
    // screen without the suite acquiring a write.
    func testCatalogSoloLiveSet()            { captureCatalog("solo-live-set") }

    // Home v2 (home-v2 catalog plan): both arrangements, each in its own
    // fixture world and in the other's. These four ARE the deliverable — the
    // owner asked to judge A and B as implemented screens rather than
    // mockups, and the CI artifact is the only way a design round sees a
    // screen before TestFlight. Production Home is untouched, so
    // `testHomeTab`'s capture still shows the live screen beside them.
    func testCatalogHomeV2Tiles()            { captureCatalog("home-v2-tiles") }
    func testCatalogHomeV2Strips()           { captureCatalog("home-v2-strips") }
    func testCatalogHomeV2TilesSoloDay()     { captureCatalog("home-v2-tiles-solo-day") }
    func testCatalogHomeV2StripsCrewNight()  { captureCatalog("home-v2-strips-crew-night") }

    // Home v3 (home-v3 ten-variations plan): ten compositions of the settled
    // kit, five on the crew night and five on the solo day. Same reason the
    // v2 four exist — the owner asked for mockups, and the CI artifact is the
    // only way a design round sees a screen before TestFlight — except that
    // these ten are meant to be looked at TOGETHER, so the plan's own
    // verification step pairs them into five two-up cards (01|02, 03|04,
    // 05|06, 07|08, 09|10). Ids are ordered so that pairing is just the
    // sorted list.
    func testCatalogHomeV301Tiles()          { captureCatalog("home-v3-01-tiles") }
    func testCatalogHomeV302Strips()         { captureCatalog("home-v3-02-strips") }
    func testCatalogHomeV303WeekTiles()      { captureCatalog("home-v3-03-week-tiles") }
    func testCatalogHomeV304TileLine()       { captureCatalog("home-v3-04-tile-line") }
    func testCatalogHomeV305Recovery()       { captureCatalog("home-v3-05-recovery") }
    func testCatalogHomeV306Milestone()      { captureCatalog("home-v3-06-milestone") }
    func testCatalogHomeV307Body()           { captureCatalog("home-v3-07-body") }
    func testCatalogHomeV308Crew()           { captureCatalog("home-v3-08-crew") }
    // The 08 addendum (home-v3 addendum targets-strip plan): 08 with Coach's
    // targets strip above the calendar, and 08 with it above join-with-code
    // as the owner phrased it. These two are their own two-up pair — the
    // composition is identical and only the strip's position differs, so the
    // frame the owner is judging is the fold. Ids sort between 08 and 09,
    // keeping the sorted list the documented one.
    func testCatalogHomeV308aTargetsAboveCalendar() { captureCatalog("home-v3-08a-targets-above-calendar") }
    func testCatalogHomeV308bTargetsAboveJoin()     { captureCatalog("home-v3-08b-targets-above-join") }
    func testCatalogHomeV309Plan()           { captureCatalog("home-v3-09-plan") }
    func testCatalogHomeV310Minimal()        { captureCatalog("home-v3-10-minimal") }

    // The weekly goal (home-v3 production plan, Stream C). Owner ruling 3 on
    // Home v3 turned one strip into five: the strip renders THIS WEEK'S
    // GOAL, of which muscle sets is one kind and miles, sessions, days and a
    // lift are the others. Seven ids cover every state it can be in — the
    // five kinds, the met week, and the week before Coach has detected
    // anything — because five renderings that exist only in a plan are five
    // decisions nobody has seen.
    //
    // The two editor ids capture the sheet's two HEADER branches rather than
    // two of its five lever sets: the standing copy line on a Coach-set
    // goal, and a Coach proposal with its ACCEPT on a user-set one (owner
    // answer 3: Coach may ask, never overwrite). Lever sets are one chip-tap
    // apart in a build; that branch is not.
    func testCatalogHomeGoalStripMuscleSets() { captureCatalog("home-goal-strip-muscle-sets") }
    func testCatalogHomeGoalStripDistance()   { captureCatalog("home-goal-strip-distance") }
    func testCatalogHomeGoalStripSessions()   { captureCatalog("home-goal-strip-sessions") }
    func testCatalogHomeGoalStripDays()       { captureCatalog("home-goal-strip-days") }
    func testCatalogHomeGoalStripLift()       { captureCatalog("home-goal-strip-lift") }
    func testCatalogHomeGoalStripMet()        { captureCatalog("home-goal-strip-met") }
    func testCatalogHomeGoalStripEmpty()      { captureCatalog("home-goal-strip-empty") }
    func testCatalogHomeGoalEditor()          { captureCatalog("home-goal-editor") }
    func testCatalogHomeGoalEditorLift()      { captureCatalog("home-goal-editor-lift") }

    // Goal-first programming (Stream D, task D7). The ladder page in the
    // three standings a block can be in — on track, falling short, met — and
    // the weekly strip once the rung it renders belongs to one.
    //
    // `home-goal-strip-block` deliberately repeats
    // `home-goal-strip-muscle-sets`' four chips: the two frames differ ONLY
    // in the kicker, which is the whole of what spec §6 changes about the
    // strip, and putting them side by side in the artifact is how a reviewer
    // sees that nothing else moved.
    func testCatalogLadderBehind()            { captureCatalog("ladder-behind") }
    func testCatalogLadderMet()               { captureCatalog("ladder-met") }
    func testCatalogHomeGoalStripBlock()      { captureCatalog("home-goal-strip-block") }

    /// `ladder-on-track`, in TWO captures from ONE id — the
    /// `calendar-scheduling` precedent directly above, and for the identical
    /// reason (task review of Stream D, finding 1).
    ///
    /// The ladder page is far taller than a phone. The headline, the date,
    /// Coach's line and eight rungs fill the first screen, so **four of spec
    /// §6's seven elements are below the fold in a single capture**: EDIT THE
    /// DATE, EDIT THIS WEEK'S RUNG, LET COACH RE-LADDER and — the one the
    /// controller's ruling for this stream is actually about — the page's ONE
    /// ACCENT PRIMARY, plus the SEE THE BLOCK door under it. Without this
    /// second frame "one primary per screen" is verifiable only by reading
    /// the source, and D7's stated job is to PROVE the stream.
    ///
    /// ONLY the on-track id gets it. The three standings share one page
    /// body — the levers and the primary are identical in all three — so a
    /// second capture of `behind` and `met` would add two frames that say
    /// what this one already says, and the artifact is a design medium, not
    /// an inventory.
    ///
    /// `-2` is a second ATTACHMENT, not a second id: `CatalogScreen`, the
    /// documented id list and `FLOOR` are all untouched, and `parity_diff.js`
    /// reports it as an unmapped capture (a warning, not a failure). The
    /// frame-map entry for 97 says so in its own `note`.
    func testCatalogLadderOnTrack() {
        let app = XCUIApplication()
        var env = app.launchEnvironment
        env["UITEST_CATALOG"] = "ladder-on-track"
        app.launchEnvironment = env
        app.launch()
        // Same budget and same reasoning as `captureCatalog` — a catalog
        // launch bypasses `RootView`, so there is no synchronization point
        // and this sleep is the screen's whole render budget.
        Thread.sleep(forTimeInterval: catalogRenderBudget)
        attachScreenshot(app, named: "app-ladder-on-track.png")

        // To the bottom. The page is a plain `ScrollView` with no competing
        // gesture, so an ordinary swipe scrolls wherever it lands; two are
        // enough to clear eight rungs and reach the foot.
        app.swipeUp()
        app.swipeUp()
        Thread.sleep(forTimeInterval: catalogRenderBudget)
        attachScreenshot(app, named: "app-ladder-on-track-2.png")
    }

    // congruence B2 T2.3 (frame 103): the block calendar's checkered flag on
    // the block's first day and trophy on its last. e52df22 claimed
    // "Proves: app-block-calendar" while no such capture existed; this is it.
    // The fixture pins the block to October 2026 so both glyphs land in one
    // month column and inside the viewport — one capture, no scroll.
    func testCatalogBlockCalendar()           { captureCatalog("block-calendar") }

    // The page the calendar card is a door onto (Stream D). Rendered from a
    // fixture world — no clock, no repository — so the frame is comparable
    // against the v7 proof and against itself on any run day.
    //
    // TWO captures from ONE catalog id, which is why this does not go
    // through `captureCatalog`. The page is taller than a phone: the month
    // card and the week's agenda fill the first screen, so the block row,
    // the campaign row and the pinned primary — everything task D4 and plan
    // D2 item 6 build — are only provable from a second frame taken at the
    // bottom. `-2` is a second ATTACHMENT, not a second id: the enum, the
    // documented id list and `FLOOR` are all untouched, and `parity_diff.js`
    // simply reports it as an unmapped capture (a warning, not a failure).
    func testCatalogCalendarScheduling() {
        let app = XCUIApplication()
        var env = app.launchEnvironment
        env["UITEST_CATALOG"] = "calendar-scheduling"
        app.launchEnvironment = env
        app.launch()
        // Same budget and same reasoning as `captureCatalog` — a catalog
        // launch bypasses `RootView`, so there is no synchronization point
        // and this sleep is the screen's whole render budget.
        Thread.sleep(forTimeInterval: catalogRenderBudget)
        attachScreenshot(app, named: "app-calendar-scheduling.png")

        // To the bottom. Both of the page's drag gestures are
        // `simultaneousGesture` and ignore a mostly-vertical translation, so
        // a swipe that lands on the grid or on an agenda row still scrolls.
        app.swipeUp()
        app.swipeUp()
        Thread.sleep(forTimeInterval: catalogRenderBudget)
        attachScreenshot(app, named: "app-calendar-scheduling-2.png")
    }

    // Goal-first programming, the door (Stream C, frames 93-96). The goal
    // screen every build now begins on, and three of its eleven milestone
    // cards — the three shapes a card can have, rather than three of one
    // shape: a picker with a load and a date, a segmented switch between two
    // ways of saying one milestone, and a card held for the block that asks
    // for no date at all.
    func testCatalogGoalScreen()             { captureCatalog("goal-screen") }
    func testCatalogGoalMilestoneStrength()  { captureCatalog("goal-milestone-strength") }
    func testCatalogGoalMilestoneBodyComposition() {
        captureCatalog("goal-milestone-body-composition")
    }
    func testCatalogGoalMilestoneRecovery()  { captureCatalog("goal-milestone-recovery") }

    // Social cards (Stage 1, frame 101) — the Crews tab's first fixture
    // world. Two crews: Push Crew carries spec §3's honor line, Sunday Squad
    // is a crew at rest and carries none (the decay is the line's absence).
    func testCatalogCrewsTab()               { captureCatalog("crews-tab") }

    // The focused session design round (group-session-and-lobby spec §8 step
    // 1, owner decision 10 — "proof frames for the live session are part of
    // the plan, after a focused design round"). Fourteen catalog ids, frames
    // 106-119, one capture each.
    //
    // Same reason the Home v3 ten exist: the group live workout has never had
    // a catalog frame at all (spec §7), the owner picks a composition before
    // any production view is touched, and the CI artifact is the only way a
    // design round sees a screen before TestFlight. Ids are ordered so that
    // the two-up pairs the controller composes — waiting a|b, warm-up solo
    // a|b, round wait a|b — are just the sorted list.
    //
    // THE LOBBY AND THE SHARED WARM-UP (frames 106-111).
    func testCatalogLobbyCrewWaitingA()      { captureCatalog("lobby-crew-waiting-a") }
    func testCatalogLobbyCrewWaitingB()      { captureCatalog("lobby-crew-waiting-b") }
    func testCatalogLobbyCrewReady()         { captureCatalog("lobby-crew-ready") }
    func testCatalogWarmupSoloA()            { captureCatalog("warmup-solo-a") }
    func testCatalogWarmupSoloB()            { captureCatalog("warmup-solo-b") }
    func testCatalogWarmupCrew()             { captureCatalog("warmup-crew") }

    // THE THREE STYLES (frames 112-117). Rounds' rest screen in its two
    // compositions, then the two states only Rounds has — the hold threshold
    // and spotter mode — then Freestyle's shared rail and Together's clock.
    func testCatalogRoundWaitA()             { captureCatalog("round-wait-a") }
    func testCatalogRoundWaitB()             { captureCatalog("round-wait-b") }
    func testCatalogRoundSkipOffer()         { captureCatalog("round-skip-offer") }
    func testCatalogRoundSpotter()           { captureCatalog("round-spotter") }
    func testCatalogFreestyleRail()          { captureCatalog("freestyle-rail") }
    func testCatalogTogetherClock()          { captureCatalog("together-clock") }

    // MARK: - Seeded deep-screen captures
    //
    // Reachable via the deterministic fixture world the QA seed builds for the
    // `CI_TEST_USERNAME` account (Task 3, `scripts/seed_qa_fixtures.js`, which
    // takes that username): a group named "[QA] Push Crew" with one
    // session in every state (scheduled/lobby_open/voting/locked/in_progress/
    // completed), a 3-message chat thread, one accepted + one pending friend,
    // and three private routines ("[QA] Push Day/Pull Day/Leg Day").
    //
    // Every navigation step below is defensive (guarded `waitForExistence`,
    // no `XCTFail`) rather than the hard-fail style `selectTab` uses for the
    // tab bar itself — the `screenshots` CI job is `continue-on-error`, and a
    // missed accessibility-label query one navigation level down should still
    // attach whatever screen the app landed on instead of aborting the test
    // with no PNG at all.

    /// Taps the Social tab's "[QA] Push Crew" group row. Deliberately CONTAINS
    /// rather than BEGINSWITH: `SocialTabView.groupRow(_:)` renders a square
    /// initials-avatar `Text` ("PC") ahead of the group-name `Text` in the
    /// same `HStack`, so the row's default composed accessibility label is
    /// "PC, [QA] Push Crew, …" — a BEGINSWITH query against the group name
    /// would never match.
    private func openPushCrew(_ app: XCUIApplication) {
        let crew = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '[QA] Push Crew'")
        ).firstMatch
        if crew.waitForExistence(timeout: 15) {
            crew.tap()
            settleAfterNavigation()
        }
    }

    /// Crew room → GroupView (behind MANAGE) → a named sub-tab.
    ///
    /// `SocialTabView`'s group row pushes `CrewRoomView`, not `GroupView`:
    /// the crew-room redesign moved the four sub-tabs (Chat/Members/Sessions/
    /// Stats) behind the room's `MANAGE` toolbar item. So every
    /// `app.buttons["Sessions"]` lookup here used to time out and leave the
    /// capture showing the crew room — four separate failed navigations, not
    /// one repeated screenshot. MANAGE is the missing first hop.
    ///
    /// GroupView's own segmented control renders each SubTab's `rawValue` as
    /// plain `Text` (no icon, no composed-label ambiguity — unlike the
    /// icon-led rows elsewhere in this file), so an exact-match button lookup
    /// is right for the sub-tab itself.
    ///
    /// `settleAfterNavigation()` on both hops rather than `settle()`: the
    /// MANAGE tap pushes a screen and the sub-tab tap swaps (and, for Stats,
    /// fetches) content, and nothing waits on either result.
    private func openManageSubTab(_ app: XCUIApplication, _ tab: String) {
        let manage = app.buttons["MANAGE"]
        if manage.waitForExistence(timeout: 10) {
            manage.tap()
            settleAfterNavigation()
        }
        let subTab = app.buttons[tab]
        if subTab.waitForExistence(timeout: 10) {
            subTab.tap()
            settleAfterNavigation()
        }
    }

    /// The crew ROOM itself, with THE CHAT preview card in frame.
    ///
    /// congruence B9: T9.2's proof used to ride on `app-session-recap`, which
    /// landed on the crew room before T-F.1 fixed that id's routing. Nothing
    /// captures the room now, so `CrewRoomView.chatPreview` — the second site
    /// wired through `ChatMessage.displayBody` — is on no frame at all. This
    /// is that frame.
    ///
    /// The swipe is `testChat`'s own defensive scroll, for its reason: the
    /// preview card is the LAST card in the room's ScrollView and can sit
    /// below the fold. It is NOT a second attachment — one capture, after the
    /// card is reachable.
    func testCrewRoom() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        let chatCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'THE CHAT'")
        ).firstMatch
        if chatCard.waitForExistence(timeout: 10), !chatCard.isHittable {
            app.swipeUp()
            settle()
        }
        attachScreenshot(app, named: "app-crew-room.png")
    }

    func testChat() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        // The crew room does NOT land on chat: it opens `ChatView` as a
        // SHEET from its `THE CHAT` preview card (`CrewRoomView`'s
        // `chatPreviewCard` sets `showChat`; the `.sheet` presents it).
        // CONTAINS because that card's composed label is "THE CHAT" followed
        // by "OPEN" and the message-preview lines.
        let chatCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'THE CHAT'")
        ).firstMatch
        if chatCard.waitForExistence(timeout: 10) {
            // The preview card is the LAST card in the room's ScrollView, so
            // it can sit below the fold — same defensive scroll
            // `testActivityFeed` uses for its Activity row.
            if !chatCard.isHittable {
                app.swipeUp()
                settle()
            }
            chatCard.tap()
            settleAfterNavigation()
        }
        attachScreenshot(app, named: "app-chat.png")
    }

    /// The sessions LIST, not a session.
    ///
    /// congruence B9: T9.1 replaced `GroupView.sessionRow`'s emoji state
    /// glyphs with SF Symbols, and every existing walk through this list
    /// (`testLobby`, `testSessionRecap`) taps straight through it to a pushed
    /// screen, so the glyphs are on no frame. This stops on the list.
    ///
    /// The seed writes one session per state — scheduled, lobby_open, voting,
    /// locked, in_progress, completed (`scripts/seed_qa_fixtures.js:306`) —
    /// and NO abandoned one, so this frame proves the completed tick and the
    /// absence of a glyph on the rest. The abandoned cross has no fixture.
    func testGroupSessions() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)
        openManageSubTab(app, "Sessions")
        attachScreenshot(app, named: "app-group-sessions.png")
    }

    func testLobby() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)
        openManageSubTab(app, "Sessions")

        // The seeded world has exactly one session per state; "Lobby Open"
        // is `"lobby_open".replacingOccurrences(of: "_", with: " ").capitalized`
        // — the state caption GroupView.sessionRow renders below "Workout".
        // All non-completed/abandoned sessions push LobbyView, so matching
        // this specific caption (rather than "Workout" alone, which every
        // row shares) is what picks the lobby-eligible row deterministically.
        let lobbySession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Lobby Open'")
        ).firstMatch
        if lobbySession.waitForExistence(timeout: 10) {
            lobbySession.tap()
            settleAfterNavigation()
        }
        attachScreenshot(app, named: "app-lobby.png")
    }

    func testSessionRecap() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)
        openManageSubTab(app, "Sessions")

        // The seeded world's one "completed" session is the only row whose
        // state caption reads "Completed" — it's in the "Past" section and
        // pushes CompletedSessionView (GroupView.sessionsList).
        let completedSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Completed'")
        ).firstMatch
        if completedSession.waitForExistence(timeout: 10) {
            completedSession.tap()
            settleAfterNavigation()
        }
        attachScreenshot(app, named: "app-session-recap.png")
    }

    func testBurpeeLedger() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        // NOT through MANAGE, unlike testLobby/testSessionRecap/testGroupStats
        // above: the ledger is one of the crew ROOM's own rows. The redesign
        // gave `CrewRoomView` a `burpeeLedgerRow` NavigationLink (inside the
        // routines-together card, under its GSDivider) labelled `BURPEES`, which pushes
        // `BurpeeLedgerView` directly — so this walk stays on the room and
        // never needs GroupView at all. CONTAINS (not exact/BEGINSWITH) for
        // the same reason testFriends/testRoutineDetail/testActivityFeed use
        // it: the row's composed label is "BURPEES" followed by each member's
        // initials avatar and outstanding count.
        let ledgerRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'BURPEES'")
        ).firstMatch
        if ledgerRow.waitForExistence(timeout: 10) {
            ledgerRow.tap()
            settleAfterNavigation()
        }
        attachScreenshot(app, named: "app-burpee-ledger.png")
    }

    func testGroupStats() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        // Stats is a GroupView sub-tab, and GroupView now sits behind the
        // crew room's MANAGE toolbar item — MANAGE is the first hop, which is
        // what `openManageSubTab` adds. The sub-tab lookup itself stays an
        // exact match: the themed segmented control renders each SubTab's
        // `rawValue` as plain Text (no icon, no composed accessibility-label
        // ambiguity — unlike Friends' icon-led row or BURPEES' avatar-trailed one elsewhere
        // in this file).
        openManageSubTab(app, "Stats")
        attachScreenshot(app, named: "app-group-stats.png")
    }

    func testFriends() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()

        // SocialTabView's "Friends" row is a NavigationLink whose label
        // composes an icon + "Friends" + optional "N new" tag + count +
        // chevron; CONTAINS is used since the exact composed string (and
        // whether the icon contributes spoken text) isn't guaranteed.
        let friendsRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Friends'")
        ).firstMatch
        if friendsRow.waitForExistence(timeout: 15) {
            friendsRow.tap()
            settleAfterNavigation()
        }
        attachScreenshot(app, named: "app-friends.png")
    }

    /// The pump feed on the LIVE account — the post `seed_qa_fixtures.js`
    /// writes, rendered by the real `PumpFeedView` against the real
    /// repositories, trajectory and all.
    ///
    /// This is the capture a fixture frame cannot stand in for: the catalog's
    /// `app-pump-feed-post` builds `PumpPostCard` directly with values, so it
    /// would look perfect while `WorkoutPostRepository.feed()`'s decode, the
    /// signed-URL fetch or the trajectory column's round trip were broken.
    ///
    /// CONTAINS, not BEGINSWITH, for the reason `testFriends` gives: the row's
    /// composed accessibility label prepends an icon and appends a subtitle.
    func testPumpFeedLive() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()

        let feedRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Pump checks from your friends'")
        ).firstMatch
        if feedRow.waitForExistence(timeout: 15) {
            feedRow.tap()
            settleAfterNavigation()
        }
        // A second settle: the feed's `.task` fetches the page, then hydrates
        // authors and reactions in a second round trip — the same two-cycle
        // wait `testExerciseDetail` and `testActivityFeed` already take.
        settleAfterNavigation()
        attachScreenshot(app, named: "app-pump-feed.png")
    }

    func testRoutineDetail() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Routines and programming")

        // The seeded "[QA] Push Day" routine card's name Text is the FIRST
        // element in its VStack (no avatar ahead of it, unlike the group
        // row above), so BEGINSWITH is reliable here.
        let pushDay = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '[QA] Push Day'")
        ).firstMatch
        if pushDay.waitForExistence(timeout: 15) {
            pushDay.tap()
            settleAfterNavigation()
        }

        // A SECOND cycle, and unconditional. RoutineDetailView's `.task`
        // fetches the routine's exercises over the network before the list
        // renders, and the tap above pushed the screen with nothing waiting
        // on it — one cycle captured the detail mid-load. Two is what every
        // other deep capture that waits on a fetch already spends
        // (`testExerciseDetail`, `testActivityFeed` below).
        settleAfterNavigation()
        attachScreenshot(app, named: "app-routine-detail.png")
    }

    func testExerciseDetail() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        // EXERCISES moved into the Routines hub (owner 2026-08-16).
        openYouWidget(app, label: "Routines and programming")
        openExercisesRow(app)
        // The tap pushes ExercisesListView; give the push its tail before the
        // app.cells query below starts looking for rows that are not on the
        // hub at all.
        settle()

        // Unlike the seeded "[QA] Push Day" routine above, exercise rows have
        // no stable predictable name to match on (the live catalog, not a QA
        // fixture) — grab the first List row directly. `ExercisesListView`
        // renders rows via `List(filtered) { NavigationLink { ... } }`, which
        // backs a table, so `app.cells` (not `app.buttons`, which would also
        // catch the muscle-filter chip row above the list) finds it.
        let firstExercise = app.cells.firstMatch
        if firstExercise.waitForExistence(timeout: 15) {
            firstExercise.tap()
        }

        // Demo frames download over the network — two cycles (mirrors
        // captureCatalog's own double budget for async image loads) before
        // capture, and both are the navigation budget: the tap above pushes
        // ExerciseDetailView with nothing waiting on it.
        settleAfterNavigation()
        settleAfterNavigation()
        attachScreenshot(app, named: "app-exercise-detail.png")
    }

    func testActivityFeed() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Stats")

        // StatsTabView's "Recent Activity" row is a NavigationLink labeled
        // "Activity" (retitled from "View sessions" for this frame) + a
        // trailing chevron — CONTAINS mirrors testFriends'/testRoutineDetail's
        // defensive row queries above since the chevron's contribution to the
        // composed label isn't guaranteed.
        let activityRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Activity'")
        ).firstMatch
        if activityRow.waitForExistence(timeout: 15) {
            // The new Stats streak card may push Activity below the fold;
            // scroll to bring it into view if needed before tapping.
            if !activityRow.isHittable {
                app.swipeUp()
                settle()
                if !activityRow.isHittable {
                    app.swipeUp()
                    settle()
                }
            }
            activityRow.tap()
        }

        // Two cycles (mirrors testExerciseDetail above) — the feed's `.task`
        // issues a network RPC call before rows render, and the tap above
        // pushed the screen with nothing waiting on it.
        settleAfterNavigation()
        settleAfterNavigation()
        attachScreenshot(app, named: "app-activity-feed.png")
    }
}
