import XCTest
@testable import GymSync

/// Pure-function coverage for `WorkingWeight.suggest` — the bar loader's
/// prefill ladder. No network/live-DB setUp (the ProgramMathTests /
/// BurpeeLedgerMathTests pattern).
///
/// The contract under test is as much about what this DOESN'T return as
/// what it does: every rung must decline when its inputs are missing, and
/// the whole ladder must return nil rather than guess. A wrong prefilled
/// weight is worse than none — someone will load it onto a bar.
final class WorkingWeightTests: XCTestCase {

    private let exerciseID = UUID()
    private let otherExerciseID = UUID()
    private let userID = UUID()
    private let sessionID = UUID()

    private func log(reps: Int?, weight: Decimal?,
                     failed: Bool = false, penalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: userID, sessionID: sessionID,
               exerciseID: exerciseID, setIndex: 1, reps: reps, weight: weight,
               rpe: nil, isFailed: failed, isPenalty: penalty, note: nil,
               loggedAt: Date(timeIntervalSince1970: 1_784_000_000))
    }

    /// An enrollment on the 8-week "march-to-1rm" template (week 1 = 75%),
    /// focused on `exerciseID` with a 300 lb frozen baseline.
    private func enrollment(startedOn: String = "2026-07-01",
                            focus: [UUID]? = nil,
                            baseline: [String: Double]? = nil,
                            endedAt: Date? = nil) -> ProgramEnrollment? {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(userID.uuidString)",
          "template_slug": "march-to-1rm",
          "focus": {"exercise_ids": ["\((focus ?? [exerciseID])[0].uuidString)"]},
          "baseline": {"\(exerciseID.uuidString.lowercased())": 300},
          "started_on": "\(startedOn)",
          "weeks": 8,
          "ended_at": \(endedAt == nil ? "null" : "\"2026-07-20T00:00:00Z\""),
          "ended_reason": null,
          "created_at": "2026-07-01T00:00:00Z"
        }
        """
        _ = baseline
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProgramEnrollment.self, from: Data(json.utf8))
    }

    /// Week 1 of march-to-1rm is 75%; 75% of a 300 lb baseline = 225.
    private var weekOneNow: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 2))!
    }

    // MARK: - Rung 1: campaign

    func testCampaignWinsOverEverything() {
        guard let enrollment = enrollment() else { return XCTFail("fixture") }
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID,
            targetReps: 5,
            routineTargetPounds: 185,               // present, must LOSE
            history: [log(reps: 5, weight: 275)],   // present, must LOSE
            lastSetPounds: 200,                     // present, must LOSE
            enrollment: enrollment,
            now: weekOneNow
        )
        XCTAssertEqual(result?.pounds, 225)
        XCTAssertEqual(result?.source, .campaign(percent: 75, week: 1))
    }

    func testCampaignIgnoredForAnExerciseOutsideItsFocus() {
        guard let enrollment = enrollment() else { return XCTFail("fixture") }
        let result = WorkingWeight.suggest(
            exerciseID: otherExerciseID,   // not a focus lift
            targetReps: nil,
            routineTargetPounds: 185,
            history: [], lastSetPounds: nil,
            enrollment: enrollment, now: weekOneNow
        )
        XCTAssertEqual(result?.source, .routine)
        XCTAssertEqual(result?.pounds, 185)
    }

    func testEndedEnrollmentIsIgnored() {
        guard let enrollment = enrollment(endedAt: Date()) else { return XCTFail("fixture") }
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: nil,
            routineTargetPounds: 185, history: [], lastSetPounds: nil,
            enrollment: enrollment, now: weekOneNow
        )
        XCTAssertEqual(result?.source, .routine)
    }

    // MARK: - Rung 2/3/4 ordering

    func testRoutineTargetBeatsRepGoalAndLastSet() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: 185,
            history: [log(reps: 5, weight: 225)],
            lastSetPounds: 200, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 185)
        XCTAssertEqual(result?.source, .routine)
    }

    func testRepGoalProjectsFromBestSetWhenNoRoutineTarget() {
        // Best set 5×225 → Epley 1RM 262.5 → 8 reps: 262.5 / (1 + 8/30)
        // = 207.2 → rounds to 205.
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: nil,
            history: [log(reps: 5, weight: 225), log(reps: 10, weight: 135)],
            lastSetPounds: 200, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 205)
        XCTAssertEqual(result?.source, .repGoal(targetReps: 8))
    }

    func testLastSetIsTheFinalRung() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: nil,
            routineTargetPounds: nil, history: [],
            lastSetPounds: 200, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 200)
        XCTAssertEqual(result?.source, .lastSet)
    }

    // MARK: - The floor: never invent a number

    func testNothingKnownReturnsNil() {
        XCTAssertNil(WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: nil, history: [],
            lastSetPounds: nil, enrollment: nil
        ))
    }

    func testRepGoalDeclinesWithoutAQualifyingSet() {
        // Failed, penalty, and incomplete sets all fail to qualify — with
        // no other history the ladder must fall through to nil, not guess.
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 5,
            routineTargetPounds: nil,
            history: [log(reps: 5, weight: 225, failed: true),
                      log(reps: 5, weight: 225, penalty: true),
                      log(reps: nil, weight: 225),
                      log(reps: 5, weight: nil)],
            lastSetPounds: nil, enrollment: nil
        )
        XCTAssertNil(result)
    }

    func testZeroAndNegativeInputsNeverBecomeSuggestions() {
        XCTAssertNil(WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 0,
            routineTargetPounds: 0, history: [log(reps: 5, weight: 0)],
            lastSetPounds: 0, enrollment: nil
        ))
    }

    // MARK: - bestQualifyingSet

    func testBestQualifyingSetPicksHighestEpley() {
        let best = WorkingWeight.bestQualifyingSet(in: [
            log(reps: 10, weight: 135),   // 180
            log(reps: 5, weight: 225),    // 262.5 — the best
            log(reps: 1, weight: 245),    // 253.2
            log(reps: 3, weight: 400, failed: true),  // excluded
        ])
        XCTAssertEqual(best?.weight, 225)
        XCTAssertEqual(best?.reps, 5)
    }
}
