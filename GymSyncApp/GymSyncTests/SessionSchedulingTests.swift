import XCTest
@testable import GymSync

/// Live-DB tests for the scheduling lifecycle and join-by-code paths.
/// Single actor — test methods run serially within this class.
final class SessionSchedulingTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    // MARK: - Full scheduling lifecycle

    func testScheduleAndLifecycle() async throws {
        // 1. Schedule an ad-hoc session with a room code
        // scheduledFor must be within the 20-minute check-in window (step 4
        // below checks in immediately) — see
        // supabase/migrations/20260715000003_checkin_window.sql.
        let scheduledFor = Date().addingTimeInterval(15 * 60) // +15 minutes
        let session = try await SessionRepository.schedule(
            groupID: nil,
            inviteeIDs: [],
            routineID: nil,
            scheduledFor: scheduledFor,
            generateRoomCode: true
        )

        XCTAssertEqual(session.state, "scheduled")
        XCTAssertNotNil(session.roomCode, "generateRoomCode: true should produce a room code")
        let code = try XCTUnwrap(session.roomCode)
        XCTAssertEqual(code.count, 6, "room code must be 6 characters")

        // 2. upcoming() must include the newly scheduled session
        let upcomingSessions = try await SessionRepository.upcoming()
        XCTAssertTrue(
            upcomingSessions.contains { $0.id == session.id },
            "scheduled session should appear in upcoming()"
        )

        // 3. Open the lobby
        try await SessionRepository.openLobby(sessionID: session.id)

        // Verify state changed (fetch via upcoming — still pre-workout)
        let afterOpen = try await SessionRepository.upcoming()
        let opened = afterOpen.first { $0.id == session.id }
        XCTAssertEqual(opened?.state, "lobby_open", "state should be lobby_open after openLobby")

        // 4. Check in
        try await SessionRepository.checkIn(sessionID: session.id, method: "traveling_override")

        // 5. Verify own participant row shows ready
        let myID = await SupabaseService.shared.currentUserID()
        let parts = try await SessionRepository.participants(sessionID: session.id)
        guard let myPart = parts.first(where: { $0.profile.id == myID }) else {
            XCTFail("own participant row not found"); return
        }
        XCTAssertEqual(myPart.participant.checkInState, "ready")
        XCTAssertEqual(myPart.participant.checkInMethod, "traveling_override")
        XCTAssertNotNil(myPart.participant.checkInAt)

        // 6. Start (evaluate_lateness + in_progress)
        try await SessionRepository.start(sessionID: session.id)

        // 7. Complete
        let completed = try await SessionRepository.complete(sessionID: session.id)
        XCTAssertEqual(completed.state, "completed")
        XCTAssertNotNil(completed.completedAt)
    }

    // MARK: - joinByCode negative path

    func testJoinByCodeBadCodeThrows() async throws {
        do {
            _ = try await SessionRepository.joinByCode("XXXXXX")
            XCTFail("expected an error for invalid room code")
        } catch {
            // Any error thrown is acceptable — the RPC raises P0001 which
            // ErrorMapping maps to .validation or .unknown depending on
            // how the PostgREST error surfaces the PG SQLSTATE.
            // We only assert that an error is indeed thrown.
        }
    }
}
