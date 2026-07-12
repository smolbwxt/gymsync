import XCTest
@testable import GymSync

final class PersonalRecordTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testRecordAndRecentRoundTrip() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })

        let record = try await PersonalRecordRepository.record(
            exerciseID: bench.id,
            weight: 225,
            reps: 3,
            previousBest: 205,
            sessionID: nil
        )
        XCTAssertEqual(record.userID, userID)
        XCTAssertEqual(record.exerciseID, bench.id)
        XCTAssertEqual(record.weight, 225)
        XCTAssertEqual(record.previousBest, 205)

        let recent = try await PersonalRecordRepository.recent(userID: userID, limit: 10)
        XCTAssertTrue(recent.contains { $0.id == record.id })
        // desc by achieved_at: our just-inserted record should sort first.
        XCTAssertEqual(recent.first?.id, record.id)
    }

    func testCountSinceBoundary() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })

        _ = try await PersonalRecordRepository.record(
            exerciseID: bench.id,
            weight: 230,
            reps: 1,
            previousBest: 225,
            sessionID: nil
        )

        let past = Date().addingTimeInterval(-3600)
        let countFromPast = try await PersonalRecordRepository.countSince(userID: userID, date: past)
        XCTAssertGreaterThanOrEqual(countFromPast, 1)

        let future = Date().addingTimeInterval(3600)
        let countFromFuture = try await PersonalRecordRepository.countSince(userID: userID, date: future)
        XCTAssertEqual(countFromFuture, 0)
    }
}
