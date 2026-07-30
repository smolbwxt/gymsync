import XCTest
@testable import GymSync

/// Pure-function coverage for `RoutineProgression.currentExercise` — the
/// group session's exercise-progression rule. No network setUp (the
/// ProgramMathTests pattern).
final class RoutineProgressionTests: XCTestCase {

    private let routineID = UUID()
    private let exA = UUID()
    private let exB = UUID()
    private let exC = UUID()

    private func re(_ exerciseID: UUID, position: Int, targetSets: Int?) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routineID, exerciseID: exerciseID,
                        position: position, targetSets: targetSets,
                        targetReps: nil, targetWeight: nil,
                        restSeconds: nil, notes: nil)
    }

    private var routine: [RoutineExercise] {
        [re(exA, position: 1, targetSets: 3),
         re(exB, position: 2, targetSets: 4),
         re(exC, position: 3, targetSets: 2)]
    }

    func testStartsAtTheFirstExercise() {
        let current = RoutineProgression.currentExercise(routine: routine) { _ in 0 }
        XCTAssertEqual(current?.exerciseID, exA)
    }

    func testAdvancesWhenTargetIsMet() {
        // THE 13/3 BUG: three sets logged on A must move the lifter to B —
        // before this rule, A stayed current forever and the counter climbed.
        let counts = [exA: 3, exB: 0, exC: 0]
        let current = RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }
        XCTAssertEqual(current?.exerciseID, exB)
    }

    func testDoesNotAdvanceEarly() {
        let counts = [exA: 2]
        let current = RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }
        XCTAssertEqual(current?.exerciseID, exA)
    }

    func testOverflowStillAdvances() {
        // A lifter who somehow logged PAST the target (the shipped bug's
        // aftermath: 12 sets against 3) still moves on.
        let counts = [exA: 12, exB: 4, exC: 0]
        let current = RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }
        XCTAssertEqual(current?.exerciseID, exC)
    }

    func testAllFinishedReturnsLastNotNil() {
        // The session keeps a valid write target for bonus sets.
        let counts = [exA: 3, exB: 4, exC: 2]
        let current = RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }
        XCTAssertEqual(current?.exerciseID, exC)
    }

    func testPositionOrderWinsOverArrayOrder() {
        let shuffled = [re(exC, position: 3, targetSets: 2),
                        re(exA, position: 1, targetSets: 3),
                        re(exB, position: 2, targetSets: 4)]
        let current = RoutineProgression.currentExercise(routine: shuffled) { _ in 0 }
        XCTAssertEqual(current?.exerciseID, exA)
    }

    func testNilTargetMeansOneSet() {
        let routine = [re(exA, position: 1, targetSets: nil),
                       re(exB, position: 2, targetSets: 1)]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { _ in 0 }?.exerciseID, exA)
        let counts = [exA: 1]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }?.exerciseID, exB)
    }

    func testEmptyRoutineReturnsNil() {
        XCTAssertNil(RoutineProgression.currentExercise(routine: []) { _ in 0 })
    }
}
