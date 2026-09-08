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
}
