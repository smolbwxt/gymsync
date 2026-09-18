import XCTest
@testable import GymSync

/// Spec §5's third move, pinned: the feed card's per-set rows become one line
/// per exercise, and the wording is the same wherever it is printed. Pure over
/// `PostSummary.ExerciseEntry` and the viewer's unit — no view, no clock, no
/// repository.
final class PumpCardCollapseTests: XCTestCase {

    private func set(_ weight: Decimal?, _ reps: Int?,
                     pr: Bool = false, failed: Bool = false)
        -> PostSummary.ExerciseEntry.SetEntry {
        .init(weightLbs: weight, reps: reps, isPR: pr, isFailed: failed)
    }

    private func exercise(_ name: String,
                          _ sets: [PostSummary.ExerciseEntry.SetEntry],
                          equipment: String = "barbell") -> PostSummary.ExerciseEntry {
        .init(name: name, equipment: equipment, sets: sets)
    }

    // MARK: - The line

    func testThreeSetsCollapseToTheCountAndTheHeaviestBar() {
        let line = PumpCardCollapse.line(
            for: exercise("Back Squat", [set(225, 5), set(235, 3), set(205, 8)]),
            unit: .lbs)
        XCTAssertEqual(line, "Back Squat · 3 × 235 lbs")
    }

    func testTheCountIsEverySetAndTheWeightIsTheHeaviestOneThatLanded() {
        // The failed 275 was attempted — it counts as a set — but it is not
        // the lifter's top set, which is the same rule the bar loader obeys.
        let line = PumpCardCollapse.line(
            for: exercise("Back Squat", [set(225, 5), set(275, 1, failed: true)]),
            unit: .lbs)
        XCTAssertEqual(line, "Back Squat · 2 × 225 lbs")
    }

    func testAnEntryWithNoWeightFallsBackToItsBestRepCount() {
        let line = PumpCardCollapse.line(
            for: exercise("Walking Lunge", [set(nil, 20)], equipment: "bodyweight"),
            unit: .lbs)
        XCTAssertEqual(line, "Walking Lunge · 1 × 20")
    }

    func testAnEntryWithNeitherWeightNorRepsPrintsABareSetCount() {
        // A cardio entry logged as time only: `— × —` says nothing, so the
        // line says what it knows.
        XCTAssertEqual(
            PumpCardCollapse.line(for: exercise("Rower", [set(nil, nil)], equipment: "machine"),
                                  unit: .lbs),
            "Rower · 1 set")
        XCTAssertEqual(
            PumpCardCollapse.line(for: exercise("Rower", [set(nil, nil), set(nil, nil)],
                                                equipment: "machine"),
                                  unit: .lbs),
            "Rower · 2 sets")
    }

    func testTheWeightIsTheViewersUnit() {
        // 225 lb is 102.1 kg — the snapshot stays canonical pounds and the
        // FEED converts (the Units doctrine).
        let line = PumpCardCollapse.line(for: exercise("Back Squat", [set(225, 5)]), unit: .kg)
        XCTAssertTrue(line.hasSuffix(" kg"), line)
        XCTAssertFalse(line.contains("225"), line)
    }

    // MARK: - The PR tag

    func testAPRSetEarnsTheTagAndAnOrdinaryExerciseDoesNot() {
        XCTAssertTrue(PumpCardCollapse.hasPR(
            exercise("Back Squat", [set(225, 5), set(235, 3, pr: true)])))
        XCTAssertFalse(PumpCardCollapse.hasPR(
            exercise("Back Squat", [set(225, 5), set(235, 3)])))
    }

    func testAPROnAFailedSetIsNotARecord() {
        XCTAssertFalse(PumpCardCollapse.hasPR(
            exercise("Back Squat", [set(275, 1, pr: true, failed: true)])))
    }

    // MARK: - The island's detail line

    func testTheNoteNamesTheKindInWords() {
        XCTAssertEqual(
            PumpCardCollapse.note(for: PostHighlight(kind: .pr, text: "PR — Back Squat",
                                                     weightLbs: 235, reps: 3)),
            "a personal record")
        XCTAssertEqual(
            PumpCardCollapse.note(for: PostHighlight(kind: .topSet, text: "Top set — Back Squat",
                                                     weightLbs: 225, reps: 5)),
            "the day's top set")
        XCTAssertEqual(
            PumpCardCollapse.note(for: PostHighlight(kind: .milestone,
                                                     text: "Lifetime total crossed",
                                                     weightLbs: 1_000_000, reps: nil)),
            "a milestone")
    }

    func testThePhotoCaptionSaysTheTileIsADoor() {
        XCTAssertEqual(PumpCardCollapse.photoCaption, "Tap for the full workout")
    }
}
