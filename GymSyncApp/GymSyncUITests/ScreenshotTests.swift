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

    // MARK: - Launch

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        var env = app.launchEnvironment
        // Sourced from the UI test *process's* environment — CI's
        // `xcodebuild test` step sets these via `env:`, which XCTest inherits
        // into ProcessInfo.processInfo.environment on the Mac running the
        // test bundle. We must explicitly forward them into
        // `launchEnvironment` for the simulated app process to see them.
        if let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"] {
            env["UITEST_EMAIL"] = email
        }
        if let password = ProcessInfo.processInfo.environment["UITEST_PASSWORD"] {
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

    // MARK: - Tab screenshots

    func testHomeTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        settle()
        attachScreenshot(app, named: "tab-home.png")
    }

    func testLibraryTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Library")
        settle()
        attachScreenshot(app, named: "tab-library.png")
    }

    func testSocialTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Social")
        settle()
        attachScreenshot(app, named: "tab-social.png")
    }

    func testStatsTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Stats")
        settle()
        attachScreenshot(app, named: "tab-stats.png")
    }

    func testYouTab() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "You")
        settle()
        attachScreenshot(app, named: "tab-you.png")
    }

    // MARK: - You -> Appearance

    func testYouAppearance() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "You")
        settle()

        let appearanceRow = app.buttons["Appearance"]
        guard appearanceRow.waitForExistence(timeout: 15) else {
            XCTFail("Appearance settings row not found on You tab")
            return
        }
        appearanceRow.tap()
        settle()
        attachScreenshot(app, named: "you-appearance.png")
    }
}
