import Foundation
import Supabase

@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: Secrets.supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }

    func currentUserID() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            AppLogger.auth.debug("no active session: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
