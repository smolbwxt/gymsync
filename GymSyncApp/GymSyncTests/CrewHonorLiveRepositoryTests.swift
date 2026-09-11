import XCTest
@testable import GymSync

/// `group_consistency_honor` against the live project, as the CI account.
/// READ-ONLY: this test writes nothing, so it has no teardown to register —
/// the row it reads is `scripts/seed_qa_fixtures.js`'s own `[QA] Push Crew`.
final class CrewHonorLiveRepositoryTests: XCTestCase {

    func testTheHonorRPCDecodes() async throws {
        try await TestAuth.signInIfConfigured()
        let groups = try await GroupRepository.myGroups()
        let crew = groups.first { $0.name.hasPrefix("[QA] ") }
        let group = try XCTUnwrap(crew, "seed_qa_fixtures.js has not run for this account")

        // Bind, THEN unwrap — `XCTUnwrap(await …)` is a compile error in this
        // target's Swift mode (global constraint 4).
        let rows = try await GroupRepository.consistencyHonor(groupID: group.id)
        XCTAssertFalse(rows.isEmpty,
                       "the seeded crew has one completed session with a participant row")
        let crown = try XCTUnwrap(CrewHonorMath.crown(rows))
        XCTAssertGreaterThan(crown.sessions, 0)
    }
}
