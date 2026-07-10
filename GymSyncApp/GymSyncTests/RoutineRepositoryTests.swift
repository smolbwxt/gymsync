import XCTest
@testable import GymSync

final class RoutineRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testCreateThenFetchRoundTrip() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in")
            return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })

        let routine = Routine(
            id: UUID(),
            ownerID: userID,
            name: "Test Push Day \(UUID().uuidString.prefix(6))",
            description: nil,
            visibility: "private",
            createdAt: Date(),
            updatedAt: Date()
        )
        let rex = [RoutineExercise(
            id: UUID(), routineID: routine.id, exerciseID: bench.id,
            position: 1, targetSets: 5, targetReps: "5", targetWeight: "185",
            restSeconds: 120, notes: nil
        )]

        try await RoutineRepository.save(routine, exercises: rex)
        let fetched = try await RoutineRepository.fetch(id: routine.id)
        XCTAssertEqual(fetched?.0.id, routine.id)
        XCTAssertEqual(fetched?.1.count, 1)
        XCTAssertEqual(fetched?.1.first?.exerciseID, bench.id)

        try await RoutineRepository.delete(id: routine.id)
        let afterDelete = try await RoutineRepository.fetch(id: routine.id)
        XCTAssertNil(afterDelete)
    }
}
