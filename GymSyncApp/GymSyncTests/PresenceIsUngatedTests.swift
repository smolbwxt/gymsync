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
}
