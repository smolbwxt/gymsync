import XCTest
@testable import GymSync

final class ModerationRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        // Clean slate: make sure a leftover block on the counterpart account
        // from a previous failed run doesn't make testBlockUnblockLifecycle's
        // "contains" assertion ambiguous with prior state.
        if let other = try await ProfileRepository.fetchByUsername("ci_test_user_2") {
            try? await ModerationRepository.unblock(userID: other.id)
        }
    }

    func testBlockUnblockLifecycle() async throws {
        guard let other = try await ProfileRepository.fetchByUsername("ci_test_user_2") else {
            XCTFail("seeded counterpart account must exist (run scripts/create_second_test_user.js)")
            return
        }
        defer { Task { try? await ModerationRepository.unblock(userID: other.id) } }

        try await ModerationRepository.block(userID: other.id)

        let blocked = try await ModerationRepository.blockedUsers()
        XCTAssertTrue(blocked.contains { $0.id == other.id },
                      "blocked user must appear in blockedUsers()")

        try await ModerationRepository.unblock(userID: other.id)

        let after = try await ModerationRepository.blockedUsers()
        XCTAssertFalse(after.contains { $0.id == other.id },
                       "unblocked user must disappear from blockedUsers()")
    }

    func testReportInsert() async throws {
        guard let other = try await ProfileRepository.fetchByUsername("ci_test_user_2") else {
            XCTFail("seeded counterpart account must exist (run scripts/create_second_test_user.js)")
            return
        }
        // `user_reports` is insert-only from the client (no UPDATE/DELETE
        // policy — see supabase/migrations/20260721000001_moderation_block_
        // report.sql's "No UPDATE/DELETE policy" note), and
        // ModerationRepository exposes no read-back method for own reports,
        // so there is no row for this test to clean up — asserting no-throw
        // is the full extent of what the repository's public surface allows.
        try await ModerationRepository.report(
            userID: other.id,
            contentType: .profile,
            contentID: other.id,
            reason: "CI test report — safe to ignore"
        )
    }
}
