import Foundation
import Supabase
import AuthenticationServices

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    enum AuthState: Equatable {
        case signedOut
        case signedIn(userID: UUID)
        case pending
    }

    private(set) var state: AuthState = .pending

    private init() {
        Task { await bootstrap() }
    }

    func bootstrap() async {
        #if DEBUG
        // CI screenshot pipeline (infra/ci-screenshots): a debug-only escape
        // hatch so `GymSyncScreenshots` UI tests can reach a signed-in state
        // without automating Sign in with Apple (not automatable against a
        // real Apple ID in CI). Only engages when BOTH env vars are present —
        // `ScreenshotTests` sets them via `XCUIApplication.launchEnvironment`;
        // absent in every other run (including local debug builds and the
        // regular `GymSyncTests` unit-test target), so this is a no-op there.
        // Compile-gated out of release builds entirely.
        if let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"],
           let password = ProcessInfo.processInfo.environment["UITEST_PASSWORD"] {
            do {
                let session = try await SupabaseService.shared.client.auth.signIn(
                    email: email,
                    password: password
                )
                state = .signedIn(userID: session.user.id)
                AppLogger.auth.info("UI test autologin succeeded")
                return
            } catch {
                AppLogger.auth.error("UI test autologin failed: \(error.localizedDescription, privacy: .public)")
                // Fall through to the normal bootstrap path below.
            }
        }
        #endif

        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        } else {
            state = .signedOut
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
        )
        state = .signedIn(userID: session.user.id)
        AppLogger.auth.info("signed in as \(session.user.id, privacy: .public)")
    }

    func signOut() async throws {
        // Best-effort, and must run BEFORE the Supabase session is torn
        // down — push_devices' owner-only RLS policy needs an authenticated
        // auth.uid() to match. A failed cleanup here must never block
        // sign-out itself (a stray device row just means a future push to a
        // token nobody's listening on anymore; push-dispatcher already
        // handles dead tokens via APNs' 410/BadDeviceToken response).
        try? await PushDeviceRepository.deleteOwnDevices()
        // Phase 3e (Task 3): sign-out must leave any active voice room and
        // restore the audio session — never throws, so this can't block
        // sign-out itself, and it's a harmless no-op if no room was ever
        // joined (VoiceRoomService.leave() is idempotent from `.idle`).
        // Phase O Task 5 (3e follow-up queue item 1): bounded to 2s —
        // `leave()`'s own `await room.disconnect()` is LiveKit's network
        // teardown and could hang on a wedged connection; sign-out must
        // proceed regardless. See VoiceRoomService.leave(timeout:)'s doc
        // comment for the full contract (it logs and lets the real
        // teardown keep running in the background rather than blocking).
        await VoiceRoomService.shared.leave(timeout: .seconds(2))
        try await SupabaseService.shared.signOut()
        // Phase U (Task 1 fix): wipe the cached stat-tile snapshot so a
        // second user signing into a shared device doesn't see the first
        // user's numbers rendered as their own OFFLINE·STALE-CACHE row.
        // UserDefaults-backed and synchronous — unlike the cleanups above,
        // this can't fail, so there's no try? to swallow.
        StatTilesSnapshotStore.clear()
        // Phase H Task 2: same "second user on a shared device must not
        // inherit the first user's local state" reasoning as
        // StatTilesSnapshotStore.clear() above — wipes the local
        // session_id->eventIdentifier mapping AND the calendar-sync toggle
        // itself, so a second user signing in sees the toggle back at its
        // true default (OFF) rather than inheriting the first user's
        // choice. See SessionCalendarSyncStore.swift's doc comments for why
        // this doesn't touch the calendar itself (no bulk EKEvent deletion
        // on sign-out).
        SessionCalendarSyncStore.clear()
        CalendarSyncPrefsStore.clear()
        // Compliance review fix: drop the cached profile alongside the auth
        // state change so a stale (possibly now-deleted, see
        // `forceSignedOutAfterDeletion()`) profile can't linger in the
        // `AppState` singleton and get read by `RootView`/tab views before
        // the next sign-in's refetch. Both `AuthService` and `AppState` are
        // `@MainActor` singletons, so this cross-object write is a same-
        // actor synchronous assignment — no isolation hop needed (matches
        // the existing direct-write precedent in
        // `CatalogHostView.content_sessionChat`, which sets
        // `AppState.shared.currentProfile` the same way).
        AppState.shared.currentProfile = nil
        // Fix wave 1 (Task 6 review, CRITICAL): same shared-device reasoning
        // as StatTilesSnapshotStore/SessionCalendarSyncStore/
        // CalendarSyncPrefsStore/currentProfile above — chatDrafts is keyed
        // by conversation UUID only, so a second user signing into a shared
        // device would otherwise inherit the first user's unsent draft text
        // via ChatView.onAppear (AppState.chatDrafts' doc comment).
        AppState.shared.chatDrafts.removeAll()
        // Same shared-device reasoning: a pending push route (deep-link
        // UUID) consumed by the NEXT account's HomeView is cross-account
        // state, even though RLS makes the fetch a silent no-op in the
        // common case.
        AppState.shared.pendingRoute = nil
        // Deliberately NOT cleared here: `OfflineSetLogQueue`'s SwiftData-
        // backed pending-writes queue (Services/OfflineSetLogQueue.swift).
        // This looks like the same shared-device gap as chatDrafts/
        // pendingRoute/currentProfile above, but it isn't — a gate finding
        // caught an actual instance of the naive fix (clear-on-signout)
        // being WORSE than doing nothing: this device may hold this user's
        // own not-yet-synced reps (still offline, or online but not yet
        // drained), and wiping them here would silently destroy real
        // workout data the lifter believes is saved. The finding also
        // caught the OPPOSITE failure mode of leaving the queue
        // unscoped — the next user to sign in on this device would have
        // their auth-transition drain (`RootView`'s `.onChange(of:
        // auth.state)`) replay THIS user's still-queued rows under the
        // next user's Supabase session, hitting an RLS denial that
        // `OfflineSetLogQueue.replay()`'s permanent-drop bucket would then
        // silently discard — losing this user's reps AND submitting their
        // set content under someone else's identity.
        // Fix (see `OfflineSetLogQueue`'s class doc comment): every row
        // already carries `PendingSetLog.userID`, so `replay()` and
        // `refreshPendingIDs()` now scope to rows where `userID` equals the
        // CURRENTLY signed-in user's id instead. That makes leaving the
        // queue unscoped by sign-out actually SAFE: this user's queued rows sit invisible
        // and unreplayable to anyone else until this same user signs back
        // in on this device, at which point they drain normally — the
        // honest fix, not clear-on-signout's data loss.
        state = .signedOut
    }

    /// Best-effort local teardown called ONLY after
    /// `AccountDeletionRepository.deleteAccount()` has already returned
    /// successfully. At that point `account-deletion-cascade` has
    /// hard-deleted this user's `auth.users` row server-side — the local
    /// Supabase session is already orphaned, so revoking it locally
    /// (`SupabaseService.shared.signOut()`) can throw (e.g. the
    /// now-nonexistent user's session rejects the request). For an
    /// irreversible action, "cascade succeeded" is the point of no return:
    /// a local-cleanup failure must never look like "deletion failed," so
    /// unlike `signOut()` this method is declared non-throwing and swallows
    /// every error from the local revoke — it always lands the app in
    /// `.signedOut`, unconditionally.
    func forceSignedOutAfterDeletion() async {
        // Debt-zero sprint item 3 (Phase O gate ledger, gate fix de85ec4:
        // "forceSignedOutAfterDeletion could purge the deleted user's
        // queue rows (inert + 90d-pruned meanwhile — nice-to-have)").
        // Captured from `state` BEFORE anything below overwrites it — this
        // function is only ever called while `state` is still `.signedIn`
        // for the account that's just been hard-deleted server-side
        // (`DeleteAccountSheet.performDelete()`'s sole call site, right
        // after `AccountDeletionRepository.deleteAccount()` returns).
        // Unlike `signOut()` above, whose doctrine comment explains why
        // that path deliberately does NOT purge (the user can sign back
        // in and drain the queue normally), THIS user never can — the
        // account is gone, so its queued rows can never sync.
        if case .signedIn(let userID) = state {
            OfflineSetLogQueue.shared.purge(userID: userID)
        }
        try? await SupabaseService.shared.signOut()
        AppState.shared.currentProfile = nil
        // Fix wave 1 (Task 6 review, CRITICAL): same gap as signOut() above
        // — this path also lands a shared device at .signedOut without
        // clearing chatDrafts, so it needs the identical clear.
        AppState.shared.chatDrafts.removeAll()
        AppState.shared.pendingRoute = nil
        state = .signedOut
    }

    func refreshSession() async throws {
        _ = try await SupabaseService.shared.client.auth.refreshSession()
        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        }
    }
}
