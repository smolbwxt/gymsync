import XCTest
@testable import GymSync

/// Live-DB integration tests for `SessionKudosRepository` (Fix round 1 —
/// task-4-report.md Finding 3). No coverage previously existed for the
/// kudos client at all.
///
/// Fan-out to N-1 crew members (SessionKudosRepository.send's crew-wide
/// model) genuinely needs a SECOND AUTHENTICATED account, to prove each
/// teammate independently receives their own row as a distinct sender/
/// recipient pair. This harness can't do that: Swift tests never sign in as
/// the seeded counterpart account (ProfileRepositoryTests.swift's
/// documented convention — "Swift tests never sign in as this user; they
/// only target its username/id", scripts/create_second_test_user.js) and
/// no test anywhere in this suite signs in as a third account either
/// (ProposalRepositoryTests.testDuplicateAffectsExerciseThrowsValidation
/// hits the same "only one authenticated account available" wall for its
/// two-participant scenario and falls back to `XCTSkip` for the same
/// reason).
///
/// What IS testable with the one authenticated CI account (`ci_test_user`)
/// plus the seeded, never-signed-in-as counterpart profile
/// (`ci_test_user_2`) as a target id: a send to a SPECIFIC recipient
/// inserts exactly the expected row(s) (testSendToSpecificRecipient...),
/// and the repository's fetch -> per-recipient totals aggregation math over
/// fixture rows (testCountsAggregation...). The N-1 fan-out COUNT itself is
/// covered by GroupRecapView's `#if DEBUG` catalog fixture and device QA
/// (proof-frame-08.png shows all four lifters' counts at once) — not by
/// this live-Supabase suite.
final class SessionKudosTests: XCTestCase {
    private var session: WorkoutSession!
    private var recipientID: UUID!

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        guard let counterpart = try await ProfileRepository.fetchByUsername("ci_test_user_2") else {
            throw XCTSkip("seeded counterpart account missing — run scripts/create_second_test_user.js")
        }
        recipientID = counterpart.id

        // Organizer (me, ci_test_user) + invitee (ci_test_user_2) as
        // session_participants. "participants insertable only by session
        // organizer" RLS (20260709000006_create_sessions.sql:77-79) lets the
        // organizer add ANY user id as a participant — no group/friendship
        // required, same fixture shape activity_feed_test.sql's S3 uses to
        // reach a real second participant without ever authenticating as
        // them. This gives `is_session_participant` a true row for BOTH
        // sender and recipient, which the session_kudos INSERT policy
        // requires for both parties.
        //
        // makeTempScheduledSession (TestSession.swift) registers deleteSession
        // in a teardown block before returning, from setUp — so a throw in any
        // of the three test methods still removes the row. The old tearDown
        // called complete() and called it cleanup: that left the row behind in
        // history(), 3 per build-test run. session_kudos.session_id and
        // session_participants.session_id are both ON DELETE CASCADE
        // (20260720000001_session_kudos.sql:30,
        // 20260709000006_create_sessions.sql:19), so the delete takes the kudos
        // rows and BOTH participant rows — organizer and the ci_test_user_2
        // invitee — with it.
        session = try await makeTempScheduledSession(
            inviteeIDs: [recipientID],
            scheduledFor: Date()
        )
    }

    func testSendToSpecificRecipientInsertsExpectedRow() async throws {
        let before = try await SessionKudosRepository.counts(sessionID: session.id)
        XCTAssertTrue(before.isEmpty, "fresh session starts with no kudos")

        await SessionKudosRepository.send(sessionID: session.id, recipients: [recipientID], emoji: "💪")

        let after = try await SessionKudosRepository.counts(sessionID: session.id)
        XCTAssertEqual(after.count, 1, "exactly one recipient received a row")
        XCTAssertEqual(after[recipientID], 1, "the specific recipient's count is exactly 1")
    }

    func testCountsAggregationMath() async throws {
        // One-row-per-tap (20260720000001_session_kudos.sql: "deliberately
        // no UNIQUE/upsert constraint ... repeated taps ... are additional
        // rows, not an incrementing counter column"), so three taps insert
        // three separate rows. This asserts the REPOSITORY's fetch ->
        // per-recipient totals reduce (SessionKudosRepository.counts), not
        // a server-side counter.
        await SessionKudosRepository.send(sessionID: session.id, recipients: [recipientID], emoji: "💪")
        await SessionKudosRepository.send(sessionID: session.id, recipients: [recipientID], emoji: "🔥")
        await SessionKudosRepository.send(sessionID: session.id, recipients: [recipientID], emoji: "👏")

        let counts = try await SessionKudosRepository.counts(sessionID: session.id)
        XCTAssertEqual(counts[recipientID], 3, "three separate taps aggregate to a per-recipient total of 3")
        XCTAssertEqual(counts.count, 1, "aggregation groups all three rows under the one recipient, not three")
    }

    /// Self-kudos guard (Fix round 1 Finding 2,
    /// 20260720000002_session_pr_counts_and_kudos_guard.sql's
    /// session_kudos_no_self CHECK). `SessionKudosRepository.send` already
    /// filters `recipientID != senderID` client-side, so it can never
    /// exercise this path — this test bypasses the client guard with a raw
    /// insert to prove the SERVER independently rejects it too, matching
    /// session_kudos_test.sql's pgTAP coverage of the same constraint.
    func testSelfKudosRejectedServerSide() async throws {
        guard let myID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        do {
            try await SupabaseService.shared.client
                .from("session_kudos")
                .insert([
                    "session_id": session.id.uuidString,
                    "sender_id": myID.uuidString,
                    "recipient_id": myID.uuidString,
                    "emoji": "💪"
                ])
                .execute()
            XCTFail("self-kudos insert must be rejected by the session_kudos_no_self CHECK constraint")
        } catch {
            // Expected — 23514 check_violation surfaces through PostgREST.
        }
    }
}
