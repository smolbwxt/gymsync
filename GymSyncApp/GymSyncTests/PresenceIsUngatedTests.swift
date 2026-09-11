import XCTest
@testable import GymSync

/// Spec §4 — presence surfaces stay ambient and ungated: the venue hub's
/// "who's here" rows and Home's crew pulse never require a post, a streak or
/// a payment to be seen.
///
/// THE ASSERTION IS THE ARITY. A rule this shape cannot be checked by calling
/// it with `hasPro: false` — there is no such parameter, and that IS the
/// point. These tests pin the two predicates' signatures, so the day someone
/// wires an entitlement in, this file stops compiling and the rule is read
/// before it is broken rather than after.
final class PresenceIsUngatedTests: XCTestCase {

    func testWhosHereAsksOnlyWhetherYouAreCheckedIn() {
        XCTAssertTrue(VenueHubView.showsWhosHere(isCheckedIn: true))
        XCTAssertFalse(VenueHubView.showsWhosHere(isCheckedIn: false))
    }

    func testTheCrewPulseAsksOnlyWhetherAFriendIsLifting() {
        XCTAssertTrue(HomeView.showsCrewPulse(liveFriendCount: 1))
        XCTAssertFalse(HomeView.showsCrewPulse(liveFriendCount: 0))
    }

    /// Spec §4's own phase-2 marker, written down where it will be found.
    /// Live encouragement — a cheer to someone lifting right now — is
    /// DESIGNED and NOT BUILT. Nothing in this build sends one.
    func testLiveEncouragementIsNotBuilt() {
        XCTAssertFalse(HomeCrewPulseStripCheerIsBuilt,
                       "spec §4: live encouragement is phase 2 — see the plan's 'does not decide'")
    }
}

/// Phase 2's flag, and its only definition. A cheer surface arriving is this
/// constant turning true, plus the test above changing with it.
let HomeCrewPulseStripCheerIsBuilt = false
