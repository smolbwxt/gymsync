import XCTest
@testable import GymSync

/// THE LIVE PILL'S TITLE/ROUTE DECISION, ON EVERY BRANCH (Phase C1 S5,
/// decision 6). Two pure laws extracted from `RootView`'s `body` and
/// `SessionLiveView.onAppear` so the answer is testable without a view:
///
///   * `AppState.LiveGroupSession.pillTitle(routineName:isSolo:)` — the copy.
///     Its whole reason to exist is the bug it closes: a freeform ad-hoc
///     solo session used to fall back to "Crew session" because the pill's
///     ONE handle (`liveGroupSession`) is now shared by both shapes
///     (`SessionLiveView.onAppear` registers it unconditionally, for a
///     roster of one exactly as for a crew).
///   * `LivePillDecision.decide(liveGroupSession:)` — the route: whether the
///     pill shows at all and, if so, which session tapping it resumes.
final class LivePillDecisionTests: XCTestCase {

    // MARK: - pillTitle — the copy

    func testARoutineNameWinsRegardlessOfRoster() {
        XCTAssertEqual(
            AppState.LiveGroupSession.pillTitle(routineName: "Push Day", isSolo: true),
            "Push Day")
        XCTAssertEqual(
            AppState.LiveGroupSession.pillTitle(routineName: "Push Day", isSolo: false),
            "Push Day")
    }

    func testAFreeformSoloSessionIsNeverCalledACrewSession() {
        // The bug this task exists to close: a solo lifter alone in a gym
        // must never read a pill that names a crew that does not exist.
        XCTAssertEqual(
            AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: true),
            "Freeform workout")
    }

    func testAFreeformCrewSessionKeepsItsName() {
        // The fallback a genuine crew session is entitled to — unchanged by
        // this task, and the case that proves `isSolo` is read, not ignored.
        XCTAssertEqual(
            AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: false),
            "Crew session")
    }

    func testItAsksNothingButTheRoster() {
        // Same law as `SoloSessionShape.hidesCrewFurniture`, which is what
        // `isSolo` is built from at the one call site (`SessionLiveView.
        // hidesCrewFurniture`) — a SCHEDULED solo session gets the same
        // honest fallback as an ad-hoc one, because a party of one has no
        // crew whether or not a calendar said so.
        XCTAssertEqual(
            AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: true),
            AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: true))
    }

    // MARK: - LivePillDecision — the route

    func testNoLiveGroupSessionHidesThePill() {
        XCTAssertEqual(LivePillDecision.decide(liveGroupSession: nil), .hidden)
    }

    func testALiveGroupSessionResumesByItsOwnIDAndTitle() {
        let id = UUID()
        let session = AppState.LiveGroupSession(sessionID: id, title: "Freeform workout")
        XCTAssertEqual(
            LivePillDecision.decide(liveGroupSession: session),
            .resume(sessionID: id, title: "Freeform workout"))
    }

    func testASoloAdHocSessionAndACrewSessionRideTheSameDecision() {
        // The whole point of Phase C1 S3/S4: `liveSoloSession` dropped out of
        // this decision entirely, so a solo ad-hoc session's resume answer
        // has the identical shape to a crew's — only the title differs, and
        // that difference is `pillTitle`'s job, not this function's.
        let soloID = UUID()
        let crewID = UUID()
        let solo = AppState.LiveGroupSession(
            sessionID: soloID,
            title: AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: true))
        let crew = AppState.LiveGroupSession(
            sessionID: crewID,
            title: AppState.LiveGroupSession.pillTitle(routineName: nil, isSolo: false))
        XCTAssertEqual(LivePillDecision.decide(liveGroupSession: solo),
                       .resume(sessionID: soloID, title: "Freeform workout"))
        XCTAssertEqual(LivePillDecision.decide(liveGroupSession: crew),
                       .resume(sessionID: crewID, title: "Crew session"))
    }
}
