import XCTest
@testable import GymSync

/// `group_consistency_honor` against the live project, as the CI account.
/// READ-ONLY: this test writes nothing, so it has no teardown to register —
/// the crew it reads is `scripts/seed_qa_fixtures.js`'s own `[QA] Push Crew`.
///
/// A REACHABILITY PROBE, and deliberately nothing more. The call itself is the
/// assertion: before migration 20260911000001 was applied to the live project
/// this threw `42883 undefined_function`, without the
/// `GRANT ... TO authenticated` it would throw insufficient_privilege, and a
/// column rename would throw a decoding error. One live assertion rides along
/// — that the server-side `COALESCE(session_count, 0) > 0` filter holds, which
/// no other test in this suite covers from the client side.
///
/// What this must NOT do is assert the seeded crew has a crown.
/// `scripts/seed_qa_fixtures.js` runs in the **screenshots** job
/// (`ios.yml:195-211`), which declares `needs: build-test` (`ios.yml:126`) —
/// the job these unit tests run in. An assertion here about seed content the
/// seed has not written yet is a deadlock, not a flake. The crown's own
/// behaviour is unit-tested in `CrewHonorMathTests`; the seed -> RPC -> crown
/// -> line end-to-end proof is the `app-tab-social` capture, which runs after
/// the seed and now waits for the line before the shutter.
final class CrewHonorLiveRepositoryTests: XCTestCase {

    func testTheHonorRPCDecodes() async throws {
        try await TestAuth.signInIfConfigured()
        let groups = try await GroupRepository.myGroups()
        let crew = groups.first { $0.name.hasPrefix("[QA] ") }
        let group = try XCTUnwrap(crew, "seed_qa_fixtures.js has not run for this account")

        // Bind, THEN unwrap — `XCTUnwrap(await …)` is a compile error in this
        // target's Swift mode (global constraint 4). A throw here fails the
        // test, which is the point.
        let rows = try await GroupRepository.consistencyHonor(groupID: group.id)

        // The migration filters members with no qualifying session out
        // server-side, so a zero row reaching the client is a regression in
        // the function.
        XCTAssertTrue(rows.allSatisfy { $0.sessions > 0 },
                      "the RPC returns only members who trained in the window")
    }
}
