import SwiftData
import XCTest
@testable import GymSync

/// Hermetic tests for `OfflineSetLogQueue`'s enqueue/replay/dedupe/prune
/// logic (Phase O Task 3, master spec §6.4) — no network, no Supabase.
///
/// The server round trip is faked via `SetLogSubmitting`
/// (Services/OfflineSetLogQueue.swift), the same "protocol + production
/// conformer + test fake" seam idiom `VoiceRoomServiceTests` uses for
/// `VoiceTokenFetching` (VoiceRoomServiceTests.swift's 19 hermetic tests) —
/// this file never imports Supabase or touches the network either.
///
/// SwiftData persistence is faked via an in-memory `ModelContainer`
/// (`ModelConfiguration(isStoredInMemoryOnly: true)`) — this is the FIRST
/// SwiftData usage anywhere in the codebase (see PendingSetLog.swift's doc
/// comment), so there's no prior in-repo precedent for this setup; it's
/// Apple's documented pattern for hermetic SwiftData tests.
@MainActor
final class OfflineSetLogQueueTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeSetLogSubmitter: SetLogSubmitting {
        enum Outcome {
            case success
            case failure(GymSyncError)
        }

        /// Per-id scripted outcome — lets a test control exactly which
        /// queued item fails and how, independent of submit order.
        var outcomes: [UUID: Outcome] = [:]
        var defaultOutcome: Outcome = .success
        private(set) var submittedIDsInOrder: [UUID] = []

        func submit(_ log: SetLog) async throws {
            submittedIDsInOrder.append(log.id)
            switch outcomes[log.id] ?? defaultOutcome {
            case .success: return
            case .failure(let error): throw error
            }
        }
    }

    /// Parks inside `submit()` until resumed — for the reentrancy-guard
    /// test. Continuation is stored BEFORE `pending` becomes observable,
    /// same safety ordering `VoiceRoomServiceTests.PendingTokenFetcher`
    /// documents (avoids the class of deadlock its HISTORY comment
    /// describes: a spinning observer resuming a continuation that hasn't
    /// been stored yet).
    private final class ParkingSubmitter: SetLogSubmitting {
        private var continuation: CheckedContinuation<Void, Error>?
        private(set) var callCount = 0
        private(set) var pending = false

        func submit(_ log: SetLog) async throws {
            callCount += 1
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                continuation = cont
                pending = true
            }
        }

        func resume() {
            pending = false
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PendingSetLog.self, configurations: config)
        return ModelContext(container)
    }

    private func makeSetLog(id: UUID = UUID(), reps: Int = 5, weight: Decimal = 100,
                             isFailed: Bool = false, isPenalty: Bool = false) -> SetLog {
        SetLog(
            id: id, userID: UUID(), sessionID: UUID(), exerciseID: UUID(),
            setIndex: 1, reps: reps, weight: weight, rpe: 7,
            isFailed: isFailed, isPenalty: isPenalty, note: nil, loggedAt: Date()
        )
    }

    /// Inserts a `PendingSetLog` directly (bypassing `enqueue()`) so a test
    /// can pin an exact `enqueuedAt` — needed for deterministic ordering
    /// assertions without sleep-based flakiness.
    private func insertPending(_ log: SetLog, enqueuedAt: Date, into context: ModelContext) {
        context.insert(PendingSetLog(setLog: log, enqueuedAt: enqueuedAt))
    }

    /// Bounded main-actor wait — mirrors `VoiceRoomServiceTests.settleUntil`:
    /// yields until `condition` or the bound trips, so a broken guard fails
    /// loud with a normal test failure instead of hanging the run.
    private func settleUntil(_ condition: () -> Bool) async -> Bool {
        var iterations = 0
        while !condition() && iterations < 50_000 {
            await Task.yield()
            iterations += 1
        }
        return condition()
    }

    // MARK: - Enqueue

    func testEnqueueAddsToPendingIDsAndPersists() throws {
        let context = try makeInMemoryContext()
        let queue = OfflineSetLogQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let log = makeSetLog()
        queue.enqueue(log)

        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id))
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.map(\.id), [log.id])
        XCTAssertEqual(stored.first?.reps, 5)
        XCTAssertEqual(stored.first?.weight, 100)
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }

    func testEnqueueIsIdempotentOnDuplicateID() throws {
        let context = try makeInMemoryContext()
        let queue = OfflineSetLogQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let log = makeSetLog()
        queue.enqueue(log)
        queue.enqueue(log) // same id — must not double-queue

        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.count, 1)
    }

    func testEnqueueBeforeConfigureIsHarmlessNoOp() {
        // No configure(modelContext:) call — enqueue must not crash.
        let queue = OfflineSetLogQueue(submitter: FakeSetLogSubmitter())
        queue.enqueue(makeSetLog())
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
    }

    // MARK: - Replay ordering

    func testReplaySubmitsInEnqueueOrderOldestFirst() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let now = Date()
        let oldest = makeSetLog()
        let middle = makeSetLog()
        let newest = makeSetLog()
        // Inserted out of order to prove replay sorts by enqueuedAt, not insert order.
        insertPending(newest, enqueuedAt: now.addingTimeInterval(20), into: context)
        insertPending(oldest, enqueuedAt: now, into: context)
        insertPending(middle, enqueuedAt: now.addingTimeInterval(10), into: context)
        try context.save()

        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [oldest.id, middle.id, newest.id])
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
    }

    // MARK: - Dedupe on 23505

    func testReplayTreatsConflictAsSuccessAndRemoves() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.conflict)
        queue.enqueue(log)

        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty, "a 23505 duplicate must be treated as already-landed and removed")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
        XCTAssertNil(queue.lastPermanentFailure, "a dedupe-success must not be reported as a permanent failure")
    }

    // MARK: - Permanent 4xx drop

    func testReplayDropsPermanentFailureAndSurfacesReason() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.validation("set_index must be >= 1"))
        queue.enqueue(log)

        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty, "a permanent (non-retryable) failure must be dropped, not left queued forever")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
        XCTAssertEqual(queue.lastPermanentFailure?.setLogID, log.id)
        XCTAssertEqual(queue.lastPermanentFailure?.message, "set_index must be >= 1")
    }

    func testReplayDropsNotFoundAndUnknownAsPermanentToo() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let notFound = makeSetLog()
        let unknown = makeSetLog()
        submitter.outcomes[notFound.id] = .failure(.notFound)
        submitter.outcomes[unknown.id] = .failure(.unknown("weird server response"))
        queue.enqueue(notFound)
        queue.enqueue(unknown)

        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
    }

    // MARK: - Transient (network) stop

    func testReplayStopsPassOnTransientFailureKeepingRemainderQueued() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let now = Date()
        let first = makeSetLog()
        let second = makeSetLog()
        let third = makeSetLog()
        insertPending(first, enqueuedAt: now, into: context)
        insertPending(second, enqueuedAt: now.addingTimeInterval(10), into: context)
        insertPending(third, enqueuedAt: now.addingTimeInterval(20), into: context)
        try context.save()
        submitter.outcomes[first.id] = .failure(.network)

        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [first.id],
                        "a transient failure on the oldest item must stop the pass — later items must not even be attempted")
        XCTAssertEqual(queue.pendingSetLogIDs, [first.id, second.id, third.id],
                        "nothing should be dropped on a transient failure")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingSetLog>()).count, 3)

        // Next trigger, now succeeding — the whole remainder drains, in order.
        submitter.outcomes[first.id] = .success
        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [first.id, first.id, second.id, third.id])
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
    }

    func testReplayTreatsUnauthorizedAsTransientNotPermanentDrop() async throws {
        // Deliberate judgment call (see OfflineSetLogQueue.replay()'s .unauthorized
        // case comment + task-3-report.md): unlike the task brief's named permanent-
        // 4xx examples (RLS denial → .validation, bad input → .validation),
        // "no valid session right now" is treated as recoverable/transient so a
        // lifter's captured reps are never dropped over an auth hiccup.
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.unauthorized)
        queue.enqueue(log)

        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id), ".unauthorized must NOT drop the item")
        XCTAssertNil(queue.lastPermanentFailure)
    }

    // MARK: - 90-day prune

    func testReplayPrunesEntriesOlderThan90DaysBeforeSubmitting() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let stale = makeSetLog()
        let fresh = makeSetLog()
        insertPending(stale, enqueuedAt: Date().addingTimeInterval(-91 * 24 * 60 * 60), into: context)
        insertPending(fresh, enqueuedAt: Date(), into: context)
        try context.save()

        await queue.replay()

        XCTAssertFalse(submitter.submittedIDsInOrder.contains(stale.id),
                        "a >90-day-old entry must be pruned before any submit attempt, never sent to the server")
        XCTAssertEqual(submitter.submittedIDsInOrder, [fresh.id])
        XCTAssertFalse(queue.pendingSetLogIDs.contains(stale.id))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
    }

    func testReplayKeepsEntriesJustUnder90Days() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let almostStale = makeSetLog()
        insertPending(almostStale, enqueuedAt: Date().addingTimeInterval(-89 * 24 * 60 * 60), into: context)
        try context.save()

        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [almostStale.id])
    }

    // MARK: - Not configured

    func testReplayIsNoOpWhenNeverConfigured() async {
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        await queue.replay() // must not crash
        XCTAssertTrue(submitter.submittedIDsInOrder.isEmpty)
    }

    // MARK: - Reentrancy guard

    func testReplayReentrancyGuardSkipsConcurrentPass() async throws {
        let context = try makeInMemoryContext()
        let submitter = ParkingSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter)
        queue.configure(modelContext: context)
        queue.enqueue(makeSetLog())

        let firstPass = Task { await queue.replay() }
        let parked = await settleUntil { submitter.pending }
        XCTAssertTrue(parked, "first pass should be parked inside submit()")

        // A concurrent replay() call while the first pass is still in flight
        // must be a no-op — it must NOT re-enter submit() (mirrors
        // EventKitBridge.isReconciling's exact reentrancy-guard idiom).
        await queue.replay()
        XCTAssertEqual(submitter.callCount, 1, "reentrant replay() must not call submit() again")

        submitter.resume()
        await firstPass.value
        XCTAssertEqual(submitter.callCount, 1)
    }
}
