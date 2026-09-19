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

    /// `SlotProgress` over a one-slot routine — the shorthand most cases
    /// here want.
    private func count(_ re: RoutineExercise, _ logged: [SetLog],
                       routine: [RoutineExercise]? = nil) -> Int {
        SlotProgress(routine: routine ?? [re], logs: logged).count(for: re)
    }

    // MARK: - The rule, stated once and asserted once

    func testASlotCountsTheRowsThatNameIt() {
        let bench = slot(benchID, sets: 3, position: 0)
        XCTAssertEqual(
            count(bench, logs(benchID, 2, slot: bench.id)
                         + logs(squatID, 5, slot: UUID(), from: 100)),
            2)
    }

    func testARowNamingADIFFERENTSlotIsNeverClaimedBackByLift() {
        let bench = slot(benchID, sets: 3, position: 0)
        let otherSlot = UUID()
        XCTAssertEqual(
            count(bench, logs(benchID, 2, slot: nil)                     // pre-column: mine
                         + logs(benchID, 4, slot: otherSlot, from: 100)), // another slot's
            2)
    }

    /// REVIEW F2. Decision 3 said "plus — ONLY when the slot has zero such
    /// rows", and that LOSES SETS: a session straddling the app update
    /// counted the one attributed row and dropped the two logged minutes
    /// earlier, rewinding the lifter into work already in the log — a
    /// one-session instance of the failure this phase exists to end.
    func testTheStraddlingSessionCountsBothItsHalves() {
        let bench = slot(benchID, sets: 3, position: 0)
        let straddling = logs(benchID, 2, slot: nil)
            + logs(benchID, 1, slot: bench.id, from: 100)
        XCTAssertEqual(count(bench, straddling), 3)
        // …and the cursor therefore does not send them back to set 2.
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: [bench, slot(squatID, sets: 3, position: 1)],
                                    swapOverrides: [:], logs: straddling),
            SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1))
    }

    /// The same rule from the other side: a wrist tap from a Watch build
    /// predating the column writes a NULL slot, and it must still count at
    /// the slot the phone was on rather than vanish because the phone had
    /// already attributed a set there.
    func testAWatchLoggedNullRowStillCountsAtTheSlotThePhoneWasOn() {
        let bench = slot(benchID, sets: 4, position: 0)
        XCTAssertEqual(
            count(bench, logs(benchID, 2, slot: bench.id)
                         + logs(benchID, 1, slot: nil, from: 100)),
            3)
    }

    /// Nothing is dropped, ever. A pile bigger than every target's room —
    /// bonus sets logged before the column existed — lands on the LAST slot
    /// naming that lift, which is where the shipped walk left the lifter.
    func testSurplusPreColumnRowsLandOnTheLastSlotRatherThanVanishing() {
        let first = slot(benchID, sets: 3, position: 0)
        let second = slot(benchID, sets: 3, position: 1)
        let routine = [first, second]
        let logged = logs(benchID, 10, slot: nil)
        XCTAssertEqual(count(first, logged, routine: routine), 3)
        XCTAssertEqual(count(second, logged, routine: routine), 7)
        XCTAssertEqual(count(first, logged, routine: routine)
                       + count(second, logged, routine: routine), 10,
                       "every logged set belongs to exactly one slot")
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
        XCTAssertEqual(count(bench, logged), 4)

        let rows = [bench, slot(squatID, sets: 3, position: 1)]
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: logged),
                       SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1))
    }

    // MARK: - A routine naming one lift twice

    func testTwoSlotsOneLiftThreeSetsOnTheFirstAndTheSecondStillShowsZero() {
        let first = slot(benchID, sets: 3, position: 0)
        let second = slot(benchID, sets: 3, position: 1)
        let logged = logs(benchID, 3, slot: first.id)

        let progress = SlotProgress(routine: [first, second], logs: logged)
        XCTAssertEqual(progress.count(for: first), 3)
        XCTAssertEqual(progress.count(for: second), 0)

        // The walk therefore opens the second slot at set 1 — and the
        // progression returns the SECOND row, not the first.
        let current = RoutineProgression.currentSlot(
            routine: [first, second],
            completedSets: { re in progress.count(for: re) })
        XCTAssertEqual(current?.id, second.id)
        XCTAssertEqual(SoloResumeCursor.derive(rows: [first, second],
                                               swapOverrides: [:], logs: logged),
                       SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1))
    }

    /// REVIEW F5. `prefillLogInputs`' body is byte-identical, but its SEAM
    /// moved: `defaultReps(for:)` now answers from the slot the progression
    /// landed on rather than the first layered row naming that lift. The
    /// difference is visible only on a routine naming one lift twice with
    /// DIFFERENT rep targets — where the old answer was the first slot's, on
    /// every set of both. Pinned at the level a pure test can reach: the slot
    /// the walk selects, and the prescription that rides on it.
    func testTheSlotTheWalkSelectsCarriesItsOWNRepTarget() {
        var first = slot(benchID, sets: 3, position: 0)
        first.targetReps = "5"
        var second = slot(benchID, sets: 3, position: 1)
        second.targetReps = "12"
        let logged = logs(benchID, 3, slot: first.id)
        let progress = SlotProgress(routine: [first, second], logs: logged)
        let current = RoutineProgression.currentSlot(
            routine: [first, second],
            completedSets: { re in progress.count(for: re) })
        XCTAssertEqual(current?.id, second.id)
        XCTAssertEqual(current?.targetReps, "12",
                       "the by-lift lookup would have answered the FIRST slot's 5")
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
        XCTAssertEqual(count(synthesized, logs(benchID, 2, slot: nil)), 2)
    }

    // MARK: - A swap with nothing logged yet

    func testASwapWithNoSetsYetShowsTheSubstituteAndCountsZero() {
        let rows = [slot(benchID, sets: 3, position: 0),
                    slot(squatID, sets: 3, position: 1)]
        let layered = RoutineLayering.apply(rows, selfScale: [rows[0].id: inclineID])
        XCTAssertEqual(layered[0].exerciseID, inclineID)
        XCTAssertEqual(layered[0].id, rows[0].id, "the slot's identity is the row")
        XCTAssertEqual(count(layered[0], []), 0)
        XCTAssertEqual(SoloResumeCursor.derive(rows: rows, swapOverrides: [:], logs: []),
                       SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 1))
    }

    // MARK: - The walk's own order (final review N4)
    //
    // `derive` used to enumerate the array exactly as handed in, while
    // `SlotProgress.init` and `RoutineProgression.currentSlot` both sort by
    // `position`. Every caller passes position-ordered rows today, so nothing
    // was wrong on screen — but the answer is positional and the order was the
    // caller's to get right. Both cases below fail on the enumerated spelling.

    func testTheWalkIsInPositionOrderEvenWhenTheRowsArriveOutOfIt() {
        let second = slot(squatID, sets: 3, position: 1)
        let first = slot(benchID, sets: 3, position: 0)
        // Handed in BACKWARDS, nothing logged: the lifter belongs on the
        // routine's first movement, whose index in this array is 1.
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: [second, first], swapOverrides: [:], logs: []),
            SoloResumeCursor.Position(exerciseIndex: 1, setIndex: 1),
            "the enumerated walk answered the array's first row, which is position 2")
    }

    /// A finished routine lands on the LAST slot BY POSITION — the one the
    /// lifter finishes bonus sets from — not on whichever row the array
    /// happened to end with.
    func testAFinishedRoutineLandsOnTheLastSlotByPositionNotByArrayOrder() {
        let second = slot(squatID, sets: 1, position: 1)
        let first = slot(benchID, sets: 1, position: 0)
        let logged = logs(benchID, 1, slot: first.id)
            + logs(squatID, 1, slot: second.id, from: 100)
        XCTAssertEqual(
            SoloResumeCursor.derive(rows: [second, first], swapOverrides: [:], logs: logged),
            SoloResumeCursor.Position(exerciseIndex: 0, setIndex: 2),
            "index 0 IS position 2 in this array — the answer is the caller's index of the last slot")
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

    /// RULING R-C-6. The queue had never mirrored `bodyWeightLbs` either, so
    /// a set of pull-ups logged offline replayed with no body weight and
    /// contributed NO tonnage, while the identical set logged online
    /// contributed all of it.
    func testTheOfflineQueueCarriesTheBodyWeightASetWasLiftedAt() {
        var original = logs(benchID, 1, slot: UUID())[0]
        original.weight = 0
        original.bodyWeightLbs = 183
        let replayed = PendingSetLog(setLog: original).asSetLog
        XCTAssertEqual(replayed.bodyWeightLbs, 183)
        XCTAssertEqual(replayed.effectiveWeightPounds, 183,
                       "a bodyweight set's tonnage IS the body weight")
    }

    /// A set log naming NEITHER new field mirrors into the queue as two nils
    /// and reconstitutes as two nils — the in-memory leg of the claim, and
    /// the only leg this pure file can reach.
    ///
    /// RULING F9: THIS TEST DOES NOT PROVE THE MIGRATION. Its earlier name,
    /// `testAnItemQueuedBeforeEitherColumnStillReplays`, claimed that an item
    /// queued by the PREVIOUS build still replays; what it actually does is
    /// construct a fresh `PendingSetLog` and assert the defaults it was just
    /// given. The store round trip lives where the `ModelContainer` does —
    /// `OfflineSetLogQueueTests.testAnItemNamingNeitherNewColumnSurvivesThe`
    /// `StoreAndReplaysWithNils` — and even that one states in its own
    /// comment that a store file written by the older schema is out of reach
    /// without a versioned schema. The migration claim rests on SwiftData's
    /// documented lightweight case, not on an assertion, and no comment here
    /// says otherwise any more.
    func testAMirroredSetLogWithNeitherFieldCarriesTwoNils() {
        var bare = logs(benchID, 1, slot: nil)[0]
        bare.bodyWeightLbs = nil
        let pending = PendingSetLog(setLog: bare)
        XCTAssertNil(pending.routineExerciseID)
        XCTAssertNil(pending.bodyWeightLbs)
        XCTAssertEqual(pending.asSetLog.id, bare.id)
        XCTAssertNil(pending.asSetLog.routineExerciseID)
        XCTAssertNil(pending.asSetLog.bodyWeightLbs)
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
