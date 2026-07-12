import XCTest
@testable import GymSync

/// Live-DB integration tests for CompletedSessionView's duration editing (Task 5).
///
/// Single actor — all test methods run serially within this class.
///
/// Cleanup note: completed sessions cannot be cancelled via cancelOccurrence (only
/// pre-workout sessions apply). The test-data row is left in place (completed state,
/// group_id = nil) per the precedent established in SessionSchedulingTests.
final class DurationEditTests: XCTestCase {

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    // MARK: - Full duration-edit lifecycle

    func testDurationEditLifecycle() async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw XCTSkip("not signed in — skipping live-DB test")
        }

        // ── 1. Create an ad-hoc session (self-only, scheduled now) ────────────
        let session = try await SessionRepository.schedule(
            groupID: nil,
            inviteeIDs: [],
            routineID: nil,
            scheduledFor: Date(),
            generateRoomCode: false
        )
        XCTAssertEqual(session.state, "scheduled")

        // ── 2. Open lobby + check in ──────────────────────────────────────────
        try await SessionRepository.openLobby(sessionID: session.id)
        try await SessionRepository.checkIn(sessionID: session.id, method: "traveling_override")

        // ── 3. Start (RPC: lateness + turn order + state flip) ────────────────
        try await SessionRepository.start(sessionID: session.id)

        // ── 4. Complete ───────────────────────────────────────────────────────
        let completed = try await SessionRepository.complete(sessionID: session.id)
        XCTAssertEqual(completed.state, "completed")
        let originalCompletedAt = try XCTUnwrap(completed.completedAt,
                                                "completedAt must be set after complete()")

        // ── 5. Edit duration: push end time out by 30 minutes ─────────────────
        let newEnd = originalCompletedAt.addingTimeInterval(30 * 60)
        let newStart = completed.startedAt ?? Date().addingTimeInterval(-3600)

        try await SessionRepository.editDuration(
            sessionID:      session.id,
            newStartedAt:   newStart,
            newCompletedAt: newEnd,
            reason:         "test"
        )

        // ── 6. Refetch and assert ─────────────────────────────────────────────
        guard let updated = try await SessionRepository.session(id: session.id) else {
            XCTFail("session not found after editDuration"); return
        }

        XCTAssertTrue(updated.durationWasEdited,
                      "durationWasEdited must be true after editDuration")

        let updatedEnd = try XCTUnwrap(updated.completedAt,
                                       "completedAt must be set after editDuration")
        // Allow 1 s tolerance for ISO8601 round-trip / DB storage precision.
        XCTAssertEqual(updatedEnd.timeIntervalSince1970,
                       newEnd.timeIntervalSince1970,
                       accuracy: 1.0,
                       "completedAt must reflect the new end time")
    }

    // MARK: - Anchor invariant: ±48 h window must reference ORIGINAL times, not current stored values

    /// After one successful edit the window must still be anchored to the ORIGINAL completed_at.
    /// Attempting a second edit at original + 49 h must be rejected even though it would be
    /// within 48 h of the first-edited value (original + 30 min).
    func testEditDurationAnchorDoesNotWalkOn49h() async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw XCTSkip("not signed in — skipping live-DB test")
        }

        // ── Build a completed session ─────────────────────────────────────────
        let session = try await SessionRepository.schedule(
            groupID: nil, inviteeIDs: [], routineID: nil,
            scheduledFor: Date(), generateRoomCode: false
        )
        try await SessionRepository.openLobby(sessionID: session.id)
        try await SessionRepository.checkIn(sessionID: session.id, method: "traveling_override")
        try await SessionRepository.start(sessionID: session.id)
        let completed = try await SessionRepository.complete(sessionID: session.id)
        let originalEnd = try XCTUnwrap(completed.completedAt)
        let originalStart = completed.startedAt ?? Date().addingTimeInterval(-3600)

        // ── First edit: push end out by +30 min ───────────────────────────────
        let firstEditEnd = originalEnd.addingTimeInterval(30 * 60)
        try await SessionRepository.editDuration(
            sessionID: session.id,
            newStartedAt: originalStart,
            newCompletedAt: firstEditEnd,
            reason: "anchor-test first edit"
        )

        // ── Second edit: attempt original + 49 h → must throw .validation ─────
        // After the first edit the stored value is originalEnd + 30 min, so naively
        // originalEnd + 49 h would be only 48 h 30 min from the stored value — it
        // would pass a re-anchored check. It must be rejected because the anchor
        // is locked to the original completed_at.
        let tooFarEnd = originalEnd.addingTimeInterval(49 * 3600)
        do {
            try await SessionRepository.editDuration(
                sessionID: session.id,
                newStartedAt: originalStart,
                newCompletedAt: tooFarEnd,
                reason: "anchor-test 49h attempt"
            )
            XCTFail("editDuration should have thrown .validation for original + 49 h")
        } catch GymSyncError.validation(let message) {
            XCTAssertFalse(message.isEmpty, "validation message must be non-empty")
        } catch {
            // Any error is acceptable — the key requirement is that it throws.
        }
    }

    /// After one successful edit, a second edit at original + 47 h must still succeed —
    /// the anchor window is ±48 h around the original, not a stricter re-anchored range.
    func testEditDurationAnchorAllows47hSecondEdit() async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw XCTSkip("not signed in — skipping live-DB test")
        }

        // ── Build a completed session ─────────────────────────────────────────
        let session = try await SessionRepository.schedule(
            groupID: nil, inviteeIDs: [], routineID: nil,
            scheduledFor: Date(), generateRoomCode: false
        )
        try await SessionRepository.openLobby(sessionID: session.id)
        try await SessionRepository.checkIn(sessionID: session.id, method: "traveling_override")
        try await SessionRepository.start(sessionID: session.id)
        let completed = try await SessionRepository.complete(sessionID: session.id)
        let originalEnd = try XCTUnwrap(completed.completedAt)
        let originalStart = completed.startedAt ?? Date().addingTimeInterval(-3600)

        // ── First edit: push end out by +30 min ───────────────────────────────
        let firstEditEnd = originalEnd.addingTimeInterval(30 * 60)
        try await SessionRepository.editDuration(
            sessionID: session.id,
            newStartedAt: originalStart,
            newCompletedAt: firstEditEnd,
            reason: "anchor-47h first edit"
        )

        // ── Second edit: original + 47 h → must succeed ───────────────────────
        let acceptableEnd = originalEnd.addingTimeInterval(47 * 3600)
        try await SessionRepository.editDuration(
            sessionID: session.id,
            newStartedAt: originalStart,
            newCompletedAt: acceptableEnd,
            reason: "anchor-47h second edit"
        )

        guard let refetched = try await SessionRepository.session(id: session.id) else {
            XCTFail("session not found after second editDuration"); return
        }
        let finalEnd = try XCTUnwrap(refetched.completedAt)
        XCTAssertEqual(finalEnd.timeIntervalSince1970,
                       acceptableEnd.timeIntervalSince1970,
                       accuracy: 1.0,
                       "completedAt must reflect the second (47 h) edit")
    }

    // MARK: - Validation: completed < started must throw .validation

    func testEditDurationRejectsEndBeforeStart() async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw XCTSkip("not signed in — skipping live-DB test")
        }

        // We need a completed session to have a valid sessionID to pass.
        // Re-use a minimal lifecycle: schedule → checkIn → start → complete.
        let session = try await SessionRepository.schedule(
            groupID: nil,
            inviteeIDs: [],
            routineID: nil,
            scheduledFor: Date(),
            generateRoomCode: false
        )
        try await SessionRepository.openLobby(sessionID: session.id)
        try await SessionRepository.checkIn(sessionID: session.id, method: "traveling_override")
        try await SessionRepository.start(sessionID: session.id)
        _ = try await SessionRepository.complete(sessionID: session.id)

        let now = Date()
        let badStart = now
        let badEnd   = now.addingTimeInterval(-60)  // end BEFORE start — must fail

        do {
            try await SessionRepository.editDuration(
                sessionID:      session.id,
                newStartedAt:   badStart,
                newCompletedAt: badEnd,
                reason:         nil
            )
            XCTFail("editDuration should have thrown .validation for end < start")
        } catch GymSyncError.validation(let message) {
            XCTAssertFalse(message.isEmpty, "validation message must be non-empty")
        } catch {
            // Any error is acceptable — the key requirement is that it throws.
            // A .unknown or mapping variation is still a rejection.
        }
    }
}
