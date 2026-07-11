import XCTest
@testable import GymSync

final class FriendRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        // Clean slate: remove any leftover request to the counterpart account
        if let other = try await ProfileRepository.fetchByUsername("ci_test_user_2") {
            try? await FriendRepository.removeFriendship(with: other.id)
        }
    }

    func testSendRequestAppearsInOutgoingThenCancel() async throws {
        try await FriendRepository.sendRequest(toUsername: "ci_test_user_2")

        let outgoing = try await FriendRepository.outgoingRequests()
        XCTAssertTrue(outgoing.contains { $0.username == "ci_test_user_2" },
                      "sent request must appear in outgoing list")

        let other = try await ProfileRepository.fetchByUsername("ci_test_user_2")!
        try await FriendRepository.removeFriendship(with: other.id)

        let after = try await FriendRepository.outgoingRequests()
        XCTAssertFalse(after.contains { $0.username == "ci_test_user_2" },
                       "cancelled request must disappear")
    }

    func testSendRequestToUnknownUsernameThrowsNotFound() async throws {
        do {
            try await FriendRepository.sendRequest(toUsername: "no_such_user_zzz")
            XCTFail("expected notFound")
        } catch let error as GymSyncError {
            guard case .notFound = error else {
                return XCTFail("expected .notFound, got \(error)")
            }
        }
    }
}
