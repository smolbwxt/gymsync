import XCTest
@testable import GymSync

/// `LiveBlockGoalRepository` against the real `block_goals` /
/// `block_goal_rungs` tables, in the repo's live-DB idiom
/// (`WeeklyGoalLiveRepositoryTests`' header states it in full):
/// `TestAuth.signInIfConfigured()` skips when secrets are placeholders, every
/// test registers its cleanup with `addTeardownBlock` BEFORE it writes, and
/// every date is far-future so nothing here can reach a screenshot.
///
/// CLEANUP IS THE LAW HERE. XCTest awaits teardown blocks, so they run on
/// success, on `XCTFail`, on a thrown error and on `XCTSkip`; a
/// `defer { Task { … } }` can lose the race with process exit
/// (`ModerationRepositoryTests.swift:20-27`). Registering BEFORE the write
/// means a throw mid-test still leaves nothing behind.
///
/// THESE TESTS BORROW THE CI ACCOUNT'S ACTIVE BLOCK rather than creating one,
/// and skip when there is none: `one_active_program_per_user` is a unique index,
/// so a test that enrolled would fight whatever block the account already has.
/// They skip again when that block already carries a goal, because
/// `UNIQUE (enrollment_id)` is owner decision 2 and a second one is impossible
/// by design rather than by accident.
final class BlockGoalLiveRepositoryTests: XCTestCase {

    private let repository = LiveBlockGoalRepository()
    private let weekly = LiveWeeklyGoalRepository()

    /// Registers the delete first, then hands back the id to write against.
    /// `block_goal_rungs` cascades from the goal, so one delete cleans both.
    private func temporaryGoal(_ id: UUID) -> UUID {
        let repository = self.repository
        addTeardownBlock { await repository.deleteGoal(id: id) }
        return id
    }

    /// Same contract for the `weekly_goals` row a materialisation writes.
    private func temporaryWeek(_ weekStart: String) -> String {
        let weekly = self.weekly
        addTeardownBlock { await weekly.deleteRow(weekStart: weekStart) }
        return weekStart
    }

    /// The account's active block, or a skip. Also skips when that block
    /// already has a goal — see the type's own comment.
    private func borrowedBlock() async throws -> ProgramEnrollment {
        let active = try? await ProgramRepository.active()
        try XCTSkipIf(active == nil, "no active block on the CI account")
        let block = try XCTUnwrap(active)
        let existing = await repository.goal(enrollmentID: block.id)
        try XCTSkipIf(existing != nil,
                      "this block already carries a goal — UNIQUE (enrollment_id)")
        return block
    }

    private func goal(_ id: UUID, owner: UUID, enrollmentID: UUID,
                      byDate: Date?) -> BlockGoal {
        BlockGoal(id: id, userID: owner, enrollmentID: enrollmentID,
                  metric: .liftOneRepMax,
                  target: GoalTarget(exerciseID: UUID(), targetWeightLbs: 225),
                  byDate: byDate, preset: .strength, source: .user,
                  outcome: nil, outcomeValue: nil,
                  createdAt: Date(), updatedAt: Date())
    }

    func testAGoalAndItsRungsRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)          // never XCTUnwrap(await …)
        let block = try await borrowedBlock()

        let goalID = temporaryGoal(UUID())
        // 2099, like every other row a live test writes here.
        let milestone = Date(timeIntervalSince1970: 4_070_000_000)
        let saved = await repository.save(goal(goalID, owner: owner,
                                               enrollmentID: block.id,
                                               byDate: milestone))
        XCTAssertTrue(saved)

        let read = await repository.goal(id: goalID)
        XCTAssertEqual(read?.target.targetWeightLbs, 225,
                       "target keeps its camelCase key through the round trip")
        XCTAssertEqual(read?.metric, .liftOneRepMax)
        XCTAssertEqual(read?.preset, .strength)
        XCTAssertEqual(read?.source, .user, "save stamps the athlete")

        // THE DATE ASSERTION, compared as a DAY and not as an instant. `by_date`
        // is a `date` column: it round trips through the day string, so the
        // time of day is not preserved and comparing `timeIntervalSince1970`
        // would be asserting something the column never promised.
        let byDate = try XCTUnwrap(read?.byDate)
        XCTAssertEqual(SessionSeries.dayString(for: byDate, in: .current),
                       SessionSeries.dayString(for: milestone, in: .current),
                       "a DATE column round trips through the day string, "
                       + "not the timestamp decoder")

        let ladder = Ladder(goalID: goalID, rungs: [
            .init(weekIndex: 0, weekStartString: "2099-01-04",
                  target: GoalTarget(targetWeightLbs: 190), status: .met),
            .init(weekIndex: 1, weekStartString: "2099-01-11",
                  target: GoalTarget(targetWeightLbs: 195), status: .current),
        ], derivedAt: Date())
        let savedLadder = await repository.saveLadder(ladder)
        XCTAssertTrue(savedLadder)

        let back = await repository.ladder(goalID: goalID)
        XCTAssertEqual(back?.rungs.count, 2)
        XCTAssertEqual(back?.rungs.first?.weekStartString, "2099-01-04",
                       "week_start round-trips as a STRING, never through a date decoder")
        XCTAssertEqual(back?.rungs.first?.status, .met)
        XCTAssertEqual(back?.rungs.first?.target.targetWeightLbs, 190)

        // Re-saving the same ladder EDITS its rows rather than colliding on the
        // (goal_id, week_index) primary key — which is what makes re-laddering
        // an upsert rather than a delete-and-insert.
        let again = await repository.saveLadder(ladder)
        XCTAssertTrue(again, "the rungs upsert on (goal_id, week_index)")
        let unchanged = await repository.ladder(goalID: goalID)
        XCTAssertEqual(unchanged?.rungs.count, 2, "two weeks, saved twice, still two rows")
    }

    func testASecondGoalForTheSameBlockIsRefused() async throws {
        try await TestAuth.signInIfConfigured()
        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)
        let block = try await borrowedBlock()

        let firstID = temporaryGoal(UUID())
        // The second id is registered too — if the database ever stopped
        // refusing it, this test must not be the thing that leaks the row.
        let secondID = temporaryGoal(UUID())

        let first = await repository.save(goal(firstID, owner: owner,
                                               enrollmentID: block.id, byDate: nil))
        XCTAssertTrue(first)

        let second = await repository.save(goal(secondID, owner: owner,
                                                enrollmentID: block.id, byDate: nil))
        XCTAssertFalse(second,
                       "UNIQUE (enrollment_id) is owner decision 2 in the database — "
                       + "the second save returns false rather than throwing")

        let stillOne = await repository.goal(enrollmentID: block.id)
        XCTAssertEqual(stillOne?.id, firstID, "the first goal is the one that stands")
    }

    func testMaterialisingARungWritesTheWeekAndThenRespectsTheAthletesOwn() async throws {
        try await TestAuth.signInIfConfigured()
        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)
        let block = try await borrowedBlock()

        let goalID = temporaryGoal(UUID())
        let week = temporaryWeek("2099-04-05")
        let saved = await repository.save(goal(goalID, owner: owner,
                                               enrollmentID: block.id, byDate: nil))
        XCTAssertTrue(saved)

        let ladder = Ladder(goalID: goalID, rungs: [
            .init(weekIndex: 0, weekStartString: week,
                  target: GoalTarget(targetWeightLbs: 205), status: .current),
        ], derivedAt: Date())
        let savedLadder = await repository.saveLadder(ladder)
        XCTAssertTrue(savedLadder)

        let materialised = await repository.materialiseRung(goalID: goalID, weekStart: week)
        XCTAssertEqual(materialised?.kind, .lift)
        XCTAssertEqual(materialised?.source, .coach,
                       "materialisation is a Coach write")
        XCTAssertEqual(materialised?.params.goalID, goalID, "the row knows its ladder")
        XCTAssertEqual(materialised?.params.targetWeightLbs, 205)

        // THE OVERRIDE. `save` on the weekly repository always stamps `.user`,
        // so this is the athlete taking the week back — and the next
        // materialisation must leave it exactly as they set it. That refusal is
        // WeeklyGoalWriteRule's, consulted by `materialiseRung`, and it is what
        // spec §4 means by "an athlete's edit of this week's row is an override
        // of the rung".
        let mine = WeeklyGoal(userID: owner, weekStartString: week, kind: .days,
                              params: WeeklyGoalParams(), source: .coach,
                              setAt: Date())
        let athleteSaved = await weekly.save(mine)
        XCTAssertTrue(athleteSaved)

        let afterOverride = await repository.materialiseRung(goalID: goalID, weekStart: week)
        XCTAssertEqual(afterOverride?.source, .user,
                       "Coach may not overwrite the athlete's own week")
        XCTAssertEqual(afterOverride?.kind, .days,
                       "the row still says what the athlete set, not what the rung wanted")
    }

    /// END TO END, against the real `ON DELETE SET NULL`: materialise a rung,
    /// delete the goal, and the week must come back as a PLAIN weekly goal —
    /// the row standing, its numbers intact, and `params.goalID` gone.
    ///
    /// The column is cleared by the database; the param is cleared by
    /// `reconcileLadderLink` on the read, because JSON does not participate in a
    /// foreign key. Without both halves the client's `isLadderWeek` would keep
    /// saying yes about a goal that no longer exists.
    func testAWeekOutlivesItsGoalAndStopsBeingALadderWeek() async throws {
        try await TestAuth.signInIfConfigured()
        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)
        let block = try await borrowedBlock()

        let goalID = temporaryGoal(UUID())
        let week = temporaryWeek("2099-05-03")
        let saved = await repository.save(goal(goalID, owner: owner,
                                               enrollmentID: block.id, byDate: nil))
        XCTAssertTrue(saved)

        let ladder = Ladder(goalID: goalID, rungs: [
            .init(weekIndex: 4, weekStartString: week,
                  target: GoalTarget(targetWeightLbs: 215), status: .current),
        ], derivedAt: Date())
        let savedLadder = await repository.saveLadder(ladder)
        XCTAssertTrue(savedLadder)

        let materialised = await repository.materialiseRung(goalID: goalID, weekStart: week)
        XCTAssertEqual(materialised?.params.goalID, goalID)

        // The goal goes; the week the athlete trained does not.
        await repository.deleteGoal(id: goalID)

        let after = await weekly.goal(weekStart: week)
        XCTAssertNotNil(after, "deleting the block goal must not delete the week")
        XCTAssertEqual(after?.params.targetWeightLbs, 215,
                       "the week keeps its own numbers")
        XCTAssertNil(after?.params.goalID,
                     "a week whose goal is gone is a plain weekly goal again, "
                     + "not a frozen ladder week")
    }
}
