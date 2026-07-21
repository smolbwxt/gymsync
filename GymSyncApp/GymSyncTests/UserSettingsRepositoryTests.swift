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
        XCTAssertEqual(settings.palette, "onyx")   // redesign 20260728000007: Onyx is the new default
        XCTAssertEqual(settings.accent, "sky")
    }

    // MARK: - Pure defaults (no network)

    func testDefaultsUseOnyxAndSky() {
        let s = UserSettings.defaults(userID: UUID())
        XCTAssertEqual(s.palette, "onyx")
        XCTAssertEqual(s.accent, "sky")
    }

    func testUpsertRoundTripInsertsThenUpdates() async throws {
        // `userID` here is a throwaway — UserSettingsRepository.upsert always
        // re-derives the real authenticated user id itself rather than
        // trusting the struct's field (documented on the repository).
        let first = UserSettings(
            userID: UUID(),
            defaultRestSeconds: 150,
            palette: "arena",
            updatedAt: Date(),
            shareHeartRate: true,
            accent: "amber"
        )
        try await UserSettingsRepository.upsert(first)

        let fetched = try await UserSettingsRepository.get()
        XCTAssertEqual(fetched.defaultRestSeconds, 150)
        XCTAssertEqual(fetched.palette, "arena")
        // Redesign: proves `UserSettingsUpsert` actually carries `accent` over
        // the wire — same live-DB guard against the "field on the model but
        // missing from the Upsert struct silently never persists" bug that the
        // `shareHeartRate` assertion below defends against.
        XCTAssertEqual(fetched.accent, "amber")
        // Phase W Task 4 — proves `UserSettingsUpsert` actually carries
        // `shareHeartRate` over the wire (live DB round trip, not just a
        // Codable unit test): if a future edit re-introduces the
        // `updated_at`-class bug (a field on `UserSettings` but missing from
        // `UserSettingsUpsert`), this assertion fails instead of silently
        // passing with a stale `false`.
        XCTAssertTrue(fetched.shareHeartRate)

        // Second upsert — same row (primary key on user_id), not a duplicate.
        var second = fetched
        second.defaultRestSeconds = 90
        second.palette = "ink"
        second.shareHeartRate = false
        second.accent = "lime"
        try await UserSettingsRepository.upsert(second)

        let refetched = try await UserSettingsRepository.get()
        XCTAssertEqual(refetched.defaultRestSeconds, 90)
        XCTAssertEqual(refetched.palette, "ink")
        XCTAssertFalse(refetched.shareHeartRate)
        XCTAssertEqual(refetched.accent, "lime")
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
