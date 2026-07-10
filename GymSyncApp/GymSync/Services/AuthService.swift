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
