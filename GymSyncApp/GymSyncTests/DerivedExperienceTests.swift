import XCTest
@testable import GymSync

/// Derived experience (spec 2026-08-22): the comfort-probe derivation
/// and its selection consequences, pinned.
final class DerivedExperienceTests: XCTestCase {

    func testCoherentPrefixDerivation() {
        // Nothing answered -> nil (legacy profiles keep stored age).
        XCTAssertNil(GeneratorScience.derivedComplexityCap(from: [:]))
        // Nothing comfortable -> the honest floor.
        XCTAssertEqual(GeneratorScience.derivedComplexityCap(
            from: ["goblet-squat": false]), 2)
        // Goblet only -> still the floor's ceiling (2).
        XCTAssertEqual(GeneratorScience.derivedComplexityCap(
            from: ["goblet-squat": true, "back-squat-heavy": false]), 2)
        // Through the c3 pair -> 3.
        XCTAssertEqual(GeneratorScience.derivedComplexityCap(
            from: ["goblet-squat": true, "deadlift": true,
                   "weighted-pullup": false]), 3)
        // The full ladder -> 5.
        XCTAssertEqual(GeneratorScience.derivedComplexityCap(
            from: ["goblet-squat": true, "back-squat-heavy": true,
                   "weighted-pullup": true, "power-clean": true]), 5)
        // Bravado doesn't skip rungs: comfortable cleans without a
        // comfortable squat reads as the floor, not 5.
        XCTAssertEqual(GeneratorScience.derivedComplexityCap(
            from: ["goblet-squat": true, "back-squat-heavy": false,
                   "power-clean": true]), 2)
    }

    func testRegisterTierFromCap() {
        XCTAssertEqual(GeneratorScience.experience(forCap: 2), .new)
        XCTAssertEqual(GeneratorScience.experience(forCap: 3), .intermediate)
        XCTAssertEqual(GeneratorScience.experience(forCap: 5), .advanced)
    }

    func testCapOverrideGatesFinerThanBuckets() {
        // Cap 4 (comfortable weighted pull-ups, never cleaned): an
        // advanced-labeled lifter would see c5; the derived cap gates it.
        func cat(_ rank: Int, _ name: String, complexity: Int, score: Int)
            -> ProgramGenerator.CatalogExercise {
            var c = ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0008-%012d", rank))!,
                name: name, primaryMuscle: "quads", secondaryMuscles: [],
                category: "compound", equipment: "barbell", movementPattern: "squat",
                rank: rank)
            c.focusScores = ["strength": score]
            c.complexity = complexity
            return c
        }
        let oly = cat(1, "Squat Snatchish", complexity: 5, score: 9)
        let squat = cat(2, "Back Squattish", complexity: 3, score: 7)
        let advanced = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [oly, squat],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .advanced)
        XCTAssertEqual(advanced?.name, "Squat Snatchish",
                       "label-driven: advanced opens c5")
        let capped = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [oly, squat],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .advanced, complexityCapOverride: 4)
        XCTAssertEqual(capped?.name, "Back Squattish",
                       "the derived cap is finer than the label")
    }

    func testProfileFlowsCapIntoInputs() {
        var p = TrainingProfile()
        p.comfortAnswers = ["goblet-squat": true, "back-squat-heavy": true]
        p.derivedComplexityCap = 3
        XCTAssertEqual(p.generatorInputs(durationWeeks: 8).complexityCapOverride, 3)
        // Legacy profile: no answers, no override.
        XCTAssertNil(TrainingProfile().generatorInputs(durationWeeks: 8).complexityCapOverride)
    }
}
