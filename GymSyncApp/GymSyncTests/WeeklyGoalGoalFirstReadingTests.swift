import XCTest
@testable import GymSync

/// The goal-first readings that are not `recovery` — plan task 0.3's other
/// three kinds and the formatters they print through.
///
/// `WeeklyGoalRecoveryReadingTests` covers `recovery` because it had a
/// controller ruling; this file covers the rest, which had none and shipped
/// untested (review finding 6). Everything here is pure: no store, no clock,
/// no HealthKit — the measured value is a parameter in every case, which is
/// what makes a Health-backed reading testable at all (global constraint 5).
final class WeeklyGoalGoalFirstReadingTests: XCTestCase {

    // MARK: - Fixtures

    /// A calendar with a fixed timezone and `firstWeekday`, so "this week" is
    /// the same week on every machine — `WeeklyGoalProgressTests`' own.
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

    private func goal(_ kind: WeeklyGoalKind, _ params: WeeklyGoalParams,
                      source: WeeklyGoalSource = .coach) -> WeeklyGoal {
        WeeklyGoal(userID: UUID(),
                   weekStartString: WeekMath.weekStartString(wednesday,
                                                             calendar: testCalendar),
                   kind: kind, params: params, source: source, setAt: wednesday)
    }

    // MARK: - benchmark: no attempt is not a zero (review finding 2)

    func testABenchmarkNobodyHasRunReadsAnEmDashRatherThanZero() {
        let progress = WeeklyGoalProgressMath.benchmarkProgress(
            goal: goal(.benchmark, WeeklyGoalParams(routineID: UUID(),
                                                    targetSeconds: 2700)),
            bestSeconds: nil, startSeconds: nil, routineName: "Murph",
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0, "value 0 is the SIGNAL for no attempt")
        XCTAssertEqual(progress.target, 2700)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.rightHandRead, WeeklyGoalProgressMath.noAttemptRead,
                       "the state is said, not shown as a time that means something else")
        XCTAssertEqual(progress.chips.first?.done, 0, "and the meter is empty")

        // The reading itself — a 0:00 here would claim the fastest Murph ever
        // run. This is the half the doc comment promised and the code did not
        // deliver before finding 2.
        XCTAssertEqual(HomeWeeklyGoalStrip.benchmarkReading(progress),
                       "Murph — → 45:00")
    }

    func testABenchmarkWithAnAttemptPrintsBothClocks() {
        let progress = WeeklyGoalProgressMath.benchmarkProgress(
            goal: goal(.benchmark, WeeklyGoalParams(routineID: UUID(),
                                                    targetSeconds: 2700)),
            bestSeconds: 2830, startSeconds: 3000, routineName: "Murph",
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 2830)
        XCTAssertFalse(progress.met, "47:10 has not beaten 45:00")
        XCTAssertEqual(HomeWeeklyGoalStrip.benchmarkReading(progress),
                       "Murph 47:10 → 45:00")
        // The meter runs DOWNWARD from the first attempt: 170 s shaved of the
        // 300 s there were to shave.
        XCTAssertEqual(progress.chips.first?.done, 170)
        XCTAssertEqual(progress.chips.first?.target, 300)
    }

    func testABenchmarkIsMetWhenTheTimeFALLSBelowTheTarget() {
        let progress = WeeklyGoalProgressMath.benchmarkProgress(
            goal: goal(.benchmark, WeeklyGoalParams(routineID: UUID(),
                                                    targetSeconds: 2700)),
            bestSeconds: 2650, startSeconds: 3000, routineName: "Murph",
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met, "lower is better on this one")
        XCTAssertEqual(progress.rightHandRead, "",
                       "the met kicker already says how much week is left")
    }
}
