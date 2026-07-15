import XCTest
@testable import GymSync

/// Live-DB tests (ci_test_user). Curator-positive publishing is NOT tested
/// here — the CI user is deliberately not a curator, and self-promotion is
/// server-blocked (that's test 6's subject); the curator happy path is
/// covered by pgTAP (fixture curator) + manual QA.
final class CurationRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testCatalogDecodesWithIconAndCategory() async throws {
        let catalog = try await SoundboardRepository.fetchCatalog()
        XCTAssertGreaterThanOrEqual(catalog.count, 4)
        let airhorn = try XCTUnwrap(catalog.first { $0.slug == "airhorn" })
        XCTAssertEqual(airhorn.icon, "📯")
        XCTAssertEqual(airhorn.category, "hype")
    }

    func testFavoritesRoundTrip() async throws {
        let original = try await SoundboardFavoritesRepository.get()
        defer { Task { try? await SoundboardFavoritesRepository.set(original) } }
        try await SoundboardFavoritesRepository.set(["boo", "ding"])
        let fetched = try await SoundboardFavoritesRepository.get()
        XCTAssertEqual(fetched, ["boo", "ding"])
    }

    func testNonCuratorCannotPublish() async throws {
        guard let uid = await SupabaseService.shared.currentUserID() else {
            throw XCTSkip("unconfigured")
        }
        let sneaky = Routine(
            id: UUID(), ownerID: uid, name: "Sneaky Publish Test",
            description: nil, visibility: "public",
            createdAt: Date(), updatedAt: Date()
        )
        do {
            try await RoutineRepository.save(sneaky, exercises: [])
            // If the insert somehow succeeded, clean up and fail loudly.
            try? await RoutineRepository.delete(id: sneaky.id)
            XCTFail("non-curator publish must be rejected by RLS")
        } catch {
            // expected: RLS violation surfaces as an error
        }
    }

    func testCloneCopiesExercisesAsPrivate() async throws {
        guard let uid = await SupabaseService.shared.currentUserID() else {
            throw XCTSkip("unconfigured")
        }
        // Source: the caller's own routine (public not required for clone's
        // read path when you own it — RLS allows either way).
        let source = Routine(
            id: UUID(), ownerID: uid, name: "Clone Source",
            description: nil, visibility: "private",
            createdAt: Date(), updatedAt: Date()
        )
        let exercises = try await ExerciseRepository.fetchAll()
        let ex = try XCTUnwrap(exercises.first)
        let sourceExercises = [RoutineExercise(
            id: UUID(), routineID: source.id, exerciseID: ex.id,
            position: 1, targetSets: 3, targetReps: "10",
            targetWeight: nil, restSeconds: 90, notes: nil
        )]
        try await RoutineRepository.save(source, exercises: sourceExercises)
        defer { Task { try? await RoutineRepository.delete(id: source.id) } }

        let copy = try await RoutineRepository.clone(routineID: source.id)
        defer { Task { try? await RoutineRepository.delete(id: copy.id) } }

        XCTAssertEqual(copy.visibility, "private")
        XCTAssertEqual(copy.name, "Clone Source")
        let fetchedCopy = try await RoutineRepository.fetch(id: copy.id)
        let (_, copiedEx) = try XCTUnwrap(fetchedCopy)
        XCTAssertEqual(copiedEx.count, 1)
        XCTAssertEqual(copiedEx.first?.targetReps, "10")
    }

    /// Smoke test for `publicRoutines()`'s double-container PostgREST embed
    /// decode. Its failure mode is SILENT — a decode or FK-hint regression
    /// just makes the Library Featured shelf vanish with no surfaced error
    /// (final review flagged this as priority coverage). The bare call throws
    /// on an FK/decode regression; the assertions prove the joined owner
    /// username actually populates and ordering holds. Coverage is real while
    /// ≥1 curator-seeded public routine exists; if the shelf is ever emptied
    /// this passes without false-failing.
    func testPublicRoutinesDecodesEmbeddedOwner() async throws {
        let rows = try await RoutineRepository.publicRoutines()
        for (routine, ownerUsername) in rows {
            XCTAssertEqual(routine.visibility, "public",
                           "publicRoutines must only return public routines")
            XCTAssertFalse(ownerUsername.isEmpty,
                           "embedded owner username must decode from the join, not come back empty")
        }
        let dates = rows.map(\.routine.createdAt)
        XCTAssertEqual(dates, dates.sorted(by: >), "publicRoutines must be newest-first")
    }
}
