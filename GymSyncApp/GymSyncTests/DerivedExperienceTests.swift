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

    // Exhaustion stagger (owner 2026-08-22): accessories alternate
    // high/low systemic drain; mains keep their block.
    func testFatigueStaggerWeavesAccessories() {
        func cat(_ rank: Int, _ name: String, fatigue: Int)
            -> ProgramGenerator.CatalogExercise {
            var c = ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0009-%012d", rank))!,
                name: name, primaryMuscle: "quads", secondaryMuscles: [],
                category: "isolation", equipment: "machine", movementPattern: "isolation",
                rank: rank)
            c.fatigueCost = fatigue
            return c
        }
        func ex(_ c: ProgramGenerator.CatalogExercise, isMain: Bool = false)
            -> ProgramGenerator.Exercise {
            ProgramGenerator.Exercise(
                exerciseID: c.id, name: c.name, sets: 3, repsLow: 8, repsHigh: 12,
                restSeconds: 90, percentOfMax: nil, isMain: isMain,
                cardioZone: nil, cardioMinutes: nil)
        }
        let heavy1 = cat(1, "Drainer A", fatigue: 5)
        let heavy2 = cat(2, "Drainer B", fatigue: 4)
        let light1 = cat(3, "Easy A", fatigue: 1)
        let light2 = cat(4, "Easy B", fatigue: 2)
        let main = cat(5, "Main Lift", fatigue: 5)
        let catalog = [heavy1, heavy2, light1, light2, main]
        let day = [ex(main, isMain: true), ex(heavy1), ex(heavy2), ex(light1), ex(light2)]
        let staggered = ProgramGenerator.staggerFatigue(day, catalog: catalog)
        XCTAssertEqual(staggered.first?.name, "Main Lift", "mains keep their block")
        XCTAssertEqual(staggered.dropFirst().map(\.name),
                       ["Drainer A", "Easy A", "Drainer B", "Easy B"],
                       "high and low drain interleave - never two drainers back to back")
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
