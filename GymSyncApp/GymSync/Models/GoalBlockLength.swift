import Foundation

// MARK: - GoalBlockLength
//
// Spec §5.3: the goal sets "the block length from the date". PURE, so the
// answer is a test rather than a clock.
enum GoalBlockLength {

    /// The generator's own limits. Below four weeks a block has no wave to
    /// speak of (`ProgramGenerator.swift`'s wave: flat under 8, deload at the
    /// ¾ mark from 8), and `program_enrollments.weeks` is CHECKed BETWEEN 1
    /// AND 52 (`20260728000009_program_enrollments.sql:42`).
    static let minimumWeeks = 4
    static let maximumWeeks = 52
    /// What a block is when the goal names no date — Maintenance, Recovery and
    /// Consistency are "held for the block" (spec §2.1), and eight weeks is
    /// what `ProgramBuilder.build` has always defaulted to
    /// (`ProgramBuilder.swift`'s `answers?.durationWeeks ?? 8`).
    static let defaultWeeks = 8

    /// Whole weeks from `now` to `byDate`, clamped. A date inside four weeks
    /// still gets a four-week block: the ladder then says the milestone is out
    /// of reach (task B5), which is honest, where refusing to build is not.
    static func weeks(byDate: Date?, from now: Date = .now,
                      calendar: Calendar = .current) -> Int {
        guard let byDate else { return defaultWeeks }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: byDate)).day ?? 0
        let raw = Int((Double(days) / 7.0).rounded(.up))
        return min(maximumWeeks, max(minimumWeeks, raw))
    }
}
