import XCTest
@testable import GymSync

/// THE ONLY PLACE THE LAYERING ORDER IS ASSERTED (plan task S7).
///
/// The order is a product decision, not an implementation detail: the squad's
/// swap is everyone's, my own quiet self-scale beats it for my body, and
/// today's accepted set reduction rides the SLOT rather than the lift. It was
/// hand-copied into three files before this type existed, which is three
/// chances for two screens to print two prescriptions for the same lift.
final class RoutineLayeringTests: XCTestCase {

    private let benchID = UUID()
    private let squatID = UUID()
    private let inclineID = UUID()
    private let machinePressID = UUID()

    private func row(_ exerciseID: UUID, sets: Int?, reps: String? = "5",
                     weight: String? = "225", position: Int = 0) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: exerciseID,
                        position: position, targetSets: sets, targetReps: reps,
                        targetWeight: weight, restSeconds: nil, notes: nil)
    }

    func testNoLayersLeavesTheRoutineExactlyAsItIs() {
        let rows = [row(benchID, sets: 4), row(squatID, sets: 3, position: 1)]
        let applied = RoutineLayering.apply(rows)
        XCTAssertEqual(applied.map(\.exerciseID), [benchID, squatID])
        XCTAssertEqual(applied.map(\.targetSets), [4, 3])
        XCTAssertEqual(applied.map(\.targetWeight), ["225", "225"])
    }

    func testASquadSwapReplacesTheLiftForEveryone() {
        let applied = RoutineLayering.apply([row(benchID, sets: 4)],
                                            squadSwaps: [benchID: inclineID])
        XCTAssertEqual(applied.first?.exerciseID, inclineID)
        // The prescription survives; the bar number does not — a weight for
        // one lift is not a weight for another.
        XCTAssertEqual(applied.first?.targetSets, 4)
        XCTAssertEqual(applied.first?.targetReps, "5")
        XCTAssertNil(applied.first?.targetWeight)
    }

    func testMyOwnSelfScaleBeatsTheSquadSwapForTheSameSlot() {
        // Layer 2 over layer 1: my own choice for my own body outranks the
        // crew's choice for the room, and it is never announced.
        let applied = RoutineLayering.apply([row(benchID, sets: 4)],
                                            squadSwaps: [benchID: inclineID],
                                            selfScale: [benchID: machinePressID])
        XCTAssertEqual(applied.first?.exerciseID, machinePressID)
    }

    func testTodaysScaleRidesASWAPPEDSlotBecauseItIsKeyedOnTheRoutinesOwnExercise() {
        // The athlete accepted "one set fewer" against the routine's row. A
        // squad swap landing afterwards changes the LIFT in that slot; the
        // reduced set count stays with the SLOT, which is what the athlete
        // agreed to.
        let applied = RoutineLayering.apply(
            [row(benchID, sets: 4)],
            squadSwaps: [benchID: inclineID],
            todaysScale: TodaysScale(exerciseID: benchID, setsInstead: 3))
        XCTAssertEqual(applied.first?.exerciseID, inclineID)
        XCTAssertEqual(applied.first?.targetSets, 3)
    }

    func testTodaysScaleKeyedOnTheREPLACEMENTChangesNothing() {
        // The mirror of the case above, stated so the keying cannot be
        // quietly inverted later: the scale is keyed on the routine's own
        // exercise, so naming the swapped-IN lift matches no row.
        let applied = RoutineLayering.apply(
            [row(benchID, sets: 4)],
            squadSwaps: [benchID: inclineID],
            todaysScale: TodaysScale(exerciseID: inclineID, setsInstead: 3))
        XCTAssertEqual(applied.first?.targetSets, 4)
    }

    func testAllThreeLayersTogether() {
        let rows = [row(benchID, sets: 4), row(squatID, sets: 5, position: 1)]
        let applied = RoutineLayering.apply(
            rows,
            squadSwaps: [benchID: inclineID],
            selfScale: [squatID: machinePressID],
            todaysScale: TodaysScale(exerciseID: benchID, setsInstead: 3))
        XCTAssertEqual(applied.map(\.exerciseID), [inclineID, machinePressID])
        XCTAssertEqual(applied.map(\.targetSets), [3, 5])
    }

    func testTheScaleOnlyTouchesItsOwnSlot() {
        let rows = [row(benchID, sets: 4), row(squatID, sets: 5, position: 1)]
        let applied = RoutineLayering.apply(
            rows, todaysScale: TodaysScale(exerciseID: squatID, setsInstead: 4))
        XCTAssertEqual(applied.map(\.targetSets), [4, 4])
        XCTAssertEqual(applied.map(\.exerciseID), [benchID, squatID])
    }

    /// R-B2-13, kept where the rebuild now lives: a prescribed failure is the
    /// assignment fulfilled, and swapping the lift does not cancel it.
    func testASwapCarriesAPrescribedFailure() {
        var amrap = row(benchID, sets: 3, reps: nil)
        amrap.targetFailure = true
        let applied = RoutineLayering.swapped(amrap, to: inclineID)
        XCTAssertEqual(applied.exerciseID, inclineID)
        XCTAssertEqual(applied.targetFailure, true)
        XCTAssertEqual(applied.targetSets, 3)
    }

    /// Hotfix 2026-09-18 (ruling H6). Solo renders drop prescriptions —
    /// "REPS · TOP + DROP 2×20%" on the entry card, and the drop-ladder
    /// sheet arms off `setType` — and solo now routes its swap through
    /// here. A set STRUCTURE is the dose, not the lift, so it rides the
    /// slot exactly as the set count does; dropping it silently cancelled
    /// a prescribed ladder the moment a station was taken.
    func testASwapCarriesTheSetStructure() {
        var drop = row(benchID, sets: 4)
        drop.setType = "drop"
        drop.dropSteps = 3
        drop.dropPercent = 15
        let applied = RoutineLayering.swapped(drop, to: inclineID)
        XCTAssertEqual(applied.exerciseID, inclineID)
        XCTAssertEqual(applied.setType, "drop")
        XCTAssertEqual(applied.dropSteps, 3)
        XCTAssertEqual(applied.dropPercent, 15)
    }

    /// The whole row, field by field, so the next field added to
    /// `RoutineExercise` cannot be quietly left behind by a hand-written
    /// argument list — which is how `targetFailure` and the three above
    /// were lost in the first place. The bar number is the ONE deliberate
    /// omission: a weight for one lift is not a weight for another.
    func testASwapKeepsEveryPrescriptionFieldAndOnlyDropsTheBarNumber() {
        var full = row(benchID, sets: 4, reps: "6", weight: "225", position: 2)
        full.restSeconds = 150
        full.notes = "pause on the chest"
        full.setType = "burnout"
        full.supersetGroup = 1
        full.dropSteps = 2
        full.dropPercent = 20
        full.targetFailure = true
        full.targetRepsLow = 6
        full.targetRepsHigh = 9
        full.cardioZone = 2
        full.cardioMinutes = 20

        let expected = RoutineExercise(
            id: full.id, routineID: full.routineID, exerciseID: inclineID,
            position: full.position, targetSets: full.targetSets,
            targetReps: full.targetReps, targetWeight: nil,
            restSeconds: full.restSeconds, notes: full.notes,
            setType: full.setType, supersetGroup: full.supersetGroup,
            dropSteps: full.dropSteps, dropPercent: full.dropPercent,
            targetFailure: full.targetFailure,
            targetRepsLow: full.targetRepsLow, targetRepsHigh: full.targetRepsHigh,
            cardioZone: full.cardioZone, cardioMinutes: full.cardioMinutes)

        XCTAssertEqual(RoutineLayering.swapped(full, to: inclineID), expected)
        XCTAssertNil(RoutineLayering.swapped(full, to: inclineID).targetWeight)
        // The slot's identity survives — that is what makes a second swap
        // of the same slot replace the first rather than stack on it.
        XCTAssertEqual(RoutineLayering.swapped(full, to: inclineID).id, full.id)
    }
}
