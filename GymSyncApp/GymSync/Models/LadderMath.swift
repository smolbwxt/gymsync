import Foundation

// MARK: - LadderMath
//
// THE PURE ARITHMETIC OF A LADDER — no clock, no network, no catalog fetch.
//
// **THIS FILE IS STREAM A'S (task A9), AND STREAM B REACHED IT FIRST.** The
// plan says so in as many words: `LadderMath.weekStartStrings(from:count:)`
// "is a two-line pure helper this task adds to `LadderMath` (A9's file) —
// coordinate with Stream A: it lands in whichever branch reaches it first and
// the other rebases. It is the only symbol the two streams both write."
// `reached(metric:measured:target:)` joins it in task B5, because
// `GoalBlockLength.reach(…)` is written verbatim in the plan around a call to
// it, and `detectedGoal(profile:)` is the stand-in A13 replaces (see its own
// doc comment). Everything Stream A adds here is additive; nothing below is
// Stream A's to delete.
enum LadderMath {

    /// The `count` consecutive week keys a ladder's rungs sit on, walking
    /// forward one week at a time from the week containing `start`.
    ///
    /// `WeekMath`'s device-calendar week, not an ISO one, because that is what
    /// `weekly_goals.week_start` already means everywhere else in this app —
    /// a rung and the row it materialises into must name the same seven days.
    static func weekStartStrings(from start: Date, count: Int,
                                 calendar: Calendar = .current) -> [String] {
        guard count > 0 else { return [] }
        let first = WeekMath.startOfWeek(start, calendar: calendar)
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: index * 7, to: first)
                .map { WeekMath.weekStartString($0, calendar: calendar) }
        }
    }

    /// The goal a block gets when nobody named one.
    ///
    /// **INTERIM, AND TASK A13 REPLACES IT.** Spec §5.4: "Existing enrollments
    /// without a goal get a Coach-detected one on first Home load, derived
    /// from the enrollment's `focus` and `baseline`." A13 owns that function;
    /// this one answers the different question task B4 has to answer TODAY —
    /// what does `ProgramBuilder.build(goal:)` receive from the two call sites
    /// Stream C has not reached yet, so that the tree is never in a state that
    /// builds an unconsidered block. The two overload on their parameters, so
    /// A13 lands beside this rather than on top of it.
    ///
    /// **CONSISTENCY, DELIBERATELY, AND IT IS THE ONLY SAFE ANSWER HERE.**
    /// `GoalGeneratorMapping` moves the focus band for eight of the eleven
    /// presets and places cardio for five of them; a placeholder that picked
    /// any of those would silently change what the generator builds for every
    /// athlete who comes through the consult before Stream C lands — a
    /// Maintenance stand-in would drop a strength athlete into the hypertrophy
    /// band, a Body-composition one would buy two cardio days nobody asked
    /// for. `consistency` moves NOTHING (no band override, no placement), and
    /// it is not a fiction either: a block built with no milestone named is
    /// still a commitment to train the days the profile says.
    static func detectedGoal(profile: TrainingProfile) -> BlockGoalDraft {
        BlockGoalDraft(metric: .trainingDaysPerWeek,
                       target: GoalTarget(days: profile.daysPerWeek),
                       byDate: nil,
                       preset: .consistency,
                       // COACH'S reading, not the athlete's: nobody chose this
                       // at a door, so `WeeklyGoalWriteRule` must let the
                       // athlete's own goal win over it.
                       source: .coach)
    }
}
