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
/// This account (ci_test_user_2 — same one the GymSyncTests unit test target
/// uses) is shared and its data mutates between runs; these screenshots are
/// for layout/visual verification only, not content assertions. Deliberately
/// no pixel-diffing here — that's a follow-up once this pipeline is proven
/// stable.
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
        // Suppress the first-run walkthrough cover: RootView presents it off
        // @AppStorage("hasSeenWalkthroughV1"), and a fresh CI simulator has it
        // false. The covered tab buttons still EXIST in the AX hierarchy (so
        // waitForTabBar passes) but aren't hittable — every tab tap then dies
        // in kAXErrorCannotComplete scroll-to-visible. NSArgumentDomain sits
        // first in UserDefaults.standard's search list, so this overrides
        // without touching app code or persisted state.
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
        return appeared
    }

    /// Brief settle so in-flight layout/animations (tab transition, palette
    /// re-render) finish before the screenshot is taken. Not a hard
    /// synchronization point — deliberately simple per the "no brittle
    /// queries" brief.
    private func settle() {
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
    /// accessibility label ("Stats", "Routines", "Exercises", "Programs",
    /// "Discover", "The Rack", "Settings"). Scrolls once if the widget sits
    /// below the fold.
    private func openYouWidget(_ app: XCUIApplication, label: String) {
        selectTab(app, label: "You")
        settle()
        let widget = app.buttons[label]
        guard widget.waitForExistence(timeout: 15) else {
            XCTFail("\(label) widget not found on You tab")
            return
        }
        if !widget.isHittable {
            app.swipeUp()
            settle()
        }
        widget.tap()
        settle()
    }

    // MARK: - Tab screenshots

    func testHomeTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        settle()
        attachScreenshot(app, named: "app-tab-home.png")
    }

    func testLibraryTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Routines")
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
        openYouWidget(app, label: "Routines")
        let exercisesRow = app.buttons["Exercises"]
        if exercisesRow.waitForExistence(timeout: 10) { exercisesRow.tap() }
        settle()
        attachScreenshot(app, named: "app-library-exercises.png")
    }

    func testSocialTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        attachScreenshot(app, named: "app-tab-social.png")
    }

    func testStatsTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Stats")
        attachScreenshot(app, named: "app-tab-stats.png")
    }

    func testYouTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "You")
        settle()
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
        settle()
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
        var env = app.launchEnvironment
        env["UITEST_CATALOG"] = id
        app.launchEnvironment = env
        app.launch()
        settle()
        settle()
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

    // MARK: - Seeded deep-screen captures
    //
    // Reachable via the deterministic `ci_test_user_2` fixture world (Task 3,
    // `scripts/seed_qa_fixtures.js`): a group named "[QA] Push Crew" with one
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
            settle()
        }
    }

    func testChat() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        // GroupView's `subTab` defaults to `.chat`, so tapping into the crew
        // lands directly on ChatView — no further navigation needed.
        openPushCrew(app)
        attachScreenshot(app, named: "app-chat.png")
    }

    func testLobby() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        let sessionsTab = app.buttons["Sessions"]
        if sessionsTab.waitForExistence(timeout: 10) {
            sessionsTab.tap()
            settle()
        }

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
            settle()
        }
        attachScreenshot(app, named: "app-lobby.png")
    }

    func testSessionRecap() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        let sessionsTab = app.buttons["Sessions"]
        if sessionsTab.waitForExistence(timeout: 10) {
            sessionsTab.tap()
            settle()
        }

        // The seeded world's one "completed" session is the only row whose
        // state caption reads "Completed" — it's in the "Past" section and
        // pushes CompletedSessionView (GroupView.sessionsList).
        let completedSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Completed'")
        ).firstMatch
        if completedSession.waitForExistence(timeout: 10) {
            completedSession.tap()
            settle()
        }
        attachScreenshot(app, named: "app-session-recap.png")
    }

    func testBurpeeLedger() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        let sessionsTab = app.buttons["Sessions"]
        if sessionsTab.waitForExistence(timeout: 10) {
            sessionsTab.tap()
            settle()
        }

        // The Burpee Ledger row is GroupView.sessionsList's first Section,
        // always present regardless of the seeded world's upcoming/past
        // session mix (unlike testLobby's "Lobby Open"/testSessionRecap's
        // "Completed" caption matches, which depend on a specific session
        // existing in that state). CONTAINS (not an exact/BEGINSWITH match)
        // for the same reason testFriends/testRoutineDetail/testActivityFeed
        // use it above: the row's composed accessibility label prepends an
        // SF Symbol icon ahead of the "Burpee Ledger" Text, and whether/how
        // that icon contributes to the composed label isn't guaranteed.
        let ledgerRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Burpee Ledger'")
        ).firstMatch
        if ledgerRow.waitForExistence(timeout: 10) {
            ledgerRow.tap()
            settle()
        }
        attachScreenshot(app, named: "app-burpee-ledger.png")
    }

    func testGroupStats() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()
        openPushCrew(app)

        // GroupView's themed segmented control renders each SubTab's
        // `rawValue` as plain Text (no icon, no composed accessibility
        // label ambiguity — unlike the icon-led "Burpee Ledger"/"Friends"
        // rows elsewhere in this file), same as the existing `sessionsTab =
        // app.buttons["Sessions"]` exact-match lookup above.
        let statsTab = app.buttons["Stats"]
        if statsTab.waitForExistence(timeout: 10) {
            statsTab.tap()
            settle()
        }
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
            settle()
        }
        attachScreenshot(app, named: "app-friends.png")
    }

    func testRoutineDetail() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        openYouWidget(app, label: "Routines")

        // The seeded "[QA] Push Day" routine card's name Text is the FIRST
        // element in its VStack (no avatar ahead of it, unlike the group
        // row above), so BEGINSWITH is reliable here.
        let pushDay = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '[QA] Push Day'")
        ).firstMatch
        if pushDay.waitForExistence(timeout: 15) {
            pushDay.tap()
            settle()
        }
        attachScreenshot(app, named: "app-routine-detail.png")
    }

    func testExerciseDetail() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        // EXERCISES moved into the Routines hub (owner 2026-08-16).
        openYouWidget(app, label: "Routines")
        let exercisesRow = app.buttons["Exercises"]
        if exercisesRow.waitForExistence(timeout: 10) { exercisesRow.tap() }

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

        // Demo frames download over the network — two settle cycles (mirrors
        // captureCatalog's double-settle for async image loads) before capture.
        settle()
        settle()
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

        // Two settle cycles (mirrors testExerciseDetail's double-settle) —
        // the feed's `.task` issues a network RPC call before rows render.
        settle()
        settle()
        attachScreenshot(app, named: "app-activity-feed.png")
    }
}
