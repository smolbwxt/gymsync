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

    /// Sum of reps×weight for `logs`, bucketed into `weeks` Monday-start
    /// calendar weeks ending with the current week (last element). Excludes
    /// failed/penalty sets and sets missing reps or weight — mirrors the
    /// exclusion filters used by `SessionRepository.exerciseHistory`/
    /// `recentSetLogs`. Weeks with no qualifying volume return `0`.
    ///
    /// `now` defaults to `.now` (not part of the brief's call signature) so
    /// production call sites read as `weeklyVolumes(logs:weeks:calendar:)`
    /// while tests can still pin the reference date.
    static func weeklyVolumes(
        logs: [SetLog],
        weeks: Int = 6,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Decimal] {
        guard weeks > 0 else { return [] }
        let currentWeekStart = startOfWeek(containing: now, calendar: calendar)
        let weekStarts: [Date] = (0..<weeks).map { offset in
            calendar.date(byAdding: .day, value: -7 * (weeks - 1 - offset), to: currentWeekStart)
                ?? currentWeekStart
        }

        var totals = [Decimal](repeating: 0, count: weeks)
        for log in logs {
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.weight else { continue }
            for (index, weekStart) in weekStarts.enumerated() {
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { continue }
                if log.loggedAt >= weekStart && log.loggedAt < weekEnd {
                    totals[index] += Decimal(reps) * weight
                    break
                }
            }
        }
        return totals
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

    // MARK: - Estimated 1RM (Exercise History stat tile + trend chart)

    /// Epley-formula estimated one-rep max: `weight × (1 + reps/30)`.
    static func estimatedOneRepMax(weight: Decimal, reps: Int) -> Decimal {
        guard reps > 0 else { return weight }
        return weight * (1 + Decimal(reps) / 30)
    }

    // MARK: - Routine duration estimate (Home / Library / Routine Builder)

    /// Rough duration estimate for a routine card's "~X min" meta suffix.
    /// Flat ~15 min/exercise (warmup + working sets + rest) — a single shared
    /// heuristic so Home, Library, and the Routine Builder header all agree.
    static func estimatedMinutes(exerciseCount: Int) -> Int {
        max(0, exerciseCount) * 15
    }

    // MARK: - Month-over-month volume trend (Stats Lifetime Volume card)

    /// Percent change in lifted volume between the calendar month containing
    /// `now` (so far) and the immediately preceding calendar month.
    /// Returns `nil` when there's no prior-month volume to compare against
    /// (division by zero / no baseline — the caller should hide the trend).
    static func monthOverMonthVolumeChangePercent(
        logs: [SetLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let currentMonthStart = calendar.date(from: components),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart)
        else { return nil }

        var thisMonthVolume = Decimal(0)
        var lastMonthVolume = Decimal(0)
        for log in logs {
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.weight else { continue }
            let volume = Decimal(reps) * weight
            if log.loggedAt >= currentMonthStart {
                thisMonthVolume += volume
            } else if log.loggedAt >= lastMonthStart {
                lastMonthVolume += volume
            }
        }

        guard lastMonthVolume > 0 else { return nil }
        let delta = NSDecimalNumber(decimal: (thisMonthVolume - lastMonthVolume) / lastMonthVolume).doubleValue
        return delta * 100
    }

    // MARK: - Body weight trend (Stats "Body Weight" card, Phase H Task 3)

    /// Maps `logs` (any order) into `TrendChartView`'s `(Date, Double)` chart
    /// point shape (Features/Stats/TrendChartView.swift:26), chronologically
    /// sorted oldest-first — `BodyWeightLogRepository.recent` returns
    /// newest-first (a display-list order), so this re-sorts before handing
    /// data to the chart, same "sort before plotting" step
    /// `ExerciseHistoryView.chartData` performs for the Est. 1RM trend
    /// (Features/Stats/ExerciseHistoryView.swift:23-31).
    static func bodyWeightTrendPoints(logs: [BodyWeightLog]) -> [(Date, Double)] {
        logs
            .map { ($0.loggedAt, NSDecimalNumber(decimal: $0.weight).doubleValue) }
            .sorted { $0.0 < $1.0 }
    }

    /// "182.4 lbs" / "181 kg" — trims a trailing ".0" the same way
    /// `ExerciseHistoryView.weightText`/`StatsTabView.trimmedDecimal` already
    /// do for other weight displays on this screen, so a whole-number log
    /// doesn't grow a spurious decimal.
    static func formattedBodyWeight(_ weight: Decimal, unit: String) -> String {
        var value = weight
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let text = rounded == value ? "\(rounded)" : "\(value)"
        return "\(text) \(unit)"
    }
}
