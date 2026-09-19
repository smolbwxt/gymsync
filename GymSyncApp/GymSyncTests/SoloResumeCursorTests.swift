import XCTest
@testable import GymSync

/// WHERE A RESUMED SOLO SESSION PICKS BACK UP.
///
/// The owner's 2026-09-18 report: swipe the session sheet down, come back
/// through the SESSION LIVE pill, and the screen was on the exercise he had
/// SWAPPED OUT, at set 1 — so he repeated three sets that were already in
/// the log, under a second exercise id. Volume and set count double-counted.
///
/// The cause was arithmetic, and it lived in a `private func` on a `View`
/// where nothing could assert it: the walk attributed logged sets to slots
/// by comparing `log.exerciseID` against the ROUTINE'S row, while the sets
/// had been written under the SUBSTITUTE's id. Zero matches, so the slot
/// read as untouched. Every test below is written against the swap being
/// LOST — the state the view was in — because that is the defect, not a
/// hypothetical.
final class SoloResumeCursorTests: XCTestCase {

    private let benchID = UUID()
    private let inclineID = UUID()
    private let barbellRowID = UUID()
    private let squatID = UUID()
    private let legPressID = UUID()
    private let sessionID = UUID()
    private let userID = UUID()

    private func slot(_ exerciseID: UUID, sets: Int?, position: Int) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: exerciseID,
                        position: position, targetSets: sets, targetReps: "8",
                        targetWeight: "135", restSeconds: 90, notes: nil)
    }

    /// `count` sets logged under `exerciseID`, in order.
    private func logs(_ exerciseID: UUID, _ count: Int,
                      isPenalty: Bool = false, from: TimeInterval = 0) -> [SetLog] {
        (0..<count).map { i in
            SetLog(id: UUID(), userID: userID, sessionID: sessionID,
                   exerciseID: exerciseID, setIndex: i + 1,
                   reps: 8, weight: 135, rpe: 7,
                   isFailed: false, isPenalty: isPenalty, note: nil,
                   loggedAt: Date(timeIntervalSince1970: from + Double(i)))
        }
    }

    // MARK: - (d) The docket case, end to end

    /// THE EXACT REPORT. Two slots; the first was swapped bench → incline
    /// and three sets were logged under INCLINE; two sets of the second
    /// slot followed. The lifter belongs on slot 2, set 3.
    func testTheReportedCaseSwappedSlotsSetsCountTowardTheSlotTheySitIn() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        let overrides = [rows[0].id: RoutineLayering.swapped(rows[0], to: inclineID)]
        let logged = logs(inclineID, 3) + logs(squatID, 2, from: 100)

        let cursor = SoloResumeCursor.derive(rows: rows, swapOverrides: overrides,
                                             logs: logged)
        XCTAssertEqual(cursor, SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 3))

        // AND THE DEFECT ITSELF, stated as an assertion: the ONLY thing that
        // changed in the failing build was that the layer was gone (it lived
        // in `@State` on a view a swipe-down destroys). Same rows, same logs,
        // empty layer → back to slot 1 set 1, three sets into the void. If
        // this line ever stops being the "wrong" answer, the layering above
        // is doing nothing and the test above is passing by accident.
        let layerLost = SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                                logs: logged)
        XCTAssertEqual(layerLost, SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    // MARK: - (a) A swapped slot with later slots already finished

    /// Slot 2 swapped and fully logged under the substitute, slots 3 and 4
    /// worked afterwards: the cursor lands where the lifter actually is,
    /// and NEVER back on slot 2's original.
    func testASwappedSlotDoesNotDragTheCursorBackPastFinishedWork() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(barbellRowID, sets: 3, position: 1),
                    slot(squatID, sets: 3, position: 2),
                    slot(legPressID, sets: 3, position: 3)]
        let overrides = [rows[1].id: RoutineLayering.swapped(rows[1], to: inclineID)]
        let logged = logs(benchID, 3)
            + logs(inclineID, 3, from: 100)
            + logs(squatID, 3, from: 200)
            + logs(legPressID, 2, from: 300)

        let cursor = SoloResumeCursor.derive(rows: rows, swapOverrides: overrides,
                                             logs: logged)
        XCTAssertEqual(cursor, SoloResumeCursor.Position(exerciseIndex: 3, setIndex: 3))
        // Never the swapped-away row — the specific harm (re-lifting work
        // already logged) is worth its own assertion, not just an equality.
        XCTAssertNotEqual(cursor.exerciseIndex, 1)

        let layerLost = SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                                logs: logged)
        XCTAssertEqual(layerLost, SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1),
                       "the lost-layer walk strands eight logged sets and reopens slot 2")
    }

    // MARK: - (b) No swaps: byte-for-byte today's behaviour

    func testWithNoSwapsTheWalkIsExactlyWhatItAlwaysWas() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                    logs: logs(benchID, 3) + logs(squatID, 2, from: 100)),
            SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 3))
    }

    func testAnUntouchedRoutineStartsAtTheTop() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: []),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    func testAnEmptyRoutineIsTheHonestFloorRatherThanACrash() {
        XCTAssertEqual(SoloResumeCursor.derive(rows: [], swapOverrides: [:], logs: []),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    /// A finished routine parks on the LAST slot one past its target — the
    /// lifter finishes from there rather than being walked off the end.
    func testAFullyLoggedRoutineParksPastTheLastSlotsTarget() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                    logs: logs(benchID, 3) + logs(squatID, 3, from: 100)),
            SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 4))
    }

    /// Penalty rows are not progress through the plan. Filtered inside the
    /// walk so no caller can forget to.
    func testPenaltySetsAreNotProgress() {
        let rows = [slot(benchID, sets: 3, position: 0)]
        let logged = logs(benchID, 1) + logs(benchID, 5, isPenalty: true, from: 100)
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logged),
            SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 2))
    }

    // MARK: - (c) A swap with nothing logged against it yet

    /// WITH NO SETS LOGGED, THE CURSOR CANNOT DISCRIMINATE — and saying so
    /// is the point of the name (review F5). An unswapped slot and a
    /// swapped one with nothing under either lift are both "0 of 3", so
    /// `(0, 1)` is what the old logic returned too. That assertion is a
    /// BEHAVIOUR PIN, not a regression test; the real discriminators for
    /// H2 are the two cases above, which each also assert the defect
    /// directly by deriving with an empty layer.
    ///
    /// What IS new here is the second half: the slot the cursor lands on
    /// must SHOW the substitute. That is the half a lost layer destroyed
    /// even before a single set was logged, and `layered` is the call that
    /// decides it — the same call `activeExercises` makes, so the screen
    /// and the cursor can never be looking at two different routines.
    func testASwapWithNoSetsYetStillShowsTheSubstituteInTheSlot() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        let overrides = [rows[0].id: RoutineLayering.swapped(rows[0], to: inclineID)]

        // Pin (not a discriminator — see above).
        let cursor = SoloResumeCursor.derive(rows: rows, swapOverrides: overrides, logs: [])
        XCTAssertEqual(cursor, SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))

        // Discriminator: the layer is what the lifter sees.
        let layered = SoloResumeCursor.layered(rows, swapOverrides: overrides)
        XCTAssertEqual(layered[cursor.exerciseIndex].exerciseID, inclineID)
        XCTAssertEqual(layered[1].exerciseID, squatID)
        // The slot's identity is the ROW, so the prescription rides with it.
        XCTAssertEqual(layered[0].id, rows[0].id)
        XCTAssertEqual(layered[0].targetSets, 3)
        // Losing the layer is losing the substitute, with nothing logged yet.
        XCTAssertEqual(SoloResumeCursor.layered(rows, swapOverrides: [:])[0].exerciseID,
                       benchID)
    }

    func testSwappingTheSameSlotTwiceReplacesRatherThanStacks() {
        let rows = [slot(benchID, sets: 3, position: 0)]
        var overrides: [UUID: RoutineExercise] = [:]
        overrides[rows[0].id] = RoutineLayering.swapped(rows[0], to: inclineID)
        // The second swap is applied to the ALREADY-SWAPPED row, exactly as
        // `applySwap` does (it reads `currentRoutineExercise`, which is the
        // layered one) — the row id carries through, so one entry.
        let alreadySwapped = overrides[rows[0].id]!
        overrides[rows[0].id] = RoutineLayering.swapped(alreadySwapped, to: legPressID)
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(SoloResumeCursor.layered(rows, swapOverrides: overrides)
                        .map(\.exerciseID), [legPressID])
    }

    // MARK: - Pinned, known, and Phase C's to fix

    /// A ROUTINE NAMING THE SAME LIFT TWICE still fills the first slot to
    /// its target before the second sees a set, because attribution is by
    /// EXERCISE ID and both slots claim the same one. Unchanged by this
    /// hotfix and pinned here so it cannot drift silently: the honest fix
    /// is slot attribution (a `routine_exercise_id` on the set log), which
    /// is Phase C's, and which this test should be deleted with.
    func testARoutineNamingOneLiftTwiceKeepsTodaysGreedyAttribution() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(benchID, sets: 3, position: 1)]
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logs(benchID, 2)),
            SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 3))
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logs(benchID, 4)),
            SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 2))
    }
}
