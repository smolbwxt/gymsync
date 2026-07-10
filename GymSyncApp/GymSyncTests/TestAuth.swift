import XCTest
import Supabase
@testable import GymSync

enum TestAuth {
    /// Signs in as the dedicated CI test user, or skips the test when
    /// TestSecrets holds placeholders (fork PRs, unconfigured local runs).
    static func signInIfConfigured() async throws {
        guard TestSecrets.testUserEmail != "PLACEHOLDER" else {
            throw XCTSkip("TestSecrets not configured — skipping authenticated network test")
        }
        if await SupabaseService.shared.currentUserID() != nil { return }
        _ = try await SupabaseService.shared.client.auth.signIn(
            email: TestSecrets.testUserEmail,
            password: TestSecrets.testUserPassword
        )
    }
}
