import XCTest
@testable import GymSync

/// THE FALLBACK DECISION FOR A SESSION'S PLAN (final review NEW-1).
///
/// `RoutineRepository.fetch(id:)` has no cache, so a session re-entered with
/// no signal came back with `routineExercises == []` — and an empty routine is
/// what makes a restored swap layer invisible (F2), leaves restored set rows
/// with no slot to belong to (F3), and writes `routine_exercise_id NULL` on
/// the next set logged. The rule is one call, so no caller can implement half
/// of it, and these are its four cases.
///
/// In-memory on purpose, like `SessionSwapPendingStore`: it survives the
/// destruction of a view, not a relaunch. A cold launch with no network needs
/// the plan on disk and is deliberately out of scope (C2).
@MainActor
final class SessionRoutineCacheTests: XCTestCase {

    private let routineID = UUID()
    private let benchID = UUID()
    private let squatID = UUID()

    private func routine(_ name: String) -> Routine {
        Routine(id: routineID, ownerID: UUID(), name: name, description: nil,
                visibility: "private", createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func row(_ exerciseID: UUID, position: Int) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routineID, exerciseID: exerciseID,
                        position: position, targetSets: 3, targetReps: "8",
                        targetWeight: "135", restSeconds: 90, notes: nil)
    }

    private func loaded(_ name: String, _ rows: [RoutineExercise]) -> SessionRoutineCache.Loaded {
        SessionRoutineCache.Loaded(routine: routine(name), exercises: rows)
    }

    /// A read that SUCCEEDED is the answer, and is what the next failure will
    /// fall back to.
    func testAFreshFetchWinsAndIsRemembered() {
        let cache = SessionRoutineCache()
        let fresh = loaded("Push A", [row(benchID, position: 0)])

        let answer = cache.resolve(routineID: routineID, fetched: fresh)
        XCTAssertEqual(answer?.routine.name, "Push A")
        XCTAssertEqual(answer?.exercises.map(\.exerciseID), [benchID])
        XCTAssertEqual(cache.cached(routineID: routineID)?.routine.name, "Push A")
    }

    /// The walk this exists for: MINIMISE, re-enter with no signal, the fetch
    /// throws — the plan is still there.
    func testAFailedFetchFallsBackToTheLastPlanThisProcessSaw() {
        let cache = SessionRoutineCache()
        cache.resolve(routineID: routineID,
                      fetched: loaded("Push A", [row(benchID, position: 0),
                                                 row(squatID, position: 1)]))

        let offline = cache.resolve(routineID: routineID, fetched: nil)
        XCTAssertEqual(offline?.routine.name, "Push A")
        XCTAssertEqual(offline?.exercises.map(\.exerciseID), [benchID, squatID],
                       "the rows the swap layer layers and the cursor walks")
    }

    /// Nothing remembered — today's behaviour exactly, and no pretending.
    func testAFailedFetchWithNothingRememberedAnswersNothing() {
        let cache = SessionRoutineCache()
        XCTAssertNil(cache.resolve(routineID: routineID, fetched: nil))
        XCTAssertNil(cache.cached(routineID: routineID))
    }

    /// A ROUTINE EDITED BETWEEN TWO ENTRIES IS NEVER MASKED. This is why the
    /// cache is a fallback and not a cache the app reads first.
    func testAnEditedRoutineIsNeverMaskedByTheRememberedCopy() {
        let cache = SessionRoutineCache()
        cache.resolve(routineID: routineID, fetched: loaded("Push A", [row(benchID, position: 0)]))

        let edited = loaded("Push A (revised)", [row(benchID, position: 0),
                                                 row(squatID, position: 1)])
        let answer = cache.resolve(routineID: routineID, fetched: edited)
        XCTAssertEqual(answer?.routine.name, "Push A (revised)")
        XCTAssertEqual(answer?.exercises.count, 2)
        // …and the remembered copy is now the edited one, so the NEXT failure
        // falls back to what the lifter last actually saw.
        XCTAssertEqual(cache.cached(routineID: routineID)?.exercises.count, 2)
    }

    func testOneRoutinesPlanIsNeverServedForAnother() {
        let cache = SessionRoutineCache()
        cache.resolve(routineID: routineID, fetched: loaded("Push A", [row(benchID, position: 0)]))
        XCTAssertNil(cache.resolve(routineID: UUID(), fetched: nil))
    }
}
