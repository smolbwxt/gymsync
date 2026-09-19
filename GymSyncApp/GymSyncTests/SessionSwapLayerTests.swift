import XCTest
@testable import GymSync

/// THE DURABLE SWAP LAYER'S CODEC AND ITS KEYING (plan task S1, decision 2).
///
/// Two of these assert behaviour the shipped app gets WRONG — the slot cases.
/// Before Phase C1 both layers were keyed by exercise id, so a routine naming
/// one lift twice had slot 7 swapped by a decision about slot 3, and slot 7's
/// sets counted toward slot 3. Keyed by exercise id,
/// `testOnlyTheSwappedSlotChangesWhenARoutineNamesOneLiftTwice` fails.
final class SessionSwapLayerTests: XCTestCase {

    private let benchID = UUID()
    private let squatID = UUID()
    private let inclineID = UUID()
    private let machinePressID = UUID()

    private func row(_ exerciseID: UUID, sets: Int? = 3, position: Int = 0) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: exerciseID,
                        position: position, targetSets: sets, targetReps: "5",
                        targetWeight: "225", restSeconds: nil, notes: nil)
    }

    private func decode(_ json: String) throws -> SessionSwapLayer {
        try JSONDecoder().decode(SessionSwapLayer.self, from: Data(json.utf8))
    }

    // MARK: - Codec

    func testTheLayerRoundTripsThroughItsColumnShape() throws {
        let slotA = UUID(), slotB = UUID()
        let original = SessionSwapLayer([slotA: inclineID, slotB: machinePressID])
        let data = try JSONEncoder().encode(original)
        // The wire is the column's own shape: a flat object of uuid → uuid.
        let asObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(asObject[slotA.uuidString], inclineID.uuidString)
        XCTAssertEqual(asObject[slotB.uuidString], machinePressID.uuidString)

        let decoded = try JSONDecoder().decode(SessionSwapLayer.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAnEmptyObjectAndAnAbsentColumnAreTheSameLayer() throws {
        // The column is nullable and the migration's own comment says NULL
        // and `{}` must read identically. A nil column never reaches the
        // decoder at all — it is the call site's `?? SessionSwapLayer()` —
        // so the two spellings have to agree here.
        XCTAssertEqual(try decode("{}"), SessionSwapLayer())
        XCTAssertTrue(try decode("{}").isEmpty)
        XCTAssertTrue(SessionSwapLayer().isEmpty)
    }

    func testAMalformedEntryIsDroppedRatherThanFailingTheWholeRow() throws {
        // This column rides on `session_participants`, which is also the
        // roster. One unparsable pair must cost that pair and nothing else.
        let slot = UUID()
        let layer = try decode("""
        {"not-a-uuid":"\(inclineID.uuidString)",\
        "\(slot.uuidString)":"also-not-a-uuid",\
        "\(slot.uuidString)x":"\(inclineID.uuidString)"}
        """)
        XCTAssertTrue(layer.isEmpty)

        let good = UUID()
        let mixed = try decode("""
        {"not-a-uuid":"\(inclineID.uuidString)","\(good.uuidString)":"\(squatID.uuidString)"}
        """)
        XCTAssertEqual(mixed[good], squatID)
    }

    func testSeedingKeepsTheLocalEntryOverTheRows() {
        // A swap applied a moment ago and still in flight must not be erased
        // by the reload that lands while its write is travelling.
        let slot = UUID()
        let mine = SessionSwapLayer([slot: machinePressID])
        let fromRow = SessionSwapLayer([slot: inclineID])
        XCTAssertEqual(mine.merging(fromRow)[slot], machinePressID)
    }

    func testSeedingAddsEverySlotTheRowKnowsAndThisClientDoesNot() {
        let mineSlot = UUID(), theirsSlot = UUID()
        let merged = SessionSwapLayer([mineSlot: machinePressID])
            .merging(SessionSwapLayer([theirsSlot: inclineID]))
        XCTAssertEqual(merged[mineSlot], machinePressID)
        XCTAssertEqual(merged[theirsSlot], inclineID)
    }

    // MARK: - The keying, applied

    func testASlotIdThisRoutineDoesNotCarryIsInert() {
        // No foreign key, deliberately: a routine edited after a swap can
        // orphan a key. An orphan changes nothing and raises nothing.
        let rows = [row(benchID), row(squatID, position: 1)]
        let applied = RoutineLayering.apply(rows, squadSwaps: [UUID(): inclineID])
        XCTAssertEqual(applied.map(\.exerciseID), [benchID, squatID])
        XCTAssertEqual(applied, rows)
    }

    /// THE CASE THE OLD KEYING GOT WRONG, and the reason both columns are
    /// keyed by the routine-exercises row id.
    func testOnlyTheSwappedSlotChangesWhenARoutineNamesOneLiftTwice() {
        let first = row(benchID, position: 0)
        let second = row(benchID, position: 1)
        XCTAssertNotEqual(first.id, second.id, "two slots, one lift")

        let applied = RoutineLayering.apply([first, second],
                                            squadSwaps: [first.id: inclineID])
        XCTAssertEqual(applied.map(\.exerciseID), [inclineID, benchID],
                       "keyed by exercise id, the crew's vote about slot 1 "
                       + "silently replaced slot 2 as well")
        // And the untouched slot keeps its bar number, which a swap drops.
        XCTAssertNil(applied[0].targetWeight)
        XCTAssertEqual(applied[1].targetWeight, "225")
    }

    func testMyQuietSwapOfTheSecondSlotLeavesTheFirstAlone() {
        let first = row(benchID, position: 0)
        let second = row(benchID, position: 1)
        let applied = RoutineLayering.apply([first, second],
                                            selfScale: [second.id: machinePressID])
        XCTAssertEqual(applied.map(\.exerciseID), [benchID, machinePressID])
    }

    /// The three-layer order, re-asserted against SLOT ids — the same rule
    /// `RoutineLayeringTests` states, restated here because the keys changed
    /// meaning and an order that survived the re-key is the thing worth
    /// proving.
    func testTheThreeLayerOrderHoldsWithSlotKeys() {
        let benchSlot = row(benchID, sets: 4, position: 0)
        let squatSlot = row(squatID, sets: 5, position: 1)
        let applied = RoutineLayering.apply(
            [benchSlot, squatSlot],
            squadSwaps: [benchSlot.id: inclineID],
            selfScale: [benchSlot.id: machinePressID],
            todaysScale: TodaysScale(exerciseID: benchID, setsInstead: 3))
        // 1 squad, 2 mine beats it, 3 the dose rides the slot.
        XCTAssertEqual(applied.map(\.exerciseID), [machinePressID, squatID])
        XCTAssertEqual(applied.map(\.targetSets), [3, 5])
    }

    // MARK: - The outbox (ruling F1)
    //
    // S1 deleted the hotfix's in-memory mirror because the row replaced it —
    // on every path the write SUCCEEDS on. On the one it does not, the swap
    // was left in `@State` alone, a swipe-down destroyed it, and the lifter
    // came back on the lift they had swapped away. These pin the lifecycle
    // that closes it. `flushIfDirty` is not asserted here: it is the one
    // member that touches the network.

    @MainActor
    func testARecordedLayerIsDirtyUntilTheRowConfirmsIt() {
        let store = SessionSwapPendingStore()
        let session = UUID(), slot = UUID()
        XCTAssertFalse(store.isDirty(session))
        XCTAssertTrue(store.layer(for: session).isEmpty)

        store.record(SessionSwapLayer([slot: inclineID]), for: session)
        XCTAssertTrue(store.isDirty(session))
        XCTAssertEqual(store.layer(for: session)[slot], inclineID)

        store.confirm(session, matching: SessionSwapLayer([slot: inclineID]))
        XCTAssertFalse(store.isDirty(session))
        XCTAssertEqual(store.layer(for: session)[slot], inclineID,
                       "a confirmed layer is kept — it is what a FAILED read falls back to")
    }

    /// RULING F1a. `confirm` used to clear by SESSION, so the FIRST write to
    /// return marked whatever the store held at that moment clean — including
    /// a second, larger layer recorded while write 1 was still travelling. A
    /// failing write 2 then never retried (`flushIfDirty` short-circuits on
    /// `isDirty`) although its notice had just promised it would, and the
    /// second swap survived a swipe-down but not a relaunch.
    @MainActor
    func testTheFIRSTWriteToLandDoesNotMarkASECONDSwapClean() {
        let store = SessionSwapPendingStore()
        let session = UUID(), first = UUID(), second = UUID()

        let layerA = SessionSwapLayer([first: inclineID])
        store.record(layerA, for: session)           // write A starts

        let layerB = SessionSwapLayer([first: inclineID, second: machinePressID])
        store.record(layerB, for: session)           // write B starts, inside A's latency

        store.confirm(session, matching: layerA)     // A lands FIRST
        XCTAssertTrue(store.isDirty(session),
                      "the row holds A; B has not landed and must still be retried")
        XCTAssertEqual(store.layer(for: session), layerB,
                       "and the layer the lifter sees is still B")

        store.confirm(session, matching: layerB)     // B lands
        XCTAssertFalse(store.isDirty(session))
        XCTAssertEqual(store.layer(for: session), layerB)
    }

    /// A confirm for a session the store has forgotten (a `clear` that raced
    /// a write home) is a no-op, never a resurrection.
    @MainActor
    func testConfirmingAClearedSessionPutsNothingBack() {
        let store = SessionSwapPendingStore()
        let session = UUID(), slot = UUID()
        let layer = SessionSwapLayer([slot: inclineID])
        store.record(layer, for: session)
        store.clear(session)
        store.confirm(session, matching: layer)
        XCTAssertTrue(store.layer(for: session).isEmpty)
        XCTAssertFalse(store.isDirty(session))
    }

    @MainActor
    func testADirtyLayerBEATSTheRowItHasNotReachedYet() {
        let store = SessionSwapPendingStore()
        let session = UUID(), slot = UUID()
        store.record(SessionSwapLayer([slot: machinePressID]), for: session)
        // The row still holds the swap from before the refused write.
        let seeded = store.seeded(from: SessionSwapLayer([slot: inclineID]), for: session)
        XCTAssertEqual(seeded[slot], machinePressID)
    }

    @MainActor
    func testSeedingKeepsEverySlotEitherSideKnowsAbout() {
        let store = SessionSwapPendingStore()
        let session = UUID(), mine = UUID(), theirs = UUID()
        store.record(SessionSwapLayer([mine: machinePressID]), for: session)
        let seeded = store.seeded(from: SessionSwapLayer([theirs: inclineID]), for: session)
        XCTAssertEqual(seeded[mine], machinePressID)
        XCTAssertEqual(seeded[theirs], inclineID)
    }

    @MainActor
    func testAnEmptyStoreSeedsToExactlyTheRow() {
        let store = SessionSwapPendingStore()
        let session = UUID(), slot = UUID()
        let row = SessionSwapLayer([slot: inclineID])
        XCTAssertEqual(store.seeded(from: row, for: session), row)
    }

    @MainActor
    func testOneSessionsOutboxIsNotAnothers() {
        let store = SessionSwapPendingStore()
        let a = UUID(), b = UUID(), slot = UUID()
        store.record(SessionSwapLayer([slot: inclineID]), for: a)
        XCTAssertTrue(store.layer(for: b).isEmpty)
        XCTAssertFalse(store.isDirty(b))
    }

    @MainActor
    func testFinishingASessionClearsItsOutbox() {
        let store = SessionSwapPendingStore()
        let session = UUID(), slot = UUID()
        store.record(SessionSwapLayer([slot: inclineID]), for: session)
        store.clear(session)
        XCTAssertTrue(store.layer(for: session).isEmpty)
        XCTAssertFalse(store.isDirty(session))
        // And a cleared session seeds to the row alone, never to a ghost.
        let row = SessionSwapLayer([slot: machinePressID])
        XCTAssertEqual(store.seeded(from: row, for: session), row)
    }

    @MainActor
    func testASecondSwapWhileStillDirtyRecordsTheWholeLayerNotJustTheNewSlot() {
        // Both bodies hand `record` the whole layer, because `self_swaps` is
        // a plain jsonb column with no server-side merge — a partial write
        // would erase the slot it did not name.
        let store = SessionSwapPendingStore()
        let session = UUID(), first = UUID(), second = UUID()
        store.record(SessionSwapLayer([first: inclineID]), for: session)
        store.record(SessionSwapLayer([first: inclineID, second: machinePressID]), for: session)
        XCTAssertTrue(store.isDirty(session))
        XCTAssertEqual(store.layer(for: session).bySlot.count, 2)
    }

    func testTodaysScaleStaysKeyedOnTheLiftNotTheSlot() {
        // Decision 2's last paragraph: the athlete accepted "one set fewer"
        // against a LIFT at the warm-up, and both slots naming that lift are
        // the same dose decision. Only the swaps are per-slot.
        let first = row(benchID, sets: 4, position: 0)
        let second = row(benchID, sets: 4, position: 1)
        let applied = RoutineLayering.apply(
            [first, second],
            todaysScale: TodaysScale(exerciseID: benchID, setsInstead: 3))
        XCTAssertEqual(applied.map(\.targetSets), [3, 3])
    }
}
