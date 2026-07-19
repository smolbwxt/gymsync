import XCTest
@testable import GymSync

final class EventKitBridgeTests: XCTestCase {
    // MARK: - eventTitle (pure — no EKEventStore access)

    func testEventTitleWithRoutineName() {
        XCTAssertEqual(EventKitBridge.eventTitle(routineName: "Push Day"), "Gym Sync: Push Day")
    }

    func testEventTitleFallsBackWhenNoRoutine() {
        XCTAssertEqual(EventKitBridge.eventTitle(routineName: nil), "Gym Sync Session")
    }

    func testEventTitleFallsBackForBlankRoutineName() {
        // Defends against an empty/whitespace-only routine name (shouldn't
        // happen given RoutineBuilderView's own validation, but the title
        // helper should never render "Gym Sync: " with nothing after it).
        XCTAssertEqual(EventKitBridge.eventTitle(routineName: ""), "Gym Sync Session")
        XCTAssertEqual(EventKitBridge.eventTitle(routineName: "   "), "Gym Sync Session")
    }

    // MARK: - estimatedDuration (pure — mirrors StatMath.estimatedMinutes)

    func testEstimatedDurationUsesRoutineExerciseCount() {
        // StatMath.estimatedMinutes(exerciseCount: 6) == 90 min (flat 15
        // min/exercise) — well above the 30-min floor.
        XCTAssertEqual(EventKitBridge.estimatedDuration(exerciseCount: 6), 90 * 60)
    }

    func testEstimatedDurationFloorsAtThirtyMinutesForSmallRoutines() {
        // 1 exercise -> StatMath's raw 15 min, floored to 30.
        XCTAssertEqual(EventKitBridge.estimatedDuration(exerciseCount: 1), 30 * 60)
        // 0 exercises (routine with nothing added yet) -> also floored to 30,
        // never a zero-length event.
        XCTAssertEqual(EventKitBridge.estimatedDuration(exerciseCount: 0), 30 * 60)
    }

    func testEstimatedDurationDefaultsToSixtyMinutesWithNoRoutine() {
        // Master spec Flow 10's own default ("estimated end (default 60
        // min...)", :937) — used when no routine is selected at all.
        XCTAssertEqual(EventKitBridge.estimatedDuration(exerciseCount: nil), 60 * 60)
    }

    // MARK: - staleSessionIDs (pure — extracted from reconcile(), Phase O
    // Task 2 fix wave 1, reviewer Finding 3; no EKEventStore/network access)

    func testAbandonedStateIsStale() {
        let id = UUID()
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: [id], liveStates: [id: "abandoned"])
        XCTAssertEqual(staleIDs, [id])
    }

    func testMissingFromLiveStatesIsStale() {
        // Covers BOTH "cancelled" (hard-DELETEd row, no `'cancelled'` value
        // even exists in the DB's CHECK constraint) and "genuinely
        // nonexistent"/"RLS-hidden" — all three collapse into "absent from
        // the batch fetch," which is exactly what this case exercises.
        let id = UUID()
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: [id], liveStates: [:])
        XCTAssertEqual(staleIDs, [id])
    }

    func testScheduledStateIsKept() {
        let id = UUID()
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: [id], liveStates: [id: "scheduled"])
        XCTAssertTrue(staleIDs.isEmpty)
    }

    func testCompletedStateIsKept() {
        // A session that already happened is a legitimate calendar record,
        // not stale state — deliberately NOT removed.
        let id = UUID()
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: [id], liveStates: [id: "completed"])
        XCTAssertTrue(staleIDs.isEmpty)
    }

    func testEveryOtherActiveStateIsKept() {
        let ids = (0..<5).map { _ in UUID() }
        let states = ["lobby_open", "editing", "voting", "locked", "in_progress"]
        let liveStates = Dictionary(uniqueKeysWithValues: zip(ids, states))
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: ids, liveStates: liveStates)
        XCTAssertTrue(staleIDs.isEmpty)
    }

    func testEmptyMappedIDsReturnsEmpty() {
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: [], liveStates: [UUID(): "abandoned"])
        XCTAssertTrue(staleIDs.isEmpty)
    }

    func testEmptyLiveStatesTreatsEveryMappedIDAsStale() {
        let ids = (0..<3).map { _ in UUID() }
        let staleIDs = EventKitBridge.staleSessionIDs(mappedIDs: ids, liveStates: [:])
        XCTAssertEqual(Set(staleIDs), Set(ids))
    }

    func testMixedIDsReturnOnlyTheStaleOnes() {
        let scheduled = UUID()
        let abandoned = UUID()
        let missing = UUID()
        let completed = UUID()
        let liveStates = [scheduled: "scheduled", abandoned: "abandoned", completed: "completed"]
        let staleIDs = EventKitBridge.staleSessionIDs(
            mappedIDs: [scheduled, abandoned, missing, completed],
            liveStates: liveStates
        )
        XCTAssertEqual(Set(staleIDs), Set([abandoned, missing]))
    }
}

// MARK: - SessionCalendarSyncStore (hermetic — isolated UserDefaults suite,
// never UserDefaults.standard, so this test can't collide with a real
// device's synced-session mapping or leak state across test runs)

final class SessionCalendarSyncStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SessionCalendarSyncStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRoundTripSetAndGet() {
        let sessionID = UUID()
        XCTAssertNil(SessionCalendarSyncStore.eventIdentifier(for: sessionID, defaults: defaults))

        SessionCalendarSyncStore.setEventIdentifier("event-123", for: sessionID, defaults: defaults)
        XCTAssertEqual(SessionCalendarSyncStore.eventIdentifier(for: sessionID, defaults: defaults), "event-123")
    }

    func testSetOverwritesExistingMapping() {
        // The reschedule "update in place" path relies on this: syncing the
        // same session id twice must replace, not duplicate, the mapping.
        let sessionID = UUID()
        SessionCalendarSyncStore.setEventIdentifier("event-A", for: sessionID, defaults: defaults)
        SessionCalendarSyncStore.setEventIdentifier("event-B", for: sessionID, defaults: defaults)
        XCTAssertEqual(SessionCalendarSyncStore.eventIdentifier(for: sessionID, defaults: defaults), "event-B")
    }

    func testRemoveMappingReturnsRemovedValueAndClearsIt() {
        let sessionID = UUID()
        SessionCalendarSyncStore.setEventIdentifier("event-123", for: sessionID, defaults: defaults)

        let removed = SessionCalendarSyncStore.removeMapping(for: sessionID, defaults: defaults)
        XCTAssertEqual(removed, "event-123")
        XCTAssertNil(SessionCalendarSyncStore.eventIdentifier(for: sessionID, defaults: defaults))
    }

    func testRemoveMappingOnAbsentSessionIsANoOp() {
        let removed = SessionCalendarSyncStore.removeMapping(for: UUID(), defaults: defaults)
        XCTAssertNil(removed)
    }

    func testAllSessionIDsReflectsEveryMapping() {
        let a = UUID()
        let b = UUID()
        SessionCalendarSyncStore.setEventIdentifier("event-A", for: a, defaults: defaults)
        SessionCalendarSyncStore.setEventIdentifier("event-B", for: b, defaults: defaults)

        let ids = Set(SessionCalendarSyncStore.allSessionIDs(defaults: defaults))
        XCTAssertEqual(ids, Set([a, b]))
    }

    func testClearWipesEveryMapping() {
        let sessionID = UUID()
        SessionCalendarSyncStore.setEventIdentifier("event-123", for: sessionID, defaults: defaults)

        SessionCalendarSyncStore.clear(defaults: defaults)

        XCTAssertNil(SessionCalendarSyncStore.eventIdentifier(for: sessionID, defaults: defaults))
        XCTAssertTrue(SessionCalendarSyncStore.allSessionIDs(defaults: defaults).isEmpty)
    }
}

// MARK: - CalendarSyncPrefsStore (hermetic — isolated UserDefaults suite)

final class CalendarSyncPrefsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CalendarSyncPrefsStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToDisabledWhenNeverSet() {
        // "default off" (Phase H Task 2 brief) needs no explicit bootstrap
        // write — UserDefaults.bool(forKey:) already returns false for an
        // absent key.
        XCTAssertFalse(CalendarSyncPrefsStore.isEnabled(defaults: defaults))
    }

    func testRoundTripEnableAndDisable() {
        CalendarSyncPrefsStore.setEnabled(true, defaults: defaults)
        XCTAssertTrue(CalendarSyncPrefsStore.isEnabled(defaults: defaults))

        CalendarSyncPrefsStore.setEnabled(false, defaults: defaults)
        XCTAssertFalse(CalendarSyncPrefsStore.isEnabled(defaults: defaults))
    }

    func testClearRevertsToDefaultOff() {
        CalendarSyncPrefsStore.setEnabled(true, defaults: defaults)
        CalendarSyncPrefsStore.clear(defaults: defaults)
        XCTAssertFalse(CalendarSyncPrefsStore.isEnabled(defaults: defaults))
    }
}
