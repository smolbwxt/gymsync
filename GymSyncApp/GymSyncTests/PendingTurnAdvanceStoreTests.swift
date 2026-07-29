import XCTest
@testable import GymSync

/// The client half of the rotation guard (migration 20260801000001). The
/// server-side no-op is proven in `supabase/tests/advance_turn_version_guard_test.sql`;
/// these pin the bookkeeping that decides WHICH version gets replayed.
@MainActor
final class PendingTurnAdvanceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: PendingTurnAdvanceStore!

    override func setUp() {
        super.setUp()
        // A throwaway suite so these never touch the real user's queue.
        let name = "PendingTurnAdvanceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        store = PendingTurnAdvanceStore(defaults: defaults)
    }

    func testStartsEmpty() {
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.pendingVersion(for: UUID()))
    }

    func testRecordsTheObservedVersionPerSession() {
        let a = UUID(), b = UUID()
        store.record(sessionID: a, observedVersion: 3)
        store.record(sessionID: b, observedVersion: 7)
        XCTAssertEqual(store.pendingVersion(for: a), 3)
        XCTAssertEqual(store.pendingVersion(for: b), 7)
        XCTAssertFalse(store.isEmpty)
    }

    /// A lifter can only owe the rotation one advance at a time — a second
    /// offline set on the same session supersedes the first observation
    /// rather than queuing a second advance that would fizzle.
    func testASecondRecordSupersedesTheFirst() {
        let session = UUID()
        store.record(sessionID: session, observedVersion: 1)
        store.record(sessionID: session, observedVersion: 2)
        XCTAssertEqual(store.pendingVersion(for: session), 2)
    }

    func testClearRemovesOnlyThatSession() {
        let a = UUID(), b = UUID()
        store.record(sessionID: a, observedVersion: 1)
        store.record(sessionID: b, observedVersion: 1)
        store.clear(sessionID: a)
        XCTAssertNil(store.pendingVersion(for: a))
        XCTAssertEqual(store.pendingVersion(for: b), 1)
    }

    /// Survives relaunch: the whole point of persisting rather than holding
    /// this in view state is that a force-quit mid-rotation still heals.
    func testPersistsAcrossStoreInstances() {
        let session = UUID()
        store.record(sessionID: session, observedVersion: 5)

        let reopened = PendingTurnAdvanceStore(defaults: defaults)
        XCTAssertEqual(reopened.pendingVersion(for: session), 5)
    }

    func testEmptyingClearsTheBackingKey() {
        let session = UUID()
        store.record(sessionID: session, observedVersion: 1)
        store.clear(sessionID: session)
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(defaults.dictionary(forKey: "pendingTurnAdvances.v1"))
    }
}
