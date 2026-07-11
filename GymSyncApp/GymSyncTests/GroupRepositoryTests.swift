import XCTest
@testable import GymSync

final class GroupRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testCreateGroupBootstrapsSelfAsAdminThenAddMemberAndCleanup() async throws {
        let group = try await GroupRepository.create(name: "CI Test Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        // Creator appears as admin
        let members = try await GroupRepository.members(groupID: group.id)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.member.role, .admin)

        // Group appears in myGroups
        let mine = try await GroupRepository.myGroups()
        XCTAssertTrue(mine.contains { $0.id == group.id })

        // Admin adds the counterpart account
        try await GroupRepository.addMember(groupID: group.id, username: "ci_test_user_2")
        let after = try await GroupRepository.members(groupID: group.id)
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(after.contains { $0.profile.username == "ci_test_user_2" })

        // Explicit cleanup (defer above is a safety net)
        try await GroupRepository.deleteGroup(groupID: group.id)
        let gone = try await GroupRepository.myGroups()
        XCTAssertFalse(gone.contains { $0.id == group.id })
    }

    func testAddUnknownMemberThrowsNotFound() async throws {
        let group = try await GroupRepository.create(name: "CI Ghost Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }
        do {
            try await GroupRepository.addMember(groupID: group.id, username: "no_such_user_zzz")
            XCTFail("expected notFound")
        } catch let error as GymSyncError {
            guard case .notFound = error else {
                return XCTFail("expected .notFound, got \(error)")
            }
        }
        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
