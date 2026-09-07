import Foundation

// MARK: - Ladder
//
// Spec §3. THE LADDER IS A READ-OUT of the generated block projected onto
// the goal's metric — not a second schedule. `ProgramGenerator` already
// produces `Program.weeks` (volumeMultiplier / intensityMultiplier /
// isDeload) and per-slot prescriptions (sets, repsLow/High, percentOfMax,
// RIR); the rungs are computed FROM those, which is what makes it impossible
// for the ladder and the plan to disagree.

enum RungStatus: String, Codable, Equatable, Sendable {
    case ahead, current, met, missed, overridden
}

struct LadderRung: Codable, Equatable, Sendable {
    let weekIndex: Int            // 0-based within the block
    let weekStartString: String   // WeekMath's device-calendar week key, same as weekly_goals
    var target: GoalTarget        // this week's subgoal, typed per metric
    var status: RungStatus        // ahead | current | met | missed | overridden
}

struct Ladder: Codable, Equatable, Sendable {
    let goalID: UUID
    var rungs: [LadderRung]       // exactly enrollment.weeks entries
    var derivedAt: Date
}

/// One row of the ladder page, already worded.
///
/// The page prints strings; it does not read a `GoalTarget` and decide how a
/// bench rung is spelled. That decision is `LadderReadout`'s (task A8) and
/// the ramp rules' (A7), which is what keeps "3 × 5 at 190" identical on the
/// ladder page, on the schedule card and in Coach's line.
struct LadderRow: Equatable, Sendable {
    let weekNumber: Int          // 1-based, what the page prints
    let weekStartString: String
    let targetText: String       // "3 × 5 at 190" · "12 chest sets" · "120 LISS min · 6 stretches"
    /// The second line, when a rung implies something the target text does
    /// not say — a strength rung's e1RM ("≈ 214 e1RM"). nil when there is
    /// none; never an empty string, so a view can branch on presence.
    let implication: String?
    let status: RungStatus
    let isDeload: Bool
    /// The generator's own decision-log line for this week, when one names
    /// it (`Program.notes`) — spec §6: "so the ladder says why a week is
    /// what it is". nil is the normal case.
    let note: String?
}

/// Everything the ladder page renders, resolved.
struct LadderPageModel: Equatable, Sendable {
    /// The milestone as the headline — "Bench 225 by Oct 18".
    var headline: String = ""
    /// The date on its own line, or "" for a held-for-the-block goal.
    var dateLine: String = ""
    /// Coach's one line on standing — "On track" /
    /// "This ladder reaches 218 — move the date?" (spec §6).
    var coachLine: String = ""
    var rows: [LadderRow] = []
    /// False when the re-derived ladder can no longer reach the milestone by
    /// the date. The page shows the gap honestly either way (spec §3.5); this
    /// only decides whether Coach's line is a proposal.
    var reachesMilestone: Bool = true
    /// 1-based, for the strip's block kicker and the page's own subtitle.
    var weekNumber: Int = 1
    var weekCount: Int = 1
    /// Whose milestone this is, for the kicker's COACH'S GOAL / YOUR GOAL.
    var source: WeeklyGoalSource = .coach
}
