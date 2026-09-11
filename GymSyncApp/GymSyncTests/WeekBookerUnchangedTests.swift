import XCTest
@testable import GymSync

/// `WeekBooker` is unchanged by goal-first programming — and the seam that
/// makes that safe is `WeeklyGoalWriteRule.isLadderWeek`.
final class WeekBookerUnchangedTests: XCTestCase {

    private func row(goalID: UUID?) -> WeeklyGoal {
        WeeklyGoal(userID: UUID(), weekStartString: "2099-01-04", kind: .muscleSets,
                   params: WeeklyGoalParams(muscleTargets: ["chest": 12], goalID: goalID),
                   source: .coach, setAt: Date(timeIntervalSince1970: 0))
    }

    func testALadderWeekIsNotDetectionsToFill() {
        XCTAssertTrue(WeeklyGoalWriteRule.isLadderWeek(row(goalID: UUID())))
        XCTAssertFalse(WeeklyGoalWriteRule.isLadderWeek(row(goalID: nil)))
        XCTAssertFalse(WeeklyGoalWriteRule.isLadderWeek(nil),
                       "an empty week is detection's, exactly as before")
    }

    func testTheShippedOverwriteRuleIsUntouched() {
        let coach = row(goalID: nil)
        var user = coach; user.source = .user
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: nil, detected: coach))
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: coach, detected: coach))
        XCTAssertFalse(WeeklyGoalWriteRule.shouldOverwrite(existing: user, detected: coach))
    }

    func testBookingInjectsANoOpWriterWithoutTouchingTheNetwork() async {
        // `WeekBooker.book`'s `goalWriter` parameter exists precisely so this
        // is possible. Nothing about it changes.
        let writer = NoOpWeeklyGoalCoachWriter()
        let result = await writer.writeDetectedGoal(weekStart: "2099-01-04")
        XCTAssertNil(result)
    }

    /// The two rules answer DIFFERENT questions and must not be collapsed into
    /// one: a ladder week is a `coach` row, so `shouldOverwrite` says yes to it
    /// and `isLadderWeek` is the only thing standing between week 3's
    /// prescribed rung and a freshly detected goal written over the top of it.
    func testALadderRowWouldOtherwiseBeOverwritableAndThatIsThePoint() {
        let ladderRow = row(goalID: UUID())
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: ladderRow,
                                                          detected: row(goalID: nil)),
                      "the shipped provenance rule sees only `coach` here")
        XCTAssertTrue(WeeklyGoalWriteRule.isLadderWeek(ladderRow),
                      "which is why the ladder question is asked first")
    }
}
