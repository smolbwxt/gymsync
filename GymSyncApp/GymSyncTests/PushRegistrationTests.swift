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

        let device = try await PushDeviceRepository.upsert(token: token)
        XCTAssertEqual(device.userID, userID)
        XCTAssertEqual(device.apnsToken, PushDeviceRepository.hexEncode(token))

        // Re-upsert the same token — updates the same row (conflict target
        // is apns_token), doesn't create a duplicate.
        let device2 = try await PushDeviceRepository.upsert(token: token)
        XCTAssertEqual(device2.id, device.id)
    }

    func testPushDeviceDeleteOwnDevicesOnSignOut() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let token = Data("push-test-signout-\(UUID().uuidString)".utf8)
        _ = try await PushDeviceRepository.upsert(token: token)

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
