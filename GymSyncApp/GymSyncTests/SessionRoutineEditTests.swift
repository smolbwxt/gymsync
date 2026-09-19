import XCTest
@testable import GymSync

/// THE MID-SESSION ROUTINE EDIT MEETS SLOT-KEYED STATE (Phase C2, plan task
/// S1, decision 2) — the phase's highest-risk seam, asserted rather than
/// reasoned about.
///
/// The rule the whole file obeys: **a surviving slot keeps its id; an edit is
/// in place; a removal is a removal, never a re-key** (ruling R-C-5,
/// generalised). `set_logs.routine_exercise_id` has no foreign key, so a
/// re-keyed slot raises nothing at all — the sets simply stop counting, which
/// is the exact class of silent failure this phase exists to end.
final class SessionRoutineEditTests: XCTestCase {

    private let benchID = UUID()
    private let squatID = UUID()
    private let rowID = UUID()
    private let curlID = UUID()
    private let sessionID = UUID()
    private let userID = UUID()
    private let routineID = UUID()

    private func slot(_ exerciseID: UUID, sets: Int?, position: Int,
                      id: UUID = UUID()) -> RoutineExercise {
        RoutineExercise(id: id, routineID: routineID, exerciseID: exerciseID,
                        position: position, targetSets: sets, targetReps: "8",
                        targetWeight: "135", restSeconds: 90, notes: nil)
    }

    /// `count` sets under `exerciseID`, attributed to `slotID` (nil = a
    /// freeform or pre-column row).
    private func logs(_ exerciseID: UUID, _ count: Int, slot slotID: UUID?,
                      from: TimeInterval = 0) -> [SetLog] {
        (0..<count).map { i in
            SetLog(id: UUID(), userID: userID, sessionID: sessionID,
                   exerciseID: exerciseID, setIndex: i + 1,
                   reps: 8, weight: 135, rpe: 7,
                   isFailed: false, isPenalty: false, note: nil,
                   loggedAt: Date(timeIntervalSince1970: from + Double(i)),
                   routineExerciseID: slotID)
        }
    }

    /// The body's own derivation, as a function: `effectiveRoutineExercises`
    /// → `SlotProgress` → `RoutineProgression.currentSlot`. The view reads
    /// exactly this chain; asserting it here asserts the cursor.
    private func cursor(_ rows: [RoutineExercise],
                        _ logged: [SetLog]) -> RoutineExercise? {
        let effective = RoutineLayering.apply(rows)
        let progress = SlotProgress(routine: effective, logs: logged)
        return RoutineProgression.currentSlot(routine: effective,
                                              completedSets: { progress.count(for: $0) })
    }

    // MARK: - Decision 2's action table, row by row

    /// REORDER — ids are stable, only `position` moves. The counts do not
    /// change; only the order does, and the cursor recomputes in the new
    /// order, which can legitimately move the lifter to a different "current"
    /// slot mid-session.
    func testReorderMovesTheCursorAndChangesNoCount() {
        let bench = slot(benchID, sets: 3, position: 1)
        let squat = slot(squatID, sets: 3, position: 2)
        let logged = logs(benchID, 3, slot: bench.id)          // bench is done

        XCTAssertEqual(cursor([bench, squat], logged)?.id, squat.id)

        // The editor hands back the same rows, renumbered — squat first.
        let reordered = SessionRoutineEdit.rowsForUpdate([squat, bench])
        XCTAssertEqual(reordered.map(\.id), [squat.id, bench.id])
        XCTAssertEqual(reordered.map(\.position), [1, 2])

        let progress = SlotProgress(routine: reordered, logs: logged)
        // The counts are untouched by the move…
        XCTAssertEqual(progress.count(for: reordered[1]), 3)   // bench
        XCTAssertEqual(progress.count(for: reordered[0]), 0)   // squat
        // …and the walk now lands on squat because it comes first and is short.
        XCTAssertEqual(cursor(reordered, logged)?.id, squat.id)
    }

    /// ADD — the new slot carries a CLIENT-MINTED id, stable for the rest of
    /// the session, and sets stamp it. The id is not yet in
    /// `routine_exercises` and does not need to be: there is no FK on
    /// `set_logs.routine_exercise_id`.
    func testAnAddedSlotOwnsTheSetsLoggedAgainstItsClientMintedID() {
        let bench = slot(benchID, sets: 3, position: 1)
        let added = slot(curlID, sets: 2, position: 2)          // minted mid-session
        let logged = logs(benchID, 3, slot: bench.id)
            + logs(curlID, 1, slot: added.id, from: 100)

        let progress = SlotProgress(routine: [bench, added], logs: logged)
        XCTAssertEqual(progress.count(for: added), 1)
        XCTAssertEqual(cursor([bench, added], logged)?.id, added.id)
    }

    /// REMOVE — the removed slot's rows STAY in `set_logs` with a now-dangling
    /// slot id. They leave `SlotProgress` because the slot is gone from the
    /// list, and the cursor recomputes over the shorter list. This is the one
    /// place the recap total and the on-screen "sets done" can diverge, and
    /// both are correct.
    func testARemovedSlotsRowsLeaveSlotProgressAndStayInTheSessionsSets() {
        let bench = slot(benchID, sets: 3, position: 1)
        let squat = slot(squatID, sets: 3, position: 2)
        let logged = logs(benchID, 2, slot: bench.id)
            + logs(squatID, 1, slot: squat.id, from: 100)

        // The lifter removes the bench slot mid-session.
        let after = SessionRoutineEdit.rowsForUpdate([squat])
        let progress = SlotProgress(routine: after, logs: logged)

        // Its two rows are no longer attributable to any slot on screen…
        XCTAssertEqual(progress.count(for: after[0]), 1)        // squat only
        XCTAssertEqual(after.count, 1)
        // …and they are still in the session's own set list, which is what
        // the recap, volume, PR basis and block goals all read.
        XCTAssertEqual(logged.filter { $0.routineExerciseID == bench.id }.count, 2)
        XCTAssertEqual(logged.count, 3)
        XCTAssertEqual(cursor(after, logged)?.id, squat.id)
    }

    /// A DANGLING SLOT ID IS NEVER CLAIMED BACK BY LIFT. The removed slot's
    /// rows name a slot that no longer exists; a surviving slot for the SAME
    /// lift must not inherit them, or a removal would silently credit work to
    /// the wrong row.
    func testARemovedSlotsRowsAreNotInheritedByAnotherSlotOfTheSameLift() {
        let first = slot(benchID, sets: 3, position: 1)
        let second = slot(benchID, sets: 3, position: 2)         // same lift, second slot
        let logged = logs(benchID, 2, slot: first.id)

        let after = SessionRoutineEdit.rowsForUpdate([second])
        XCTAssertEqual(SlotProgress(routine: after, logs: logged).count(for: after[0]), 0)
    }

    // MARK: - The two persist branches (decision 2's "per persist branch")

    /// "Update this routine" — surviving slots keep their ids, so an ADDED
    /// slot's set rows become valid retroactively, and positions renumber
    /// from 1.
    func testUpdateThisRoutinePreservesEveryIDAndRenumbers() {
        let bench = slot(benchID, sets: 3, position: 7)
        let added = slot(curlID, sets: 2, position: 99)
        let rows = SessionRoutineEdit.rowsForUpdate([added, bench])

        XCTAssertEqual(rows.map(\.id), [added.id, bench.id])
        XCTAssertEqual(rows.map(\.position), [1, 2])
        XCTAssertEqual(rows.map(\.routineID), [routineID, routineID])
    }

    /// "Save as a new routine" — a CLONE. Fresh row ids, the new routine's
    /// id on every row, and the ORIGINAL routine's rows untouched (nothing
    /// the live session logged is re-keyed, because the session's
    /// `routine_id` still points at the original).
    func testSaveAsANewRoutineMintsFreshIDsAndTouchesOnlyTheClone() {
        let bench = slot(benchID, sets: 3, position: 1)
        let added = slot(curlID, sets: 2, position: 2)
        let newRoutineID = UUID()
        let rows = SessionRoutineEdit.rowsForNewRoutine([bench, added],
                                                        routineID: newRoutineID)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.routineID), [newRoutineID, newRoutineID])
        XCTAssertEqual(rows.map(\.position), [1, 2])
        XCTAssertFalse(rows.contains { $0.id == bench.id || $0.id == added.id })
        // The lift, the prescription and every trailing field ride along —
        // `RoutineLayering.copied` is the one copy helper (ruling R-C-6).
        XCTAssertEqual(rows.map(\.exerciseID), [benchID, curlID])
        XCTAssertEqual(rows.map(\.targetSets), [3, 2])
    }

    /// And the clone carries the fields a hand-written copy dropped (R-B2-13):
    /// a drop ladder and an AMRAP prescription survive "save as new".
    func testTheCloneCarriesTheSetStructureFields() {
        var bench = slot(benchID, sets: 3, position: 1)
        bench.setType = "drop"
        bench.dropSteps = 2
        bench.dropPercent = Decimal(string: "0.15")
        bench.targetFailure = true
        bench.supersetGroup = 4
        let rows = SessionRoutineEdit.rowsForNewRoutine([bench], routineID: UUID())

        XCTAssertEqual(rows[0].setType, "drop")
        XCTAssertEqual(rows[0].dropSteps, 2)
        XCTAssertEqual(rows[0].dropPercent, Decimal(string: "0.15"))
        XCTAssertTrue(rows[0].targetFailure)
        XCTAssertEqual(rows[0].supersetGroup, 4)
    }

    // MARK: - The freeform ("empty") workout, walked

    /// THE DEGENERATE CASE (decision 2). A freeform session starts with no
    /// routine rows at all; every exercise arrives through the editor's own
    /// picker and nothing is ever persisted. Add three, log two against the
    /// second, remove the first — and the cursor and the counts must both be
    /// right.
    func testTheFreeformWalk() {
        let stored: [RoutineExercise] = []                       // `isFreeform`
        XCTAssertNil(cursor(stored, []))

        let a = slot(benchID, sets: 3, position: 1)
        let b = slot(squatID, sets: 3, position: 2)
        let c = slot(rowID, sets: 3, position: 3)
        let three = SessionRoutineEdit.rowsForUpdate([a, b, c])
        XCTAssertEqual(cursor(three, [])?.id, a.id)              // 0 done, first slot

        // Two sets logged against the SECOND slot, stamped with its
        // client-minted id (a freeform row's slot id never reaches
        // `routine_exercises` and does not need to).
        let logged = logs(squatID, 2, slot: b.id)
        XCTAssertEqual(SlotProgress(routine: three, logs: logged).count(for: b), 2)
        XCTAssertEqual(cursor(three, logged)?.id, a.id)          // a is still short

        // Remove the first.
        let two = SessionRoutineEdit.rowsForUpdate([b, c])
        XCTAssertEqual(two.map(\.id), [b.id, c.id])
        XCTAssertEqual(two.map(\.position), [1, 2])
        let after = SlotProgress(routine: two, logs: logged)
        XCTAssertEqual(after.count(for: two[0]), 2)              // b keeps its two
        XCTAssertEqual(after.count(for: two[1]), 0)
        XCTAssertEqual(cursor(two, logged)?.id, b.id)            // 2 of 3 — still b
    }

    /// A TRULY UNSLOTTED FREEFORM ROW still places. Sets logged while the
    /// routine was empty carry `routine_exercise_id = NULL`
    /// (`currentRoutineExercise` is nil for an empty routine), and
    /// `SlotProgress`'s permanent fallback places them on the slot naming
    /// that lift once the editor adds one.
    func testNullSlotFreeformRowsPlaceOnTheSlotAddedAfterwards() {
        let added = slot(benchID, sets: 3, position: 1)
        let logged = logs(benchID, 2, slot: nil)
        XCTAssertEqual(SlotProgress(routine: [added], logs: logged).count(for: added), 2)
        XCTAssertEqual(cursor([added], logged)?.id, added.id)
    }

    // MARK: - The store's lifecycle (the MINIMISE path)

    /// MINIMISE DESTROYS THE VIEW, and the overlay must survive it. The store
    /// is app-level and keyed by session: record on Done, read back on the
    /// reload that follows re-entry, cleared only on a deliberate exit.
    @MainActor
    func testTheOverlaySurvivesTheViewAndIsClearedOnlyOnExit() {
        let store = SessionRoutineEditStore()
        let session = UUID()
        XCTAssertNil(store.edited(for: session))                  // never edited

        let rows = SessionRoutineEdit.rowsForUpdate([slot(benchID, sets: 3, position: 1)])
        store.record(rows, for: session)
        // …the view is destroyed and rebuilt; `reload()` seeds from here.
        XCTAssertEqual(store.edited(for: session)?.map(\.id), rows.map(\.id))

        store.clear(session)
        XCTAssertNil(store.edited(for: session))
    }

    /// NIL AND EMPTY ARE DIFFERENT, and the fallback is `??` rather than
    /// `isEmpty` for exactly this reason: a lifter who removed every slot
    /// must not have the stored routine silently resurrected under them.
    @MainActor
    func testAnEmptiedListIsHeldAsEmptyAndNotAsUnedited() {
        let store = SessionRoutineEditStore()
        let session = UUID()
        store.record([], for: session)
        XCTAssertEqual(store.edited(for: session)?.count, 0)
        XCTAssertNotNil(store.edited(for: session))
    }

    /// One session's overlay is not another's — the key is the session id,
    /// the same shape `SessionSwapPendingStore` uses.
    @MainActor
    func testTheStoreIsKeyedBySession() {
        let store = SessionRoutineEditStore()
        let mine = UUID(), other = UUID()
        store.record([slot(benchID, sets: 3, position: 1)], for: mine)
        XCTAssertNil(store.edited(for: other))
        store.clear(other)
        XCTAssertEqual(store.edited(for: mine)?.count, 1)
    }
}
