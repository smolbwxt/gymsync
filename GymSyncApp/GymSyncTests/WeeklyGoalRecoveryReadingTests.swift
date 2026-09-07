import XCTest
@testable import GymSync

/// The `recovery` kind's reading — controller ruling 1 on plan task 0.3.
///
/// Recovery is the one goal with TWO metrics and it is still ONE goal
/// (spec §2.3). The ruling settles which of the two owns what:
///
///   * the PRIMARY is the stretching count — what the block actually
///     schedules. It owns `value`, `target`, `met` and the strip's
///     right-hand read;
///   * the LISS minutes are a COMPANION, carried as their own chip beside
///     the subject;
///   * and when Apple Health has never been asked, that companion reads
///     **CONNECT HEALTH**, never `0 min` — the same harm
///     `distanceProgress` already guards against, pointed at the companion.
///     LISS minutes come from Health and nowhere else, so an unasked
///     permission produces a perfect, silent zero.
final class WeeklyGoalRecoveryReadingTests: XCTestCase {

    /// A calendar with a fixed timezone and `firstWeekday`, so "this week"
    /// is the same week on every machine that runs these —
    /// `WeeklyGoalProgressTests`' own fixture calendar.
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 2026-09-09, noon Eastern. Its week runs Sun 09-06 …
    /// Sat 09-12, so `daysRemaining` is 4.
    private var wednesday: Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
    }

    private func recoveryGoal(stretches: Int, liss: Int,
                              source: WeeklyGoalSource = .coach) -> WeeklyGoal {
        WeeklyGoal(userID: UUID(),
                   weekStartString: WeekMath.weekStartString(wednesday,
                                                             calendar: testCalendar),
                   kind: .recovery,
                   params: WeeklyGoalParams(count: stretches, lissMinutes: liss),
                   source: source,
                   setAt: wednesday)
    }

    // MARK: - The primary owns the fraction

    func testTheStretchingCountOwnsTheFractionAndTheRightHandRead() {
        let progress = WeeklyGoalProgressMath.recoveryProgress(
            goal: recoveryGoal(stretches: 6, liss: 150),
            stretchingExercisesDone: 4, lissMinutesDone: 120,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 4, "the fraction is the stretching count's")
        XCTAssertEqual(progress.target, 6)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT",
                       "the week's read, not Health's — the count is the app's own")
        XCTAssertEqual(progress.kicker, "THIS WEEK · COACH'S GOAL")
    }

    func testTheStretchingCountAloneDecidesMet() {
        let progress = WeeklyGoalProgressMath.recoveryProgress(
            goal: recoveryGoal(stretches: 6, liss: 150),
            stretchingExercisesDone: 6, lissMinutesDone: 0,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met, "the primary metric is what the block schedules")
        XCTAssertEqual(progress.rightHandRead, "",
                       "the met kicker already says how much week is left")
    }

    // MARK: - The companion is its own chip

    func testTheLissCompanionIsItsOwnChipBesideTheSubject() {
        let progress = WeeklyGoalProgressMath.recoveryProgress(
            goal: recoveryGoal(stretches: 6, liss: 150),
            stretchingExercisesDone: 4, lissMinutesDone: 120,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 2, "the subject, then the companion")
        XCTAssertEqual(progress.chips.first?.name, "STRETCHES")
        XCTAssertEqual(progress.chips.first?.done, 4)
        XCTAssertEqual(progress.chips.first?.target, 6)

        let companion = progress.chips.last
        XCTAssertEqual(companion?.name, WeeklyGoalProgressMath.lissChipName)
        XCTAssertEqual(companion?.done, 120)
        XCTAssertEqual(companion?.target, 150)

        XCTAssertEqual(HomeWeeklyGoalStrip.recoveryCompanionLine(companion),
                       "120 / 150 LISS min")
    }

    // MARK: - CONNECT HEALTH, never 0 min

    func testAnUnaskedHealthPermissionSaysConnectRatherThanZeroMinutes() {
        let progress = WeeklyGoalProgressMath.recoveryProgress(
            goal: recoveryGoal(stretches: 6, liss: 150),
            stretchingExercisesDone: 4, lissMinutesDone: 0,
            healthNeedsConnecting: true,
            now: wednesday, calendar: testCalendar)

        let companion = progress.chips.last
        XCTAssertEqual(companion?.name, WeeklyGoalProgressMath.connectHealthRead)
        XCTAssertEqual(HomeWeeklyGoalStrip.recoveryCompanionLine(companion),
                       "CONNECT HEALTH",
                       "0 min must never be how the strip says Health is not connected")

        // And the primary is untouched: the stretching count is the app's
        // own record, so it still reads and still owns the right-hand read.
        XCTAssertEqual(progress.value, 4)
        XCTAssertEqual(progress.target, 6)
        XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT")
    }

    func testAGoalWithNoLissCompanionDrawsNoCompanionLine() {
        let progress = WeeklyGoalProgressMath.recoveryProgress(
            goal: recoveryGoal(stretches: 6, liss: 0),
            stretchingExercisesDone: 4, lissMinutesDone: 0,
            now: wednesday, calendar: testCalendar)

        XCTAssertNil(HomeWeeklyGoalStrip.recoveryCompanionLine(progress.chips.last),
                     "a recovery goal that asks for no minutes says nothing about them")
        XCTAssertNil(HomeWeeklyGoalStrip.recoveryCompanionLine(nil))
    }
}
