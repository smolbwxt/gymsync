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

    // MARK: - Superset alternation (set structures phase B)

    private func paired(_ exerciseID: UUID, position: Int, targetSets: Int?,
                        group: Int) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routineID, exerciseID: exerciseID,
                        position: position, targetSets: targetSets,
                        targetReps: nil, targetWeight: nil,
                        restSeconds: nil, notes: nil, supersetGroup: group)
    }

    /// A+B paired (3 sets each), C after. The full alternation walk:
    /// A → B → A → B → A → B → C.
    func testSupersetPairAlternates() {
        let routine = [paired(exA, position: 1, targetSets: 3, group: 1),
                       paired(exB, position: 2, targetSets: 3, group: 1),
                       re(exC, position: 3, targetSets: 2)]
        let walk: [([UUID: Int], UUID)] = [
            ([:], exA),
            ([exA: 1], exB),
            ([exA: 1, exB: 1], exA),
            ([exA: 2, exB: 1], exB),
            ([exA: 2, exB: 2], exA),
            ([exA: 3, exB: 2], exB),
            ([exA: 3, exB: 3], exC),
        ]
        for (counts, expected) in walk {
            let current = RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }
            XCTAssertEqual(current?.exerciseID, expected,
                           "counts \(counts) should land on \(expected)")
        }
    }

    /// Uneven targets: A capped at 2, B runs to 4 — B finishes solo.
    func testSupersetUnevenTargetsFinishOnB() {
        let routine = [paired(exA, position: 1, targetSets: 2, group: 1),
                       paired(exB, position: 2, targetSets: 4, group: 1),
                       re(exC, position: 3, targetSets: 2)]
        let counts = [exA: 2, exB: 2]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }?.exerciseID, exB)
        let done = [exA: 2, exB: 4]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { done[$0] ?? 0 }?.exerciseID, exC)
    }

    /// A dangling group (no adjacent partner) behaves as a straight
    /// exercise — the builder normalizes these away, but the math must
    /// not trust that.
    func testDanglingSupersetGroupIsStraight() {
        let routine = [paired(exA, position: 1, targetSets: 2, group: 1),
                       re(exB, position: 2, targetSets: 1)]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { _ in 0 }?.exerciseID, exA)
        let counts = [exA: 2]
        XCTAssertEqual(RoutineProgression.currentExercise(routine: routine) { counts[$0] ?? 0 }?.exerciseID, exB)
    }

    func testArePairedRequiresAdjacency() {
        let a = paired(exA, position: 1, targetSets: 3, group: 1)
        let b = paired(exB, position: 2, targetSets: 3, group: 1)
        let cDangling = paired(exC, position: 3, targetSets: 2, group: 9)
        let routine = [a, b, cDangling]
        XCTAssertTrue(RoutineProgression.arePaired(a, b, in: routine))
        XCTAssertTrue(RoutineProgression.arePaired(b, a, in: routine))
        XCTAssertFalse(RoutineProgression.arePaired(a, cDangling, in: routine))
        XCTAssertFalse(RoutineProgression.arePaired(a, nil, in: routine))
        XCTAssertFalse(RoutineProgression.arePaired(a, a, in: routine))
    }
}
