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
}
