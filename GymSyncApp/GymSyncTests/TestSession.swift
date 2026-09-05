import XCTest
@testable import GymSync

/// Session factories for live-DB tests. Sessions come from here — never from
/// a bare `SessionRepository.startSolo`/`.schedule` call in a test.
///
/// `complete()` is NOT cleanup. It is a state transition: it writes only
/// `state` and `completed_at` (SessionRepository.swift:59-68), moving the row
/// out of `upcoming()` and into `history()` — `organizer_id = <this account>
/// AND state = 'completed'` (SessionRepository.swift:141-153) — which
/// `HomeView.fetchHistory` feeds to `StatMath.workoutsThisWeek`, the stat tile
/// inside the `app-tab-home` screenshot. Six test files independently reached
/// for it as cleanup; between them they leaked 13 completed sessions per
/// `build-test` run into `ci_test_user` (see
/// `.superpowers/sdd/2026-09-05-screenshot-pipeline/leak-hunt.md`).
///
/// `SessionRepository.deleteSession(id:)` is cleanup: it removes `set_logs`
/// then the session row (SessionRepository.swift:126-133). Every FK pointing at
/// `sessions` is either ON DELETE CASCADE (`session_participants`,
/// 20260709000006_create_sessions.sql:19; also `session_kudos`,
/// `routine_proposals`, `session_duration_edits`) or ON DELETE SET NULL
/// (`chat_messages`, `personal_records`) — nothing blocks the delete and no
/// participant row survives it.
///
/// Both factories register that deletion with `addTeardownBlock` BEFORE
/// returning, so a caller can never be handed an unregistered session. Every
/// exit path from the test — success, `XCTFail`, a thrown error, `XCTSkip` —
/// runs it, because XCTest awaits teardown blocks. `defer { Task { … } }` does
/// not: that detached task can lose the race with process exit, which is the
/// defect ModerationRepositoryTests.swift:20-27 records having already been
/// bitten by.
extension XCTestCase {

    /// Solo session (`state: in_progress`, `started_at` set, self as the sole
    /// `ready` participant), deletion pre-registered. See the extension comment.
    func makeTempSoloSession(routineID: UUID? = nil) async throws -> WorkoutSession {
        let session = try await SessionRepository.startSolo(routineID: routineID)
        let sessionID = session.id
        addTeardownBlock {
            try? await SessionRepository.deleteSession(id: sessionID)
        }
        return session
    }

    /// Scheduled session (`state: scheduled`, `started_at` NULL, organizer as an
    /// `online` participant plus one `invited` participant per invitee),
    /// deletion pre-registered. See the extension comment.
    func makeTempScheduledSession(
        groupID: UUID? = nil,
        inviteeIDs: [UUID] = [],
        routineID: UUID? = nil,
        scheduledFor: Date,
        generateRoomCode: Bool = false
    ) async throws -> WorkoutSession {
        let session = try await SessionRepository.schedule(
            groupID: groupID,
            inviteeIDs: inviteeIDs,
            routineID: routineID,
            scheduledFor: scheduledFor,
            generateRoomCode: generateRoomCode
        )
        let sessionID = session.id
        addTeardownBlock {
            try? await SessionRepository.deleteSession(id: sessionID)
        }
        return session
    }
}
