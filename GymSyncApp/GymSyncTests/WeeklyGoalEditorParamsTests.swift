import XCTest
@testable import GymSync

/// The editor's params builder, at the one seam goal-first programming
/// touches: an override must stay attached to the rung it overrides.
///
/// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
/// task D3. The existing editor had no test file — this is it, and it is
/// deliberately narrow: `params()` is the one piece of the sheet that can
/// silently LOSE data, and losing `goalID` is the single most likely defect
/// in this stream.
final class WeeklyGoalEditorParamsTests: XCTestCase {

    func testAnOverrideKeepsTheRowAttachedToItsLadder() {
        let goalID = UUID()
        let existing = WeeklyGoal(
            userID: UUID(), weekStartString: "2099-01-04", kind: .muscleSets,
            params: WeeklyGoalParams(muscleTargets: ["chest": 12], goalID: goalID),
            source: .coach, setAt: Date(timeIntervalSince1970: 0))

        let edited = WeeklyGoalEditorSheet.params(
            kind: .muscleSets,
            muscleTargets: [.chest: 16, .back: 12],
            existing: existing)

        XCTAssertEqual(edited.goalID, goalID,
                       "an edit is an OVERRIDE of the rung, not a divorce from it")
        XCTAssertEqual(edited.muscleTargets?["chest"], 16)
        XCTAssertNil(edited.targetSource,
                     "the athlete typed these; they did not come from the block")
    }

    func testAStandaloneGoalStillCarriesNoLadder() {
        let edited = WeeklyGoalEditorSheet.params(
            kind: .days, muscleTargets: [:], existing: nil)
        XCTAssertNil(edited.goalID)
    }

    /// Changing the KIND of this week's row is still an override of the same
    /// rung — the athlete decided this week is about volume rather than the
    /// lift, and the ladder needs to know which week that was.
    func testSwitchingKindStillOverridesTheSameRung() {
        let goalID = UUID()
        let existing = WeeklyGoal(
            userID: UUID(), weekStartString: "2099-01-04", kind: .lift,
            params: WeeklyGoalParams(exerciseID: UUID(), targetWeightLbs: 225,
                                     goalID: goalID),
            source: .coach, setAt: Date(timeIntervalSince1970: 0))

        let edited = WeeklyGoalEditorSheet.params(
            kind: .volume, muscleTargets: [:], volumeLbs: 120_000, existing: existing)

        XCTAssertEqual(edited.goalID, goalID)
        XCTAssertEqual(edited.volumeLbs, 120_000)
        XCTAssertNil(edited.targetWeightLbs,
                     "only the chosen kind's fields are written")
    }

    /// A `days` row writes NOTHING but its ladder attachment: the number is
    /// `profiles.weekly_session_goal` and there is exactly one of it.
    func testTheDaysKindStillWritesNoCount() {
        let goalID = UUID()
        let existing = WeeklyGoal(
            userID: UUID(), weekStartString: "2099-01-04", kind: .days,
            params: WeeklyGoalParams(goalID: goalID),
            source: .coach, setAt: Date(timeIntervalSince1970: 0))

        let edited = WeeklyGoalEditorSheet.params(
            kind: .days, muscleTargets: [:], existing: existing)

        XCTAssertNil(edited.count)
        XCTAssertEqual(edited.goalID, goalID)
    }

    // MARK: - The rung header

    /// Verbatim from the plan, straight quotes included: the ladder page's
    /// headline and this line have to name one milestone in one spelling.
    func testTheRungHeaderNamesTheWeekAndTheMilestone() {
        let line = WeeklyGoalEditorSheet.rungLine(
            .init(weekNumber: 3, weekCount: 8, milestone: "Bench 225 by Oct 18"))
        XCTAssertEqual(line,
                       "Week 3 of 8 of \"Bench 225 by Oct 18\". "
                       + "Change this week and Coach ladders from where you actually are.")
    }
}
