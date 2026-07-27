import Foundation

// MARK: - Training Programs P1: bundled templates + pure math
//
// Design: docs/superpowers/specs/2026-07-24-training-programs-design.md.
// Templates are code-defined app-shipped values, NOT database rows ("a
// template is logic + copy that must stay in lockstep with the client that
// renders it"); server state is the single `program_enrollments` table
// (20260728000009). All math here is pure and testable (ProgramMathTests)
// — the StatMath/BurpeeLedgerMath pattern.

// MARK: - Template shapes (spec "Templates: bundled in-app" section)

/// How a template's focus is chosen at enrollment.
enum ProgramFocusRule: Sendable {
    /// One barbell lift (March to One-Rep Max).
    case singleBarbellLift
    /// A squat-pattern main lift plus an accessory hinge (Leg-Focused
    /// Strength) — two exercises picked at enrollment.
    case liftPlusAccessory
    /// A muscle-group emphasis (Hypertrophy Block) — no per-lift baseline;
    /// weeks are volume-driven (`percentOfBaseline == nil`).
    case muscleGroup
}

struct ProgramWeek: Sendable {
    /// Percent of the frozen enrollment baseline (e.g. 82.5 → "82.5%").
    /// `nil` for volume-driven weeks (hypertrophy) and test weeks — the
    /// row shows its note instead of a computed weight.
    let percentOfBaseline: Double?
    let sets: Int
    let reps: Int
    let isDeload: Bool
    let note: String?

    init(percentOfBaseline: Double? = nil, sets: Int, reps: Int,
         isDeload: Bool = false, note: String? = nil) {
        self.percentOfBaseline = percentOfBaseline
        self.sets = sets
        self.reps = reps
        self.isDeload = isDeload
        self.note = note
    }
}

struct ProgramTemplate: Identifiable, Sendable {
    let slug: String
    let name: String
    let summary: String
    let weeks: [ProgramWeek]
    let focusRule: ProgramFocusRule
    let sessionsPerWeek: Int
    var id: String { slug }

    /// The v1 template list (spec table). Week schemes are the spec's
    /// "scheme summary" column made concrete; every target the app shows
    /// derives transparently from these percents × the frozen baseline.
    static let all: [ProgramTemplate] = [
        ProgramTemplate(
            slug: "march-to-1rm",
            name: "March to One-Rep Max",
            summary: "8-week linear peak on one barbell lift: fives to triples to heavy singles, deload on week 5, test on week 8.",
            weeks: [
                ProgramWeek(percentOfBaseline: 75, sets: 3, reps: 5),
                ProgramWeek(percentOfBaseline: 80, sets: 3, reps: 5),
                ProgramWeek(percentOfBaseline: 85, sets: 4, reps: 3),
                ProgramWeek(percentOfBaseline: 87.5, sets: 4, reps: 3),
                ProgramWeek(percentOfBaseline: 60, sets: 2, reps: 5, isDeload: true, note: "Deload — move fast, leave the gym fresh."),
                ProgramWeek(percentOfBaseline: 90, sets: 3, reps: 2),
                ProgramWeek(percentOfBaseline: 95, sets: 2, reps: 1),
                ProgramWeek(sets: 1, reps: 1, note: "Test week — warm up thoroughly and work to a new heavy single."),
            ],
            focusRule: .singleBarbellLift,
            sessionsPerWeek: 3
        ),
        ProgramTemplate(
            slug: "leg-strength-block",
            name: "Leg-Focused Strength",
            summary: "6 weeks of 5×5 on a squat pattern plus an accessory hinge, two lower-body sessions a week, deload on week 4.",
            weeks: [
                ProgramWeek(percentOfBaseline: 75, sets: 5, reps: 5),
                ProgramWeek(percentOfBaseline: 77.5, sets: 5, reps: 5),
                ProgramWeek(percentOfBaseline: 80, sets: 5, reps: 5),
                ProgramWeek(percentOfBaseline: 60, sets: 3, reps: 5, isDeload: true, note: "Deload — keep the pattern, drop the load."),
                ProgramWeek(percentOfBaseline: 82.5, sets: 5, reps: 5),
                ProgramWeek(percentOfBaseline: 85, sets: 5, reps: 5),
            ],
            focusRule: .liftPlusAccessory,
            sessionsPerWeek: 2
        ),
        ProgramTemplate(
            slug: "hypertrophy-block",
            name: "Hypertrophy Block",
            summary: "8 weeks of volume on a muscle group you pick: 10–12 rep sets, set count ramps up, deload on week 5.",
            weeks: [
                ProgramWeek(sets: 3, reps: 10),
                ProgramWeek(sets: 3, reps: 12),
                ProgramWeek(sets: 4, reps: 10),
                ProgramWeek(sets: 4, reps: 12),
                ProgramWeek(sets: 2, reps: 10, isDeload: true, note: "Deload — half the sets, same crisp form."),
                ProgramWeek(sets: 4, reps: 10),
                ProgramWeek(sets: 5, reps: 10),
                ProgramWeek(sets: 5, reps: 12),
            ],
            focusRule: .muscleGroup,
            sessionsPerWeek: 4
        ),
    ]

    static func bySlug(_ slug: String) -> ProgramTemplate? {
        all.first { $0.slug == slug }
    }
}

// MARK: - ProgramMath (pure — see ProgramMathTests)

enum ProgramMath {

    /// 1-based current program week, clamped to `1...weeks`. Weeks anchor
    /// to `startedOn` (NOT calendar Mondays — a Thursday start means
    /// Thursday-to-Wednesday weeks), so this is plain day arithmetic.
    /// Days before `startedOn` count as week 1.
    static func currentWeek(startedOn: Date, weeks: Int, now: Date = .now,
                            calendar: Calendar = .current) -> Int {
        min(max(unclampedWeek(startedOn: startedOn, now: now, calendar: calendar), 1), max(weeks, 1))
    }

    /// True once the full program duration has elapsed (`now` is past the
    /// last day of the final week) — drives the completion state.
    static func isComplete(startedOn: Date, weeks: Int, now: Date = .now,
                           calendar: Calendar = .current) -> Bool {
        unclampedWeek(startedOn: startedOn, now: now, calendar: calendar) > max(weeks, 1)
    }

    private static func unclampedWeek(startedOn: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: startedOn)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return days < 0 ? 1 : days / 7 + 1
    }

    /// The [start, end) date window of `week` (1-based) for session
    /// counting ("1 of 3 sessions done this week").
    static func weekWindow(startedOn: Date, week: Int,
                           calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: startedOn)
        let weekStart = calendar.date(byAdding: .day, value: (week - 1) * 7, to: start) ?? start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return (weekStart, weekEnd)
    }

    /// Count of `completionDates` falling inside `window` — the program
    /// card's sessions-this-week numerator.
    static func sessionsCompleted(completionDates: [Date],
                                  window: (start: Date, end: Date)) -> Int {
        completionDates.filter { $0 >= window.start && $0 < window.end }.count
    }

    /// Working weight for a percent week: `percent% × baseline`, rounded
    /// to the nearest 5 lb — the same rounding contract as
    /// `StatMath.projectedWeight` (`StatMath.swift:124`). `nil` when the
    /// result would be non-positive (no baseline → no number, never a
    /// guess).
    static func targetWeight(percentOfBaseline: Double, baseline: Decimal) -> Int? {
        let raw = NSDecimalNumber(decimal: baseline).doubleValue * percentOfBaseline / 100
        let rounded = Int((raw / 5).rounded() * 5)
        return rounded > 0 ? rounded : nil
    }

    /// Frozen-at-enrollment training max from the user's qualifying set
    /// history: the best Epley est-1RM across `logs`
    /// (`StatMath.estimatedOneRepMax`). `nil` when no set has both reps
    /// and weight — the enrollment UI then asks for one real set instead
    /// (spec: the app never invents a number).
    static func baseline(fromHistory logs: [SetLog]) -> Decimal? {
        logs.compactMap { log -> Decimal? in
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.weight, reps > 0, weight > 0 else { return nil }
            return StatMath.estimatedOneRepMax(weight: weight, reps: reps)
        }.max()
    }

    /// "3×5 @ 82.5% → 185 lb" / "3×5 @ 82.5%" (no baseline) /
    /// "3×10 · pick a weight leaving ~2 reps in reserve" (volume week).
    /// The transparency doctrine's one-line form: the math is IN the copy.
    /// Units sweep: `unit` renders the target in the user's unit, rounded in
    /// THAT unit's grid (defaults lbs so existing call sites/tests compile
    /// and behave unchanged).
    static func prescriptionText(week: ProgramWeek, baseline: Decimal?,
                                 unit: WeightUnit = .lbs) -> String {
        let setsReps = "\(week.sets)×\(week.reps)"
        guard let percent = week.percentOfBaseline else {
            if let note = week.note { return "\(setsReps) · \(note)" }
            return setsReps
        }
        let percentText = trimmedPercent(percent)
        if let baseline, let target = targetText(percentOfBaseline: percent, baseline: baseline, unit: unit) {
            return "\(setsReps) @ \(percentText)% → \(target)"
        }
        return "\(setsReps) @ \(percentText)%"
    }

    /// "185 lb" / "85 kg" — the percent-week target rounded in the USER'S
    /// unit grid (5 lb / 2.5 kg). Rounding the lbs number first and then
    /// converting would print kg values nobody programs (83.9 kg); the
    /// doctrine is round-in-the-user's-unit, same as `Units.roundToIncrement`.
    static func targetText(percentOfBaseline: Double, baseline: Decimal,
                           unit: WeightUnit) -> String? {
        guard unit != .lbs else {
            return targetWeight(percentOfBaseline: percentOfBaseline, baseline: baseline)
                .map { "\($0) lb" }
        }
        let rawLbs = NSDecimalNumber(decimal: baseline).doubleValue * percentOfBaseline / 100
        let rawInUnit = Units.fromPounds(rawLbs, to: unit)
        let step = NSDecimalNumber(decimal: unit.displayIncrement).doubleValue
        let snapped = (rawInUnit / step).rounded() * step
        guard snapped > 0 else { return nil }
        let text = snapped == snapped.rounded() ? String(Int(snapped)) : String(snapped)
        return "\(text) \(unit.label)"
    }

    /// "87.5" stays "87.5", "80.0" trims to "80".
    static func trimmedPercent(_ percent: Double) -> String {
        percent == percent.rounded() ? String(Int(percent)) : String(percent)
    }
}
