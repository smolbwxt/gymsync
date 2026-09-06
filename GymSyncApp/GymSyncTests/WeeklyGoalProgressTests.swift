import XCTest
@testable import GymSync

/// `WeeklyGoalProgressMath` — the pure arithmetic behind the weekly goal
/// strip. Plan: Stream A tasks A3-A7.
///
/// The contract these pin: a penalty is not training, a missed single is
/// not a set, a failed triple IS two reps of work, and the six-group
/// rollup is applied once per counted log.
final class WeeklyGoalProgressTests: XCTestCase {

    // MARK: - Fixtures

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func exercise(_ n: Int, _ name: String, _ primary: String,
                          secondaries: [String] = [],
                          category: String = "compound") -> Exercise {
        Exercise(id: id(n), name: name, slug: name.lowercased(),
                 category: category, primaryMuscle: primary,
                 secondaryMuscles: secondaries, equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func log(_ exercise: Exercise, reps: Int?, index: Int = 1,
                     failed: Bool = false, penalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: id(9001), sessionID: id(9002),
               exerciseID: exercise.id, setIndex: index, reps: reps,
               weight: 135, rpe: nil, isFailed: failed, isPenalty: penalty,
               note: nil, loggedAt: Date(timeIntervalSince1970: 1_788_696_000))
    }

    private func catalog(_ exercises: [Exercise]) -> [UUID: Exercise] {
        Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    /// The plan's own worked example: chest 1.0, arms 0.5, shoulders 0.5.
    private let benchPrimary = "chest"
    private let benchSecondaries = ["triceps", "front_delts"]

    // MARK: - A3: what counts as a set

    func testCleanSetCreditsThePerSetMap() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8)], catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0)
        XCTAssertEqual(tally[.arms], 0.5)
        XCTAssertEqual(tally[.shoulders], 0.5)
        XCTAssertNil(tally[.back])
    }

    func testFailedSingleCreditsNothing() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 1, failed: true)], catalog: catalog([bench]))

        XCTAssertTrue(tally.isEmpty,
                      "a missed single completed zero reps — nothing was lifted")
    }

    func testFailedTripleCreditsFully() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 3, failed: true)], catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0,
                       "a failed triple completed 2 reps — that is a set of work")
        XCTAssertEqual(tally[.arms], 0.5)
        XCTAssertEqual(tally[.shoulders], 0.5)
    }

    func testPenaltySetCreditsNothing() {
        let burpee = exercise(2, "Burpee", "legs", secondaries: ["chest", "core"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(burpee, reps: 20, penalty: true)], catalog: catalog([burpee]))

        XCTAssertTrue(tally.isEmpty,
                      "the late-arrival burpee tax is not training volume")
    }

    func testNilRepsCreditsNothing() {
        let bench = exercise(1, "Bench Press", benchPrimary)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: nil)], catalog: catalog([bench]))

        XCTAssertTrue(tally.isEmpty, "a log with no reps proves no work")
    }

    func testTwoSetsCreditTwiceThePerSetMap() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8, index: 1), log(bench, reps: 6, index: 2)],
            catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 2.0)
        XCTAssertEqual(tally[.arms], 1.0)
        XCTAssertEqual(tally[.shoulders], 1.0)
    }

    func testUnknownExerciseIsSkippedNotGuessed() {
        let bench = exercise(1, "Bench Press", benchPrimary)
        let ghost = exercise(99, "Ghost Lift", "back")
        // `ghost` is logged but absent from the catalog — a stale local copy.
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8), log(ghost, reps: 8)],
            catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0)
        XCTAssertNil(tally[.back], "an exercise the catalog does not carry credits nothing")
    }

    func testUnmappedMuscleCreditsNothingAndIsNotAnError() {
        let shrug = exercise(3, "Neck Curl", "neck", secondaries: ["neck"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(shrug, reps: 12)], catalog: catalog([shrug]))

        XCTAssertTrue(tally.isEmpty,
                      "`neck` is real catalog data that belongs to none of the six groups")
    }

    func testEmptyWeekIsAnEmptyTally() {
        XCTAssertTrue(WeeklyGoalProgressMath.muscleSetCredit(logs: [], catalog: [:]).isEmpty)
    }

    func testBackSquatPaysLegsOnceNotTwice() {
        // The rollup-before-dedupe rule, exercised through the tally rather
        // than through `MuscleGroup.credit` directly: glutes and hamstrings
        // both roll up to `legs`, which is already the primary's group.
        let squat = exercise(4, "Back Squat", "quads",
                             secondaries: ["glutes", "hamstrings", "core"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(squat, reps: 5)], catalog: catalog([squat]))

        XCTAssertEqual(tally[.legs], 1.0, "legs is paid once, as the primary")
        XCTAssertEqual(tally[.core], 0.5)
        XCTAssertEqual(tally.count, 2)
    }
}
