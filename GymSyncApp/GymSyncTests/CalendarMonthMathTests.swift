import XCTest
@testable import GymSync

/// The one part of the calendar page with a real chance of being silently
/// wrong: the header rotation and the leading-blank count have to agree, and
/// the `calendar-scheduling` catalog frame cannot catch a disagreement
/// because that frame is a fixture built to match the v7 proof's grid rather
/// than any real month (review finding F7).
///
/// Pure and hermetic — a fixed Gregorian calendar in a fixed locale and
/// time zone, no `Date.now`, no network.
final class CalendarMonthMathTests: XCTestCase {

    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func monthStart(_ year: Int, _ month: Int, in cal: Calendar) -> Date {
        let date = cal.date(from: DateComponents(year: year, month: month, day: 1))
        return unwrap(date)
    }

    /// `XCTUnwrap` throws, and every caller here is non-throwing; this keeps
    /// the failure message without spreading `throws` through the file.
    private func unwrap(_ date: Date?, file: StaticString = #filePath, line: UInt = #line) -> Date {
        guard let date else {
            XCTFail("could not build the date", file: file, line: line)
            return .distantPast
        }
        return date
    }

    // MARK: The rotation itself

    func testWeekdayLabelsStartAtTheCalendarsFirstWeekday() {
        let sundayFirst = calendar(firstWeekday: 1)
        let mondayFirst = calendar(firstWeekday: 2)

        let sundayLabels = CalendarMonthMath.weekdayLabels(sundayFirst)
        let mondayLabels = CalendarMonthMath.weekdayLabels(mondayFirst)

        XCTAssertEqual(sundayLabels.count, 7)
        XCTAssertEqual(mondayLabels.count, 7)
        XCTAssertEqual(sundayLabels, ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(mondayLabels, ["M", "T", "W", "T", "F", "S", "S"])
        // A rotation, not a reshuffle: the same multiset either way.
        XCTAssertEqual(sundayLabels.sorted(), mondayLabels.sorted())
    }

    // MARK: The count

    func testLeadingBlanksForAKnownMonth() {
        // 1 September 2026 is a Tuesday.
        let sundayFirst = calendar(firstWeekday: 1)
        let mondayFirst = calendar(firstWeekday: 2)

        XCTAssertEqual(
            CalendarMonthMath.leadingBlanks(monthStart: monthStart(2026, 9, in: sundayFirst),
                                            cal: sundayFirst),
            2, "Sunday-first: Sun and Mon come before Tuesday the 1st")
        XCTAssertEqual(
            CalendarMonthMath.leadingBlanks(monthStart: monthStart(2026, 9, in: mondayFirst),
                                            cal: mondayFirst),
            1, "Monday-first: only Mon comes before Tuesday the 1st")
    }

    func testLeadingBlanksIsAlwaysAColumnIndex() {
        for firstWeekday in 1...7 {
            let cal = calendar(firstWeekday: firstWeekday)
            for month in 1...12 {
                let blanks = CalendarMonthMath.leadingBlanks(monthStart: monthStart(2026, month, in: cal),
                                                             cal: cal)
                XCTAssertTrue((0...6).contains(blanks),
                              "firstWeekday \(firstWeekday), month \(month): \(blanks)")
            }
        }
    }

    // MARK: The pair — the invariant that actually matters
    //
    // Day 1 is drawn in column `leadingBlanks`. The heading above that column
    // must therefore be day 1's own weekday. Get one rotation right and the
    // other wrong and the grid renders a plausible month with every day in
    // the wrong column; this is the assertion that catches it.

    func testTheHeadingAboveDayOneIsDayOnesWeekday() {
        for firstWeekday in 1...7 {
            let cal = calendar(firstWeekday: firstWeekday)
            let labels = CalendarMonthMath.weekdayLabels(cal)
            for year in [2025, 2026, 2027] {
                for month in 1...12 {
                    let start = monthStart(year, month, in: cal)
                    let blanks = CalendarMonthMath.leadingBlanks(monthStart: start, cal: cal)
                    let weekday = cal.component(.weekday, from: start)   // 1 = Sunday
                    let expected = cal.veryShortWeekdaySymbols[weekday - 1].uppercased()
                    XCTAssertEqual(labels[blanks], expected,
                                   "firstWeekday \(firstWeekday), \(year)-\(month): day 1 sits under \(labels[blanks]), not \(expected)")
                }
            }
        }
    }
}
