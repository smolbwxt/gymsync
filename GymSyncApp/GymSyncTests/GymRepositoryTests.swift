import XCTest
@testable import GymSync

final class GymRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    /// The `gyms` table has a unique partial index allowing at most one
    /// `is_primary = true` row per user, so a naive second INSERT would
    /// violate that index. This asserts `upsertPrimary` instead UPDATEs the
    /// existing primary row in place: same row id survives across both calls,
    /// and the second call's fields (including radius) win.
    func testUpsertPrimaryCreatesThenUpdates() async throws {
        // Clean slate: delete any existing gyms for this user so the test exercises
        // both INSERT (first upsert) and UPDATE (second upsert) paths.
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in")
            return
        }
        try await SupabaseService.shared.client
            .from("gyms")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .execute()

        let first = try await GymRepository.upsertPrimary(
            name: "Test Gym A \(UUID().uuidString.prefix(6))",
            latitude: 37.7955,
            longitude: -122.3937,
            radiusMeters: 200
        )
        XCTAssertTrue(first.isPrimary)
        XCTAssertEqual(first.radiusMeters, 200)

        let secondName = "Test Gym B \(UUID().uuidString.prefix(6))"
        let second = try await GymRepository.upsertPrimary(
            name: secondName,
            latitude: 40.7128,
            longitude: -74.0060,
            radiusMeters: 150
        )

        // Same row updated in place, not a second row.
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.name, secondName)
        XCTAssertEqual(second.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(second.longitude, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(second.radiusMeters, 150)
        XCTAssertTrue(second.isPrimary)

        // Confirm the read path agrees — still exactly one primary gym.
        let fetched = try await CheckInService.primaryGym()
        XCTAssertEqual(fetched?.id, first.id)
        XCTAssertEqual(fetched?.radiusMeters, 150)
    }
}
