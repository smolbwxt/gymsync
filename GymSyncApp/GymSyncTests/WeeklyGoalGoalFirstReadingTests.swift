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

    // MARK: - bodyWeight: a cut and a bulk fill the same meter

    private func bodyWeightGoal(_ targetLbs: Decimal) -> WeeklyGoal {
        goal(.bodyWeight, WeeklyGoalParams(bodyWeightLbs: targetLbs))
    }

    /// A CUT. 183 at the block's start, chasing 178, currently 181: two of
    /// the five pounds are behind them.
    func testACutMeasuresTheSpanBelowTheBlocksStartWeight() {
        let progress = WeeklyGoalProgressMath.bodyWeightProgress(
            goal: bodyWeightGoal(178), currentLbs: 181, blockStartLbs: 183,
            unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 181)
        XCTAssertEqual(progress.target, 178)
        XCTAssertEqual(progress.unitLabel, "lbs")
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.chips.first?.done, 2, "two pounds down")
        XCTAssertEqual(progress.chips.first?.target, 5, "of the five there were")
    }

    /// A BULK — the same five-pound span, pointed the other way, filling
    /// identically. The direction comes from which side of the floor the
    /// milestone sits on, never from a flag.
    func testABulkFillsTheSameMeterInTheOppositeDirection() {
        let progress = WeeklyGoalProgressMath.bodyWeightProgress(
            goal: bodyWeightGoal(183), currentLbs: 180, blockStartLbs: 178,
            unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.chips.first?.done, 2)
        XCTAssertEqual(progress.chips.first?.target, 5)
    }

    /// MOVING THE WRONG WAY IS AN EMPTY METER, not negative progress: a
    /// cutting athlete who gained three pounds has none of the five behind
    /// them, and a meter that ran backwards would be arithmetic nobody asked
    /// a strip to show.
    func testMovingTheWrongWayReadsEmptyRatherThanNegative() {
        let progress = WeeklyGoalProgressMath.bodyWeightProgress(
            goal: bodyWeightGoal(178), currentLbs: 186, blockStartLbs: 183,
            unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.first?.done, 0)
        XCTAssertEqual(progress.chips.first?.target, 5)
        XCTAssertFalse(progress.met)
    }

    func testACutIsMetWhenTheScaleGoesBELOWTheTargetAndTheMeterFills() {
        let progress = WeeklyGoalProgressMath.bodyWeightProgress(
            goal: bodyWeightGoal(178), currentLbs: 177, blockStartLbs: 183,
            unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met, "a cut is met by going DOWN through the target")
        XCTAssertEqual(progress.chips.first?.done, 5,
                       "overshoot fills the meter, it does not run past it")
        XCTAssertEqual(progress.chips.first?.target, 5)
    }

    /// No scale reading is not a zero-pound athlete. The chrome renders and
    /// the meter stays empty, exactly as `liftProgress` does for a goal that
    /// was never finished being set.
    func testNoScaleReadingRendersChromeRatherThanAZero() {
        let progress = WeeklyGoalProgressMath.bodyWeightProgress(
            goal: bodyWeightGoal(178), currentLbs: nil, blockStartLbs: nil,
            unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.chips.isEmpty)
        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.target, 0)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.unitLabel, "lbs")
    }

    // MARK: - volume

    func testVolumeReadsFromZeroBecauseAWeeksTonnageStartsThere() {
        let progress = WeeklyGoalProgressMath.volumeProgress(
            goal: goal(.volume, WeeklyGoalParams(volumeLbs: 100_000)),
            volumeLbs: 62_400, unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 62_400)
        XCTAssertEqual(progress.target, 100_000)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.chips.first?.name, "VOLUME")
        XCTAssertEqual(progress.chips.first?.done, 62_400,
                       "no floor to measure from — value over target IS the fraction")
    }

    func testVolumeConvertsBOTHNumbersIntoTheAthletesUnit() {
        let progress = WeeklyGoalProgressMath.volumeProgress(
            goal: goal(.volume, WeeklyGoalParams(volumeLbs: 100_000)),
            volumeLbs: 50_000, unit: .kg, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.unitLabel, "kg")
        XCTAssertEqual(progress.value, 50_000 / 2.2046226218, accuracy: 0.01)
        XCTAssertEqual(progress.target, 100_000 / 2.2046226218, accuracy: 0.01)
        XCTAssertFalse(progress.met, "half the tonnage is half in either unit")
    }

    func testVolumeIsMetOnlyAgainstARealTarget() {
        let met = WeeklyGoalProgressMath.volumeProgress(
            goal: goal(.volume, WeeklyGoalParams(volumeLbs: 100_000)),
            volumeLbs: 100_000, unit: .lbs, now: wednesday, calendar: testCalendar)
        XCTAssertTrue(met.met)

        let noTarget = WeeklyGoalProgressMath.volumeProgress(
            goal: goal(.volume, WeeklyGoalParams()),
            volumeLbs: 0, unit: .lbs, now: wednesday, calendar: testCalendar)
        XCTAssertFalse(noTarget.met, "0 of 0 is not a week anyone finished")
    }

    // MARK: - The formatters

    /// `groupedNumber` is hand-rolled precisely so it is POSIX by
    /// construction — a `NumberFormatter` would put a full stop where a comma
    /// belongs in half of Europe and drift the capture. That is a
    /// correctness claim, and nothing checked it.
    func testGroupedNumberSeparatesThousandsWithoutALocale() {
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(0), "0")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(999), "999")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(1_000), "1,000")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(62_400), "62,400")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(1_000_000), "1,000,000")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(-1_234), "-1,234")
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(.infinity), "—",
                       "a number that is not one prints an em dash, never garbage")
    }

    /// Above a million is exactly where a block-long tonnage goal lives, and
    /// exactly where `HomeWeeklyGoalStrip.number`'s own ceiling would have
    /// printed an em dash — which is why volume does not go through it.
    func testGroupedNumberHandlesTheTonnageAMillionPoundGoalReaches() {
        XCTAssertEqual(WeeklyGoalProgressMath.groupedNumber(2_450_000), "2,450,000")
    }

    func testClockPrintsMinutesAndSecondsWithMinutesUnbounded() {
        XCTAssertEqual(WeeklyGoalProgressMath.clock(0), "0:00")
        XCTAssertEqual(WeeklyGoalProgressMath.clock(59), "0:59")
        XCTAssertEqual(WeeklyGoalProgressMath.clock(2_700), "45:00")
        XCTAssertEqual(WeeklyGoalProgressMath.clock(2_830), "47:10")
        XCTAssertEqual(WeeklyGoalProgressMath.clock(5_400), "90:00",
                       "a 90-minute benchmark reads 90:00, not 1:30:00")
        XCTAssertEqual(WeeklyGoalProgressMath.clock(-1), "—")
    }

    func testSpokenClockSaysTimeRatherThanAClockFace() {
        XCTAssertEqual(HomeWeeklyGoalStrip.spokenClock(2_700), "45 minutes")
        XCTAssertEqual(HomeWeeklyGoalStrip.spokenClock(2_830), "47 minutes 10 seconds")
        XCTAssertEqual(HomeWeeklyGoalStrip.spokenClock(60), "1 minute")
        XCTAssertEqual(HomeWeeklyGoalStrip.spokenClock(61), "1 minute 1 second")
    }

    // MARK: - What the dispatcher does until Stream A5 lands

    /// **THIS TEST DOCUMENTS AN ORDERING HAZARD, not a desired behaviour.**
    ///
    /// The dispatcher's signature is the shipped one and widening it is task
    /// A5's, so its four goal-first arms pass `0` / `nil` for every measured
    /// value: the rung's own TARGET survives (it comes from `params`) and the
    /// reading of what the athlete did is absent. Between task A2 (which
    /// widens `weekly_goals.kind`'s CHECK constraint and makes these rows
    /// insertable) and A5, a real row therefore renders a false zero.
    ///
    /// **A5 should land with or before A2.** When it does, these assertions
    /// change — that is the point of writing them down rather than leaving
    /// the hazard in prose only.
    func testTheFourNewKindsRenderChromeUntilStreamA5LandsTheirReaders() {
        let recovery = WeeklyGoalProgressMath.progress(
            goal: goal(.recovery, WeeklyGoalParams(count: 6, lissMinutes: 150)),
            logs: [], catalog: [:], sessions: [], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)
        XCTAssertEqual(recovery.target, 6, "the rung's own number survives")
        XCTAssertEqual(recovery.value, 0, "nothing reads the stretching count yet — A5")

        let bodyWeight = WeeklyGoalProgressMath.progress(
            goal: bodyWeightGoal(178),
            logs: [], catalog: [:], sessions: [], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)
        XCTAssertTrue(bodyWeight.chips.isEmpty, "no scale reading, so no meter")
        XCTAssertEqual(bodyWeight.value, 0)

        let volume = WeeklyGoalProgressMath.progress(
            goal: goal(.volume, WeeklyGoalParams(volumeLbs: 100_000)),
            logs: [], catalog: [:], sessions: [], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)
        XCTAssertEqual(volume.target, 100_000)
        XCTAssertEqual(volume.value, 0, "nothing sums the week's tonnage yet — A5")

        let benchmark = WeeklyGoalProgressMath.progress(
            goal: goal(.benchmark, WeeklyGoalParams(routineID: UUID(),
                                                    targetSeconds: 2_700)),
            logs: [], catalog: [:], sessions: [], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)
        XCTAssertEqual(benchmark.rightHandRead, WeeklyGoalProgressMath.noAttemptRead)
        XCTAssertEqual(HomeWeeklyGoalStrip.benchmarkReading(benchmark), "— → 45:00",
                       "and it says so rather than claiming a 0:00")
    }
}
