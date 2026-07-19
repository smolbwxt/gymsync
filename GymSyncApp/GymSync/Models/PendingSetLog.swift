import Foundation
import SwiftData

/// Local SwiftData record for a `set_logs` write that hasn't been confirmed
/// landed on the server yet — master spec §6.4's "pending writes queue".
/// This is the FIRST use of SwiftData anywhere in this codebase (verified by
/// grep — the only prior "SwiftData" mention is `StatTilesSnapshot.swift`'s
/// doc comment explicitly ruling it OUT for that narrower cache, "Per the
/// Phase U plan's Global Constraints, this is explicitly NOT SwiftData").
/// No linking step is required beyond `import SwiftData` — it's a system
/// framework auto-linked on iOS 17+ (this project's deploymentTarget,
/// `GymSyncApp/project.yml:5`), the same way `HealthKit`/`EventKit` need no
/// `sdk:` entry in `project.yml` either.
///
/// Mirrors `SetLog`'s fields (Models/SetLog.swift) 1:1 plus queue-only
/// additions: `enqueuedAt` and `attemptCount` (brief's "mirror SetLog's
/// fields + enqueue timestamp + attempt count" requirement), and
/// `unauthorizedAttemptCount` (fix wave 2, not part of the original brief —
/// see that field's own doc comment below for why it exists as a separate
/// field rather than reusing `attemptCount`).
///
/// `id` doubles as the idempotency key: it's the SAME client-generated UUID
/// `SetLog.id` already carries end-to-end (WorkoutSessionView.swift:675,
/// GroupSessionLiveView.swift:1733/1826 all construct `SetLog(id: UUID(),
/// ...)` fresh per attempt) — `set_logs.id uuid PRIMARY KEY` is commented
/// "client-generated for idempotent retry" in the migration
/// (supabase/migrations/20260709000007_create_set_logs.sql:2). Replaying
/// this exact row is therefore safe to retry: a duplicate lands as
/// `GymSyncError.conflict` (23505), not a new row.
@Model
final class PendingSetLog {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var setIndex: Int
    var reps: Int?
    var weight: Decimal?
    var rpe: Decimal?
    var isFailed: Bool
    var isPenalty: Bool
    var note: String?
    /// The set's own `logged_at` — when the lifter actually performed it,
    /// NOT when it was queued. Preserved as-is through replay so the
    /// server row's timestamp matches what really happened, matching
    /// every other offline-queue precedent's "don't rewrite history" norm.
    var loggedAt: Date
    /// When this entry was queued — drives both replay ordering ("ordered
    /// by enqueue time" per brief) and the 90-day prune window (master
    /// spec §6.4's stated cache/queue retention).
    var enqueuedAt: Date
    /// Bumped on every replay attempt, regardless of outcome — the
    /// total-attempts diagnostic (kept per the brief's explicit "mirror
    /// SetLog's fields + enqueue timestamp + attempt count" requirement).
    /// Every transient `.network` failure still just stops the pass and
    /// retries next trigger with no cap (see `OfflineSetLogQueue.replay()`).
    /// Reviewer Finding 3 (fix wave 1) briefly wired THIS field into the
    /// `.unauthorized` escalation check, but that made the escalation
    /// non-auth-specific: a long offline stretch of `.network` failures
    /// bumps this same counter, so a single later `.unauthorized` could
    /// read as the Nth failure and drop the item after just one real auth
    /// failure. Fix wave 2 moved the escalation check onto the dedicated
    /// `unauthorizedAttemptCount` field below instead — this field is back
    /// to being the pure, honest total-attempts count it always claimed to
    /// be, not read by any cap/backoff logic.
    var attemptCount: Int

    /// Bumped ONLY on an `.unauthorized` replay failure (fix wave 2,
    /// reviewer follow-up to Finding 3's escalation) — this is the value
    /// `OfflineSetLogQueue.maxUnauthorizedAttempts` actually compares
    /// against in `replay()`'s `.unauthorized` case, not `attemptCount`.
    /// Kept as its own field so a long run of transient `.network` failures
    /// can never count toward the auth-specific escalation threshold; only
    /// genuine `.unauthorized` responses do. Defaults to 0: this model was
    /// never shipped before this branch (see the class doc comment above —
    /// no SwiftData migration concern), and the default means any existing
    /// in-memory test fixture that doesn't reference this field explicitly
    /// still compiles and behaves correctly (starts at 0, same as a freshly
    /// enqueued item).
    var unauthorizedAttemptCount: Int = 0

    init(setLog: SetLog, enqueuedAt: Date = Date()) {
        self.id = setLog.id
        self.userID = setLog.userID
        self.sessionID = setLog.sessionID
        self.exerciseID = setLog.exerciseID
        self.setIndex = setLog.setIndex
        self.reps = setLog.reps
        self.weight = setLog.weight
        self.rpe = setLog.rpe
        self.isFailed = setLog.isFailed
        self.isPenalty = setLog.isPenalty
        self.note = setLog.note
        self.loggedAt = setLog.loggedAt
        self.enqueuedAt = enqueuedAt
        self.attemptCount = 0
    }

    /// Reconstitutes the wire model for a replay submit attempt.
    var asSetLog: SetLog {
        SetLog(
            id: id, userID: userID, sessionID: sessionID, exerciseID: exerciseID,
            setIndex: setIndex, reps: reps, weight: weight, rpe: rpe,
            isFailed: isFailed, isPenalty: isPenalty, note: note, loggedAt: loggedAt
        )
    }
}
