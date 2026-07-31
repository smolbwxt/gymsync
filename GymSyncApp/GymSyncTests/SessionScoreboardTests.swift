import XCTest
@testable import GymSync

/// Pure-function coverage for `SessionScoreboard` — the BOARD page's
/// % SELF / LOAD math. Expected est-1RM values are computed through the
/// same `StatMath.estimatedOneRepMax` the production path uses, so these
/// tests pin the PIPELINE (baselines, exclusions, ranking), not Epley.
final class SessionScoreboardTests: XCTestCase {

    private let sessionID = UUID()
    private let priorSession = UUID()
    private let userA = UUID()
    private let userB = UUID()
    private let squat = UUID()
    private let bench = UUID()

    private func set(_ user: UUID, _ exercise: UUID, session: UUID,
                     weight: Decimal?, reps: Int?, rpe: Decimal? = 7,
                     failed: Bool = false, penalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: user, sessionID: session, exerciseID: exercise,
               setIndex: 1, reps: reps, weight: weight, rpe: rpe,
               isFailed: failed, isPenalty: penalty, note: nil, loggedAt: Date())
    }

    // MARK: baseline

    func testBaselineExcludesCurrentSessionFailedAndPenalty() {
        let history = [
            set(userA, squat, session: priorSession, weight: 225, reps: 3),
            set(userA, squat, session: priorSession, weight: 275, reps: 1, failed: true),
            set(userA, squat, session: priorSession, weight: 300, reps: 1, penalty: true),
            set(userA, squat, session: sessionID, weight: 400, reps: 5),   // today — excluded
        ]
        let base = SessionScoreboard.baseline(history: history, excludingSessionID: sessionID)
        XCTAssertEqual(base[squat], StatMath.estimatedOneRepMax(weight: 225, reps: 3))
    }

    func testBaselinePicksBestPerExercise() {
        let history = [
            set(userA, squat, session: priorSession, weight: 200, reps: 8),
            set(userA, squat, session: priorSession, weight: 245, reps: 1),
            set(userA, bench, session: priorSession, weight: 155, reps: 5),
        ]
        let base = SessionScoreboard.baseline(history: history, excludingSessionID: sessionID)
        let squatBest = max(StatMath.estimatedOneRepMax(weight: 200, reps: 8),
                            StatMath.estimatedOneRepMax(weight: 245, reps: 1))
        XCTAssertEqual(base[squat], squatBest)
        XCTAssertEqual(base[bench], StatMath.estimatedOneRepMax(weight: 155, reps: 5))
    }

    // MARK: rows

    func testLoadIsRepsTimesRPEAndSkipsRPElessSets() {
        let sets = [
            set(userA, squat, session: sessionID, weight: 200, reps: 5, rpe: 8),
            set(userA, squat, session: sessionID, weight: 200, reps: 5, rpe: nil),
            set(userA, bench, session: sessionID, weight: nil, reps: 10, rpe: 6),
        ]
        let rows = SessionScoreboard.rows(participants: [userA],
                                          sessionSets: sets, baselines: [:])
        XCTAssertEqual(rows[0].sets, 3)
        XCTAssertEqual(rows[0].load, 5 * 8 + 10 * 6)
        XCTAssertNil(rows[0].pctSelf)
        XCTAssertFalse(rows[0].ceilingBroken)
    }

    func testPenaltySetsNeverCount() {
        let sets = [
            set(userA, squat, session: sessionID, weight: 200, reps: 5, rpe: 8),
            set(userA, squat, session: sessionID, weight: nil, reps: 10, rpe: 10, penalty: true),
        ]
        let rows = SessionScoreboard.rows(participants: [userA],
                                          sessionSets: sets, baselines: [:])
        XCTAssertEqual(rows[0].sets, 1)
        XCTAssertEqual(rows[0].load, 40)
    }

    func testPctSelfIsBestSetVersusCeiling() {
        let ceiling = StatMath.estimatedOneRepMax(weight: 225, reps: 3)
        let sets = [
            set(userA, squat, session: sessionID, weight: 185, reps: 5),
            set(userA, squat, session: sessionID, weight: 215, reps: 4),
        ]
        let rows = SessionScoreboard.rows(participants: [userA], sessionSets: sets,
                                          baselines: [userA: [squat: ceiling]])
        let bestToday = max(StatMath.estimatedOneRepMax(weight: 185, reps: 5),
                            StatMath.estimatedOneRepMax(weight: 215, reps: 4))
        let expected = NSDecimalNumber(decimal: bestToday / ceiling * 100).intValue
        XCTAssertEqual(rows[0].pctSelf, expected)
        XCTAssertLessThanOrEqual(expected, 100)
    }

    func testCeilingBrokenAbove100() {
        let ceiling = StatMath.estimatedOneRepMax(weight: 225, reps: 3)
        let sets = [set(userA, squat, session: sessionID, weight: 250, reps: 3)]
        let rows = SessionScoreboard.rows(participants: [userA], sessionSets: sets,
                                          baselines: [userA: [squat: ceiling]])
        XCTAssertGreaterThan(rows[0].pctSelf ?? 0, 100)
        XCTAssertTrue(rows[0].ceilingBroken)
    }

    func testFailedSetsCountForSetsButNotPct() {
        let ceiling = StatMath.estimatedOneRepMax(weight: 100, reps: 1)
        let sets = [set(userA, squat, session: sessionID, weight: 500, reps: 1, failed: true)]
        let rows = SessionScoreboard.rows(participants: [userA], sessionSets: sets,
                                          baselines: [userA: [squat: ceiling]])
        XCTAssertEqual(rows[0].sets, 1)     // consumed an attempt
        XCTAssertNil(rows[0].pctSelf)       // a miss proves no ceiling
    }

    func testRankingPctDescThenDashesLast() {
        let ceilingA = StatMath.estimatedOneRepMax(weight: 200, reps: 1)
        let ceilingB = StatMath.estimatedOneRepMax(weight: 200, reps: 1)
        let sets = [
            set(userA, squat, session: sessionID, weight: 180, reps: 1),
            set(userB, squat, session: sessionID, weight: 210, reps: 1),
        ]
        let rows = SessionScoreboard.rows(
            participants: [userA, userB], sessionSets: sets,
            baselines: [userA: [squat: ceilingA], userB: [squat: ceilingB]])
        XCTAssertEqual(rows.map(\.userID), [userB, userA])

        let withDash = SessionScoreboard.rows(
            participants: [userA, userB], sessionSets: sets,
            baselines: [userA: [squat: ceilingA]])
        XCTAssertEqual(withDash.map(\.userID), [userA, userB])
        XCTAssertNil(withDash[1].pctSelf)
    }
}
