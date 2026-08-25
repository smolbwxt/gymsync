import XCTest
@testable import GymSync

/// The two knobs the consult's "what challenging looks like" questions
/// write to. Both were prerequisites: RIR did not exist, and repAppetite
/// was a genuinely dead knob — personas had been seeding it since August
/// and the generator never read it.
final class EffortKnobTests: XCTestCase {

    // MARK: Effort → RIR

    func testEveryAppetiteProducesADistinctMainRIR() {
        let ranges = GeneratorScience.EffortAppetite.allCases.map { $0.rirRange.low }
        XCTAssertEqual(Set(ranges).count, GeneratorScience.EffortAppetite.allCases.count,
                       "each appetite must actually change the prescription")
    }

    func testReservedLeavesMoreInTheTankThanToFailure() {
        XCTAssertGreaterThan(GeneratorScience.EffortAppetite.reserved.rirRange.low,
                             GeneratorScience.EffortAppetite.toFailure.rirRange.low)
    }

    func testAccessoriesRunAtOrCloserToFailureThanMains() {
        // Grinding a curl costs a fraction of what grinding a heavy
        // compound costs in recovery.
        for appetite in GeneratorScience.EffortAppetite.allCases {
            XCTAssertLessThanOrEqual(appetite.accessoryRIR.low, appetite.rirRange.low,
                                     "\(appetite) accessories should not be EASIER than mains")
        }
    }

    // MARK: repAppetite → band shift

    func testHeavyLowPullsRepsDownAndRestUp() {
        let base = GeneratorScience.band(for: .hypertrophy)
        let shifted = GeneratorScience.applyRepAppetite(base, appetite: "heavy_low")
        XCTAssertLessThan(shifted.mainRepsHigh, base.mainRepsHigh)
        XCTAssertGreaterThan(shifted.mainRestSeconds, base.mainRestSeconds)
    }

    func testHighRepPumpPushesRepsUpAndRestDown() {
        let base = GeneratorScience.band(for: .hypertrophy)
        let shifted = GeneratorScience.applyRepAppetite(base, appetite: "high_rep_pump")
        XCTAssertGreaterThan(shifted.accessoryRepsHigh, base.accessoryRepsHigh)
        XCTAssertLessThan(shifted.accessoryRestSeconds, base.accessoryRestSeconds)
    }

    func testAccessoryTopStaysInsideTheCorpusWindow() {
        // The corpus's effort-matched window is 5-30 reps; the shift must
        // not walk past its own evidence.
        for focus in GeneratorScience.Focus.allCases {
            let shifted = GeneratorScience.applyRepAppetite(
                GeneratorScience.band(for: focus), appetite: "high_rep_pump")
            XCTAssertLessThanOrEqual(shifted.accessoryRepsHigh, 30)
        }
    }

    func testRepsNeverGoBelowOne() {
        for focus in GeneratorScience.Focus.allCases {
            let shifted = GeneratorScience.applyRepAppetite(
                GeneratorScience.band(for: focus), appetite: "heavy_low")
            XCTAssertGreaterThanOrEqual(shifted.mainRepsLow, 1)
            XCTAssertLessThanOrEqual(shifted.mainRepsLow, shifted.mainRepsHigh)
        }
    }

    func testModerateAndUnknownAreNoOps() {
        let base = GeneratorScience.band(for: .strength)
        for appetite in ["moderate", "something_else", nil] {
            let shifted = GeneratorScience.applyRepAppetite(base, appetite: appetite)
            XCTAssertEqual(shifted.mainRepsLow, base.mainRepsLow)
            XCTAssertEqual(shifted.mainRepsHigh, base.mainRepsHigh)
        }
    }

    // MARK: The seam

    func testGeneratorInputsDecaysExperienceAfterALongLayoff() {
        var profile = TrainingProfile()
        profile.trainingAge = .advanced
        let fresh = profile.generatorInputs(durationWeeks: 8, daysSinceLastSession: 10)
        let stale = profile.generatorInputs(durationWeeks: 8, daysSinceLastSession: 400)
        XCTAssertEqual(fresh.experience, .advanced)
        XCTAssertEqual(stale.experience, .new, "two years off is a novice again")
    }

    func testGeneratorInputsDerivesYouthFromBirthYear() {
        let profile = TrainingProfile()
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(profile.generatorInputs(durationWeeks: 8, birthYear: year - 14).isYouth)
        XCTAssertFalse(profile.generatorInputs(durationWeeks: 8, birthYear: year - 30).isYouth)
        XCTAssertFalse(profile.generatorInputs(durationWeeks: 8).isYouth,
                       "unknown age must not be treated as youth")
    }
}
