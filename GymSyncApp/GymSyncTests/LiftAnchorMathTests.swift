import XCTest
@testable import GymSync

/// Getting-started seed coverage: anchor face values, ratio-derived
/// variants with the 0.9 conservatism factor, the 5-lb grid, and the
/// `.seeded` rung's below-everything precedence in WorkingWeight.
final class LiftAnchorMathTests: XCTestCase {

    private let anchors: [String: Decimal] = [
        "back-squat": 225, "bench-press": 185, "deadlift": 315, "ohp": 115,
    ]

    func testAnchorLiftsSeedAtFaceValue() {
        XCTAssertEqual(LiftAnchorMath.seedPounds(for: "back-squat", anchors: anchors), 225)
        XCTAssertEqual(LiftAnchorMath.seedPounds(for: "ohp", anchors: anchors), 115)
    }

    func testDerivedVariantsApplyRatioAndConservatism() {
        // front-squat = 225 × 0.85 × 0.9 = 172.125 → 5-lb grid → 170
        XCTAssertEqual(LiftAnchorMath.seedPounds(for: "front-squat", anchors: anchors), 170)
        // rdl = 315 × 0.85 × 0.9 = 240.975 → 240
        XCTAssertEqual(LiftAnchorMath.seedPounds(for: "rdl", anchors: anchors), 240)
    }

    func testUnmappedSlugSeedsNothing() {
        XCTAssertNil(LiftAnchorMath.seedPounds(for: "barbell-row", anchors: anchors))
        XCTAssertNil(LiftAnchorMath.seedPounds(for: "back-squat", anchors: nil))
        XCTAssertNil(LiftAnchorMath.seedPounds(for: "back-squat", anchors: [:]))
    }

    func testDerivedNeedsItsAnchor() {
        // No deadlift anchor → no rdl seed, even with other anchors present.
        XCTAssertNil(LiftAnchorMath.seedPounds(for: "rdl",
                                               anchors: ["bench-press": 185]))
    }

    // MARK: - The .seeded rung's precedence

    func testSeedFiresOnlyWithNoRealData() {
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: 5, routineTargetPounds: nil,
            history: [], lastSetPounds: nil, enrollment: nil,
            seededPounds: 225)
        XCTAssertEqual(suggestion?.pounds, 225)
        XCTAssertEqual(suggestion?.source, .seeded)
    }

    func testAnyRealDataOutranksTheSeed() {
        // A last-set weight — the lowest real rung — still beats the seed.
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: nil, routineTargetPounds: nil,
            history: [], lastSetPounds: 185, enrollment: nil,
            seededPounds: 225)
        XCTAssertEqual(suggestion?.pounds, 185)
        XCTAssertEqual(suggestion?.source, .lastSet)
    }

    func testNoSeedNoSuggestionStaysHonest() {
        XCTAssertNil(WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: nil, routineTargetPounds: nil,
            history: [], lastSetPounds: nil, enrollment: nil,
            seededPounds: nil))
    }
}