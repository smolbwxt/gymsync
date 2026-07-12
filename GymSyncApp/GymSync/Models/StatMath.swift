import Foundation

/// Pure, testable derivations backing the Home (and later You-tab) stat tiles.
/// No repository/network dependency — callers pass already-fetched data in.
enum StatMath {

    // MARK: - Week bucketing (Monday-start, user's calendar)

    /// Start of the Monday-anchored week containing `date`, in `calendar`'s
    /// time zone. `firstWeekday` is forced to Monday (2) regardless of the
    /// calendar's locale default so "current week" is well-defined
    /// independent of the device region.
    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let components = mondayCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return mondayCalendar.date(from: components) ?? date
    }

    /// True when `date` falls within the Monday–Sunday week containing `now`.
    static func isInCurrentWeek(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let weekStart = startOfWeek(containing: now, calendar: calendar)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return date >= weekStart && date < weekEnd
    }

    /// Count of `sessions` whose `completedAt` falls in the current week.
    static func workoutsThisWeek(
        sessions: [WorkoutSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        sessions.reduce(into: 0) { count, session in
            guard let completedAt = session.completedAt,
                  isInCurrentWeek(completedAt, now: now, calendar: calendar) else { return }
            count += 1
        }
    }

    /// Start of the calendar month containing `now` — backs "PRs this month".
    static func startOfMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    // MARK: - Compact number formatting

    /// Compact display for large counts: 999 -> "999", 48_120 -> "48.1k",
    /// 1_200_000 -> "1.2M". One decimal place, trailing ".0" trimmed.
    static func compactNumber(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let sign = doubleValue < 0 ? "-" : ""
        let absValue = abs(doubleValue)

        switch absValue {
        case 1_000_000...:
            return sign + trimmedOneDecimal(absValue / 1_000_000) + "M"
        case 1_000...:
            return sign + trimmedOneDecimal(absValue / 1_000) + "k"
        default:
            return sign + String(Int(absValue.rounded()))
        }
    }

    /// Rounds to one decimal place and drops a trailing ".0".
    private static func trimmedOneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}
