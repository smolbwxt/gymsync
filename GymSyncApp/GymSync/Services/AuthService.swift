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
        await VoiceRoomService.shared.leave()
        try await SupabaseService.shared.signOut()
        // Phase U (Task 1 fix): wipe the cached stat-tile snapshot so a
        // second user signing into a shared device doesn't see the first
        // user's numbers rendered as their own OFFLINE·STALE-CACHE row.
        // UserDefaults-backed and synchronous — unlike the cleanups above,
        // this can't fail, so there's no try? to swallow.
        StatTilesSnapshotStore.clear()
        state = .signedOut
    }

    func refreshSession() async throws {
        _ = try await SupabaseService.shared.client.auth.refreshSession()
        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        }
    }
}
