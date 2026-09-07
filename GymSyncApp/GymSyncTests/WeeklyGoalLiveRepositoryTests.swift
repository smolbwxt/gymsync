import XCTest
@testable import GymSync

/// `LiveWeeklyGoalRepository` against the real `weekly_goals` table
/// (Stream A task A12), in the repo's live-DB idiom: `TestAuth
/// .signInIfConfigured()` skips when secrets are placeholders, and every
/// test registers its cleanup with `addTeardownBlock` BEFORE it writes.
///
/// CLEANUP IS THE LAW HERE (PR #27's leak fix, `TestSession.swift`'s header):
/// XCTest awaits teardown blocks, so they run on success, on `XCTFail`, on a
/// thrown error and on `XCTSkip`; a `defer { Task { … } }` can lose the race
/// with process exit. Registering BEFORE the write means a throw mid-test
/// still leaves nothing behind.
///
/// THE WEEKS ARE FAR-FUTURE DATES, one per test. `weekly_goals`' primary key
/// is `(user_id, week_start)` and these run as the shared CI account, so a
/// test writing to the CURRENT week would fight `scripts/seed_qa_fixtures.js`
/// (integration task I2 seeds this account's real goal) and change what
/// `app-tab-home` captures. A 2099 week is invisible to every screen.
final class WeeklyGoalLiveRepositoryTests: XCTestCase {

    private let repository = LiveWeeklyGoalRepository()

    /// Registers the delete first, then hands back the week to write into.
    private func temporaryWeek(_ weekStart: String) -> String {
        let repository = self.repository
        addTeardownBlock {
            await repository.deleteRow(weekStart: weekStart)
        }
        return weekStart
    }

    private func goal(_ weekStart: String, userID: UUID,
                      kind: WeeklyGoalKind = .muscleSets,
                      params: WeeklyGoalParams = .init(muscleTargets: ["chest": 12,
                                                                       "back": 10],
                                                       targetSource: "routines"),
                      source: WeeklyGoalSource = .coach) -> WeeklyGoal {
        WeeklyGoal(userID: userID, weekStartString: weekStart, kind: kind,
                   params: params, source: source, setAt: Date())
    }

    func testGoalIsNilForAWeekWithNoRow() async throws {
        try await TestAuth.signInIfConfigured()
        let empty = await repository.goal(weekStart: "2099-02-01")
        XCTAssertNil(empty, "no row is nil, not an error and not an empty goal")
    }

    func testSaveRoundTripsAndAlwaysStampsUser() async throws {
        try await TestAuth.signInIfConfigured()
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return XCTFail("signed in but no user id")
        }
        let week = temporaryWeek("2099-01-04")

        // Handed a `.coach` goal on purpose: `save` is the editor's Save and
        // must stamp `user` regardless of what it was given, because owner
        // answer 3's whole enforcement hangs off that column.
        let saved = await repository.save(goal(week, userID: userID))
        XCTAssertTrue(saved)

        let read = await repository.goal(weekStart: week)
        XCTAssertEqual(read?.kind, .muscleSets)
        XCTAssertEqual(read?.source, .user, "save() is always the athlete's own goal")
        XCTAssertEqual(read?.weekStartString, week,
                       "week_start round-trips as a STRING, never through a date decoder")
        XCTAssertEqual(read?.params.muscleTargets?["chest"], 12)
        XCTAssertEqual(read?.params.targetSource, "routines",
                       "params keys persist in camelCase — no keyEncodingStrategy anywhere")
    }

    func testSaveTwiceInOneWeekEditsOneRow() async throws {
        try await TestAuth.signInIfConfigured()
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return XCTFail("signed in but no user id")
        }
        let week = temporaryWeek("2099-01-11")

        await repository.save(goal(week, userID: userID))
        // A different kind entirely — the upsert must replace, not collide
        // with the primary key. `.lift`, not `.distance` or
        // `.sessionsOfType`: `save(_:)` requests HealthKit authorization for
        // those two kinds, and a unit test must never raise that sheet — on
        // the CI simulator it hangs build-test to its 45-minute timeout.
        await repository.save(goal(week, userID: userID, kind: .lift,
                                   params: .init(exerciseID: UUID(), targetWeightLbs: 225)))

        let read = await repository.goal(weekStart: week)
        XCTAssertEqual(read?.kind, .lift)
        XCTAssertEqual(read?.params.targetWeightLbs, 225)
        XCTAssertNil(read?.params.muscleTargets,
                     "the second save replaced the payload rather than merging into it")
    }

    func testSetAtComesBackPopulated() async throws {
        try await TestAuth.signInIfConfigured()
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return XCTFail("signed in but no user id")
        }
        let week = temporaryWeek("2099-01-18")
        let before = Date().addingTimeInterval(-60)

        await repository.save(goal(week, userID: userID))
        let read = await repository.goal(weekStart: week)

        // `setAt` has no column: the DTO maps it from `updated_at`, which A1's
        // BEFORE UPDATE trigger keeps honest. If it ever came back as
        // `.distantPast`, the mapping fell through both timestamps.
        XCTAssertNotNil(read?.setAt)
        XCTAssertGreaterThan(read?.setAt ?? .distantPast, before,
                             "setAt maps to updated_at and is stamped by the server")
    }

    /// The two `params` fields whose round trip is genuinely in question:
    /// `targetWeightLbs` is a `Decimal`, and `byDate` is a `Date` inside
    /// `jsonb` encoded by the SDK's own date strategy. `muscleTargets` and
    /// `distanceTarget` are Int and Double and were never in doubt.
    func testLiftPayloadRoundTripsItsDecimalAndItsDate() async throws {
        try await TestAuth.signInIfConfigured()
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return XCTFail("signed in but no user id")
        }
        let week = temporaryWeek("2099-02-15")
        let exerciseID = UUID()
        // A whole second, so the assertion cannot fail on sub-second
        // precision the wire format may not carry.
        let byDate = Date(timeIntervalSince1970: 4_102_444_800)

        await repository.save(goal(week, userID: userID, kind: .lift,
                                   params: .init(exerciseID: exerciseID,
                                                 targetWeightLbs: 225,
                                                 byDate: byDate)))
        let read = await repository.goal(weekStart: week)

        XCTAssertEqual(read?.kind, .lift)
        XCTAssertEqual(read?.params.exerciseID, exerciseID)
        XCTAssertEqual(read?.params.targetWeightLbs, 225,
                       "a Decimal survives the jsonb round trip")
        XCTAssertEqual(read?.params.byDate?.timeIntervalSince1970 ?? 0,
                       byDate.timeIntervalSince1970, accuracy: 1,
                       "and so does a Date, through the SDK's own encoding strategy")
    }

    func testClearToCoachLeavesACoachRow() async throws {
        try await TestAuth.signInIfConfigured()
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return XCTFail("signed in but no user id")
        }
        let week = temporaryWeek("2099-01-25")

        await repository.save(goal(week, userID: userID))
        // Bound before the assertion, never awaited inside an XCTAssert
        // autoclosure — the compile error Task 0.6 had to fix.
        let saved = await repository.goal(weekStart: week)
        XCTAssertEqual(saved?.source, .user)

        let recovered = await repository.clearToCoach(weekStart: week)
        XCTAssertEqual(recovered?.source, .coach,
                       "LET COACH SET IT hands back a detected, Coach-owned goal")

        let read = await repository.goal(weekStart: week)
        XCTAssertEqual(read?.source, .coach,
                       "and persists it, so the next read agrees with what the editor showed")
        XCTAssertEqual(read?.kind, recovered?.kind)
    }

    func testDetectWritesNothing() async throws {
        try await TestAuth.signInIfConfigured()
        let week = "2099-02-08"   // no temporaryWeek: nothing should be written
        let proposed = await repository.detect(weekStart: week)

        let stored = await repository.goal(weekStart: week)

        XCTAssertNotNil(proposed, "detection never returns nil")
        XCTAssertEqual(proposed?.source, .coach)
        XCTAssertNil(stored, "propose-only: detect() must not leave a row behind")
    }
}
