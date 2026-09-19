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
