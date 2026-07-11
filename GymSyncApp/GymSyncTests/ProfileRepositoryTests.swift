import XCTest
@testable import GymSync

final class ProfileRepositoryTests: XCTestCase {
    // These run unauthenticated (anon role): RLS hides all rows, which still
    // exercises the decode + not-found paths without needing a live session.

    func testUsernameAvailabilityForFreshName() async throws {
        let unique = "test_" + UUID().uuidString.prefix(8).lowercased()
        let available = try await ProfileRepository.usernameAvailable(String(unique))
        XCTAssertTrue(available)
    }

    func testFetchNilWhenNoProfile() async throws {
        // For a fresh UUID with no profile row.
        let randomID = UUID()
        let profile = try await ProfileRepository.fetch(userID: randomID)
        XCTAssertNil(profile)
    }

    func testFetchByUsernameFindsSecondCIUser() async throws {
        try await TestAuth.signInIfConfigured()
        let profile = try await ProfileRepository.fetchByUsername("ci_test_user_2")
        XCTAssertNotNil(profile, "seeded counterpart account must exist (run scripts/create_second_test_user.js)")
        XCTAssertEqual(profile?.username, "ci_test_user_2")
    }
}
