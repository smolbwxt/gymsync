import Foundation

// MARK: - BlockGoal
//
// Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md
// §2. Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// task 0.1.
//
// ONE PRIMARY GOAL PER BLOCK (owner decision 2). The goal and the program are
// one object at two time scales: this type is the block's whole time scale,
// and `WeeklyGoal` — already shipped — is the week's.
//
// THE REGISTRY IS OPEN BY DESIGN (owner decision 5): a new goal is a new
// `GoalMetric` case plus a reader plus a ladder rule, and the door does not
// change.

/// What a goal measures. The raw values are `block_goals.metric`'s registry
/// keys, so the enum and the column cannot drift apart silently — the same
/// contract `WeeklyGoalKind` has with `weekly_goals.kind`.
///
/// The metric's PARAMETERS (which lift, which group, which routine) do not
/// live here: they live in `GoalTarget`, beside the number they qualify,
/// exactly as `WeeklyGoalParams` carries `exerciseID` beside
/// `targetWeightLbs`. An enum with associated values would put the same
/// discriminator in two places — the `metric` column and the payload's own
/// tag — with nothing keeping them honest.
enum GoalMetric: String, Codable, CaseIterable, Sendable {
    case liftOneRepMax              = "lift_one_rep_max"
    case weeklyMuscleSets           = "weekly_muscle_sets"
    case weeklyDistance             = "weekly_distance"
    case trainingDaysPerWeek        = "training_days_per_week"
    case sessionsOfTypePerWeek      = "sessions_of_type_per_week"
    case lissMinutesPerWeek         = "liss_minutes_per_week"
    case stretchingExercisesPerWeek = "stretching_exercises_per_week"
    case bodyWeight                 = "body_weight"
    case cumulativeVolume           = "cumulative_volume"
    case benchmarkTime              = "benchmark_time"
    case liftRepsAtLoad             = "lift_reps_at_load"
}

/// A target, typed per metric — the milestone's value, and a rung's value,
/// in one shape.
///
/// ONE payload type with per-metric optional fields, for the reason
/// `WeeklyGoalParams`' own doc comment gives. Every field encodes only when
/// set (the synthesized encoder uses `encodeIfPresent`), so a `days` goal's
/// target is `{"days":4}` rather than fifteen nulls and a number.
///
/// CAMELCASE ON THE WIRE, and no `keyEncodingStrategy` anywhere in this app —
/// `20260906000001_weekly_goals.sql:35-40` states the same contract for
/// `weekly_goals.params`, and `block_goals.target` inherits it.
///
/// CANONICAL POUNDS for every weight (`Models/Units.swift:7-12`). The unit a
/// number is READ in is the athlete's; the unit it is STORED in is pounds.
struct GoalTarget: Codable, Equatable, Sendable {
    // liftOneRepMax, liftRepsAtLoad
    var exerciseID: UUID? = nil
    var targetWeightLbs: Decimal? = nil     // CANONICAL POUNDS
    var targetReps: Int? = nil
    var loadLbs: Decimal? = nil             // liftRepsAtLoad: the fixed load
    // weeklyMuscleSets — a map, because Maintenance is EVERY major group
    // (owner decision 9) and Muscle is one of them.
    var muscleTargets: [String: Int]? = nil // MuscleGroup.rawValue -> weekly sets
    // weeklyDistance
    var activity: String? = nil             // run | bike | row | walk
    var distance: Double? = nil             // in the athlete's unit (mi with lb, km with kg)
    // trainingDaysPerWeek
    var days: Int? = nil
    // sessionsOfTypePerWeek
    var sessionType: String? = nil          // hiit | mobility | cardio | class
    var sessions: Int? = nil
    // lissMinutesPerWeek, stretchingExercisesPerWeek (Recovery carries both)
    var lissMinutes: Int? = nil
    var stretchingExercises: Int? = nil
    // bodyWeight
    var bodyWeightLbs: Decimal? = nil       // CANONICAL POUNDS
    var bodyWeightRatePercent: Double? = nil // per week, signed: -0.75 = lose 0.75 %/wk
    // cumulativeVolume
    var volumeLbs: Double? = nil
    // benchmarkTime
    var routineID: UUID? = nil
    var targetSeconds: Int? = nil
}

/// The named, ready-made goals over the registry (spec §2.3). ALL FREE, all
/// offered from launch (owner decision 10).
///
/// ELEVEN presets, TEN tiles. `repStrength` is the eleventh preset and the
/// spec is explicit that it is NOT an eleventh tile (§2.3: "Rep strength
/// appears as a second lever on the Strength card — 'a max' or 'reps at a
/// load' — not as an eighth tile"), so the grid renders ten and the Strength
/// milestone card carries this case behind its own segmented switch.
enum GoalPreset: String, Codable, CaseIterable, Sendable {
    case strength
    case repStrength      = "rep_strength"
    case muscle
    case endurance
    case consistency
    case conditioning
    case maintenance
    case recovery
    case bodyComposition  = "body_composition"
    case volume
    case benchmark

    /// The metric this preset measures. Recovery's PRIMARY metric is the
    /// stretching count — what the block actually schedules; LISS minutes is
    /// its companion read on the same rung (spec §2.3's note).
    var metric: GoalMetric {
        switch self {
        case .strength:        return .liftOneRepMax
        case .repStrength:     return .liftRepsAtLoad
        case .muscle:          return .weeklyMuscleSets
        case .endurance:       return .weeklyDistance
        case .consistency:     return .trainingDaysPerWeek
        case .conditioning:    return .sessionsOfTypePerWeek
        case .maintenance:     return .weeklyMuscleSets
        case .recovery:        return .stretchingExercisesPerWeek
        case .bodyComposition: return .bodyWeight
        case .volume:          return .cumulativeVolume
        case .benchmark:       return .benchmarkTime
        }
    }

    /// Does the door ask for a date? Maintenance and Recovery do not — they
    /// are "held for the block" (spec §2.1: `byDate == nil`), and asking for
    /// one would invent a deadline for a goal that has none. **Nor does
    /// Consistency**, whose milestone spec §2.3 gives as "days per week, held
    /// for N weeks" — a count held, not a date met.
    ///
    /// The comment used to name two where the code excluded three (review
    /// finding 8). The CODE was right; the comment is what Stream C's door
    /// reads, and `BlockGoalModelTests` now pins all three rather than the two
    /// the plan's own test asserted.
    var asksForDate: Bool {
        switch self {
        case .maintenance, .recovery, .consistency: return false
        default:                                    return true
        }
    }

    /// The ten tiles the grid renders, in the spec §2.3 table's order.
    /// `repStrength` is absent on purpose — see the type's doc comment.
    static let tiles: [GoalPreset] = [
        .strength, .muscle, .endurance, .consistency, .conditioning,
        .maintenance, .recovery, .bodyComposition, .volume, .benchmark,
    ]
}

/// How a finished block's milestone came out (spec §7). PHASE 3 WRITES THESE
/// — the column exists now because the table does, and `ProgramLedgerView`
/// (task D5) renders the outcome when it is present and the milestone alone
/// when it is not.
enum GoalOutcome: String, Codable, Equatable, Sendable {
    case met, missed, partial
}

/// A row of `public.block_goals` — spec §2.1, verbatim, plus §8's two
/// outcome columns.
struct BlockGoal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let enrollmentID: UUID            // the block this goal drives (program_enrollments.id)
    var metric: GoalMetric            // what is measured (registry, §2.2)
    var target: GoalTarget            // the milestone value, typed per metric
    var byDate: Date?                 // the milestone date; nil = "held for the block"
    var preset: GoalPreset?           // which preset produced it; nil = Coach-guided or custom
    var source: WeeklyGoalSource      // coach | user — who last set the milestone
    var outcome: GoalOutcome?         // phase 3
    var outcomeValue: GoalTarget?     // phase 3
    let createdAt: Date
    var updatedAt: Date
}

/// A goal BEFORE its block exists.
///
/// `BlockGoal.enrollmentID` is `let` and non-optional because a goal without
/// a block is not a goal — but the door composes the goal FIRST and
/// `ProgramBuilder.build` writes the enrollment SECOND, so there is a real
/// moment with a milestone and no id to hang it on. This is that moment, and
/// making it its own type is what keeps `enrollmentID` honest instead of
/// optional forever after.
struct BlockGoalDraft: Equatable, Sendable {
    var metric: GoalMetric
    var target: GoalTarget
    var byDate: Date?
    var preset: GoalPreset?
    /// The door is the athlete choosing, so a drafted goal is theirs — which
    /// is also what makes `WeeklyGoalWriteRule` protect the rungs it
    /// materialises from being overwritten by a later detection.
    var source: WeeklyGoalSource = .user
}

extension BlockGoal {
    /// The draft, once the block it drives has an id.
    init(draft: BlockGoalDraft, id: UUID = UUID(), userID: UUID,
         enrollmentID: UUID, now: Date = .now) {
        self.init(id: id, userID: userID, enrollmentID: enrollmentID,
                  metric: draft.metric, target: draft.target,
                  byDate: draft.byDate, preset: draft.preset,
                  source: draft.source, outcome: nil, outcomeValue: nil,
                  createdAt: now, updatedAt: now)
    }
}
