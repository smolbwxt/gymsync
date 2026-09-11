import XCTest
@testable import GymSync

/// `group_consistency_honor` against the live project, as the CI account.
/// READ-ONLY: this test writes nothing, so it has no teardown to register —
/// the crew it reads is `scripts/seed_qa_fixtures.js`'s own `[QA] Push Crew`.
///
/// WHAT THIS CAN AND CANNOT PROVE, and why it is not "the seeded crew has a
/// crown". `scripts/seed_qa_fixtures.js` runs in the **screenshots** job
/// (`ios.yml:195-211`), which declares `needs: build-test` (`ios.yml:126`) —
/// the job these unit tests run in. A build-test assertion about seed content
/// the seed has not written yet can therefore never go green: the seed is
/// gated behind the very job that would be asserting on it, which is a
/// deadlock, not a flake. (This is the only file in `GymSyncTests` that reads
/// the `[QA]` world at all — grep-verified — so there was no precedent
/// carrying the dependency.)
///
/// What is left is not vacuous. The call itself is the assertion: before
/// migration 20260911000001 was applied to the live project this threw
/// `42883 undefined_function`, and without the `GRANT ... TO authenticated`
/// it would throw insufficient_privilege; a member reaching rows at all
/// proves the function exists, is gated the way the migration says, and that
/// its columns decode into `CrewHonorRow`. The row-shape and crown
/// invariants below hold whether the window is populated or empty.
///
/// The seed -> RPC -> crown -> line end-to-end proof is the `app-tab-social`
/// capture (plan task S1.4), which runs in the screenshots job *after* the
/// seed — the one place in this pipeline where that claim can be made
/// honestly.
final class CrewHonorLiveRepositoryTests: XCTestCase {

    func testTheHonorRPCDecodes() async throws {
        try await TestAuth.signInIfConfigured()
        let groups = try await GroupRepository.myGroups()
        let crew = groups.first { $0.name.hasPrefix("[QA] ") }
        let group = try XCTUnwrap(crew, "seed_qa_fixtures.js has not run for this account")

        // Bind, THEN unwrap — `XCTUnwrap(await …)` is a compile error in this
        // target's Swift mode (global constraint 4). A throw here fails the
        // test, which is the point: this line is the reachability assertion.
        let rows = try await GroupRepository.consistencyHonor(groupID: group.id)

        // Every row the RPC hands back is a member who trained in the window:
        // the migration filters `COALESCE(session_count, 0) > 0` server-side,
        // so a zero row reaching the client is a regression in the function.
        for row in rows {
            XCTAssertGreaterThan(row.sessions, 0,
                                 "the RPC filters out members with no qualifying session")
            XCTAssertFalse(row.username.isEmpty, "every honor row names a member")
        }

        // Spec §3's decay, as an invariant rather than a fixture: a crew with
        // rows has exactly one crown, and a crew at rest has none at all —
        // never a crown reading zero.
        let crown = CrewHonorMath.crown(rows)
        if rows.isEmpty {
            XCTAssertNil(crown, "a crew nobody has trained with has no honor line")
        } else {
            let held = try XCTUnwrap(crown, "rows exist, so one of them is the crown")
            XCTAssertGreaterThan(held.sessions, 0)
            XCTAssertEqual(held.sessions, rows.map(\.sessions).max(),
                           "the crown holds the highest session count in the window")
        }
    }
}
