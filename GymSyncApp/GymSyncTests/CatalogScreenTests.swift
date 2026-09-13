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
            // Social cards (Stage 2): the composer's review state, where
            // Coach's picks live.
            "pump-composer-highlight",
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
            "home-v3-01-tiles",
            "home-v3-02-strips",
            "home-v3-03-week-tiles",
            "home-v3-04-tile-line",
            "home-v3-05-recovery",
            "home-v3-06-milestone",
            "home-v3-07-body",
            "home-v3-08-crew",
            "home-v3-08a-targets-above-calendar",
            "home-v3-08b-targets-above-join",
            "home-v3-09-plan",
            "home-v3-10-minimal",
            // The weekly goal (home-v3 production plan, Stream C): the
            // strip's five kinds plus met and empty, and the editor's two
            // header branches.
            "home-goal-strip-muscle-sets",
            "home-goal-strip-distance",
            "home-goal-strip-sessions",
            "home-goal-strip-days",
            "home-goal-strip-lift",
            "home-goal-strip-met",
            "home-goal-strip-empty",
            "home-goal-editor",
            "home-goal-editor-lift",
            "calendar-scheduling",
            // Goal-first programming, the door (Stream C): the goal screen
            // and three milestone cards — the three SHAPES a card can have
            // (a picker + a load + a date; a segmented switch between two
            // ways of saying one milestone; one held for the block with no
            // date at all).
            "goal-screen",
            "goal-milestone-strength",
            "goal-milestone-body-composition",
            "goal-milestone-recovery",
            // Goal-first programming (Stream D): the ladder page in its three
            // standings, and the weekly strip once its rung belongs to a
            // block.
            "ladder-on-track",
            "ladder-behind",
            "ladder-met",
            "home-goal-strip-block",
            // Social cards (Stage 1): the Crews tab's first fixture world —
            // two crews, one with the honor line and one without.
            "crews-tab",
            // congruence B2 T2.3: the block calendar's flag/trophy glyphs.
            "block-calendar",
            // The focused session design round (group-session-and-lobby spec
            // §8 step 1, owner decision 10): Rounds' rest screen in two
            // compositions plus the hold threshold and spotter mode, then
            // Freestyle's shared rail and Together's one clock. The round's
            // lobby and warm-up ids (frames 106-111) retired to production
            // in the group-session Phase A plan (task S11) — see the
            // "production session screens" block below.
            "round-wait-a",
            "round-wait-b",
            "round-skip-offer",
            "round-spotter",
            "freestyle-rail",
            "together-clock",
            // The round's last two: the crew's consensus swap as a consent
            // card, and the pump-check post re-composed.
            "swap-consensus-card",
            "pump-check-card-v2",
            // The session round's SECOND PASS (frames 123-126 survive): the
            // ids the owner's picks produced, beside the frozen v1 ids they
            // answer. The pass's lobby and warm-up ids (120-122) retired
            // alongside their v1 siblings (task S11).
            "round-wait-v2",
            "round-spotter-v2",
            "swap-consensus-card-v2",
            "together-clock-v2",
            // The THIRD and last pass (frame 128 survives): spotter mode
            // with the zone colours put back. Frame 127
            // (`lobby-crew-ready-v3`) retired with the rest of the round's
            // lobby ids (task S11).
            "round-spotter-v3",
            // The production session screens (group-session Phase A plan,
            // task S11), frames 129-134 — what the ten retired ids above
            // became once the owner picked.
            "session-lobby-waiting",
            "session-lobby-ready",
            "session-lobby-late",
            "session-warmup-solo",
            "session-warmup-crew",
            "ladder-reladder-proposal",
            // Fix round 6, item 4: the lobby's own second screen (below the
            // fold on 129/130), so the owner can judge THE CREW'S WEEK trial.
            "session-lobby-week",
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
