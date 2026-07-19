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

    /// Task 6 item 9 (reliability/debt roll-up — .superpowers/sdd/
    /// progress.md:344, "publicRoutines() zero test coverage (follow-up
    /// smoke)"). Live smoke test, same idiom as
    /// `testCreateThenFetchRoundTrip` above (real network call against the
    /// CI test project, not a mock) — this specifically exercises
    /// `publicRoutines()`'s hand-rolled `RowWithOwner.init(from:)` (the
    /// `profiles!routines_owner_id_fkey(username)` embed decode), which had
    /// never been called from a test at all before this.
    ///
    /// Deliberately does NOT insert its own public routine first: the CI
    /// test user is not guaranteed to be a curator (`routines` INSERT with
    /// `visibility='public'` is curator-gated — curation_test.sql "non-
    /// curator cannot insert public routine"), so forcing one here would
    /// either need curator credentials this test doesn't have or would be
    /// testing a fixture-dependent precondition rather than the function
    /// itself. Whether or not any public routines currently exist in the
    /// CI project, this proves: the call succeeds against live Postgrest
    /// (the join embed syntax is accepted, RLS allows the read), and every
    /// row that DOES come back decodes into a well-formed
    /// (Routine, ownerUsername) pair — visibility is genuinely "public"
    /// (the `.eq("visibility", value: "public")` filter actually filtered)
    /// and the joined username is non-empty (the embed actually joined,
    /// not silently decoded to an empty placeholder).
    func testPublicRoutinesSmoke() async throws {
        let rows = try await RoutineRepository.publicRoutines()
        for (routine, ownerUsername) in rows {
            XCTAssertEqual(routine.visibility, "public",
                            "publicRoutines() must only return public-visibility rows")
            XCTAssertFalse(ownerUsername.isEmpty,
                            "owner username must decode from the profiles join, not an empty placeholder")
        }
    }
}
