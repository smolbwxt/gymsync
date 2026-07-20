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

    /// Fake for `CurrentUserIDProviding` (Services/OfflineSetLogQueue.swift)
    /// — lets a test pin exactly which user the queue currently believes is
    /// signed in, without ever touching the real `AuthService.shared`
    /// singleton (whose `init` kicks off an async `bootstrap()` that hits
    /// `SupabaseService` — not hermetic). Same "protocol + test fake" idiom
    /// as `FakeSetLogSubmitter`/`ParkingSubmitter` above.
    private final class FakeCurrentUserIDProvider: CurrentUserIDProviding {
        var currentUserID: UUID?
        init(currentUserID: UUID?) { self.currentUserID = currentUserID }
    }

    // MARK: - Helpers

    /// Fixed per-test-instance default so `makeSetLog()`'s default `userID`
    /// and `makeQueue()`'s default fake `currentUserID` agree without every
    /// test written before the gate's user-scoping fix (none of which
    /// mention a user at all) needing to pass either explicitly — see both
    /// helpers below. XCTest creates a fresh `OfflineSetLogQueueTests`
    /// instance (and so a fresh UUID here) per test method, so this can't
    /// leak identity across tests.
    private let defaultUserID = UUID()

    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PendingSetLog.self, configurations: config)
        return ModelContext(container)
    }

    /// Constructs the queue under test with a `FakeCurrentUserIDProvider`
    /// ALWAYS injected explicitly — never `OfflineSetLogQueue`'s production
    /// default (`AuthServiceCurrentUserIDProvider`), which would touch the
    /// real `AuthService.shared` singleton the moment `configure()` (called
    /// by nearly every test) triggers `refreshPendingIDs()`. Defaults to
    /// `defaultUserID`, matching `makeSetLog()`'s own default, so every
    /// pre-gate-fix test keeps working unmodified — the queue's "current
    /// user" and the fixture's "set owner" agree unless a test explicitly
    /// says otherwise (the foreign-user tests below do, via both params).
    private func makeQueue(submitter: SetLogSubmitting, userID: UUID? = nil) -> OfflineSetLogQueue {
        OfflineSetLogQueue(submitter: submitter,
                            userIDProvider: FakeCurrentUserIDProvider(currentUserID: userID ?? defaultUserID))
    }

    private func makeSetLog(id: UUID = UUID(), userID: UUID? = nil, reps: Int = 5, weight: Decimal = 100,
                             isFailed: Bool = false, isPenalty: Bool = false) -> SetLog {
        SetLog(
            id: id, userID: userID ?? defaultUserID, sessionID: UUID(), exerciseID: UUID(),
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
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
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
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let log = makeSetLog()
        queue.enqueue(log)
        queue.enqueue(log) // same id — must not double-queue

        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.count, 1)
    }

    func testEnqueueBeforeConfigureIsHarmlessNoOp() {
        // No configure(modelContext:) call — enqueue must not crash.
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.enqueue(makeSetLog())
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
    }

    // MARK: - Replay ordering

    func testReplaySubmitsInEnqueueOrderOldestFirst() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
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
        let queue = makeQueue(submitter: submitter)
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
        let queue = makeQueue(submitter: submitter)
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
        let queue = makeQueue(submitter: submitter)
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
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let now = Date()
        let first = makeSetLog()
        let second = makeSetLog()
        let third = makeSetLog()
        insertPending(first, enqueuedAt: now, into: context)
        insertPending(second, enqueuedAt: now.addingTimeInterval(10), into: context)
        insertPending(third, enqueuedAt: now.addingTimeInterval(20), into: context)
        try context.save()
        // `insertPending` writes directly into `context` (bypassing
        // `enqueue()`) so each item's `enqueuedAt` can be pinned for a
        // deterministic ordering assertion — see its doc comment above. Side
        // effect: `queue.pendingSetLogIDs` is only ever kept in sync by
        // `enqueue()`'s add, `remove()`'s remove, and `configure()`'s
        // `refreshPendingIDs()` resync — never by a raw `context.insert`. The
        // `configure()` call above (line 233) ran BEFORE these 3 rows
        // existed, so without a resync `pendingSetLogIDs` would still read
        // empty here even though all 3 rows are genuinely persisted (fix
        // wave 1, diagnosing CI's reported failure on this exact assertion:
        // `context.fetch(...).count == 3` a few lines below already passed
        // beforehand, proving the real SwiftData-persisted queue was never
        // touched — this was a test-fixture gap, not production data loss).
        // Production never hits this gap: the only insertion path there is
        // `enqueue()`, which keeps `pendingSetLogIDs` in sync itself. Re-
        // calling `configure()` here is therefore a test-fixture correction
        // only, not a change to any production code path.
        queue.configure(modelContext: context)
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
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.unauthorized)
        queue.enqueue(log)

        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id), ".unauthorized must NOT drop the item")
        XCTAssertNil(queue.lastPermanentFailure)
    }

    // MARK: - .unauthorized bounded escalation (reviewer Finding 3, fix wave 1)

    /// Below `maxUnauthorizedAttempts`, `.unauthorized` must keep behaving
    /// exactly like `testReplayTreatsUnauthorizedAsTransientNotPermanentDrop`
    /// above — each failed pass stops (doesn't drop) and bumps
    /// `unauthorizedAttemptCount` (the field the escalation actually reads,
    /// fix wave 2) by exactly one.
    func testReplayKeepsUnauthorizedBelowEscalationThreshold() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.unauthorized)
        queue.enqueue(log)

        // One short of the threshold — still transient-kept every time.
        for _ in 0..<(OfflineSetLogQueue.maxUnauthorizedAttempts - 1) {
            await queue.replay()
        }

        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id),
                       "below the escalation threshold, .unauthorized must stay queued")
        XCTAssertNil(queue.lastPermanentFailure)
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.first?.unauthorizedAttemptCount, OfflineSetLogQueue.maxUnauthorizedAttempts - 1)
    }

    /// At exactly `maxUnauthorizedAttempts` failed attempts, `.unauthorized`
    /// must flip from "keep, stop the pass" to "drop as permanent" —
    /// removed from the queue and store, surfaced via `lastPermanentFailure`.
    func testReplayDropsUnauthorizedAtEscalationThreshold() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.unauthorized)
        queue.enqueue(log)

        for _ in 0..<OfflineSetLogQueue.maxUnauthorizedAttempts {
            await queue.replay()
        }

        XCTAssertFalse(queue.pendingSetLogIDs.contains(log.id),
                        "at the escalation threshold, .unauthorized must be dropped as permanent")
        XCTAssertEqual(queue.lastPermanentFailure?.setLogID, log.id)
        XCTAssertEqual(queue.lastPermanentFailure?.message, GymSyncError.unauthorized.errorDescription)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
    }

    /// Fix wave 2 (reviewer follow-up to Finding 3, NEW-1): the escalation
    /// counter must be unauthorized-specific, not a stand-in for total
    /// attempts. Several `.network` failures (which stop the pass and bump
    /// only the diagnostic `attemptCount`, never `unauthorizedAttemptCount`)
    /// followed by a single `.unauthorized` failure must NOT read as "the
    /// Nth unauthorized failure" — it's the first one. Proves network noise
    /// no longer counts toward the auth threshold.
    func testMixedNetworkThenUnauthorizedDoesNotInflateEscalation() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        queue.enqueue(log)

        // Several `.network` failures — well past `maxUnauthorizedAttempts`
        // in raw attempt count, but none of them `.unauthorized`.
        submitter.outcomes[log.id] = .failure(.network)
        for _ in 0..<(OfflineSetLogQueue.maxUnauthorizedAttempts + 5) {
            await queue.replay()
        }
        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id), "still queued after repeated .network failures")

        // Now a single .unauthorized failure — must be treated as the
        // FIRST unauthorized attempt, not the Nth overall attempt.
        submitter.outcomes[log.id] = .failure(.unauthorized)
        await queue.replay()

        XCTAssertTrue(queue.pendingSetLogIDs.contains(log.id),
                       "a single .unauthorized failure after many .network failures must NOT trip the escalation")
        XCTAssertNil(queue.lastPermanentFailure)
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.first?.unauthorizedAttemptCount, 1,
                        "unauthorizedAttemptCount must count only the .unauthorized failure, not the prior .network ones")
        XCTAssertGreaterThan(stored.first?.attemptCount ?? 0, OfflineSetLogQueue.maxUnauthorizedAttempts,
                              "attemptCount (the total-attempts diagnostic) should be well past the threshold, proving it's genuinely NOT what the escalation reads")
    }

    // MARK: - 90-day prune

    func testReplayPrunesEntriesOlderThan90DaysBeforeSubmitting() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
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
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let almostStale = makeSetLog()
        insertPending(almostStale, enqueuedAt: Date().addingTimeInterval(-89 * 24 * 60 * 60), into: context)
        try context.save()

        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [almostStale.id])
    }

    /// ADJUDICATION test (see `pruneExpired()`'s own doc comment in
    /// Services/OfflineSetLogQueue.swift): the 90-day prune pass is
    /// deliberately GLOBAL, not scoped to the current user — age-based
    /// on-device housekeeping never talks to the server, so a different
    /// user's >90-day-old row must still be pruned from the store even
    /// though `replay()` itself would never submit it.
    func testReplayPrunesForeignUsersStaleEntriesToo() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let foreignUserID = UUID()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let staleForeign = makeSetLog(userID: foreignUserID)
        insertPending(staleForeign, enqueuedAt: Date().addingTimeInterval(-91 * 24 * 60 * 60), into: context)
        try context.save()

        await queue.replay()

        XCTAssertTrue(submitter.submittedIDsInOrder.isEmpty, "a foreign row is never submitted, stale or not")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty,
                       "prune is global — a foreign user's stale row must still be deleted from the on-device store")
    }

    // MARK: - User-scoping (gate finding — shared-device queue leak)
    //
    // Prior to this fix, `replay()` fetched EVERY `PendingSetLog` row with
    // no user filter and the SwiftData container is device-global, not
    // per-user. On a shared device: user A queues sets offline, signs out
    // (the queue is deliberately NOT cleared, see AuthService.signOut()'s
    // doctrine comment), user B signs in — the auth-transition drain would
    // replay A's rows under B's Supabase session, hit an RLS denial
    // (42501 → `.validation` via ErrorMapping), and silently drop them via
    // the permanent-failure bucket: A's captured reps lost, and A's set
    // content transmitted under B's identity. These tests exercise the fix
    // (`PendingSetLog.userID`-scoped fetches in `replay()` and
    // `refreshPendingIDs()`).

    /// A DIFFERENT user's queued row must survive a full `replay()` pass
    /// completely untouched: never submitted (never even fetched under the
    /// current user's session), never dropped, never removed from the
    /// SwiftData store or reported via `lastPermanentFailure`.
    func testReplaySkipsForeignUserRowsEntirely() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let foreignUserID = UUID()
        let queue = makeQueue(submitter: submitter) // current user = defaultUserID

        let foreignLog = makeSetLog(userID: foreignUserID)
        insertPending(foreignLog, enqueuedAt: Date(), into: context)
        try context.save()
        queue.configure(modelContext: context)

        await queue.replay()

        XCTAssertTrue(submitter.submittedIDsInOrder.isEmpty,
                       "a foreign user's row must never be submitted under the current user's session")
        XCTAssertNil(queue.lastPermanentFailure, "a skipped foreign row must not read as a dropped/failed submit")
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.map(\.id), [foreignLog.id], "the foreign row must survive untouched in the store")
        XCTAssertFalse(queue.pendingSetLogIDs.contains(foreignLog.id),
                        "the foreign row must not appear in the current user's pendingSetLogIDs either")
    }

    /// A queue holding BOTH a foreign user's row and the current user's own
    /// row: `replay()` must submit only the current user's row, leave the
    /// foreign row queued and untouched, and remove only the current
    /// user's row from the store on success.
    func testReplaySubmitsOnlyCurrentUserRowsWhenQueueIsMixed() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let foreignUserID = UUID()
        let queue = makeQueue(submitter: submitter)

        let mine = makeSetLog() // defaultUserID — matches makeQueue()'s default current user
        let theirs = makeSetLog(userID: foreignUserID)
        insertPending(theirs, enqueuedAt: Date(), into: context)
        insertPending(mine, enqueuedAt: Date().addingTimeInterval(10), into: context)
        try context.save()
        queue.configure(modelContext: context)

        await queue.replay()

        XCTAssertEqual(submitter.submittedIDsInOrder, [mine.id],
                        "only the current user's row should ever reach the submitter")
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty, "the current user's own row drains normally")
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.map(\.id), [theirs.id], "the foreign row must be the only one left in the store")
    }

    /// `refreshPendingIDs()` — the UI-badge cache backing the "syncing"
    /// chips (`WorkoutSessionView.loggedSetsTable`, `GroupSessionLiveView.
    /// feedRow`) — must exclude a foreign user's rows: a second user on a
    /// shared device must never see a syncing indicator for content that
    /// isn't theirs. Exercised both via `configure()`'s internal call and a
    /// direct re-call (mirrors RootView's `.onChange(of: auth.state)` hook).
    func testRefreshPendingIDsExcludesForeignUserRows() throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let foreignUserID = UUID()
        let queue = makeQueue(submitter: submitter)

        let mine = makeSetLog()
        let theirs = makeSetLog(userID: foreignUserID)
        insertPending(theirs, enqueuedAt: Date(), into: context)
        insertPending(mine, enqueuedAt: Date(), into: context)
        try context.save()

        queue.configure(modelContext: context) // configure() calls refreshPendingIDs() internally
        XCTAssertEqual(queue.pendingSetLogIDs, [mine.id],
                        "pendingSetLogIDs must contain only the current user's rows, never a foreign user's")

        queue.refreshPendingIDs() // direct re-call, same as RootView's auth-transition hook
        XCTAssertEqual(queue.pendingSetLogIDs, [mine.id])
    }

    /// Defensive nil-handling (brief's explicit requirement): no signed-in
    /// user — e.g. a replay call racing a sign-out transition, or running
    /// before `AuthService.bootstrap()` resolves — must skip the ENTIRE
    /// pass rather than guess which rows are "safe." Nothing submitted,
    /// nothing dropped, nothing even pruned (the guard returns before
    /// `pruneExpired()` runs).
    func testReplaySkipsEntirePassWhenNoUserSignedIn() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = OfflineSetLogQueue(submitter: submitter,
                                        userIDProvider: FakeCurrentUserIDProvider(currentUserID: nil))

        let log = makeSetLog()
        insertPending(log, enqueuedAt: Date(), into: context)
        try context.save()
        queue.configure(modelContext: context)

        await queue.replay()

        XCTAssertTrue(submitter.submittedIDsInOrder.isEmpty, "no signed-in user means nothing should ever be submitted")
        XCTAssertNil(queue.lastPermanentFailure)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingSetLog>()).count, 1,
                        "the row must survive completely untouched — not even pruned")
    }

    /// `refreshPendingIDs()` with no signed-in user must reset to empty,
    /// not "leave whatever was cached" — a prior user's in-memory IDs must
    /// not linger into a signed-out state either.
    func testRefreshPendingIDsIsEmptyWhenNoUserSignedIn() throws {
        let context = try makeInMemoryContext()
        let provider = FakeCurrentUserIDProvider(currentUserID: defaultUserID)
        let queue = OfflineSetLogQueue(submitter: FakeSetLogSubmitter(), userIDProvider: provider)

        let mine = makeSetLog()
        insertPending(mine, enqueuedAt: Date(), into: context)
        try context.save()
        queue.configure(modelContext: context)
        XCTAssertEqual(queue.pendingSetLogIDs, [mine.id])

        provider.currentUserID = nil // simulate the sign-out transition
        queue.refreshPendingIDs()

        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty,
                       "signing out must clear the in-memory badge cache, not leave the previous user's IDs cached")
    }

    // MARK: - Not configured

    func testReplayIsNoOpWhenNeverConfigured() async {
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        await queue.replay() // must not crash
        XCTAssertTrue(submitter.submittedIDsInOrder.isEmpty)
    }

    // MARK: - Replay-failure notice clear contract (debt-zero sprint item 2)

    /// `clearLastPermanentFailure()` nils the property — the dismiss action
    /// HomeView's `GSInlineNoticeBanner.onDismiss` calls.
    func testClearLastPermanentFailureNilsTheProperty() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let log = makeSetLog()
        submitter.outcomes[log.id] = .failure(.validation("bad value"))
        queue.enqueue(log)
        await queue.replay()
        XCTAssertNotNil(queue.lastPermanentFailure, "precondition: a permanent drop must have set it")

        queue.clearLastPermanentFailure()

        XCTAssertNil(queue.lastPermanentFailure)
    }

    /// "Must not re-appear forever" (task brief): dismissing must not
    /// suppress a LATER, genuinely NEW permanent drop — only the dismissed
    /// one should stay gone. Proves `clearLastPermanentFailure()` doesn't
    /// latch the property into a permanently-suppressed state.
    func testANewPermanentFailureAfterClearSurfacesAgain() async throws {
        let context = try makeInMemoryContext()
        let submitter = FakeSetLogSubmitter()
        let queue = makeQueue(submitter: submitter)
        queue.configure(modelContext: context)

        let first = makeSetLog()
        submitter.outcomes[first.id] = .failure(.validation("bad value"))
        queue.enqueue(first)
        await queue.replay()
        XCTAssertEqual(queue.lastPermanentFailure?.setLogID, first.id)

        queue.clearLastPermanentFailure()
        XCTAssertNil(queue.lastPermanentFailure)

        let second = makeSetLog()
        submitter.outcomes[second.id] = .failure(.notFound)
        queue.enqueue(second)
        await queue.replay()

        XCTAssertEqual(queue.lastPermanentFailure?.setLogID, second.id,
                        "a new, distinct permanent drop must surface after a prior dismissal")
    }

    // MARK: - purge(userID:) (debt-zero sprint item 3)
    //
    // Backs `AuthService.forceSignedOutAfterDeletion()` — a hard-deleted
    // account's queued rows can never sync (the user can never sign back
    // in to drain them), unlike `signOut()`'s deliberate non-purge.

    /// The common case: every row for the target user is removed from both
    /// the SwiftData store and the in-memory `pendingSetLogIDs` cache.
    func testPurgeRemovesAllRowsForTheGivenUser() async throws {
        let context = try makeInMemoryContext()
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let first = makeSetLog()
        let second = makeSetLog()
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertEqual(queue.pendingSetLogIDs, [first.id, second.id])

        queue.purge(userID: defaultUserID)

        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSetLog>()).isEmpty)
    }

    /// A DIFFERENT user's queued rows on the same (shared-device) store
    /// must survive a purge of one user's rows completely untouched —
    /// mirrors the same isolation `testReplaySkipsForeignUserRowsEntirely`
    /// proves for `replay()`.
    func testPurgeOnlyRemovesTheTargetUsersRowsNotOthers() async throws {
        let context = try makeInMemoryContext()
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let foreignUserID = UUID()
        let mine = makeSetLog()
        let theirs = makeSetLog(userID: foreignUserID)
        insertPending(theirs, enqueuedAt: Date(), into: context)
        try context.save()
        queue.enqueue(mine)

        queue.purge(userID: defaultUserID)

        XCTAssertFalse(queue.pendingSetLogIDs.contains(mine.id))
        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.map(\.id), [theirs.id], "a different user's row must survive the purge untouched")
    }

    /// Purging a user with nothing queued must be a harmless no-op — not a
    /// crash, not a spurious `modelContext.save()` side effect that could
    /// disturb other rows.
    func testPurgeIsNoOpWhenTheUserHasNothingQueued() async throws {
        let context = try makeInMemoryContext()
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.configure(modelContext: context)

        let foreignUserID = UUID()
        let theirs = makeSetLog(userID: foreignUserID)
        insertPending(theirs, enqueuedAt: Date(), into: context)
        try context.save()
        queue.refreshPendingIDs()

        queue.purge(userID: defaultUserID) // defaultUserID has nothing queued

        let stored = try context.fetch(FetchDescriptor<PendingSetLog>())
        XCTAssertEqual(stored.map(\.id), [theirs.id], "an unrelated user's row must be unaffected by a no-op purge")
    }

    /// Defensive nil-handling, same "never configured" contract as
    /// `testReplayIsNoOpWhenNeverConfigured` — must not crash.
    func testPurgeIsNoOpWhenNeverConfigured() {
        let queue = makeQueue(submitter: FakeSetLogSubmitter())
        queue.purge(userID: defaultUserID) // must not crash
        XCTAssertTrue(queue.pendingSetLogIDs.isEmpty)
    }

    // MARK: - Reentrancy guard

    func testReplayReentrancyGuardSkipsConcurrentPass() async throws {
        let context = try makeInMemoryContext()
        let submitter = ParkingSubmitter()
        let queue = makeQueue(submitter: submitter)
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
