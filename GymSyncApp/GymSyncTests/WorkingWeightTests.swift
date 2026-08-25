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

    // Field 2026-08-24 (the JM-press report): demonstrated strength
    // outranks the routine's typed seed — 5×225 in the log projects the
    // set of 8 regardless of the 185 written into the routine.
    func testRepGoalBeatsRoutineTargetOnceHistoryExists() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: 185,
            history: [log(reps: 5, weight: 225)],
            lastSetPounds: 200, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 205)
        XCTAssertEqual(result?.source, .repGoal(targetReps: 8))
    }

    func testRoutineTargetHoldsUntilFirstQualifyingSet() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: 185,
            history: [],
            lastSetPounds: nil, enrollment: nil
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

    // MARK: - Suggestions answer to the rep target (user 2026-08-02)
    //
    // "If your one rep max is 405, and you're doing a set of 5, 405 should not
    // be suggested." These pin the ladder's end-to-end behavior for that
    // hazard rather than any one rung's internals — the weight a lifter is
    // handed is the contract; which rung produced it is an implementation
    // detail free to move. Expectations are hand-computed from Epley, not
    // re-derived from the implementation's own arithmetic.

    /// 405 × 1 is a 418.5 est-1RM; for 5 reps that's 418.5 / (1 + 5/30)
    /// ≈ 358.7 → 360 at the 5 lb rounding. Rung 3 (rep goal) answers.
    func testAHeavySingleIsNeverSuggestedForAFiveRepTarget() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 5,
            routineTargetPounds: nil,
            history: [log(reps: 1, weight: 405)],
            lastSetPounds: 405, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 360)
        XCTAssertNotEqual(result?.pounds, 405, "a 1RM must never be suggested for a set of 5")
        XCTAssertEqual(result?.source, .repGoal(targetReps: 5))
    }

    /// The mirror case: coming off a high-rep set into a heavy target must
    /// scale UP, not leave the light weight on the bar. 200 × 10 is a 266.67
    /// est-1RM; at 1 rep that's 266.67 / (1 + 1/30) ≈ 258.1 → 260.
    func testALightHighRepSetScalesUpForASingle() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 1,
            routineTargetPounds: nil,
            history: [log(reps: 10, weight: 200)],
            lastSetPounds: 200, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 260)
    }

    /// Matching rep counts pass through untouched — no rounding drift on the
    /// ordinary "same again" case.
    func testMatchingRepTargetLeavesTheWeightAlone() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 8,
            routineTargetPounds: nil,
            history: [log(reps: 8, weight: 185)],
            lastSetPounds: 185, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 185)
    }

    /// A set you missed is not evidence of what you can lift: a failed 405
    /// single must not become the scaling basis, so the ladder falls to the
    /// raw carry-forward instead of projecting off a lift that didn't happen.
    func testAFailedSetIsNeverTheScalingBasis() {
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 5,
            routineTargetPounds: nil,
            history: [log(reps: 1, weight: 405, failed: true)],
            lastSetPounds: 225, enrollment: nil
        )
        XCTAssertEqual(result?.pounds, 225)
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
        // Failed SINGLES, penalty, and incomplete sets all fail to qualify —
        // with no other history the ladder must fall through to nil, not
        // guess. (A failed multi-rep set now DOES qualify at its completed
        // reps — failure doctrine 2026-08-13 — hence the failed set here is
        // a missed 1RM, the one failure that carries nothing.)
        let result = WorkingWeight.suggest(
            exerciseID: exerciseID, targetReps: 5,
            routineTargetPounds: nil,
            history: [log(reps: 1, weight: 225, failed: true),
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
        // Failure doctrine 2026-08-13: the failed set qualifies at its
        // COMPLETED reps (n − 1, true RIR 0) — but a missed single still
        // carries nothing.
        let best = WorkingWeight.bestQualifyingSet(in: [
            log(reps: 10, weight: 135),   // 180
            log(reps: 5, weight: 225),    // 262.5 — the best
            log(reps: 1, weight: 245),    // 253.2
            log(reps: 1, weight: 400, failed: true),  // missed 1RM — excluded
        ])
        XCTAssertEqual(best?.weight, 225)
        XCTAssertEqual(best?.reps, 5)
    }

    func testBestQualifyingSetCountsFailedSetAtCompletedReps() {
        // "3 + FAIL" at 400 = 2 completed at true RIR 0 → 400×(1+2/30) ≈
        // 426.7, outranking the clean 225×5 (262.5).
        let best = WorkingWeight.bestQualifyingSet(in: [
            log(reps: 5, weight: 225),
            log(reps: 3, weight: 400, failed: true),
        ])
        XCTAssertEqual(best?.weight, 400)
        XCTAssertEqual(best?.reps, 2)
    }
}
