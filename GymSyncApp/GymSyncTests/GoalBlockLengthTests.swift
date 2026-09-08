import XCTest
@testable import GymSync

/// The block length comes from the milestone date (task B2, spec §5.3) — and
/// it is PURE, so every one of these is a fact rather than a reading of the
/// clock.
final class GoalBlockLengthTests: XCTestCase {

    /// A fixed calendar, so a runner in any timezone counts the same days.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Noon UTC on 2026-09-07, the same anchoring the Task 0 fixtures use:
    /// midday keeps the calendar day stable across the timezones a simulator
    /// runs in.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func days(_ count: Int) -> Date {
        calendar.date(byAdding: .day, value: count, to: now) ?? now
    }

    private func weeks(_ byDate: Date?) -> Int {
        GoalBlockLength.weeks(byDate: byDate, from: now, calendar: calendar)
    }

    func testWholeWeeksComeOutWhole() {
        XCTAssertEqual(weeks(days(56)), 8)
    }

    func testAPartWeekRoundsUpRatherThanGivingUpAWeek() {
        XCTAssertEqual(weeks(days(60)), 9,
                       "a block that ends before the date is a block that gives up a week")
        XCTAssertEqual(weeks(days(57)), 9)
    }

    func testNoDateIsTheBlockLengthTheBuilderHasAlwaysDefaultedTo() {
        XCTAssertEqual(weeks(nil), GoalBlockLength.defaultWeeks)
        XCTAssertEqual(GoalBlockLength.defaultWeeks, 8)
    }

    func testADateInsideFourWeeksStillGetsAFourWeekBlock() {
        // The ladder then says the milestone is out of reach (task B5), which
        // is honest — refusing to build is not.
        XCTAssertEqual(weeks(days(3)), GoalBlockLength.minimumWeeks)
        XCTAssertEqual(weeks(days(0)), GoalBlockLength.minimumWeeks)
        XCTAssertEqual(GoalBlockLength.minimumWeeks, 4)
    }

    func testAFarDateIsCappedAtTheEnrollmentColumnsOwnCeiling() {
        XCTAssertEqual(weeks(days(500)), GoalBlockLength.maximumWeeks)
        XCTAssertEqual(GoalBlockLength.maximumWeeks, 52,
                       "program_enrollments.weeks is CHECKed BETWEEN 1 AND 52")
    }

    func testADateInThePastIsTheFloorAndNeverANegativeBlock() {
        XCTAssertEqual(weeks(days(-10)), GoalBlockLength.minimumWeeks)
        XCTAssertEqual(weeks(days(-500)), GoalBlockLength.minimumWeeks)
    }

    // MARK: - B5, "cannot reach by the date"

    /// Noon UTC on a 2026 day, read through the fixed calendar above so the
    /// formatter and the arithmetic agree in every runner timezone.
    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month,
                                           day: dayOfMonth, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func liftRungs(_ pounds: [Int]) -> [GoalTarget] {
        pounds.map { GoalTarget(targetWeightLbs: Decimal($0)) }
    }

    private func reach(_ rungs: [GoalTarget], milestone: Int,
                       byDate: Date?, weeklyGain: Double?) -> GoalBlockLength.Reach {
        GoalBlockLength.reach(metric: .liftOneRepMax, rungs: rungs,
                              milestone: GoalTarget(targetWeightLbs: Decimal(milestone)),
                              byDate: byDate, weeklyGain: weeklyGain,
                              from: day(9, 7), calendar: calendar)
    }

    func testALadderThatFallsShortSaysSoAndSaysByHowMuch() {
        let answer = reach(liftRungs([190, 200, 210, 218]), milestone: 225,
                           byDate: day(10, 18), weeklyGain: nil)
        XCTAssertFalse(answer.reaches)
        XCTAssertEqual(answer.projected.targetWeightLbs, Decimal(218),
                       "what the block DOES get to")
        XCTAssertNil(answer.achievableDate,
                     "no weekly gain is no arithmetic, and no arithmetic is no date")
    }

    func testTheSentenceNamesTheDateTheBlockCouldBuildTo() {
        // Eight rungs, 170 up to 205, against a 225 milestone: 20 lb short at
        // 5 lb a week is four more weeks, and Oct 18 + 4 weeks is Nov 15.
        let rungs = liftRungs((0..<8).map { 170 + $0 * 5 })
        let answer = reach(rungs, milestone: 225, byDate: day(10, 18), weeklyGain: 5)
        XCTAssertFalse(answer.reaches)
        XCTAssertEqual(answer.projected.targetWeightLbs, Decimal(205))
        XCTAssertEqual(answer.achievableDate, day(11, 15))
        XCTAssertEqual(
            GoalBlockLength.reachSentence(milestoneText: "Bench 225",
                                          byDate: day(10, 18), reach: answer,
                                          calendar: calendar),
            "Bench 225 by Oct 18 needs more than this block can safely give; "
            + "Nov 15 is the date I can build to.")
    }

    func testALadderThatReachesSaysNothingAtAll() {
        let answer = reach(liftRungs([205, 215, 225]), milestone: 225,
                           byDate: day(10, 18), weeklyGain: 5)
        XCTAssertTrue(answer.reaches)
        XCTAssertEqual(answer.projected.targetWeightLbs, Decimal(225))
        XCTAssertNil(answer.achievableDate)
        XCTAssertNil(GoalBlockLength.reachSentence(milestoneText: "Bench 225",
                                                   byDate: day(10, 18), reach: answer,
                                                   calendar: calendar),
                     "there is no gap to be honest about")
    }

    func testAFlatLadderStopsAfterTheFirstClauseRatherThanInventingADate() {
        let answer = reach(liftRungs([205, 205, 205]), milestone: 225,
                           byDate: day(10, 18), weeklyGain: nil)
        XCTAssertNil(answer.achievableDate)
        XCTAssertEqual(
            GoalBlockLength.reachSentence(milestoneText: "Bench 225",
                                          byDate: day(10, 18), reach: answer,
                                          calendar: calendar),
            "Bench 225 by Oct 18 needs more than this block can safely give.")
    }

    func testAGoalWithNoDateNamesNoDateInTheSentenceEither() {
        let answer = reach(liftRungs([205]), milestone: 225,
                           byDate: nil, weeklyGain: nil)
        XCTAssertEqual(
            GoalBlockLength.reachSentence(milestoneText: "Bench 225", byDate: nil,
                                          reach: answer, calendar: calendar),
            "Bench 225 needs more than this block can safely give.")
    }

    func testAnEmptyLadderReachesNothingAndProjectsTheMilestoneItself() {
        let answer = reach([], milestone: 225, byDate: day(10, 18), weeklyGain: 5)
        XCTAssertFalse(answer.reaches)
        XCTAssertEqual(answer.projected.targetWeightLbs, Decimal(225))
        XCTAssertNil(answer.achievableDate)
    }

    func testABenchmarkTimeIsBeatenByGoingDown() {
        // The one metric where the milestone is BELOW the rung, so "reached"
        // and "shortfall" both run the other way.
        let rungs = [GoalTarget(targetSeconds: 3_000)]
        let milestone = GoalTarget(targetSeconds: 2_700)
        XCTAssertFalse(LadderMath.reached(metric: .benchmarkTime,
                                          measured: rungs[0], target: milestone))
        XCTAssertTrue(LadderMath.reached(metric: .benchmarkTime,
                                         measured: GoalTarget(targetSeconds: 2_400),
                                         target: milestone))
        let answer = GoalBlockLength.reach(metric: .benchmarkTime, rungs: rungs,
                                           milestone: milestone, byDate: day(10, 18),
                                           weeklyGain: 150, from: day(9, 7),
                                           calendar: calendar)
        XCTAssertFalse(answer.reaches)
        XCTAssertEqual(answer.achievableDate, day(11, 1),
                       "300 seconds short at 150 a week is two more weeks")
    }

    func testAMuscleSetsMilestoneGetsNoInventedDateBecauseItIsNotOneNumber() {
        let answer = GoalBlockLength.reach(
            metric: .weeklyMuscleSets,
            rungs: [GoalTarget(muscleTargets: ["chest": 10])],
            milestone: GoalTarget(muscleTargets: ["chest": 16, "back": 18]),
            byDate: day(10, 18), weeklyGain: 1, from: day(9, 7), calendar: calendar)
        XCTAssertFalse(answer.reaches)
        XCTAssertNil(answer.achievableDate,
                     "six groups are six gaps — one date over them would be a guess")
    }
}
