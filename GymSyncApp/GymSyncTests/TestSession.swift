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
///
/// The one path this CANNOT cover: `startSolo` and `schedule` are not
/// transactional — each inserts the session row, then the participant rows in a
/// separate round trip (SessionRepository.swift:42-53 and :391-417) — so a
/// throw between the two orphans a session before the factory is ever handed an
/// id to register. That is a production-side gap, not something a test helper
/// can close.
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

// MARK: - Enrollments

/// A block for a live-DB test, **ended before it ever exists as an active one**
/// (fix round 1, finding F10 — this used to live in
/// `BlockGoalLiveRepositoryTests` where the next suite could not find it).
///
/// INSERTED DIRECTLY rather than through `ProgramRepository.enroll`, and that is
/// the whole point:
///
///   * `enroll` starts training TODAY. `build-test` and the screenshot job run
///     in PARALLEL on the SAME account (both read the `TEST_USER_EMAIL` secret),
///     so an enrollment that is active for even one round trip could reach
///     `app-tab-home` — a frozen, owner-approved frame. A row written with
///     `ended_at` already set is never active and `ProgramRepository.active()`
///     can never see it.
///   * `one_active_program_per_user` is a PARTIAL unique index
///     (`WHERE ended_at IS NULL`), so an ended block never contends with
///     whatever the account may already have.
///
/// The delete is registered BEFORE the insert, like every factory in this file,
/// and it cascades: `block_goals.enrollment_id` is `ON DELETE CASCADE` and the
/// rungs cascade from the goal, so one delete cleans all three tables.
extension XCTestCase {

    /// An ended `program_enrollments` row, deletion pre-registered.
    ///
    /// `slug` picks which bundled template's shape the block carries — the
    /// deload weeks and per-week notes a ladder page reads. Every date is 2099.
    func makeTempEndedEnrollment(slug: String = "march-to-1rm",
                                 startedOn: String = "2099-01-04",
                                 weeks: Int = 8) async throws -> ProgramEnrollment {
        // snake_case field names rather than `CodingKeys`, matching
        // `VolumeTargetRepository.set`'s own local `Upsert` — a throwaway DTO
        // for one insert does not need the ceremony.
        struct EndedEnrollment: Encodable {
            let id: UUID
            let user_id: UUID
            let template_slug: String
            let focus: ProgramFocus
            let baseline: [String: Double]
            let started_on: String
            let weeks: Int
            let ended_at: String
            let ended_reason: String
        }

        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)
        let id = UUID()
        addTeardownBlock {
            _ = try? await SupabaseService.shared.client
                .from("program_enrollments")
                .delete()
                .eq("id", value: id)
                .execute()
        }

        let rows: [ProgramEnrollment] = try await SupabaseService.shared.client
            .from("program_enrollments")
            .insert(EndedEnrollment(
                id: id, user_id: owner, template_slug: slug,
                focus: ProgramFocus(), baseline: [:],
                started_on: startedOn, weeks: weeks,
                ended_at: "2099-03-01T00:00:00Z", ended_reason: "completed"))
            .select()
            .execute().value
        return try XCTUnwrap(rows.first)
    }
}
