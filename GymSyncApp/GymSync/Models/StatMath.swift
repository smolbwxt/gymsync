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
            // Owner item 7 (2026-08-13): effective weight — added load plus
            // the stamped body weight, so bodyweight sets finally count.
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.effectiveWeightPounds else { continue }
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

    /// Prediction-equation validity boundary (research audit 2026-08:
    /// Epley-class formulas hold to ~10 reps and degrade sharply past ~12 —
    /// a raw 20-rep extrapolation would claim +67%). Inputs beyond the cap
    /// estimate as cap-rep sets: a conservative floor, never fiction.
    static let oneRepMaxRepCap = 12

    /// Epley-formula estimated one-rep max: `weight × (1 + reps/30)`,
    /// reps clamped to `oneRepMaxRepCap`.
    static func estimatedOneRepMax(weight: Decimal, reps: Int) -> Decimal {
        guard reps > 0 else { return weight }
        let capped = min(reps, Self.oneRepMaxRepCap)
        return weight * (1 + Decimal(capped) / 30)
    }

    /// RPE-aware variant (research audit 2026-08): effective reps = reps +
    /// reps-in-reserve (RIR = 10 − RPE, the standard coaching conversion) —
    /// a 225×5 @7 carries ~3 in the tank and estimates like an 8-rep max
    /// effort. RIR credit caps at 4 (far-from-failure self-reports are
    /// unreliable) and the summed reps still honor `oneRepMaxRepCap`.
    /// nil or out-of-range RPE falls back to the plain estimate.
    ///
    /// Consumers: SUGGESTION paths only (WorkingWeight's qualifying-set
    /// pick). PR judgments deliberately stay on the plain variant — a
    /// record is what you DID, not what you had in the tank.
    static func estimatedOneRepMax(weight: Decimal, reps: Int, rpe: Decimal?) -> Decimal {
        guard reps > 0, let rpe, rpe >= 5, rpe <= 10 else {
            return estimatedOneRepMax(weight: weight, reps: reps)
        }
        let rir = NSDecimalNumber(decimal: 10 - rpe).intValue
        return estimatedOneRepMax(weight: weight, reps: reps + max(0, min(rir, 4)))
    }

    /// Redesign (2026-07-23): projected working weight for a routine exercise
    /// row, from the user's best PR — inverse Epley (weight for target reps t
    /// = est1RM / (1 + t/30)), rounded to the nearest 5 lbs. `targetReps` nil
    /// falls back to the PR's own rep count (projection ≈ the PR itself).
    /// Callers show NO estimate when there is no PR — never a guess.
    static func projectedWeight(prWeight: Decimal, prReps: Int, targetReps: Int?) -> Int? {
        let oneRM = estimatedOneRepMax(weight: prWeight, reps: prReps)
        let t = max(1, targetReps ?? prReps)
        let raw = NSDecimalNumber(decimal: oneRM).doubleValue / (1 + Double(t) / 30)
        let rounded = Int((raw / 5).rounded() * 5)
        return rounded > 0 ? rounded : nil
    }

    // MARK: - Routine duration estimate (Home / Library / Routine Builder)

    /// Seconds budgeted per set: execution + logging overhead (owner
    /// 2026-08-13 — the flat 15 min/exercise consistently overestimated).
    /// A future pass replaces this constant with measured set durations
    /// (the set-pace instrumentation already records them).
    static let secondsPerSet = 120

    /// Duration estimate from the routine's actual prescription:
    /// 2 min per set + rest BETWEEN sets (n−1 rests) + a transit window
    /// between exercises. Exercises missing a prescription fall back to
    /// 3 sets / the caller's default rest.
    static func estimatedMinutes(exercises: [RoutineExercise], defaultRestSeconds: Int = 120) -> Int {
        guard !exercises.isEmpty else { return 0 }
        var seconds = 0
        for exercise in exercises {
            let sets = max(exercise.targetSets ?? 3, 1)
            let rest = exercise.restSeconds ?? defaultRestSeconds
            seconds += sets * secondsPerSet + (sets - 1) * rest
        }
        seconds += (exercises.count - 1) * TransitWindow.seconds
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// Count-only fallback for callers without the exercise list (schedule
    /// sheet, calendar bridge): the formula above at its defaults
    /// (3 sets × 2 min + 2 × 2 min rest + transit ≈ 12 min/exercise).
    static func estimatedMinutes(exerciseCount: Int) -> Int {
        max(0, exerciseCount) * 12
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
            // Owner item 7: effective weight, matching weeklyVolumes.
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.effectiveWeightPounds else { continue }
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
