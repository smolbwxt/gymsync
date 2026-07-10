import XCTest
@testable import GymSync

final class SupabaseServiceTests: XCTestCase {
    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(SupabaseService.shared)
    }

    func testSharedInstanceUsesConfiguredURL() {
        XCTAssertEqual(SupabaseService.shared.client.supabaseURL, Secrets.supabaseURL)
    }

    func testCurrentUserIDIsNilWhenSignedOut() async {
        let id = await SupabaseService.shared.currentUserID()
        XCTAssertNil(id, "no user should be signed in during unit test")
    }
}
