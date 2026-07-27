import Foundation
import SwiftData

// MARK: - Submit seam

/// Abstracts the server-side set-log INSERT so `OfflineSetLogQueue`'s
/// enqueue/replay/dedupe/prune logic is hermetically testable — same
/// "protocol + production conformer + test fake" idiom as
/// `VoiceRoomService`'s `VoiceTokenFetching` seam (Services/
/// VoiceRoomService.swift:39, `VoiceRoomServiceTests.swift`'s 19 hermetic
/// tests fake it as `FakeTokenFetcher`), so tests never touch Supabase or
/// the network.
protocol SetLogSubmitting {
    func submit(_ log: SetLog) async throws
}

/// Production conformer — delegates to the SAME repository method every
/// online submit surface already calls (`SessionRepository.logSet`,
/// Models/SessionRepository.swift:73), so replay is byte-identical to a
/// live submit, not a reimplementation.
struct SupabaseSetLogSubmitter: SetLogSubmitting {
    func submit(_ log: SetLog) async throws {
        try await SessionRepository.logSet(log)
    }
}

// MARK: - Current-user seam

/// Abstracts "who's the signed-in user right now" so `replay()`'s and
/// `refreshPendingIDs()`'s per-user scoping (gate finding on the shared-
/// device queue leak — see class doc comment below and task-3-report.md's
/// "## Gate fix" section) is hermetically testable, same "protocol +
/// production conformer + test fake" idiom as `SetLogSubmitting` above and
/// `VoiceRoomService`'s `VoiceTokenFetching` seam.
/// `@MainActor` because the production conformer reads the MainActor-
/// isolated `AuthService.shared.state`, and every consumer
/// (`OfflineSetLogQueue`, itself `@MainActor`) calls it from the main
/// actor anyway — isolating the protocol keeps the conformer's read legal
/// without an isolation hop.
@MainActor
protocol CurrentUserIDProviding {
    var currentUserID: UUID? { get }
}

/// Production conformer — reads `AuthService.state`, the SAME synchronous
/// accessor `RootView` already pattern-matches on for every replay trigger
/// (`case .signedIn(let userID) = auth.state`, App/RootView.swift), so this
/// isn't a second source of truth, just the existing one made injectable.
/// `nil` for `.pending`/`.signedOut` — a call that races a sign-out (or
/// runs before bootstrap resolves) has no user to scope to and must skip
/// cleanly rather than guess.
struct AuthServiceCurrentUserIDProvider: CurrentUserIDProviding {
    /// Stateless struct: an explicitly `nonisolated` init lets the type be
    /// constructed in nonisolated contexts (e.g. `OfflineSetLogQueue.init`'s
    /// default-argument expression, which Swift evaluates outside the actor)
    /// while `currentUserID` itself stays MainActor-isolated per the
    /// protocol — construction touches no isolated state, reads do.
    nonisolated init() {}

    var currentUserID: UUID? {
        guard case .signedIn(let userID) = AuthService.shared.state else { return nil }
        return userID
    }
}

// MARK: - Offline set-log queue

/// Master spec §6.4's "pending writes queue" for set logs — SCOPE: set
/// logging only, not a general offline layer (reliability-debt design §3).
/// `@Observable @MainActor final class` singleton, matching this codebase's
/// existing convention for exactly this shape of service
/// (`ConnectivityMonitor.shared`, `AppState.shared` — both `@Observable
/// @MainActor final class` singletons read directly by views with no
/// environment threading, see `ConnectivityMonitor`'s own doc comment).
/// `@MainActor` also keeps every `ModelContext` touch on one actor, which
/// SwiftData expects (a context is not meant to be used concurrently from
/// multiple threads).
///
/// **User-scoped (gate finding, post-ship).** The SwiftData container is
/// global to the device, not per-user — on a shared device, user A could
/// queue sets offline, sign out (this queue is deliberately NOT cleared on
/// sign-out, see `AuthService.signOut()`'s doctrine comment), and user B
/// could sign in and have the auth-transition drain (`RootView`'s
/// `.onChange(of: auth.state)`) replay A's rows under B's Supabase session
/// — landing a server-side RLS denial (42501) that `ErrorMapping` maps to
/// `.validation`, which `replay()`'s permanent-drop bucket then silently
/// discards. Net effect: A's captured reps lost, and A's set content sent
/// to the server under B's identity. Fixed by scoping `replay()` and
/// `refreshPendingIDs()` to rows where `PendingSetLog.userID` equals the
/// CURRENTLY signed-in user's id (`PendingSetLog.swift` already carried
/// `userID` — it mirrors every `SetLog` field 1:1). USER-SCOPING was chosen over
/// clear-on-signout: clearing would destroy A's still-legitimate queued
/// sets; scoping preserves them for A's own return while making them
/// invisible (and unreplayable) to anyone else in the meantime.
@Observable
@MainActor
final class OfflineSetLogQueue {
    static let shared = OfflineSetLogQueue()

    /// Master spec §6.4's stated local retention window ("past sessions
    /// (last 90 days), set_logs (last 90 days)").
    static let retentionWindow: TimeInterval = 90 * 24 * 60 * 60

    /// Bounded escalation for `.unauthorized` (reviewer Finding 3, fix wave
    /// 1; refined fix wave 2 — see below). The original judgment call below
    /// (see the `.unauthorized` case in `replay()`) treats "no valid session
    /// right now" as recoverable — right for a brief auth hiccup — but with
    /// no cap, an item whose session never comes back (permanently signed
    /// out, account deleted, a stuck/expired token that never refreshes)
    /// would sit in the queue forever, re-attempted on every trigger
    /// forever. 10 is a defensible, generous bound: replay is triggered on
    /// every foreground/connectivity/signed-in-transition/post-submit event
    /// (RootView.swift), so 10 attempts is 10 separate trigger firings, not
    /// 10 app launches — several orders of magnitude more slack than a
    /// normal "signed back in within the session" recovery would ever need.
    ///
    /// Compared against `PendingSetLog.unauthorizedAttemptCount`
    /// (PendingSetLog.swift), NOT `attemptCount`. Fix wave 1 originally
    /// wired this check to `attemptCount`, which bumps on every replay
    /// attempt regardless of outcome — so a long offline stretch of
    /// `.network` failures followed by a single later `.unauthorized` could
    /// read as the Nth failure and drop the item after just one real auth
    /// failure, contradicting this escalation's own "session never comes
    /// back" rationale. Fix wave 2 split out a dedicated
    /// `unauthorizedAttemptCount` that only `.unauthorized` increments, so
    /// this threshold now means exactly what its name says.
    static let maxUnauthorizedAttempts = 10

    /// IDs currently queued (enqueued, not yet confirmed landed server-side)
    /// for the CURRENT signed-in user only (gate finding — see class doc
    /// comment: a shared-device second user must never see a "syncing" chip
    /// on rows that are actually the FIRST user's still-queued sets). Views
    /// check membership to render the "syncing" indicator — e.g.
    /// `WorkoutSessionView.loggedSetsTable`'s row icon,
    /// `GroupSessionLiveView.feedRow`'s tag row (both wired in Phase O
    /// Task 3). Read directly like `ConnectivityMonitor.shared.isOnline` —
    /// no environment plumbing needed, `@Observable` tracks the read.
    private(set) var pendingSetLogIDs: Set<UUID> = []

    /// Best-effort surface for a PERMANENT (non-retryable) replay-time
    /// failure. No existing global toast/banner idiom exists in this
    /// codebase to hang this off of (checked `DesignSystem/
    /// GSComponents.swift` — no Toast/global-banner type; `GSInlineErrorBanner`
    /// and friends are all per-screen, driven by a local `@State` string, not
    /// something a background replay pass can reach into). Submit-TIME
    /// permanent failures (the common case — a bad value, RLS denial) still
    /// surface exactly as before, through each call site's own existing
    /// `errorText`/`logSetErrorText` idiom, completely unchanged. This
    /// property exists so a future screen COULD observe a background-replay
    /// drop; today it's paired with an `AppLogger.workout` line as the
    /// actual, honest surfacing mechanism.
    private(set) var lastPermanentFailure: (setLogID: UUID, message: String)?

    private let submitter: SetLogSubmitting
    /// Gate finding's scoping seam (see class doc comment) — production
    /// default reads `AuthService.state`; tests inject a fake so this file
    /// never touches the real `AuthService.shared` singleton (whose `init`
    /// kicks off an async `bootstrap()` that hits `SupabaseService` — not
    /// hermetic).
    private let userIDProvider: CurrentUserIDProviding
    private var modelContext: ModelContext?
    /// Reentrancy guard — mirrors `EventKitBridge.isReconciling`'s exact
    /// idiom (Services/EventKitBridge.swift:240): best-effort de-dupe, not a
    /// hard mutual-exclusion guarantee (acceptable here for the same reason
    /// EventKitBridge gives — a redundant pass is wasted work, never
    /// incorrect, since each pass re-fetches from the SwiftData store fresh).
    private var isReplaying = false

    init(submitter: SetLogSubmitting = SupabaseSetLogSubmitter(),
         userIDProvider: CurrentUserIDProviding = AuthServiceCurrentUserIDProvider()) {
        self.submitter = submitter
        self.userIDProvider = userIDProvider
    }

    /// Must be called once (RootView, Phase O Task 3) with the app's
    /// SwiftData `ModelContext` before enqueue/replay do anything — mirrors
    /// `ThemeStore.shared.load()`'s "singleton configured post-init from the
    /// view tree" idiom (App/GymSyncApp.swift's `.task`) rather than this
    /// class building its own `ModelContainer`, so the queue shares the
    /// app's single SwiftData store (`.modelContainer(for:
    /// PendingSetLog.self)` on the `WindowGroup`, GymSyncApp.swift).
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshPendingIDs()
    }

    /// Enqueue a set log that failed to submit for a transient (offline)
    /// reason. Idempotent on `id` — a caller retrying the same logical set
    /// (same `SetLog.id`) never double-queues it.
    func enqueue(_ log: SetLog) {
        guard let modelContext else {
            AppLogger.workout.error("OfflineSetLogQueue.enqueue called before configure(modelContext:) — set \(log.id) NOT queued")
            return
        }
        guard !pendingSetLogIDs.contains(log.id) else { return }
        modelContext.insert(PendingSetLog(setLog: log))
        try? modelContext.save()
        pendingSetLogIDs.insert(log.id)
    }

    /// Replay every queued item, oldest-enqueued first. Per-item:
    ///   - success                → remove from queue
    ///   - `.conflict` (23505)    → already landed in a prior partial
    ///                              replay; treat as success, remove
    ///   - `.network`             → transient; STOP the pass, keep this
    ///                              item and everything after it queued
    ///   - `.unauthorized`        → transient, same as `.network`, UNLESS
    ///                              this was the item's `maxUnauthorizedAttempts`th
    ///                              `.unauthorized` failure specifically
    ///                              (fix wave 2: `.network` failures no
    ///                              longer count toward this), in which
    ///                              case: permanent (see below)
    ///   - anything else          → permanent (RLS denial, validation, an
    ///                              `.unauthorized` that exhausted its
    ///                              attempts, …); drop + surface (AppLogger
    ///                              + `lastPermanentFailure`)
    /// Also prunes entries older than `retentionWindow` before attempting
    /// any submits (spec's 90-day window).
    ///
    /// Scoped to the CURRENT signed-in user only (gate finding — class doc
    /// comment): fetches only `PendingSetLog` rows whose `userID` matches
    /// `userIDProvider.currentUserID`, so a different user's still-queued
    /// rows are never even fetched, let alone submitted under this user's
    /// auth session. No signed-in user → skip the WHOLE pass (nothing to
    /// scope to); every real trigger site (RootView) already gates on
    /// `.signedIn` before calling this, so that should be rare in practice
    /// — logged so a gap is traceable, matching this file's existing
    /// "log what's dropped/skipped" norm.
    func replay() async {
        guard let modelContext else { return }
        guard !isReplaying else { return }
        isReplaying = true
        defer { isReplaying = false }

        guard let userID = userIDProvider.currentUserID else {
            AppLogger.workout.notice("OfflineSetLogQueue.replay skipped — no signed-in user")
            return
        }

        // Prune stays GLOBAL (not scoped to `userID`) — deliberate, see
        // pruneExpired()'s own doc comment: age-based housekeeping of
        // another user's >90-day-old rows is fine, unlike replay, which
        // would submit those rows to the server under the WRONG user's
        // auth session.
        pruneExpired(modelContext: modelContext)

        let descriptor = FetchDescriptor<PendingSetLog>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            item.attemptCount += 1
            do {
                try await submitter.submit(item.asSetLog)
                remove(item, modelContext: modelContext)
            } catch let error as GymSyncError {
                switch error {
                case .conflict:
                    remove(item, modelContext: modelContext)
                case .network:
                    try? modelContext.save()
                    return
                case .unauthorized:
                    // Deliberate judgment call (recorded in task-3-report.md's
                    // design-decisions section): treated as transient rather
                    // than a permanent drop. Unlike `.network`, this isn't one
                    // of the task brief's named "permanent 4xx" examples (RLS
                    // denial, validation) — RLS denial itself already surfaces
                    // as `.validation` (PostgrestError, not AuthError) and
                    // stays in the permanent-drop bucket below. `.unauthorized`
                    // specifically means "no valid session right now" (expired
                    // token, mid-sign-out race), which is recoverable once the
                    // SAME user is signed back in — dropping a lifter's already
                    // -captured reps over a recoverable auth hiccup would be a
                    // far worse failure mode than a network blip, and retry is
                    // free (idempotent via the UUID PK either way). The replay
                    // trigger sites (RootView) already gate on `auth.state ==
                    // .signedIn` before calling `replay()` at all, so this case
                    // should be rare in practice — reached only by a race
                    // between the gate check and the actual request.
                    //
                    // Reviewer Finding 3, fix wave 1: "rare in practice" isn't
                    // "never" — bounded via `maxUnauthorizedAttempts` above so
                    // a session that genuinely never comes back doesn't queue
                    // this item forever. Fix wave 2: bumps
                    // `item.unauthorizedAttemptCount` here — NOT the
                    // unconditional `item.attemptCount` already incremented
                    // above for every attempt regardless of outcome — so a
                    // run of `.network` failures can never count toward this
                    // auth-specific threshold; only a real `.unauthorized`
                    // response does. `>=` here means "this was the Nth
                    // unauthorized failure."
                    item.unauthorizedAttemptCount += 1
                    if item.unauthorizedAttemptCount >= Self.maxUnauthorizedAttempts {
                        let message = error.errorDescription ?? "You're signed out. Please sign in again."
                        AppLogger.workout.error("offline set-log \(item.id, privacy: .public) dropped after \(item.unauthorizedAttemptCount) unauthorized attempts: \(message, privacy: .public)")
                        lastPermanentFailure = (item.id, message)
                        remove(item, modelContext: modelContext)
                        // Deliberately falls through to the next item (no
                        // `return`) — matches the `default:` permanent-drop
                        // case's behavior below, not `.network`'s pass-stopping
                        // behavior. Only this one stale item exceeded its
                        // budget; a fresher item later in the same pass hasn't,
                        // and still deserves its own "stop the pass" chance if
                        // it also hits `.unauthorized`.
                    } else {
                        try? modelContext.save()
                        return
                    }
                default:
                    let message = error.errorDescription ?? "Couldn't save that set."
                    AppLogger.workout.error("offline set-log \(item.id, privacy: .public) dropped permanently: \(message, privacy: .public)")
                    lastPermanentFailure = (item.id, message)
                    remove(item, modelContext: modelContext)
                }
            } catch {
                // SessionRepository.logSet always wraps via ErrorMapping, so
                // this branch shouldn't be reachable in production — kept
                // conservative (drop, don't wedge the pass on a malformed
                // item forever) rather than looping on an unrecognized error.
                let message = error.localizedDescription
                AppLogger.workout.error("offline set-log \(item.id, privacy: .public) unmapped error: \(message, privacy: .public)")
                lastPermanentFailure = (item.id, message)
                remove(item, modelContext: modelContext)
            }
        }
    }

    /// Clears the observable replay-failure surface (HomeView's dismissible
    /// notice, debt-zero sprint item 2, `DesignSystem/GSComponents.swift`'s
    /// `GSInlineNoticeBanner.onDismiss`) — called ONLY on user dismissal.
    /// Deliberately does NOT get cleared by anything else (a later
    /// SUCCESSFUL `replay()` pass leaves it alone; only a NEW permanent
    /// drop reassigns it, in `replay()` itself, or an explicit dismissal
    /// here). "Must not re-appear forever" (task brief) means "does not
    /// re-show the SAME dismissed failure," not "auto-dismisses on its
    /// own" — a genuinely NEW future permanent drop is new information and
    /// SHOULD surface again.
    func clearLastPermanentFailure() {
        lastPermanentFailure = nil
    }

    /// Purges every locally queued row belonging to one user — called ONLY
    /// by `AuthService.forceSignedOutAfterDeletion()` (debt-zero sprint
    /// item 3), after that user's `auth.users` row has already been
    /// hard-deleted server-side. Unlike `signOut()`'s DELIBERATE non-purge
    /// (see that function's own doctrine comment in AuthService.swift —
    /// this device may hold this user's own not-yet-synced reps, and that
    /// user can sign back in later to drain them normally), a deleted
    /// account can NEVER sign back in, so its queued rows can never be
    /// replayed — leaving them queued would only mean silently discarding
    /// them LATER via `pruneExpired()`'s 90-day window (or via `replay()`'s
    /// permanent-drop bucket hitting an auth failure on some future
    /// trigger) instead of NOW, for no benefit either way. Cites the Phase
    /// O gate ledger entry that first named this gap: "forceSignedOut
    /// AfterDeletion could purge the deleted user's queue rows (inert +
    /// 90d-pruned meanwhile — nice-to-have)" (`.superpowers/sdd/
    /// progress.md`, gate fix de85ec4).
    ///
    /// Scoped to `userID` (like `replay()`/`refreshPendingIDs()`, UNLIKE
    /// `pruneExpired()`'s deliberately global sweep) — this device may
    /// still hold OTHER, still-legitimate users' queued rows that must not
    /// be touched by one user's own deletion.
    ///
    /// Lock discipline: none needed, matching this class's existing
    /// internals (`remove`/`pruneExpired`/`refreshPendingIDs` above) — the
    /// whole class is `@MainActor`-isolated, so every `ModelContext` touch
    /// (including this one) is already serialized by the actor itself.
    /// `SessionCalendarSyncStore`'s `NSLock` (Models/
    /// SessionCalendarSyncStore.swift) exists for the OPPOSITE reason: it's
    /// a plain `enum` with `static` functions and no actor isolation at
    /// all, called from multiple independent `Task`s with nothing else
    /// serializing them — an `NSLock` here would be redundant, not
    /// additive safety, since MainActor isolation already rules out the
    /// exact interleaved-mutation race that store's lock exists to close.
    func purge(userID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<PendingSetLog>(predicate: #Predicate { $0.userID == userID })
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }
        for item in items {
            AppLogger.workout.notice("purging offline set-log \(item.id, privacy: .public) for deleted user \(userID, privacy: .public)")
            modelContext.delete(item)
            pendingSetLogIDs.remove(item.id)
        }
        try? modelContext.save()
    }

    /// Drops one queued set by id (delete-set flow, 2026-07-26): a set the
    /// user deleted while it was still offline-pending must leave the queue
    /// too, or the next replay would RESURRECT it on the server after the
    /// UI showed it gone. No-op when the id isn't queued (already synced —
    /// the server delete handles it).
    func discard(id: UUID) {
        guard let modelContext, pendingSetLogIDs.contains(id) else { return }
        let descriptor = FetchDescriptor<PendingSetLog>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else {
            pendingSetLogIDs.remove(id)
            return
        }
        remove(item, modelContext: modelContext)
    }

    // MARK: - Internals

    private func remove(_ item: PendingSetLog, modelContext: ModelContext) {
        modelContext.delete(item)
        try? modelContext.save()
        pendingSetLogIDs.remove(item.id)
    }

    /// Spec's 90-day local window. Logs what's dropped (brief's explicit
    /// "log what's dropped" requirement) — these are old enough that
    /// whatever session they belonged to is long past the ledger/stats
    /// windows that read `set_logs`, so silently losing them is the
    /// accepted trade-off of the window, not a bug; the log line exists so
    /// it's traceable if a user ever reports a missing old set.
    ///
    /// ADJUDICATION (gate finding, user-scoping fix): deliberately NOT
    /// scoped to `userIDProvider.currentUserID`, unlike `replay()` and
    /// `refreshPendingIDs()`. This is pure age-based local housekeeping —
    /// it only ever deletes from the on-device store, it never talks to the
    /// server — so pruning a DIFFERENT user's ancient (>90d) rows on a
    /// shared device is harmless and arguably correct (nobody's still
    /// waiting on a 90-day-stale queued set regardless of whose it is).
    /// Scoping this pass would just leave other users' stale rows to pile
    /// up forever on a device they may never sign back into.
    private func pruneExpired(modelContext: ModelContext) {
        let cutoff = Date().addingTimeInterval(-Self.retentionWindow)
        let descriptor = FetchDescriptor<PendingSetLog>(
            predicate: #Predicate { $0.enqueuedAt < cutoff }
        )
        guard let expired = try? modelContext.fetch(descriptor), !expired.isEmpty else { return }
        for item in expired {
            AppLogger.workout.notice("pruning stale offline set-log \(item.id, privacy: .public), enqueued \(item.enqueuedAt, privacy: .public) (>90d old)")
            modelContext.delete(item)
            pendingSetLogIDs.remove(item.id)
        }
        try? modelContext.save()
    }

    /// Rebuilds `pendingSetLogIDs` for the CURRENT signed-in user only (gate
    /// finding — class doc comment). Not `private`: `configure()` below
    /// calls it once at setup, and `RootView`'s auth-transition hook
    /// (`.onChange(of: auth.state)`) also calls it directly so a shared
    /// device re-syncs the in-memory badge cache on EVERY sign-in/sign-out,
    /// not just at cold launch — otherwise user B could briefly inherit
    /// user A's "syncing" chips left over in memory from A's session.
    /// No signed-in user → empty set, not "leave whatever was there": a
    /// prior user's IDs must not linger across the transition either.
    func refreshPendingIDs() {
        guard let modelContext else { return }
        guard let userID = userIDProvider.currentUserID else {
            pendingSetLogIDs = []
            return
        }
        let descriptor = FetchDescriptor<PendingSetLog>(predicate: #Predicate { $0.userID == userID })
        let items = (try? modelContext.fetch(descriptor)) ?? []
        pendingSetLogIDs = Set(items.map(\.id))
    }
}
