import XCTest
@testable import GymSync

final class StreakRepositoryTests: XCTestCase {
    // These run unauthenticated (anon role): RLS hides all rows, which still
    // exercises the decode + not-found paths without needing a live session.

    func testUserStreakNilWhenNoRow() async throws {
        // For a fresh UUID with no user_streaks row.
        let randomID = UUID()
        let userStreak = try await StreakRepository.userStreak(userID: randomID)
        XCTAssertNil(userStreak)
    }
}
