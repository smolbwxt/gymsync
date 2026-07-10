import XCTest
import Supabase

final class SupabaseImportTests: XCTestCase {
    func testSDKCanBeImported() {
        // If this test compiles + runs, the SDK is wired.
        let url = URL(string: "https://example.supabase.co")!
        let client = SupabaseClient(supabaseURL: url, supabaseKey: "anon-key-placeholder")
        XCTAssertNotNil(client.auth)
    }
}
