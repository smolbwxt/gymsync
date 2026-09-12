import XCTest
@testable import GymSync

/// This session's Coach thread, against the live project — plan task S6.
///
/// Migration 20260912000102 was applied to chjkkwqwdlmaxacwglzm at
/// 2026-09-12 23:44:50 UTC (confirmed by the controller, per global constraint
/// 8's gate — never assumed), so these run for real rather than skipping:
/// `coach_chat_threads.session_id`, the partial unique index
/// `coach_chat_threads_session_key`, `public.session_coach_thread(p_session_id
/// uuid) -> (thread_id uuid, unlocked boolean)` for participants only, and
/// `private.session_has_pro(uuid)`.
///
/// 2099 and `TestSession`, per constraint 16: these run as the shared CI
/// account alongside the screenshot job, and the factory registers
/// `deleteSession` with `addTeardownBlock` BEFORE returning. The thread rows
/// go with the session — `coach_chat_threads.session_id` is the session's
/// column, and the fixture never leaves a current-week row behind either way.
final class SessionCoachThreadLiveTests: XCTestCase {

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    private func makeSession() async throws -> WorkoutSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let when = calendar.date(from: DateComponents(year: 2099, month: 3, day: 2,
                                                      hour: 12)) ?? Date()
        return try await makeTempScheduledSession(scheduledFor: when)
    }

    // MARK: - 1: the room exists

    func testOpeningASessionsThreadReturnsAThreadID() async throws {
        let session = try await makeSession()
        let thread = try await SessionCoachThreadRepository.open(sessionID: session.id)
        XCTAssertNotEqual(thread.threadID.uuidString,
                          "00000000-0000-0000-0000-000000000000",
                          "find-or-create must hand back a real thread id")
    }

    // MARK: - 2: find-or-create, from the client's side

    /// Two lifters tapping at once land in ONE room. This is the half a single
    /// client can prove: the second call must FIND what the first created
    /// rather than open a second room. The unique index resolves the genuine
    /// race server-side, which is D4's to assert.
    func testOpeningTwiceReturnsTheSameThread() async throws {
        let session = try await makeSession()
        let first = try await SessionCoachThreadRepository.open(sessionID: session.id)
        let second = try await SessionCoachThreadRepository.open(sessionID: session.id)
        XCTAssertEqual(first.threadID, second.threadID)
    }

    // MARK: - 3: the verdict decodes

    /// Its VALUE depends on whether the CI account is Pro, so this asserts the
    /// DECODE and not the verdict — D4 owns the verdict, server-side, where
    /// `profiles.pro_until` is readable across users. A row whose `unlocked`
    /// failed to decode would throw above rather than reach this line.
    func testUnlockedDecodesAsABool() async throws {
        let session = try await makeSession()
        let thread = try await SessionCoachThreadRepository.open(sessionID: session.id)
        XCTAssertEqual(thread, SessionCoachThread(threadID: thread.threadID,
                                                  unlocked: thread.unlocked),
                       "the value round-trips both of its fields")
    }

    // MARK: - 4: the gate, pure

    /// The house convention (`CrewCoachEngine.swift:22-25`): while the paywall
    /// is dormant the room is open to everyone, whatever the server said. A
    /// Coach door that became the app's only live paywall would be a product
    /// change this plan is not entitled to make.
    func testTheDoorIsReachableWhileThePaywallIsDormant() throws {
        try XCTSkipIf(Monetization.paywallEnabled,
                      "this asserts the DORMANT branch; the paywall is on")
        let locked = SessionCoachThread(threadID: UUID(), unlocked: false)
        let unlocked = SessionCoachThread(threadID: UUID(), unlocked: true)
        XCTAssertTrue(SessionCoachThreadRepository.isReachable(locked))
        XCTAssertTrue(SessionCoachThreadRepository.isReachable(unlocked))
        XCTAssertNil(SessionCoachThreadRepository.lockedNote(locked),
                     "an explanation of a restriction that is not in force is furniture")
    }
}
