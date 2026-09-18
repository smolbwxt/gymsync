import XCTest
@testable import GymSync

/// `crew_week(p_session_id, p_week_start)` against the live project, as the CI
/// account. READ-ONLY: this test writes nothing, so it has no teardown to
/// register — the crew and the sessions it reads are
/// `scripts/seed_qa_fixtures.js`'s own `[QA] Push Crew`.
///
/// A REACHABILITY PROBE, and deliberately nothing more — `CrewHonorLive
/// RepositoryTests`' shape, for the sibling RPC this one is modelled on. The
/// call itself is the assertion: without the migration applied it throws
/// `42883 undefined_function`, without the `GRANT … TO authenticated` it throws
/// insufficient_privilege, and a column rename throws a decoding error.
///
/// It must NOT assert the seeded crew's counts. `seed_qa_fixtures.js` runs in
/// the **screenshots** job, which declares `needs: build-test` — the job these
/// unit tests run in — so an assertion here about seed content the seed has not
/// written yet is a deadlock, not a flake. The seed → RPC → strip end-to-end
/// proof is the `app-lobby` capture, which runs after the seed.
final class CrewWeekLiveRepositoryTests: XCTestCase {

    /// **SKIPPED UNTIL D1 IS APPLIED.** The migration that creates `crew_week`
    /// was written and HELD at its gate under R-B2-8 (the Supabase connector
    /// was unauthorized when this leg ran), and global constraint 8 is explicit
    /// that a test for an object the live project does not have WILL FAIL. The
    /// controller lifts this skip in a fix commit once the apply lands; the
    /// body below is what runs then, unchanged.
    /// Flip to `false` in the fix commit that follows the apply — one line, and
    /// the body below runs unchanged. `XCTSkipIf` rather than a bare
    /// `throw XCTSkip`, so the rest of the test stays reachable code the
    /// compiler keeps checking while the gate is shut.
    private static let d1IsHeldAtItsGate = true

    func testTheCrewWeekRPCDecodes() async throws {
        try XCTSkipIf(Self.d1IsHeldAtItsGate,
                      "D1 (crew_week) is not applied to the live project yet — "
                      + "constraint 8: a live test for an unapplied object "
                      + "fails. Lift this skip with the apply.")

        try await TestAuth.signInIfConfigured()
        let groups = try await GroupRepository.myGroups()
        let crew = groups.first { $0.name.hasPrefix("[QA] ") }
        let group = try XCTUnwrap(crew, "seed_qa_fixtures.js has not run for this account")

        // Bind, THEN unwrap — `XCTUnwrap(await …)` is a compile error in this
        // target's Swift mode.
        let sessions = try await SessionRepository.groupSessions(groupID: group.id)
        let first = sessions.first
        let session = try XCTUnwrap(first, "the seeded crew has no sessions")

        let rows = try await CrewWeekRepository.week(
            sessionID: session.id,
            weekStart: WeekMath.weekStartISO8601())

        // A MEMBER WITH ZERO SESSIONS IS A ROW, not an absence (plan decision
        // 2) — the one way this RPC deliberately departs from
        // `group_consistency_honor`, and the thing a crew's week would lie
        // about if it were dropped.
        XCTAssertFalse(rows.isEmpty,
                       "every participant of the session is a row, trained or not")
        XCTAssertTrue(rows.allSatisfy { $0.done >= 0 })
    }
}
