import XCTest
@testable import GymSync

final class SessionRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testStartAndCompleteSoloSession() async throws {
        let session = try await makeTempSoloSession()
        XCTAssertEqual(session.state, "in_progress")
        XCTAssertNotNil(session.startedAt)

        let completed = try await SessionRepository.complete(sessionID: session.id)
        XCTAssertEqual(completed.state, "completed")
        XCTAssertNotNil(completed.completedAt)
    }

    func testLogSetAndReadBack() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })
        let session = try await makeTempSoloSession()

        let log = SetLog(
            id: UUID(),
            userID: userID,
            sessionID: session.id,
            exerciseID: bench.id,
            setIndex: 1,
            reps: 5,
            weight: 185,
            rpe: 8,
            isFailed: false,
            isPenalty: false,
            note: nil,
            loggedAt: Date()
        )
        try await SessionRepository.logSet(log)

        let logs = try await SessionRepository.setLogs(sessionID: session.id)
        XCTAssertTrue(logs.contains { $0.id == log.id })
        // No complete() here: nothing below asserts on it and it was never
        // cleanup. makeTempSoloSession's teardown block deletes the session
        // (and its set_logs) instead.
    }
}
