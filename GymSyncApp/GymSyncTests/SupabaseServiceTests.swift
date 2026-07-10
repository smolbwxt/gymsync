import XCTest
@testable import GymSync

final class SupabaseServiceTests: XCTestCase {
    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(SupabaseService.shared)
    }

    // Note: client.supabaseURL is internal in supabase-swift v2, so URL
    // configuration can't be asserted directly; auth availability stands in.
    func testClientAuthIsAvailable() {
        XCTAssertNotNil(SupabaseService.shared.client.auth)
    }

    func testCurrentUserIDIsNilAfterSignOut() async {
        // Other test classes may have signed in the CI test user; sign out
        // first so this assertion is order-independent.
        try? await SupabaseService.shared.signOut()
        let id = await SupabaseService.shared.currentUserID()
        XCTAssertNil(id, "no user should be signed in after sign-out")
    }
}
