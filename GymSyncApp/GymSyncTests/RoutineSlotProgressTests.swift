import XCTest
@testable import GymSync

/// SET ATTRIBUTION BY SLOT (plan task S2, decision 3).
///
/// A set row now carries the `routine_exercises` row it was logged against.
/// Every case below is wrong on the shipped logic, or is the pin that proves
/// the shipped logic survives where it must:
///
///   * the root-cause report — a swapped slot's sets counting toward the
///     slot they sit in, so the lifter is not sent back to repeat them;
///   * a routine naming one lift twice — slot 2 shows zero while slot 1 is
///     being filled;
///   * a swap made MID-EXERCISE — one slot, two exercise ids, one count;
///   * a pre-column session — byte-identical to yesterday, because the
///     fallback is what serves rows that do not know their slot.
final class RoutineSlotProgressTests: XCTestCase {

    private let benchID = UUID()
    private let inclineID = UUID()
    private let squatID = UUID()
    private let sessionID = UUID()
    private let userID = UUID()

    private func slot(_ exerciseID: UUID, sets: Int?, position: Int) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: exerciseID,
                        position: position, targetSets: sets, targetReps: "8",
                        targetWeight: "135", restSeconds: 90, notes: nil)
    }

    /// `count` sets under `exerciseID`, attributed to `slotID` (nil = a
    /// pre-column or freeform row).
    private func logs(_ exerciseID: UUID, _ count: Int, slot slotID: UUID?,
                      isPenalty: Bool = false, from: TimeInterval = 0) -> [SetLog] {
        (0..<count).map { i in
            SetLog(id: UUID(), userID: userID, sessionID: sessionID,
                   exerciseID: exerciseID, setIndex: i + 1,
                   reps: 8, weight: 135, rpe: 7,
                   isFailed: false, isPenalty: isPenalty, note: nil,
                   loggedAt: Date(timeIntervalSince1970: from + Double(i)),
                   routineExerciseID: slotID)
        }
    }

    // MARK: - The rule, stated once and asserted once

    func testASlotCountsTheRowsThatNameIt() {
        let bench = slot(benchID, sets: 3, position: 0)
        let counted = RoutineProgression.completedSets(
            forSlot: bench,
            in: logs(benchID, 2, slot: bench.id) + logs(squatID, 5, slot: UUID(), from: 100))
        XCTAssertEqual(counted, 2)
    }

    func testASlotWithNoNamedRowsFallsBackToTheLiftButOnlyForUNNAMEDRows() {
        let bench = slot(benchID, sets: 3, position: 0)
        let otherSlot = UUID()
        let counted = RoutineProgression.completedSets(
            forSlot: bench,
            in: logs(benchID, 2, slot: nil)               // pre-column: mine
                + logs(benchID, 4, slot: otherSlot, from: 100))  // another slot's
        XCTAssertEqual(counted, 2,
                       "a row that names a DIFFERENT slot is that slot's, "
                       + "and the fallback must not claim it back by lift")
    }

    func testOnceASlotHasANamedRowTheUnnamedOnesStopCounting() {
        // Decision 3's rule, verbatim: "plus — ONLY when the slot has zero
        // such rows". The session that straddles the deploy keeps the old
        // behaviour until the first attributed row lands, then switches.
        let bench = slot(benchID, sets: 3, position: 0)
        let straddling = logs(benchID, 2, slot: nil) + logs(benchID, 1, slot: bench.id, from: 100)
        XCTAssertEqual(RoutineProgression.completedSets(forSlot: bench, in: straddling), 1)
    }

    // MARK: - The root-cause report

    /// `[A(3), C(3)]`, slot A swapped to B, `3×B + 2×C` logged: the lifter
    /// belongs on slot 2, set 3. On the shipped logic — no column, so no
    /// attribution — a lost swap layer answers `(0, 1)` and sends him back
    /// to repeat three sets already in the log.
    func testTheReportedCaseIsAnsweredByTheSLOTEvenWithNoSwapLayerAtAll() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        // The sets were logged under the SUBSTITUTE's exercise id, which is
        // right and deliberate (history, PRs and the debrief should all see
        // the lift actually done) — and attributed to slot A.
        let logged = logs(inclineID, 3, slot: rows[0].id)
            + logs(squatID, 2, slot: rows[1].id, from: 100)

        // THE POINT: no `swapOverrides` at all. Even with the layer lost,
        // the ROWS say where their work belongs.
        let cursor = SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logged)
        XCTAssertEqual(cursor, SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 3))

        // And the same rows with the slot stripped — what the shipped build
        // writes — is the defect, stated as an assertion.
        let preColumn = logs(inclineID, 3, slot: nil)
            + logs(squatID, 2, slot: nil, from: 100)
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: preColumn),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    // MARK: - A swap made MID-EXERCISE

    /// One slot, two exercise ids, one count. This is owner complaint B3's
    /// whole basis: per-id counting broke the moment a slot held sets of two
    /// lifts, which is why the swap affordance is gated to exercise
    /// boundaries today. C1 makes the counting honest; lifting the gate is
    /// C2's, in a view C1 is not rewriting.
    func testASwapMidExerciseCountsBothHalvesAsTheOneSlotTheyAre() {
        let bench = slot(benchID, sets: 4, position: 0)
        let logged = logs(benchID, 2, slot: bench.id)
            + logs(inclineID, 2, slot: bench.id, from: 100)
        XCTAssertEqual(RoutineProgression.completedSets(forSlot: bench, in: logged), 4)

        let rows = [bench, slot(squatID, sets: 3, position: 1)]
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logged),
                       SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1))
    }

    // MARK: - A routine naming one lift twice

    func testTwoSlotsOneLiftThreeSetsOnTheFirstAndTheSecondStillShowsZero() {
        let first = slot(benchID, sets: 3, position: 0)
        let second = slot(benchID, sets: 3, position: 1)
        let logged = logs(benchID, 3, slot: first.id)

        XCTAssertEqual(RoutineProgression.completedSets(forSlot: first, in: logged), 3)
        XCTAssertEqual(RoutineProgression.completedSets(forSlot: second, in: logged), 0)

        // The walk therefore opens the second slot at set 1 — and the
        // progression returns the SECOND row, not the first.
        let current = RoutineProgression.currentSlot(
            routine: [first, second],
            completedSets: { re in RoutineProgression.completedSets(forSlot: re, in: logged) })
        XCTAssertEqual(current?.id, second.id)
        XCTAssertEqual(SoloResumeCursor.derive(rows: [first, second],
                                               swapOverrides: [:], logs: logged),
                       SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1))
    }

    /// The shipped answer for the same routine, for contrast: counting by
    /// LIFT gives the second slot its neighbour's three sets and walks
    /// straight past it.
    func testCountingByLiftIsWhatSkippedTheSecondSlot() {
        let first = slot(benchID, sets: 3, position: 0)
        let second = slot(benchID, sets: 3, position: 1)
        let byLift = RoutineProgression.currentExercise(
            routine: [first, second],
            completedSets: { exerciseID in exerciseID == benchID ? 3 : 0 })
        XCTAssertEqual(byLift?.id, second.id,
                       "both slots read as done; the walk parks on the last")
        // …and it reports the second slot as three sets in, which is the
        // set counter climbing past its target on a lift nobody has touched.
        XCTAssertEqual(RoutineProgression.completedSets(
            forSlot: second, in: logs(benchID, 3, slot: first.id)), 0)
    }

    // MARK: - No swap, and pre-column: unchanged

    func testANoSwapSessionIsExactlyWhatItAlwaysWas() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        let attributed = logs(benchID, 3, slot: rows[0].id)
            + logs(squatID, 2, slot: rows[1].id, from: 100)
        let preColumn = logs(benchID, 3, slot: nil) + logs(squatID, 2, slot: nil, from: 100)
        let expected = SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 3)

        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                               logs: attributed), expected)
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                               logs: preColumn), expected,
                       "an all-NULL session must land where it landed yesterday")
    }

    func testAnAllNullSessionWalksTwoSlotsNamingOneLiftGreedilyAsBefore() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(benchID, sets: 3, position: 1)]
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:],
                                               logs: logs(benchID, 4, slot: nil)),
                       SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 2))
    }

    func testAFreeformRowNamesNoSlotAndIsServedByTheFallbackForever() {
        // A freeform session's rows are synthesized with a fresh id on every
        // rebuild, so stamping one would name a slot that exists only inside
        // one view instance. NULL is the permanent, correct answer.
        let synthesized = slot(benchID, sets: nil, position: 0)
        XCTAssertEqual(
            RoutineProgression.completedSets(forSlot: synthesized,
                                             in: logs(benchID, 2, slot: nil)),
            2)
    }

    // MARK: - A swap with nothing logged yet

    func testASwapWithNoSetsYetShowsTheSubstituteAndCountsZero() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        let layered = RoutineLayering.apply(rows, selfScale: [rows[0].id: inclineID])
        XCTAssertEqual(layered[0].exerciseID, inclineID)
        XCTAssertEqual(layered[0].id, rows[0].id, "the slot's identity is the row")
        XCTAssertEqual(RoutineProgression.completedSets(forSlot: layered[0], in: []), 0)
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: []),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    // MARK: - Penalties, and the queue

    func testPenaltyRowsAreStillNotProgress() {
        let bench = slot(benchID, sets: 3, position: 0)
        let logged = logs(benchID, 1, slot: bench.id)
            + logs(benchID, 5, slot: bench.id, isPenalty: true, from: 100)
        XCTAssertEqual(SoloResumeCursor.derive(rows: [bench], swapOverrides: [:], logs: logged),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 2))
    }

    /// The offline queue mirrors `SetLog`'s fields BY HAND rather than
    /// encoding one, so the slot had to be added to `PendingSetLog`
    /// explicitly. Without this round trip a set logged offline would replay
    /// with a NULL slot and rewind that slot to its fallback count.
    func testTheOfflineQueueCarriesTheSlotThroughAReplayRoundTrip() {
        let slotID = UUID()
        let original = logs(benchID, 1, slot: slotID)[0]
        let replayed = PendingSetLog(setLog: original).asSetLog
        XCTAssertEqual(replayed.routineExerciseID, slotID)
        XCTAssertEqual(replayed.id, original.id)
        XCTAssertEqual(replayed.exerciseID, original.exerciseID)
    }

    /// The column is NULLABLE and the codec must say so both ways — a
    /// pre-column row decodes to nil, and a nil never encodes a key.
    func testTheColumnRoundTripsAndOmitsItselfWhenThereIsNoSlot() throws {
        let slotID = UUID()
        let withSlot = try JSONEncoder().encode(logs(benchID, 1, slot: slotID)[0])
        let asObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: withSlot) as? [String: Any])
        XCTAssertEqual(asObject["routine_exercise_id"] as? String, slotID.uuidString)
        XCTAssertEqual(
            try JSONDecoder().decode(SetLog.self, from: withSlot).routineExerciseID, slotID)

        let withoutSlot = try JSONEncoder().encode(logs(benchID, 1, slot: nil)[0])
        let bare = try XCTUnwrap(
            JSONSerialization.jsonObject(with: withoutSlot) as? [String: Any])
        XCTAssertNil(bare["routine_exercise_id"])
    }
}
