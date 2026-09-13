import XCTest
@testable import GymSync

/// Where a session opens — plan task S10.
///
/// PURE: `SessionRouter.route` takes primitives, not a `WorkoutSession`, so
/// these tests need no fixture and no repository. The eight cases are the
/// brief's own: they exist to pin the one case a naive `group_id == nil`
/// reading would get wrong (a `.friends` or `.code` session is not solo)
/// alongside the ordinary lobby/warm-up/live split.
final class SessionEntryRouteTests: XCTestCase {

    private let noon: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 14,
                                                  hour: 12)) ?? Date()
    }()

    /// A scheduled solo session has no lobby (spec §2, owner decision 3) —
    /// the whole reason this router exists.
    func testScheduledSoloGoesToWarmUp() {
        XCTAssertEqual(
            SessionRouter.route(state: "scheduled", liftingStartedAt: nil,
                                participantCount: 1, roomCode: nil),
            .warmUp)
    }

    /// A scheduled crew session is unchanged: it opens to the lobby.
    func testScheduledCrewGoesToLobby() {
        XCTAssertEqual(
            SessionRouter.route(state: "scheduled", liftingStartedAt: nil,
                                participantCount: 4, roomCode: nil),
            .lobby)
    }

    /// The case a naive `group_id == nil` reading gets wrong: a `.friends`
    /// session also leaves `group_id` nil, but two people is not solo
    /// (`SessionShape.isSolo`, task S3).
    func testScheduledTwoPersonFriendsGoesToLobby() {
        XCTAssertEqual(
            SessionRouter.route(state: "scheduled", liftingStartedAt: nil,
                                participantCount: 2, roomCode: nil),
            .lobby)
    }

    /// A `.code` session is one participant so far, but a room code is an
    /// invitation — somebody is expected, so it is not solo either.
    func testScheduledCodeSessionGoesToLobby() {
        XCTAssertEqual(
            SessionRouter.route(state: "scheduled", liftingStartedAt: nil,
                                participantCount: 1, roomCode: "ABCD"),
            .lobby)
    }

    /// `WarmUpGate.isWarmingUp` outranks the solo check: ANY session that is
    /// live and has not started lifting goes to warm-up, crew or solo alike.
    func testInProgressWithNoLiftingStartGoesToWarmUpSoloAndCrewAlike() {
        XCTAssertEqual(
            SessionRouter.route(state: "in_progress", liftingStartedAt: nil,
                                participantCount: 1, roomCode: nil),
            .warmUp)
        XCTAssertEqual(
            SessionRouter.route(state: "in_progress", liftingStartedAt: nil,
                                participantCount: 4, roomCode: nil),
            .warmUp)
    }

    /// Once `lifting_started_at` is set, the session is live.
    func testInProgressWithALiftingDateGoesToLive() {
        XCTAssertEqual(
            SessionRouter.route(state: "in_progress", liftingStartedAt: noon,
                                participantCount: 4, roomCode: nil),
            .live)
    }

    /// `completed` and `abandoned` both go to `.live` — the live view
    /// already self-presents the recap, and this router adds no new
    /// terminal screen.
    func testCompletedGoesToLive() {
        XCTAssertEqual(
            SessionRouter.route(state: "completed", liftingStartedAt: nil,
                                participantCount: 1, roomCode: nil),
            .live)
    }

    func testAbandonedGoesToLive() {
        XCTAssertEqual(
            SessionRouter.route(state: "abandoned", liftingStartedAt: nil,
                                participantCount: 4, roomCode: nil),
            .live)
    }
}
