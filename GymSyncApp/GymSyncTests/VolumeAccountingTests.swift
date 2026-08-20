import XCTest
@testable import GymSync

/// Per-muscle weekly volume accounting — the corpus audit's confirmed
/// defect made into a contract: `secondaryMuscles` is READ, indirect
/// volume counts at half a set, and the weekly band is enforced against
/// what a week actually delivers to each muscle, not per slot.
final class VolumeAccountingTests: XCTestCase {

    private func ex(_ rank: Int, _ name: String, _ muscle: String,
                    secondaries: [String] = [],
                    cat: String = "isolation") -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
            name: name, primaryMuscle: muscle, secondaryMuscles: secondaries,
            category: cat, equipment: "barbell", movementPattern: "isolation",
            rank: rank)
    }

    private func entry(_ catalogEx: ProgramGenerator.CatalogExercise,
                       sets: Int, isMain: Bool = false) -> ProgramGenerator.Exercise {
        ProgramGenerator.Exercise(
            exerciseID: catalogEx.id, name: catalogEx.name, sets: sets,
            repsLow: 8, repsHigh: 12, restSeconds: 90,
            percentOfMax: nil, isMain: isMain)
    }

    func testSecondariesCountAtHalfASet() {
        let bench = ex(1, "Bench Press", "chest",
                       secondaries: ["triceps", "shoulders"], cat: "compound")
        let days = [ProgramGenerator.Day(name: "Push",
                                         exercises: [entry(bench, sets: 4, isMain: true)])]
        let tally = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [bench])
        XCTAssertEqual(tally["chest"], 4.0)
        XCTAssertEqual(tally["triceps"], 2.0, "4 sets x 0.5 for a secondary")
        XCTAssertEqual(tally["shoulders"], 2.0)
    }

    func testCeilingTrimsAccessoriesNeverMains() {
        let bench = ex(1, "Bench Press", "chest",
                       secondaries: ["triceps"], cat: "compound")
        let pushdown = ex(2, "Pushdown", "triceps")
        let overhead = ex(3, "Overhead Extension", "triceps")
        let catalog = [bench, pushdown, overhead]
        // Triceps: 5x0.5 (bench) + 5 + 5 = 12.5 against a ceiling of 10.
        let days = [ProgramGenerator.Day(name: "Push", exercises: [
            entry(bench, sets: 5, isMain: true),
            entry(pushdown, sets: 5),
            entry(overhead, sets: 5),
        ])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: catalog, low: 0, high: 10)
        let tally = ProgramGenerator.weeklyMuscleSets(days: result.days,
                                                     catalog: catalog)
        XCTAssertLessThanOrEqual(tally["triceps"] ?? 0, 10.0)
        XCTAssertEqual(result.trimmed, 3)
        XCTAssertEqual(result.days[0].exercises[0].sets, 5,
                       "the MAIN is never touched — slot logic owns it")
        XCTAssertEqual(result.days[0].exercises[2].sets, 2,
                       "trims come from the LAST accessory first")
    }

    func testFloorRaisesPrimaryTrainedMuscleCappedAtFive() {
        let curl = ex(1, "Curl", "biceps")
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 2)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 6, high: 20)
        XCTAssertEqual(result.days[0].exercises[0].sets, 5,
                       "adds stop at the per-exercise cap even under the floor")
        XCTAssertEqual(result.added, 3)
    }

    func testSecondaryOnlyMuscleGetsNoFloor() {
        // Forearms appear only as a secondary: incidental volume is not a
        // training commitment, so the floor must not chase it.
        let curl = ex(1, "Curl", "biceps", secondaries: ["forearms"])
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 3)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 10, high: 20)
        let tally = ProgramGenerator.weeklyMuscleSets(days: result.days,
                                                     catalog: [curl])
        XCTAssertEqual(tally["forearms"], 2.5,
                       "5 sets x 0.5 after biceps' own floor pass — never inflated for forearms' sake")
    }

    func testCardioContributesNoVolume() {
        let bike = ex(1, "Cycling", "quads", cat: "cardio")
        var cardio = entry(bike, sets: 1)
        cardio.cardioZone = 2
        cardio.cardioMinutes = 30
        let days = [ProgramGenerator.Day(name: "Cardio", exercises: [cardio])]
        let tally = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [bike])
        XCTAssertTrue(tally.isEmpty, "zone minutes are not sets")
    }
}
