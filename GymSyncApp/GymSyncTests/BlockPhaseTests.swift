import XCTest
@testable import GymSync

/// The phase taxonomy is GOAL-CONDITIONAL by evidence, not by taste
/// (corpus area 'periodization', 2026-08-25): accumulation →
/// intensification → realization is real for percentage-driven
/// performance blocks and explicitly does NOT transfer to hypertrophy,
/// which has no performance peak to aim at. These tests pin that
/// boundary so a future change cannot quietly start labelling a
/// hypertrophy block with a PEAK week.
final class BlockPhaseTests: XCTestCase {

    private func week(_ percent: Double?, sets: Int = 4, reps: Int = 5,
                      deload: Bool = false) -> ProgramWeek {
        ProgramWeek(percentOfBaseline: percent, sets: sets, reps: reps, isDeload: deload)
    }

    // MARK: - When a taxonomy exists

    func testPercentageBlockDerivesTheArc() {
        let weeks = [week(70), week(75), week(80), week(85), week(90),
                     week(60, deload: true)]
        guard let phases = BlockPhaseMap.phases(for: weeks) else {
            return XCTFail("a percentage block with real variation carries an arc")
        }
        XCTAssertEqual(phases.first, .accumulation, "the lightest week accumulates")
        XCTAssertEqual(phases[4], .peak, "the heaviest week peaks")
        XCTAssertEqual(phases.last, .deload, "a deload is a deload regardless of its percent")
        // The arc must actually move through the middle, not jump.
        XCTAssertTrue(phases.contains(.intensification))
    }

    func testDeloadWinsOverItsPercentage()  {
        // A deload week carrying a mid-range percent is still a deload —
        // the flag is the block's own statement of intent.
        let weeks = [week(70), week(80), week(85, deload: true), week(90)]
        let phases = BlockPhaseMap.phases(for: weeks)
        XCTAssertEqual(phases?[2], .deload)
    }

    // MARK: - When no taxonomy exists (the evidence boundary)

    func testVolumeDrivenBlockHasNoPhases() {
        // Hypertrophy blocks prescribe no percentages. The field says an
        // accumulation-peak arc is not meaningful here, so we assert
        // nothing rather than label it.
        let weeks = [week(nil, sets: 3, reps: 10), week(nil, sets: 4, reps: 10),
                     week(nil, sets: 5, reps: 10), week(nil, sets: 2, reps: 10, deload: true)]
        XCTAssertNil(BlockPhaseMap.phases(for: weeks),
                     "a volume-driven block must not be given a phase arc")
    }

    func testFlatPercentageBlockHasNoPhases() {
        // Same percent every week is a repeated week, not an arc — the
        // 5-point span floor keeps us from reading a phase into noise.
        let weeks = [week(80), week(80), week(82), week(80)]
        XCTAssertNil(BlockPhaseMap.phases(for: weeks))
    }

    func testTooFewPercentWeeksHaveNoPhases() {
        XCTAssertNil(BlockPhaseMap.phases(for: [week(70), week(90)]))
    }

    // MARK: - Mesocycles (universal, what hypertrophy shows instead)

    func testMesocycleClosesOnItsDeload() {
        // A mesocycle is an overload run that CLOSES on its deload, so
        // the deload belongs to the cycle it ends.
        let weeks = [week(nil), week(nil), week(nil, deload: true),
                     week(nil), week(nil), week(nil, deload: true)]
        XCTAssertEqual(BlockPhaseMap.mesocycles(for: weeks), [1, 1, 1, 2, 2, 2])
    }

    func testMesocycleLabelCountsWithinTheCycle() {
        let weeks = [week(nil), week(nil), week(nil, deload: true),
                     week(nil), week(nil), week(nil, deload: true)]
        XCTAssertEqual(BlockPhaseMap.mesocycleLabel(for: weeks, week: 1), "MESO 1 OF 2 · WK 1")
        XCTAssertEqual(BlockPhaseMap.mesocycleLabel(for: weeks, week: 5), "MESO 2 OF 2 · WK 2")
    }

    func testSingleMesocycleDropsTheCycleCount() {
        let weeks = [week(nil), week(nil), week(nil, deload: true)]
        XCTAssertEqual(BlockPhaseMap.mesocycleLabel(for: weeks, week: 2), "WK 2")
    }

    func testMesocycleLabelOutOfRangeIsNil() {
        XCTAssertNil(BlockPhaseMap.mesocycleLabel(for: [week(nil)], week: 9))
    }
}
