import XCTest
@testable import GymSync

/// Coverage for the est-1RM upgrades (research audit 2026-08): the
/// prediction-equation validity cap and the RPE/RIR-aware variant.
final class StatMathOneRepMaxTests: XCTestCase {

    func testEpleyBasicUnchanged() {
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5),
                       225 * (1 + Decimal(5) / 30))
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 300, reps: 1), 310)
    }

    func testHighRepSetsClampToValidityCap() {
        // A 20-rep set must not extrapolate fiction — it estimates as a
        // cap-rep (12) set of the same weight.
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 100, reps: 20),
                       StatMath.estimatedOneRepMax(weight: 100, reps: 12))
        // At the boundary, no clamp.
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 100, reps: 12),
                       100 * (1 + Decimal(12) / 30))
    }

    func testRPEVariantAddsReserveReps() {
        // 5 reps @7 → 3 in reserve → estimates like an 8-rep max effort.
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5, rpe: 7),
                       StatMath.estimatedOneRepMax(weight: 225, reps: 8))
        // @10 (nothing in reserve) matches the plain estimate.
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5, rpe: 10),
                       StatMath.estimatedOneRepMax(weight: 225, reps: 5))
    }

    func testRIRCreditCapsAtFour() {
        // @5 would claim 5 in reserve; credit caps at 4 (far-from-failure
        // self-reports are unreliable — research flag kept honest).
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5, rpe: 5),
                       StatMath.estimatedOneRepMax(weight: 225, reps: 9))
    }

    func testNilOrOutOfRangeRPEFallsBack() {
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5, rpe: nil),
                       StatMath.estimatedOneRepMax(weight: 225, reps: 5))
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 225, reps: 5, rpe: 3),
                       StatMath.estimatedOneRepMax(weight: 225, reps: 5))
    }

    func testEffectiveRepsStillHonorTheCap() {
        // 10 reps @6 → +4 credit → 14 effective, clamped back to 12.
        XCTAssertEqual(StatMath.estimatedOneRepMax(weight: 100, reps: 10, rpe: 6),
                       StatMath.estimatedOneRepMax(weight: 100, reps: 12))
    }
}