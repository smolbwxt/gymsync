import Foundation

// MARK: - GoalBlockLength
//
// Spec §5.3: the goal sets "the block length from the date". PURE, so the
// answer is a test rather than a clock.
//
// ── WHY THIS FILE IS ON STREAM C'S BRANCH ────────────────────────────────
//
// It is STREAM B's file (plan tasks B2 and B5). Stream C needs two of its
// declarations before B lands: `GoalMilestoneCopy.coachLine` takes a
// `Reach` and delegates the gap sentence to `reachSentence`, and the plan's
// own C2 test constructs `GoalBlockLength.Reach(reaches:projected:
// achievableDate:)` by name. C forks from Task 0, where neither exists, so
// the branch could not compile the test the plan gives it.
//
// What is here is B2's enum and B5's `Reach` + `reachSentence`, VERBATIM
// from the plan, and nothing else. `reach(metric:rungs:milestone:byDate:
// weeklyGain:from:calendar:)` and its private `shortfall(...)` are
// deliberately ABSENT: they call `LadderMath.reached`, which is Stream A's,
// and a second implementation of "has this rung reached the milestone"
// would be exactly the drift this plan's live-faithful discipline exists to
// prevent.
//
// AT INTEGRATION (task I1) this is a "both added" conflict against Stream
// B's own `GoalBlockLength.swift`. **Take B's file whole.** B's is a strict
// superset — every declaration below appears in it unchanged — so C's call
// sites compile against it untouched, and C's copy disappears. Resolving it
// the other way round loses `reach(...)` and breaks B loudly, which is the
// point of putting this at B's own path rather than at a private one that
// would collide silently as a duplicate declaration.
enum GoalBlockLength {

    /// The generator's own limits. Below four weeks a block has no wave to
    /// speak of (`ProgramGenerator.swift:918-919`: flat under 8, deload at the
    /// ¾ mark from 8), and `program_enrollments.weeks` is CHECKed BETWEEN 1
    /// AND 52 (`20260728000009_program_enrollments.sql:42`).
    static let minimumWeeks = 4
    static let maximumWeeks = 52
    /// What a block is when the goal names no date — Maintenance, Recovery and
    /// Consistency are "held for the block" (spec §2.1), and eight weeks is
    /// what `ProgramBuilder.build` has always defaulted to
    /// (`ProgramBuilder.swift:88`).
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

extension GoalBlockLength {

    /// Can the block's own prescribed loading reach `target` by `byDate`?
    ///
    /// Answered from the LADDER, not from a second model of progress: the last
    /// rung is what the block prescribes for the final week, and if that falls
    /// short of the milestone then the block falls short of the milestone.
    /// Anything else would be a third opinion about the same eight weeks.
    struct Reach: Equatable, Sendable {
        let reaches: Bool
        /// What the block DOES get to — 218, in the spec's example.
        let projected: GoalTarget
        /// The date the block COULD build to, when it cannot make the one
        /// asked for. nil when it can.
        let achievableDate: Date?
    }

    /// Coach's sentence at the door, spec §3.2 verbatim in shape:
    /// "225 by Oct 18 needs more than this block can safely give; Nov 15 is
    /// the date I can build to."
    ///
    /// Without an achievable date the sentence stops after the first clause
    /// rather than inventing a second — the design's "never lies about the
    /// gap" cuts both ways.
    static func reachSentence(milestoneText: String, byDate: Date?, reach: Reach,
                              calendar: Calendar = .current) -> String? {
        guard !reach.reaches else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"
        let asked = byDate.map { " by \(formatter.string(from: $0))" } ?? ""
        let head = "\(milestoneText)\(asked) needs more than this block can safely give"
        guard let achievable = reach.achievableDate else { return head + "." }
        return head + "; \(formatter.string(from: achievable)) is the date I can build to."
    }
}
