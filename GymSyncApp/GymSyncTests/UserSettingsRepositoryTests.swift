import XCTest
@testable import GymSync

final class UserSettingsRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    // MARK: - Repository round trip (live-DB pattern, mirrors GymRepositoryTests)

    func testGetReturnsColumnDefaultsWhenNoRowExists() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in")
            return
        }
        // Clean slate so this exercises the no-row -> defaults path, not
        // whatever a prior test run left behind.
        try await SupabaseService.shared.client
            .from("user_settings")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .execute()

        let settings = try await UserSettingsRepository.get()
        XCTAssertEqual(settings.defaultRestSeconds, 120)
        XCTAssertEqual(settings.palette, "midnight")
    }

    func testUpsertRoundTripInsertsThenUpdates() async throws {
        // `userID` here is a throwaway — UserSettingsRepository.upsert always
        // re-derives the real authenticated user id itself rather than
        // trusting the struct's field (documented on the repository).
        let first = UserSettings(
            userID: UUID(),
            defaultRestSeconds: 150,
            palette: "arena",
            updatedAt: Date()
        )
        try await UserSettingsRepository.upsert(first)

        let fetched = try await UserSettingsRepository.get()
        XCTAssertEqual(fetched.defaultRestSeconds, 150)
        XCTAssertEqual(fetched.palette, "arena")

        // Second upsert — same row (primary key on user_id), not a duplicate.
        var second = fetched
        second.defaultRestSeconds = 90
        second.palette = "ink"
        try await UserSettingsRepository.upsert(second)

        let refetched = try await UserSettingsRepository.get()
        XCTAssertEqual(refetched.defaultRestSeconds, 90)
        XCTAssertEqual(refetched.palette, "ink")
    }

    // MARK: - "m:ss" formatting (pure function, no network required)

    func testFormatRestSecondsWholeMinutes() {
        XCTAssertEqual(UserSettings.formatRestSeconds(60), "1:00")
        XCTAssertEqual(UserSettings.formatRestSeconds(120), "2:00")
        XCTAssertEqual(UserSettings.formatRestSeconds(180), "3:00")
    }

    func testFormatRestSecondsWithRemainderPadsSeconds() {
        XCTAssertEqual(UserSettings.formatRestSeconds(90), "1:30")
        XCTAssertEqual(UserSettings.formatRestSeconds(125), "2:05")
        XCTAssertEqual(UserSettings.formatRestSeconds(65), "1:05")
    }

    func testFormatRestSecondsZeroAndSubMinute() {
        XCTAssertEqual(UserSettings.formatRestSeconds(0), "0:00")
        XCTAssertEqual(UserSettings.formatRestSeconds(45), "0:45")
    }
}
