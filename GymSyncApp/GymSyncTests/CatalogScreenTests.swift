import XCTest
@testable import GymSync

/// The catalog is the only way the parity harness reaches states that
/// navigation + seeding can't (overlays, voice-dock states, onboarding steps).
/// This guards the contract Task 5's UI test relies on: every id it drives
/// resolves to a real case, and the documented set is present.
final class CatalogScreenTests: XCTestCase {
    func testEveryDocumentedIdRoundTrips() {
        let ids = [
            "pr-celebration",
            "voice-idle", "voice-connecting", "voice-transmitting",
            "voice-mic-denied", "voice-unavailable",
            "voice-coach-mark", "voice-connected-toast", "voice-mixer-sheet",
            "onboarding-signin", "onboarding-username", "onboarding-homegym",
            "onboarding-homegym-searching", "onboarding-done",
            "onboarding-push-priming", "onboarding-push-denied",
            "stattile-loading", "stattile-error", "stattile-empty",
            "recap-solo",
            "session-chat",
            "group-recap",
            "edit-profile",
            "report-sheet",
            "blocked-users",
            "delete-account",
            "discover",
            "discover-detail",
            "top-lifters",
            "body-weight-log",
            "plate-math",
            "heart-rate-pill",
            "campaigns-tab",
            "campaign-detail-unjoined",
            "campaign-detail-joined",
            "program-active",
            "program-detail",
            "program-template-detail",
            "venue-local-tab",
            "venue-hub",
            "venue-age-gate",
            "guidance-spotlight",
            "guidance-discovery",
            "bar-loader",
            "paywall",
            "pump-composer",
            "pump-feed-post",
            "appearance",
            "gym-equipment",
            "notification-preferences",
            "rest-timer-setting",
            "heart-rate-monitor",
            "coaching",
            "create-group",
            "solo-live-set",
            "home-v2-tiles",
            "home-v2-strips",
            "home-v2-tiles-solo-day",
            "home-v2-strips-crew-night",
        ]
        for id in ids {
            XCTAssertNotNil(CatalogScreen(rawValue: id), "missing catalog case: \(id)")
        }
        XCTAssertEqual(CatalogScreen.allCases.count, ids.count, "new CatalogScreen case added without updating the documented id list — also add a ScreenshotTests capture + frame-map entry")
    }

    func testAllCasesHaveUniqueRawValues() {
        let raws = CatalogScreen.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "duplicate catalog raw values")
    }
}
