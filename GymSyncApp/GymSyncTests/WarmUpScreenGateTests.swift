import XCTest
@testable import GymSync

/// When the warm-up screen renders, and the three strings it prints —
/// plan task S9.
///
/// PURE: no database, no view, and no clock beyond the `Date`s handed in.
/// `warmup_minutes` appears nowhere, which is the point: spec §6 retires it,
/// and the clock that used to END the phase is now a readout.
final class WarmUpScreenGateTests: XCTestCase {

    private let noon: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 14,
                                                  hour: 12)) ?? Date()
    }()

    // MARK: - The gate

    func testLiveAndNotYetLiftingIsWarmingUp() {
        XCTAssertTrue(WarmUpGate.isWarmingUp(state: "in_progress",
                                             liftingStartedAt: nil))
    }

    func testLiftingStartedEndsTheWarmUp() {
        XCTAssertFalse(WarmUpGate.isWarmingUp(state: "in_progress",
                                              liftingStartedAt: noon))
    }

    /// A lobby is not a warm-up. The crew reaches this screen through Start,
    /// and a scheduled solo session through `SessionEntryView` (plan task
    /// S10) — never by being merely open.
    func testALobbyIsNotAWarmUp() {
        XCTAssertFalse(WarmUpGate.isWarmingUp(state: "lobby_open",
                                              liftingStartedAt: nil))
        XCTAssertFalse(WarmUpGate.isWarmingUp(state: "scheduled",
                                              liftingStartedAt: nil))
    }

    func testAFinishedSessionIsNotAWarmUp() {
        XCTAssertFalse(WarmUpGate.isWarmingUp(state: "completed",
                                              liftingStartedAt: nil))
        XCTAssertFalse(WarmUpGate.isWarmingUp(state: "abandoned",
                                              liftingStartedAt: nil))
    }

    /// THE ONE EDGE, tested rather than discovered: a session already
    /// `in_progress` with no `lifting_started_at` when this build shipped
    /// re-enters the warm-up screen once. Self-healing and bounded by one
    /// tap — the next START LIFTING writes the column.
    func testTheMigrationEdgeIsTheGatesTrueCase() {
        XCTAssertTrue(WarmUpGate.isWarmingUp(state: "in_progress",
                                             liftingStartedAt: nil),
                      "an in-flight session re-enters the screen once, by design")
    }

    // MARK: - N1: showsWarmUp, the runner's own restatement of the gate

    /// Every state the app uses × both lifting values, for `isWarmingUp`
    /// AND `showsWarmUp` side by side. This is the exact shape of the
    /// desync review push-5's N1 named: before this test existed,
    /// `isWarmingUp` had never been asked about `scheduled` or
    /// `lobby_open` at all, even though `SessionRunnerView` (inlining its
    /// own, different law) relied on getting `scheduled` right.
    func testIsWarmingUpAndShowsWarmUpAcrossEveryStateAndLiftingValue() {
        let cases: [(state: String, isWarmingUp: Bool, showsWarmUp: Bool)] = [
            ("scheduled", false, true),
            ("lobby_open", false, true),
            ("in_progress", true, true),
            ("completed", false, false),
            ("abandoned", false, false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                WarmUpGate.isWarmingUp(state: testCase.state, liftingStartedAt: nil),
                testCase.isWarmingUp,
                "\(testCase.state) + nil lifting: isWarmingUp")
            XCTAssertFalse(
                WarmUpGate.isWarmingUp(state: testCase.state, liftingStartedAt: noon),
                "\(testCase.state) + set lifting: isWarmingUp is always false once lifting has started")
            XCTAssertEqual(
                WarmUpGate.showsWarmUp(state: testCase.state, liftingStartedAt: nil),
                testCase.showsWarmUp,
                "\(testCase.state) + nil lifting: showsWarmUp")
            XCTAssertFalse(
                WarmUpGate.showsWarmUp(state: testCase.state, liftingStartedAt: noon),
                "\(testCase.state) + set lifting: showsWarmUp is always false once lifting has started")
        }
    }

    /// The review's own words, asserted rather than trusted: for every
    /// state (crossed with solo and crew rosters) where `SessionRouter.route`
    /// returns `.warmUp` with a nil lifting date, `showsWarmUp` must also be
    /// true — otherwise the runner would draw `SessionInProgressView` for a
    /// session the router just sent to warm-up, exactly the contradiction
    /// finding 2 found in `isWarmingUp` alone.
    func testShowsWarmUpAgreesWithRouterWhereverRouterSaysWarmUp() {
        let states = ["scheduled", "lobby_open", "in_progress", "completed", "abandoned"]
        let rosters: [(participantCount: Int, roomCode: String?)] = [
            (1, nil),   // solo
            (4, nil),   // crew
        ]
        var sawAtLeastOneWarmUpRoute = false
        for state in states {
            for roster in rosters {
                let route = SessionRouter.route(state: state, liftingStartedAt: nil,
                                                participantCount: roster.participantCount,
                                                roomCode: roster.roomCode)
                guard route == .warmUp else { continue }
                sawAtLeastOneWarmUpRoute = true
                XCTAssertTrue(
                    WarmUpGate.showsWarmUp(state: state, liftingStartedAt: nil),
                    "\(state) with \(roster.participantCount) participant(s) routes to " +
                    ".warmUp but showsWarmUp says the runner would not draw it")
            }
        }
        XCTAssertTrue(sawAtLeastOneWarmUpRoute,
                      "the fixture above must exercise at least one .warmUp route")
    }

    // MARK: - The clock

    func testElapsedCountsFromTheSessionsStart() {
        XCTAssertEqual(WarmUpGate.elapsed(since: noon,
                                          now: noon.addingTimeInterval(252)),
                       "4:12")
        XCTAssertEqual(WarmUpGate.elapsed(since: noon,
                                          now: noon.addingTimeInterval(5)),
                       "0:05")
        XCTAssertEqual(WarmUpGate.elapsed(since: noon,
                                          now: noon.addingTimeInterval(3600)),
                       "60:00", "the phase has no target, so it has no cap")
    }

    /// A warm-up that has not started has not run backwards, and a session
    /// with no `started_at` has not started.
    func testElapsedNeverGoesNegativeOrNil() {
        XCTAssertEqual(WarmUpGate.elapsed(since: nil, now: noon), "0:00")
        XCTAssertEqual(WarmUpGate.elapsed(since: noon,
                                          now: noon.addingTimeInterval(-90)),
                       "0:00")
    }

    // MARK: - The crew's copy

    func testTheWarmCaption() {
        XCTAssertEqual(WarmUpGate.warmCaption(warm: 2, total: 4), "2 of 4 warm")
    }

    /// The primary stays LIVE for the leader while somebody is still warming
    /// up (spec §3.2), and the note is where that costs something rather than
    /// a second control.
    func testTheLeadersNoteNamesWhoIsStillGoing() {
        XCTAssertEqual(
            WarmUpGate.leaderNote(isOrganizer: true, stillWarming: ["Sam"]),
            "You're the leader · Sam is still warming up")
        XCTAssertEqual(
            WarmUpGate.leaderNote(isOrganizer: true, stillWarming: ["Sam", "Lee"]),
            "You're the leader · Sam and 1 more are still warming up")
    }

    /// No note for a crewmate — it is not their decision — and none when
    /// everyone is warm, because then it says nothing.
    func testNoNoteForACrewmateOrAWarmCrew() {
        XCTAssertNil(WarmUpGate.leaderNote(isOrganizer: false,
                                           stillWarming: ["Sam"]))
        XCTAssertNil(WarmUpGate.leaderNote(isOrganizer: true, stillWarming: []))
    }

    // MARK: - The catalog's worlds

    /// `session-warmup-solo` and `session-warmup-crew` (plan task S11) render
    /// these. Both must be IN the warm-up state, or the frames capture the
    /// live view instead.
    func testBothWarmUpFixturesAreInTheWarmUpState() {
        for world in [WarmUpFixtures.solo, WarmUpFixtures.crew,
                      WarmUpFixtures.suggestion] {
            XCTAssertTrue(
                WarmUpGate.isWarmingUp(state: world.session.state,
                                       liftingStartedAt: world.session.liftingStartedAt))
        }
        XCTAssertTrue(WarmUpFixtures.solo.warmthRows.isEmpty,
                      "a party of one has no readiness row")
        XCTAssertEqual(WarmUpFixtures.crew.warmthRows.filter(\.isWarm).count, 2)
    }

    /// Constraint 14: the two shipped warm-up frames carry NO suggestion, so
    /// `crewBody` draws the plain `SessionPlanCard` and `soloBody` draws its
    /// card with no rule — both byte-identical to what B1 shipped. Only the
    /// third world, which S10 gives its own id, has one (plan task S8).
    func testOnlyTheThirdWorldCarriesASuggestion() {
        XCTAssertNil(WarmUpFixtures.solo.coachSuggestion)
        XCTAssertNil(WarmUpFixtures.crew.coachSuggestion)
        XCTAssertEqual(WarmUpFixtures.suggestion.coachSuggestion?.setsInstead, 3)
        XCTAssertFalse(WarmUpFixtures.suggestion.isSolo,
                       "the private line is what the crew frame is for")
    }
}
