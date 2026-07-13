import XCTest
@testable import GymSync

final class PushRegistrationTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    // MARK: - Hex encoding (pure function, no network)

    func testHexEncodeKnownBytes() {
        let data = Data([0x00, 0x01, 0x0a, 0xff])
        XCTAssertEqual(PushDeviceRepository.hexEncode(data), "00010aff")
    }

    func testHexEncodeEmptyData() {
        XCTAssertEqual(PushDeviceRepository.hexEncode(Data()), "")
    }

    // MARK: - PushDeviceRepository upsert round-trip

    func testPushDeviceUpsertRoundTrip() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        // Unique-per-run fake token so repeated CI runs don't collide on the
        // apns_token UNIQUE constraint from a prior run's leftover row.
        let token = Data("push-test-\(UUID().uuidString)".utf8)
        let hexToken = PushDeviceRepository.hexEncode(token)

        // upsert() now delegates to the register_push_device RPC (returns
        // Void — see 20260716000007_register_push_device.sql), so verify the
        // round trip by reading the row back directly.
        try await PushDeviceRepository.upsert(token: token)
        let rows: [PushDevice] = try await SupabaseService.shared.client
            .from("push_devices")
            .select()
            .eq("apns_token", value: hexToken)
            .execute()
            .value
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.userID, userID)
        XCTAssertEqual(rows.first?.apnsToken, hexToken)
        let deviceID = rows.first?.id

        // Re-upsert the same token — updates the same row (conflict target
        // is apns_token), doesn't create a duplicate.
        try await PushDeviceRepository.upsert(token: token)
        let rowsAfter: [PushDevice] = try await SupabaseService.shared.client
            .from("push_devices")
            .select()
            .eq("apns_token", value: hexToken)
            .execute()
            .value
        XCTAssertEqual(rowsAfter.count, 1)
        XCTAssertEqual(rowsAfter.first?.id, deviceID)
    }

    func testPushDeviceDeleteOwnDevicesOnSignOut() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let token = Data("push-test-signout-\(UUID().uuidString)".utf8)
        try await PushDeviceRepository.upsert(token: token)

        try await PushDeviceRepository.deleteOwnDevices()

        // Read back directly rather than trusting the lack of a thrown
        // error — delete() on zero matching rows also succeeds silently.
        let remaining: [PushDevice] = try await SupabaseService.shared.client
            .from("push_devices")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - NotificationPrefsRepository round-trip

    func testNotificationPrefsSetReadDeleteRoundTrip() async throws {
        let category = "chat_mention"

        // Default (no row yet, or leftover from a prior run) — reset first
        // so the test starts from a known state.
        try await NotificationPrefsRepository.reset(category: category)
        let defaultValue = try await NotificationPrefsRepository.isEnabled(category: category)
        XCTAssertTrue(defaultValue)

        // Set false -> read false.
        try await NotificationPrefsRepository.setEnabled(false, category: category)
        let disabled = try await NotificationPrefsRepository.isEnabled(category: category)
        XCTAssertFalse(disabled)

        // Delete -> back to default (true).
        try await NotificationPrefsRepository.reset(category: category)
        let afterReset = try await NotificationPrefsRepository.isEnabled(category: category)
        XCTAssertTrue(afterReset)
    }

    // MARK: - NotificationPreferencesView category/label mapping (Task 6)

    /// Pure data test — no network/auth needed. Verifies the UI's category
    /// -> plain-English label mapping covers exactly the repository's 10
    /// categories, with no duplicate keys or labels, and that exact label
    /// strings match the designer brief (silent rewording caught via
    /// dictionary equality assertion).
    func testNotificationPreferencesCategoryLabelMappingIsComplete() {
        let mapping = NotificationPreferencesView.categoryLabels
        XCTAssertEqual(mapping.count, 10)

        let categories = mapping.map(\.category)
        XCTAssertEqual(Set(categories).count, categories.count, "duplicate category keys")
        XCTAssertEqual(
            Set(categories), Set(NotificationPrefsRepository.categories),
            "mapping must cover exactly the repository's categories"
        )

        let labels = mapping.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "duplicate labels")
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })

        // Assert exact label strings match expected mapping (catches silent rewording)
        let expectedMapping: [String: String] = [
            "friend_request": "Friend requests",
            "session_invite": "Session invites",
            "session_reminder_15min": "15-minute reminders",
            "session_lobby_open": "Lobby is open",
            "your_turn": "It's your turn",
            "partner_pr": "Crew PRs",
            "lateness_chirp": "Late-arrival pings",
            "session_idle": "Idle session nudges",
            "chat_mention": "Mentions in chat",
            "leaderboard_passed": "Leaderboard changes",
        ]
        let actualMapping = Dictionary(uniqueKeysWithValues: mapping)
        XCTAssertEqual(actualMapping, expectedMapping, "notification category labels must match expected strings exactly")
    }
}
