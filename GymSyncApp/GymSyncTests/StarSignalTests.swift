import XCTest
@testable import GymSync

/// Starred-routine preference (field report #18): aspiration breaks
/// ties, and ONLY ties — it never beats a score or the stretch bias.
final class StarSignalTests: XCTestCase {

    private func cat(_ rank: Int, _ name: String, score: Int = 7,
                     lengthened: Bool = false)
        -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0006-%012d", rank))!,
            name: name, primaryMuscle: "biceps", secondaryMuscles: [],
            category: "isolation", equipment: "cable", movementPattern: "isolation",
            rank: rank)
        c.focusScores = ["hypertrophy": score]
        c.complexity = 2
        c.lengthenedBias = lengthened
        return c
    }

    private let slot = ProgramGenerator.Slot.isolation("biceps")

    func testStarBreaksTies() {
        let plain = cat(1, "Curl Variant A")
        let starredLift = cat(2, "Curl Variant B")
        let unstarred = ProgramGenerator.select(
            slot: slot, from: [plain, starredLift], excluding: [],
            focus: .hypertrophy, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(unstarred?.name, "Curl Variant A", "rank decides a pure tie")
        let starred = ProgramGenerator.select(
            slot: slot, from: [plain, starredLift], excluding: [],
            focus: .hypertrophy, focusMuscles: nil, experience: .intermediate,
            starred: [starredLift.id])
        XCTAssertEqual(starred?.name, "Curl Variant B",
                       "the lift they've been eyeing wins the tie")
    }

    func testStarNeverBeatsScoreOrStretch() {
        let better = cat(1, "Curl Variant A", score: 8)
        let starredLift = cat(2, "Curl Variant B", score: 7)
        let byScore = ProgramGenerator.select(
            slot: slot, from: [better, starredLift], excluding: [],
            focus: .hypertrophy, focusMuscles: nil, experience: .intermediate,
            starred: [starredLift.id])
        XCTAssertEqual(byScore?.name, "Curl Variant A", "a star is not a score")
        // Hypertrophy's lengthened bias also outranks the star.
        let stretched = cat(3, "Curl Variant C", lengthened: true)
        let starredPlain = cat(4, "Curl Variant D")
        let byStretch = ProgramGenerator.select(
            slot: slot, from: [stretched, starredPlain], excluding: [],
            focus: .hypertrophy, focusMuscles: nil, experience: .intermediate,
            starred: [starredPlain.id])
        XCTAssertEqual(byStretch?.name, "Curl Variant C",
                       "the stretch bias outranks aspiration")
    }
}
