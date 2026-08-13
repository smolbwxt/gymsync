import XCTest
@testable import GymSync

/// The failure doctrine (owner 2026-08-13): a failed set logged at n reps
/// means the nth rep was attempted and missed — n − 1 reps COMPLETED at
/// true RIR 0, the best calibration data history can offer. The one
/// failure carrying nothing is the missed single (n ≤ 1). These pin the
/// `completedReps` primitive and its math consumers.
final class FailureDoctrineTests: XCTestCase {

    private func set(reps: Int?, weight: Decimal?, rpe: Decimal? = nil,
                     isFailed: Bool = false, isPenalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: UUID(), sessionID: UUID(), exerciseID: UUID(),
               setIndex: 1, reps: reps, weight: weight, rpe: rpe,
               isFailed: isFailed, isPenalty: isPenalty, note: nil, loggedAt: Date())
    }

    // MARK: - completedReps

    func testCleanSetPassesRepsThrough() {
        XCTAssertEqual(set(reps: 8, weight: 100).completedReps, 8)
    }

    func testFailedSetCompletesOneFewer() {
        // "7 + FAIL" = attempted the 7th, completed 6.
        XCTAssertEqual(set(reps: 7, weight: 225, isFailed: true).completedReps, 6)
    }

    func testFailedSingleCarriesNothing() {
        // The missed 1RM: zero completed reps proves nothing was lifted.
        XCTAssertNil(set(reps: 1, weight: 500, isFailed: true).completedReps)
    }

    func testMissingOrZeroRepsCarriesNothing() {
        XCTAssertNil(set(reps: nil, weight: 100).completedReps)
        XCTAssertNil(set(reps: 0, weight: 100, isFailed: true).completedReps)
    }

    // MARK: - e1RM suggestion paths

    func testFailedSetIsTrueRIRZeroCalibration() {
        // Failed 7@225 (6 completed, RIR 0) outranks a clean 5@225:
        // 225×(1+6/30) > 225×(1+5/30).
        let logs = [set(reps: 5, weight: 225), set(reps: 7, weight: 225, isFailed: true)]
        XCTAssertEqual(WorkingWeight.bestQualifyingSet(in: logs)?.reps, 6)
    }

    func testFailureOverridesContradictedRPE() {
        // A failed set logged @8 is still RIR 0 — the miss is authoritative.
        // If the logged RPE were honored (reps + RIR), the failed set would
        // inflate past the clean 7; doctrine holds it at 6 completed.
        let clean = set(reps: 7, weight: 225)                            // e1RM 277.5
        let failed = set(reps: 7, weight: 225, rpe: 8, isFailed: true)   // 6 @ RIR 0 → 270
        XCTAssertEqual(WorkingWeight.bestQualifyingSet(in: [clean, failed])?.reps, 7)
    }

    func testProgramBaselineCountsFailedCompletedReps() {
        let baseline = ProgramMath.baseline(fromHistory: [set(reps: 7, weight: 225, isFailed: true)])
        XCTAssertEqual(baseline, 225 * (1 + Decimal(6) / 30))
    }

    func testProgramBaselineIgnoresFailedSingle() {
        XCTAssertNil(ProgramMath.baseline(fromHistory: [set(reps: 1, weight: 500, isFailed: true)]))
    }

    // MARK: - PR judgment

    func testFailedSetSetsRecordAtCompletedReps() {
        // Prior best 225×5. Today "7 + FAIL" at 235 = 6 completed @ 235 — a
        // real record (owner: "Every other instance is good data").
        let basis: [(weight: Decimal, reps: Int)] = [(225, 5)]
        let failed = set(reps: 7, weight: 235, isFailed: true)
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 235, reps: failed.completedReps, basis: basis))
    }

    func testFailedSingleNeverSetsARecord() {
        let basis: [(weight: Decimal, reps: Int)] = [(225, 5)]
        let missed = set(reps: 1, weight: 500, isFailed: true)
        XCTAssertFalse(PersonalRecordMath.isPR(weight: 500, reps: missed.completedReps, basis: basis))
    }
}
