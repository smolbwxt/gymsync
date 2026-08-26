import XCTest
@testable import GymSync

/// Set STRUCTURE the generator prescribes: supersets that are actually
/// trainable, and circuits that do not eat their own volume.
///
/// Both bugs here shared a shape — the prescription looked right on the
/// page and degraded silently in the live session, with nothing anywhere
/// reporting the difference. Found by audit 2026-08-26.
final class GeneratedStructureTests: XCTestCase {

    private func cat(_ n: Int, _ name: String, _ muscle: String,
                     _ category: String, _ pattern: String)
    -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(), name: name, primaryMuscle: muscle,
            secondaryMuscles: [], category: category, equipment: "barbell",
            movementPattern: pattern, rank: n)
    }

    private func entry(_ c: ProgramGenerator.CatalogExercise, main: Bool = false)
    -> ProgramGenerator.Exercise {
        ProgramGenerator.Exercise(exerciseID: c.id, name: c.name, sets: 3,
                                  repsLow: 8, repsHigh: 12, restSeconds: 90,
                                  percentOfMax: nil, isMain: main)
    }

    /// THE BUG: pairing marked a partner at an earlier index and never
    /// moved anything, so a pair could sit two slots apart. The live
    /// session resolves a partner by probing one slot forward and one
    /// back — so a non-adjacent pair was prescribed as a superset and run
    /// as two separate straight-set exercises.
    func testAPairedSupersetEndsUpAdjacent() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let squat = cat(2, "Squat", "quads", "compound", "squat")
        let row = cat(3, "Row", "back", "compound", "pull_horizontal")
        let catalog = [bench, squat, row]
        // Deliberately interleaved: the partner for slot 0 sits at slot 2.
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(squat), entry(row, main: true),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        let groups = paired.exercises.map(\.supersetGroup)
        guard let first = groups.firstIndex(where: { $0 != nil }) else {
            return XCTFail("nothing paired — the fixture cannot test adjacency")
        }
        XCTAssertEqual(paired.exercises[first].supersetGroup,
                       paired.exercises[first + 1].supersetGroup,
                       "a prescribed superset must be adjacent or the live "
                     + "session runs it as two straight-set exercises")
    }

    func testTheReorderKeepsEveryExercise() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let squat = cat(2, "Squat", "quads", "compound", "squat")
        let row = cat(3, "Row", "back", "compound", "pull_horizontal")
        let curl = cat(4, "Curl", "biceps", "isolation", "isolation")
        let catalog = [bench, squat, row, curl]
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(squat),
            entry(row, main: true), entry(curl),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        XCTAssertEqual(paired.exercises.count, 4, "the reorder dropped a lift")
        XCTAssertEqual(Set(paired.exercises.map(\.exerciseID)),
                       Set(day.exercises.map(\.exerciseID)),
                       "the reorder changed WHICH lifts are in the day")
    }

    /// An already-adjacent pair must not be shuffled — the reorder is a
    /// repair, not a re-sort.
    func testAnAlreadyAdjacentPairIsLeftAlone() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let row = cat(2, "Row", "back", "compound", "pull_horizontal")
        let squat = cat(3, "Squat", "quads", "compound", "squat")
        let catalog = [bench, row, squat]
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(row, main: true), entry(squat),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        XCTAssertEqual(paired.exercises.map(\.name), ["Bench", "Row", "Squat"])
    }
}
