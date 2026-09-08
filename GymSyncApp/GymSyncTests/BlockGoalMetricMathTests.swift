import XCTest
@testable import GymSync

final class BlockGoalMetricMathTests: XCTestCase {

    // MARK: - Fixtures
    //
    // PRIVATE HELPERS BUILT ON THE REAL INITIALIZERS, which is this repo's
    // only fixture idiom — grep-verified: there is no `SetLog.fixture` or
    // `Exercise.fixture` anywhere, and `WeeklyGoalProgressTests:14-37` and
    // `HomeCompositionTests:196-213` each declare their own. Copy those
    // helpers' shape rather than adding a shared one: a second builder for
    // one model is how two suites come to disagree about what a failed set is.
    //
    // `reps` + `isFailed`, never a `completedReps:` argument — `completedReps`
    // is DERIVED (`SetLog.swift:41-45`), and a fixture that set it directly
    // would let a test pass against arithmetic production cannot produce.

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func log(_ exerciseID: UUID, weight: Decimal, reps: Int?,
                     failed: Bool = false, penalty: Bool = false,
                     sessionID: UUID? = nil, at seconds: TimeInterval = 0) -> SetLog {
        SetLog(id: UUID(), userID: id(9001), sessionID: sessionID ?? id(9002),
               exerciseID: exerciseID, setIndex: 1, reps: reps, weight: weight,
               rpe: nil, isFailed: failed, isPenalty: penalty, note: nil,
               loggedAt: Date(timeIntervalSince1970: seconds))
    }

    private func exercise(_ n: Int, category: String,
                          primary: String = "chest") -> Exercise {
        Exercise(id: id(n), name: "Fixture \(n)", slug: "fixture-\(n)",
                 category: category, primaryMuscle: primary,
                 secondaryMuscles: [], equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func session(routineID: UUID?, startedAt: Date?,
                         completedAt: Date?) -> WorkoutSession {
        WorkoutSession(id: UUID(), routineID: routineID, organizerID: id(9001),
                       state: "completed", startedAt: startedAt,
                       completedAt: completedAt,
                       createdAt: Date(timeIntervalSince1970: 0),
                       groupID: nil, roomCode: nil, scheduledFor: nil,
                       seriesID: nil, currentTurnUserID: nil,
                       currentTurnStartedAt: nil)
    }

    func testBodyWeightTakesTheLatestPoundsRow() {
        let userID = UUID()
        let logs = [
            BodyWeightLog(id: UUID(), userID: userID, weight: 185, unit: "lbs",
                          loggedAt: Date(timeIntervalSince1970: 100)),
            BodyWeightLog(id: UUID(), userID: userID, weight: 183, unit: "lbs",
                          loggedAt: Date(timeIntervalSince1970: 300)),
            BodyWeightLog(id: UUID(), userID: userID, weight: 83, unit: "kg",
                          loggedAt: Date(timeIntervalSince1970: 400)),
        ]
        XCTAssertEqual(BlockGoalMetricMath.currentBodyWeightPounds(logs: logs), 183,
                       "the kg row is not this app's and is skipped, not converted")
        XCTAssertNil(BlockGoalMetricMath.currentBodyWeightPounds(logs: []))
    }

    func testVolumeCountsCompletedRepsAndSkipsPenalties() {
        let bench = id(1)
        let logs = [
            log(bench, weight: 100, reps: 10),                       // 1000
            log(bench, weight: 100, reps: 3, failed: true),          // 200 — a failed triple
            log(bench, weight: 100, reps: 1, failed: true),          // a failed single: nothing
            log(bench, weight: 100, reps: 10, penalty: true),        // the burpee tax
        ]
        XCTAssertEqual(BlockGoalMetricMath.volumePounds(logs: logs), 1200, accuracy: 0.001)
    }

    func testBenchmarkTakesTheFastestFinishedRun() {
        let murph = id(2)
        let sessions = [
            session(routineID: murph, startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: Date(timeIntervalSince1970: 2_830)),
            session(routineID: murph, startedAt: Date(timeIntervalSince1970: 10_000),
                    completedAt: Date(timeIntervalSince1970: 12_700)),
            session(routineID: murph, startedAt: nil,
                    completedAt: Date(timeIntervalSince1970: 20_000)),
            session(routineID: id(3), startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: Date(timeIntervalSince1970: 60)),
        ]
        XCTAssertEqual(BlockGoalMetricMath.bestBenchmarkSeconds(sessions: sessions,
                                                               routineID: murph), 2_700)
        XCTAssertNil(BlockGoalMetricMath.bestBenchmarkSeconds(sessions: [], routineID: murph))
    }

    func testRepsAtLoadCountsSetsAtOrAboveTheLoad() {
        let bench = id(1)
        let logs = [
            log(bench, weight: 225, reps: 8),
            log(bench, weight: 235, reps: 6),
            log(bench, weight: 215, reps: 15),   // below the load: says nothing
        ]
        XCTAssertEqual(BlockGoalMetricMath.bestRepsAtLoad(logs: logs, exerciseID: bench,
                                                          loadLbs: 225), 8)
        XCTAssertNil(BlockGoalMetricMath.bestRepsAtLoad(logs: logs, exerciseID: id(9),
                                                        loadLbs: 225))
    }
}
