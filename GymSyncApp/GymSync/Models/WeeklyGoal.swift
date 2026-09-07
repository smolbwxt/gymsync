import Foundation

// MARK: - WeeklyGoal
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B. Plan: docs/superpowers/plans/2026-09-06-home-v3
// -production-plan.md, task 0.2.
//
// One goal per user per week, of one of five kinds. Coach detects it when a
// week starts with no row (Stream A's `WeeklyGoalDetector`); the user may
// override it in the editor (Stream C), and once they have, Coach may only
// PROPOSE a change (owner answer 3) — it never overwrites a `source = user`
// row. The server contract is `weekly_goals` (Stream A task A1).
//
// Repository, progress and the stub live next door in
// `WeeklyGoalRepository.swift`; this file is the data.

/// The five things a week's goal can be about. Raw values are the
/// `weekly_goals.kind` CHECK constraint's strings, so the enum and the
/// column cannot drift apart silently.
enum WeeklyGoalKind: String, Codable, CaseIterable, Sendable {
    case muscleSets = "muscle_sets"
    case distance
    case sessionsOfType = "sessions_of_type"
    case days
    case lift
}

/// Who set this week's goal. The whole of owner answer 3 turns on this one
/// column: Coach writes `coach` rows freely and may never overwrite a
/// `user` one.
enum WeeklyGoalSource: String, Codable, Sendable { case coach, user }

/// Per-kind parameters. ONE payload type with per-kind optional fields, not
/// five types: the column is a single `params jsonb`, and a Codable enum
/// with associated values would put the discriminator in two places (the
/// `kind` column and the payload's own tag) with nothing keeping them
/// honest.
///
/// Every field is optional and every field encodes only when set — the
/// synthesized encoder uses `encodeIfPresent`, so a `days` goal's params
/// are `{"count":4}` rather than seven nulls and a count.
struct WeeklyGoalParams: Codable, Equatable, Sendable {
    var muscleTargets: [String: Int]? = nil      // MuscleGroup.rawValue -> target sets, ≤ 6 keys
    var targetSource: String? = nil              // muscleSets only: "titration" (volume_targets row) | "routines" (summed targetSets)
    var activity: String? = nil                  // run | bike | row | walk
    var distanceTarget: Double? = nil            // in the user's unit (mi with lbs, km with kg)
    var sessionType: String? = nil               // hiit | mobility | cardio | class
    var count: Int? = nil                        // sessionsOfType count, or days count
    var exerciseID: UUID? = nil
    var targetWeightLbs: Decimal? = nil          // CANONICAL POUNDS, per Models/Units.swift
    var byDate: Date? = nil
}

/// A row of `weekly_goals`.
struct WeeklyGoal: Identifiable, Equatable, Sendable {
    var id: String { "\(userID.uuidString)-\(weekStartString)" }
    let userID: UUID
    /// Raw DATE string from PostgREST ("yyyy-MM-dd"). DATE columns must not
    /// go through the SDK's timestamp decoder — the `SessionSeries` idiom,
    /// documented at `Models/ProgramEnrollment.swift:36-38`. Build it with
    /// `WeekMath.weekStartString(_:)`, never by hand.
    let weekStartString: String
    var kind: WeeklyGoalKind
    var params: WeeklyGoalParams
    var source: WeeklyGoalSource
    let setAt: Date
}

// MARK: - WeekMath

/// The one definition of "this week" on Home.
///
/// DELIBERATE DEVIATION from the design, which says "ISO week". The device
/// calendar's week is what `HomeView.daysThisWeek` (:950) already uses —
/// `Calendar.current.isDate(_:equalTo:.now, toGranularity: .weekOfYear)`,
/// which honours the user's own `firstWeekday`. The design's own strip law
/// says the goal strip's right-hand read and the streak tile "must agree",
/// and two different week definitions on one page break that agreement for
/// every user whose week does not start on Monday. So: one helper, the
/// device calendar's week, used by both. Recorded here because it is a
/// documented departure, not an oversight.
///
/// Every function takes its `Calendar` so the math is testable against a
/// fixed `firstWeekday` and timezone; `.current` is the production default.
enum WeekMath {

    /// Midnight, in `calendar`'s timezone, of the first day of the week
    /// containing `date`.
    static func startOfWeek(_ date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// That day as the DATE-column string, "yyyy-MM-dd".
    ///
    /// Formatted from date COMPONENTS rather than a `DateFormatter` —
    /// `SessionSeries.dayString(for:in:)`'s idiom (`SessionSeries.swift:61`)
    /// — which gives the POSIX-locale digits the column wants without a
    /// formatter's locale, calendar or caching questions. The components are
    /// read in `calendar`'s timezone, so a device-local week produces a
    /// device-local day string.
    static func weekStartString(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let start = startOfWeek(date, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The inverse of `weekStartString(_:)`: midnight, in `calendar`'s
    /// timezone, of the day that string names.
    ///
    /// Parsed from the digits rather than through a `DateFormatter`, for the
    /// same reason the formatting side is built from components — no locale,
    /// no calendar and no caching question between the DATE column and the
    /// day it means. nil for anything that is not `yyyy-MM-dd`, which is a
    /// value this app never writes but a hand-typed one might be.
    ///
    /// `detect(weekStart:)` is why this exists (final review finding 3): a
    /// week's goal must be derived from THAT week's routines, and the only
    /// thing the caller has is the row key.
    static func date(fromWeekStartString value: String,
                     calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// Days left in `week`, counting today — 7 on the week's first day, 1 on
    /// its last. This is the number behind `1 DAY LEFT` / `3 DAYS LEFT`, and
    /// it must come from the same week the streak tile counts, which is why
    /// it is here rather than at a call site.
    static func daysRemaining(in week: Date, from now: Date = .now,
                              calendar: Calendar = .current) -> Int {
        let start = startOfWeek(week, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return 0 }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return max(0, min(7, days))
    }
}
