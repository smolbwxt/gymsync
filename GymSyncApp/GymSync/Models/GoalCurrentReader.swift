import Foundation

// MARK: - GoalCurrentReader
//
// Round 2, item 1. "Where am I now" AT THE DOOR — the reading spec §5.2's
// Coach line quotes ("You're at 205 now; that's about 6 weeks of work") and the
// one B5's reach sentence measures a block against (spec §3.2).
//
// **IT EXISTS BECAUSE THE DOOR HAD NO READING AT ALL.** `GoalFirstBuildFlow
// .current` was a `GoalTarget()` that nothing ever filled, so every milestone
// card opened on its documented defaults, Coach said "I haven't got a reading
// for this yet" to everyone, and `GoalBlockLength.reach` could not fire for any
// preset — which is why the final review's F4 could not be fixed by passing
// `reach:` and had to be recorded as a deferral instead.
//
// A PROTOCOL, so the catalog cannot reach a repository: `GoalMilestoneView`'s
// reader is OPTIONAL and nil by default, and the three catalog builders pass
// fixed `current:` values and no reader at all. Frames stay values, not fetches
// (global constraint 7).

/// Reads the athlete's current state for one metric.
///
/// `async` with no `throws`, like every other repository surface here: a blip
/// answers an empty `GoalTarget`, the card keeps its documented seed and Coach
/// says he has no reading — never an error on a door.
protocol GoalCurrentReader: Sendable {
    /// - Parameters:
    ///   - metric: which registry entry to read (spec §2.2).
    ///   - subject: the lift, routine or activity the reading is ABOUT, when
    ///     the metric has one. The door's pickers move it, which is why the
    ///     card re-asks when it changes: "where am I now" on the bench is a
    ///     different question from "where am I now" on the squat.
    func current(metric: GoalMetric, subject: GoalTarget) async -> GoalTarget
}

/// A reading that was handed in rather than read — the catalog's, and a test's.
struct FixedGoalCurrentReader: GoalCurrentReader {
    let reading: GoalTarget
    init(_ reading: GoalTarget) { self.reading = reading }
    func current(metric: GoalMetric, subject: GoalTarget) async -> GoalTarget { reading }
}

// MARK: - The reduction

/// How the ladder's PER-WEEK readings become the door's single "now".
///
/// **THE MATH IS THE LADDER'S, ONLY THE WINDOW DIFFERS**, and that is the whole
/// point of doing it this way: `LiveBlockGoalRepository.measuredByWeek` is the
/// one place each metric is actually read, the door asks it for the last few
/// weeks instead of for a block's rungs, and this folds those weeks into one
/// answer. Two readers for one metric is the drift the agreement law forbids —
/// the door would have said 205 while the ladder graded the same week against
/// 210 and neither would have been wrong on its own terms.
enum GoalCurrentReading {

    /// How far back "now" looks. Eight weeks is the default block length
    /// (`GoalBlockLength.defaultWeeks`) — a training block's worth of history,
    /// which is the same span the athlete is about to commit to.
    static let weeksOfHistory = GoalBlockLength.defaultWeeks

    /// One reading from several weeks of them.
    ///
    /// THE RULE PER METRIC, and each one is a judgement rather than an average:
    ///
    ///   * **a best** for everything that is a capacity — an e1RM, reps at a
    ///     load, a week's sets, a week's distance, days, sessions, stretches,
    ///     easy minutes. One light week is not evidence the athlete got worse,
    ///     the same reasoning `BlockGoalMetricMath.bestBenchmarkSeconds` gives
    ///     for taking the fastest run rather than the last one.
    ///   * **the fastest** for `benchmarkTime`, where smaller is better.
    ///   * **the latest** for `bodyWeight`: a scale reading is a level, not an
    ///     achievement, and the best weigh-in of the last eight weeks is not
    ///     where the athlete is standing today.
    ///   * **nothing** for `cumulativeVolume`. Its `current.volumeLbs` means
    ///     "tonnage already banked in this block" to the ladder and "the block's
    ///     total" to the door's own seed (`seededTarget`'s `.volume` arm), and a
    ///     number that means two things is worse than no number. The Volume
    ///     card therefore reads exactly as it did before this existed, and its
    ///     reach stays unanswered — recorded, not papered over.
    static func reduce(metric: GoalMetric, weekly: [String: GoalTarget]) -> GoalTarget {
        // yyyy-MM-dd sorts chronologically as a string, which is the whole
        // reason `week_start` is stored in that shape.
        let ordered = weekly.keys.sorted().compactMap { weekly[$0] }
        guard !ordered.isEmpty else { return GoalTarget() }
        var out = GoalTarget()

        switch metric {
        case .liftOneRepMax:
            out.targetWeightLbs = ordered.compactMap(\.targetWeightLbs).filter { $0 > 0 }.max()

        case .liftRepsAtLoad:
            out.targetReps = ordered.compactMap(\.targetReps).filter { $0 > 0 }.max()
            out.loadLbs = ordered.compactMap(\.loadLbs).filter { $0 > 0 }.max()

        case .weeklyMuscleSets:
            var best: [String: Int] = [:]
            for week in ordered {
                for (group, sets) in week.muscleTargets ?? [:] {
                    best[group] = max(best[group] ?? 0, sets)
                }
            }
            out.muscleTargets = best.isEmpty ? nil : best

        case .weeklyDistance:
            out.activity = ordered.compactMap(\.activity).last
            out.distance = ordered.compactMap(\.distance).filter { $0 > 0 }.max()

        case .trainingDaysPerWeek:
            out.days = ordered.compactMap(\.days).filter { $0 > 0 }.max()

        case .sessionsOfTypePerWeek:
            out.sessionType = ordered.compactMap(\.sessionType).last
            out.sessions = ordered.compactMap(\.sessions).filter { $0 > 0 }.max()

        case .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            out.lissMinutes = ordered.compactMap(\.lissMinutes).filter { $0 > 0 }.max()
            out.stretchingExercises = ordered.compactMap(\.stretchingExercises)
                .filter { $0 > 0 }.max()

        case .bodyWeight:
            out.bodyWeightLbs = ordered.compactMap(\.bodyWeightLbs).filter { $0 > 0 }.last

        case .benchmarkTime:
            out.routineID = ordered.compactMap(\.routineID).last
            out.targetSeconds = ordered.compactMap(\.targetSeconds).filter { $0 > 0 }.min()

        case .cumulativeVolume:
            break
        }
        return out
    }
}
