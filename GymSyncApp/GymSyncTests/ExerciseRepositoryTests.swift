import XCTest
@testable import GymSync

final class ExerciseRepositoryTests: XCTestCase {
    // exercises SELECT policy is TO authenticated — sign in as the CI test user.
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testFetchAllReturnsSeededExercises() async throws {
        let exercises = try await ExerciseRepository.fetchAll()
        XCTAssertGreaterThanOrEqual(exercises.count, 30)
        XCTAssertTrue(exercises.contains { $0.slug == "bench-press" })
    }

    func testFetchByIdReturnsCorrectExercise() async throws {
        let all = try await ExerciseRepository.fetchAll()
        guard let first = all.first else {
            XCTFail("no exercises seeded")
            return
        }
        let fetched = try await ExerciseRepository.fetch(id: first.id)
        XCTAssertEqual(fetched?.id, first.id)
    }
}
