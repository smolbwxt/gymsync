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
        try await SupabaseService.shared.signOut()
        state = .signedOut
    }

    func refreshSession() async throws {
        _ = try await SupabaseService.shared.client.auth.refreshSession()
        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        }
    }
}
