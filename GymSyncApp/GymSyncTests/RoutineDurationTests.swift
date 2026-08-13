import XCTest
@testable import GymSync

/// StatMath.estimatedMinutes — the owner prescription formula (2026-08-13):
/// 2 min per set + rest BETWEEN sets + a transit window between exercises,
/// replacing the flat 15 min/exercise that consistently overestimated.
final class RoutineDurationTests: XCTestCase {

    private func rx(sets: Int?, rest: Int?) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: UUID(),
                        position: 0, targetSets: sets, targetReps: nil,
                        targetWeight: nil, restSeconds: rest, notes: nil)
    }

    func testPrescribedRoutineSumsSetsRestsAndTransits() {
        // 3 exercises × (3 sets × 120 s + 2 rests × 90 s) + 2 transits × 120 s
        // = 3 × 540 + 240 = 1860 s → 31 min
        let exercises = [rx(sets: 3, rest: 90), rx(sets: 3, rest: 90), rx(sets: 3, rest: 90)]
        XCTAssertEqual(StatMath.estimatedMinutes(exercises: exercises), 31)
    }

    func testMissingPrescriptionFallsBackToThreeSetsAndDefaultRest() {
        // 2 bare exercises at defaults: 2 × (3 × 120 + 2 × 120) + 1 × 120
        // = 1320 s → 22 min
        let exercises = [rx(sets: nil, rest: nil), rx(sets: nil, rest: nil)]
        XCTAssertEqual(StatMath.estimatedMinutes(exercises: exercises), 22)
    }

    func testSingleExerciseHasNoTransitAndNoTrailingRest() {
        // 1 × (2 sets × 120 + 1 rest × 60) = 300 s → 5 min
        XCTAssertEqual(StatMath.estimatedMinutes(exercises: [rx(sets: 2, rest: 60)]), 5)
    }

    func testEmptyRoutineEstimatesZero() {
        XCTAssertEqual(StatMath.estimatedMinutes(exercises: []), 0)
    }

    func testCountOnlyFallbackMatchesFormulaDefaults() {
        // ~12 min/exercise — the prescription formula at its defaults, for
        // callers without the exercise list (schedule sheet, calendar bridge).
        XCTAssertEqual(StatMath.estimatedMinutes(exerciseCount: 6), 72)
        XCTAssertEqual(StatMath.estimatedMinutes(exerciseCount: 0), 0)
    }
}
