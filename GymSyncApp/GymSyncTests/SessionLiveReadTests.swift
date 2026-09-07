import XCTest
@testable import GymSync

/// Live-DB tests for `SessionRepository.liveForCurrentUser()` (Home v3 fix
/// round 1, review finding 2).
///
/// The read exists because `upcoming()`'s state list is the PRE-workout
/// states — `scheduled | lobby_open | editing | voting | locked` — so nothing
/// in the app could answer "is one of my sessions running right now?" without
/// a group id. Home's `JOIN THE SESSION` face read `upcoming()`, so it could
/// never fire, and a crew session disappeared from Home the moment it went
/// live. The second test below is the one that pins that: it asserts the
/// exclusion directly, so if anyone ever widens `upcoming()`'s filter, this
/// suite says so rather than leaving two overlapping reads feeding the same
/// button.
///
/// Sessions come from `TestSession.swift`'s factories, which register
/// `deleteSession` with `addTeardownBlock` BEFORE returning — never from a
/// bare `startSolo`/`schedule` call. `makeTempSoloSession` is exactly the
/// fixture this needs: `startSolo` inserts `state: "in_progress"` with
/// `started_at` set and the caller as the sole participant
/// (`SessionRepository.swift:21-57`).
final class SessionLiveReadTests: XCTestCase {

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testLiveReadReturnsMyInProgressSession() async throws {
        let session = try await makeTempSoloSession()
        let live = try await SessionRepository.liveForCurrentUser()
        XCTAssertTrue(live.contains { $0.id == session.id },
                      "a session this account just started must be visible to the live read")
        XCTAssertTrue(live.allSatisfy { $0.state == "in_progress" },
                      "the read is state-filtered — nothing else may come back")
    }

    /// The complement, and the whole reason the new read had to exist:
    /// `upcoming()` cannot see a live session. If this test ever goes red,
    /// somebody widened that filter and Home is now reading the same session
    /// from two arrays.
    func testUpcomingCannotSeeALiveSession() async throws {
        let session = try await makeTempSoloSession()
        let upcoming = try await SessionRepository.upcoming()
        XCTAssertFalse(upcoming.contains { $0.id == session.id },
                       "upcoming() is the pre-workout states; an in_progress row must not appear")
    }

    /// And the other direction: a session that has not started is not live.
    /// Together with the two above, the two reads partition this account's
    /// actionable sessions, which is what lets `HomeView.actionableSessions`
    /// concatenate them with no de-duplication.
    func testScheduledSessionIsNotLive() async throws {
        let session = try await makeTempScheduledSession(scheduledFor: Date.now.addingTimeInterval(3600))
        let live = try await SessionRepository.liveForCurrentUser()
        XCTAssertFalse(live.contains { $0.id == session.id },
                       "a scheduled session has not started — it must not read as live")
    }

    /// THE SIX-HOUR FLOOR. `in_progress` is a state nothing leaves on its
    /// own — there is no reaper, and the push cron only notifies at 30 and
    /// 60 minutes idle without ever transitioning the row — so a session
    /// nobody ends would otherwise own Home's one button for days.
    ///
    /// The factories cannot back-date `started_at`: `startSolo` stamps
    /// `Date()` at insert and takes no override
    /// (`SessionRepository.swift:26-40`). So the test ages the row itself,
    /// through the client. That is not a back door — the sessions table's
    /// "organizer or participant can update session" policy
    /// (`20260709000006_create_sessions.sql:61-67`) covers exactly this
    /// account on exactly this row, and `SessionEngineTests` already reaches
    /// for the raw client the same way. The teardown block registered by the
    /// factory still owns the deletion.
    func testALiveSessionOlderThanSixHoursAgesOutOfTheRead() async throws {
        let session = try await makeTempSoloSession()

        // Still live, still mine, but started seven hours ago.
        let stale = Date.now.addingTimeInterval(-7 * 3600)
        try await SupabaseService.shared.client
            .from("sessions")
            .update(["started_at": ISO8601DateFormatter().string(from: stale)])
            .eq("id", value: session.id.uuidString)
            .execute()

        let live = try await SessionRepository.liveForCurrentUser()
        XCTAssertFalse(live.contains { $0.id == session.id },
                       "a session that has been in_progress for seven hours is abandoned, not live")

        // And the state itself is untouched — this is a read bound, not a
        // reaper. The row is still there for the lobby's own resume and end
        // paths; only Home stops offering it.
        let row = try await SessionRepository.session(id: session.id)
        XCTAssertEqual(row?.state, "in_progress")
    }
}
