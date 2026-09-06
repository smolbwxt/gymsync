import Foundation

// MARK: - CalendarMonthMath
//
// The two expressions that place a real month on `CalendarMonthGrid`, pulled
// out as pure functions so they can be tested (the `ProgramMath` /
// `CampaignProgressMath` idiom: no network, no `Date.now`, every input a
// value).
//
// They exist as a PAIR and are only correct as a pair. `weekdayLabels`
// rotates the locale's symbols to start at `firstWeekday`; `leadingBlanks`
// counts how many of those columns come before day 1. Get one rotation right
// and the other wrong and the grid renders a plausible month with every day
// in the wrong column — which the `calendar-scheduling` frame cannot catch,
// because that frame is a fixture built to match the v7 proof's grid rather
// than any real month (review finding F7).

enum CalendarMonthMath {

    /// Column headings, first-weekday first: `S M T W T F S` under a
    /// Sunday-first locale, `M T W T F S S` under a Monday-first one.
    static func weekdayLabels(_ cal: Calendar) -> [String] {
        let symbols = cal.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        let first = cal.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7].uppercased() }
    }

    /// Blank cells before day 1, 0-6 — day 1's column index in the header
    /// `weekdayLabels` produces. Same expression `TrainingMonthField`'s
    /// callers use, so the two grids agree about where a month starts.
    static func leadingBlanks(monthStart: Date, cal: Calendar) -> Int {
        (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
    }
}
