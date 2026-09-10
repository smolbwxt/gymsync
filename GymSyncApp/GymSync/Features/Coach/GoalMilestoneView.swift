import SwiftUI

// MARK: - GoalMilestoneView
//
// Spec §5.2: ONE CARD PER PRESET WITH THE LEVERS IT NEEDS AND NOTHING ELSE
// (design rule 4: questions above the fold). Coach's line under the levers
// states current state and what the ladder would look like.
//
// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// task C2 (the levers and Coach's line) and C3 (`applying`, and the primary
// handing over the EDITED draft).
//
// HERMETIC. `current`, `lifts`, `routines` and `today` all arrive through the
// initializer — "passed in, never fetched here" — which is what lets frames
// 94-96 be values rather than fetches (global constraint 7).

// MARK: - GoalMilestoneCopy
//
// The pure half. Everything a test can hold: the seed, the edit, Coach's
// sentence, and why the primary is disabled. The VIEW below owns no arithmetic
// of its own — a body is not testable in this target, so nothing that can be
// wrong is allowed to live in one.
enum GoalMilestoneCopy {

    // MARK: The seed

    /// The milestone the card OPENS on, from what the athlete's log says now.
    ///
    /// `byDate` follows `GoalPreset.asksForDate` exactly (Task 0's frozen
    /// rule): Maintenance, Recovery and Consistency are held for the block and
    /// asking for a date would invent a deadline for a goal that has none.
    ///
    /// THE DATE IS THE LAST DAY OF THE BLOCK, not the day after it. A block
    /// that starts today and runs `weeks` weeks counts today as day one, so
    /// its final day is `today + weeks × 7 − 1`. Seeding the day after would
    /// hand `GoalBlockLength.weeks` a span of exactly `weeks × 7` days, which
    /// still rounds to `weeks` — both are self-consistent — but "by the end of
    /// the block" is the sentence the athlete reads, and the last day is what
    /// it means.
    static func draft(preset: GoalPreset,
                      current: GoalTarget,
                      today: Date,
                      unit: WeightUnit,
                      weeks: Int = GoalBlockLength.defaultWeeks,
                      calendar: Calendar = .current) -> BlockGoalDraft {
        BlockGoalDraft(
            metric: preset.metric,
            target: seededTarget(preset: preset, current: current,
                                 weeks: weeks, unit: unit),
            byDate: preset.asksForDate
                ? milestoneDate(from: today, weeks: weeks, calendar: calendar)
                : nil,
            preset: preset,
            source: .user)
    }

    /// The final day of a block of `weeks` weeks that starts on `today`.
    static func milestoneDate(from today: Date, weeks: Int,
                              calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(1, weeks) * 7 - 1, to: today) ?? today
    }

    /// **THE BLOCK LENGTH THE CARD IS WORKING TO**, and it is READ OFF THE
    /// MILESTONE DATE for the eight presets that carry one.
    ///
    /// This is the inverse of `milestoneDate` and the reason that function's
    /// round trip is tested: the date is the lever the athlete actually moves
    /// on those cards, so it — not a stepper nobody rendered — is what Coach's
    /// line counts and what body composition converts a rate over. A block
    /// length that ignored the date would print "about 8 weeks of work" under
    /// a milestone six months out, and would let the body-composition card
    /// show a weight, a rate and a date that cannot all three be true.
    ///
    /// The three HELD presets (Maintenance, Recovery, Consistency — the ones
    /// `GoalPreset.asksForDate` excludes) have no date to read, so their
    /// stepper's answer is the block length, clamped to the generator's own
    /// limits.
    static func weeks(preset: GoalPreset, byDate: Date?, heldWeeks: Int,
                      today: Date, calendar: Calendar = .current) -> Int {
        guard preset.asksForDate else {
            return max(GoalBlockLength.minimumWeeks,
                       min(GoalBlockLength.maximumWeeks, heldWeeks))
        }
        return GoalBlockLength.weeks(byDate: byDate, from: today, calendar: calendar)
    }

    /// Body composition's two readings are ONE milestone said two ways, so a
    /// change of horizon has to move whichever one the athlete is NOT holding.
    ///
    /// `stepsTheRate` is the card's segmented switch: on `A RATE` the rate is
    /// the athlete's and the weight follows it; on `A WEIGHT` the weight is
    /// theirs and the rate follows. Without this, moving the BY date left
    /// `TARGET 179 lbs`, `THAT IS −0.75 %/WK` and `BY <date>` on screen
    /// together while no longer all being true of one block.
    static func rebalancedBodyComposition(_ draft: BlockGoalDraft,
                                          startLbs: Decimal?,
                                          weeks: Int,
                                          stepsTheRate: Bool,
                                          unit: WeightUnit) -> BlockGoalDraft {
        let start = startLbs ?? draft.target.bodyWeightLbs ?? defaultBodyWeightLbs
        if stepsTheRate {
            let rate = draft.target.bodyWeightRatePercent ?? bodyCompositionRatePercent
            return applying(draft,
                            bodyWeightLbs: projectedBodyWeight(from: start, ratePercent: rate,
                                                               weeks: weeks, unit: unit))
        }
        let target = draft.target.bodyWeightLbs ?? start
        return applying(draft,
                        bodyWeightRatePercent: impliedRatePercent(from: start, to: target,
                                                                  weeks: weeks))
    }

    /// A strength block asks for about ten percent, snapped to something
    /// loadable. Never less than one increment above where the athlete is: a
    /// milestone at today's number is not a milestone.
    private static let strengthGainFactor: Decimal = 1.10
    /// The midpoint of spec §2.3's safe band for a cut (0.5 – 1 % a week),
    /// signed, applied per week and compounded across the block.
    static let bodyCompositionRatePercent = -0.75
    /// Spec §2.3's endurance ramp: +10 % a week, with every fourth week down.
    private static let enduranceWeeklyGain = 1.10
    /// A benchmark milestone is the same workout ten percent faster.
    private static let benchmarkImprovement = 0.90
    /// Spec §2.3's own worked example — "move 100,000 lb this block" over the
    /// default eight weeks.
    private static let volumePerWeekLbs = 12_500.0
    /// A block of a named workout the athlete has never run: "Murph under
    /// 45 min", the spec's example.
    private static let defaultBenchmarkSeconds = 45 * 60
    /// The seed when there is no body-weight reading at all. Internal rather
    /// than private because the card's steppers fall back to the same number,
    /// and two spellings of one default is how two of them drift.
    static let defaultBodyWeightLbs: Decimal = 190

    static func seededTarget(preset: GoalPreset, current: GoalTarget,
                             weeks: Int, unit: WeightUnit) -> GoalTarget {
        var target = GoalTarget()
        let weeks = max(1, weeks)

        switch preset {
        case .strength:
            target.exerciseID = current.exerciseID
            target.targetWeightLbs = raisedLoad(from: current.targetWeightLbs, unit: unit)

        case .repStrength:
            target.exerciseID = current.exerciseID
            // The load is FIXED — that is what "reps at a load" means — so the
            // seed keeps the athlete's own working load and climbs the reps.
            let load = current.loadLbs ?? current.targetWeightLbs ?? 225
            target.loadLbs = load
            target.targetWeightLbs = load
            // A rep every two weeks, the ramp spec §2.3 gives Consistency,
            // because a rep at a fixed load is the same kind of climb.
            target.targetReps = max(1, (current.targetReps ?? 5) + max(1, weeks / 2))

        case .muscle:
            let group = leadingGroup(current) ?? .chest
            let now = current.muscleTargets?[group.rawValue] ?? 0
            target.muscleTargets = [group.rawValue: min(30, max(recommendedWeeklySets,
                                                               now + 4))]

        case .endurance:
            target.activity = current.activity ?? "run"
            let now = current.distance ?? 10
            // Every fourth week is a down week, so the climb compounds over
            // the weeks that are not.
            let climbing = weeks - weeks / 4
            target.distance = (now * pow(enduranceWeeklyGain, Double(climbing)))
                .rounded()
            target.distance = min(200, max(1, target.distance ?? 1))

        case .consistency:
            target.days = min(7, max(1, (current.days ?? 3) + max(1, weeks / 2)))

        case .conditioning:
            target.sessionType = current.sessionType ?? "hiit"
            target.sessions = min(14, max(1, (current.sessions ?? 1) + max(1, weeks / 2)))

        case .maintenance:
            // OWNER DECISION 9: every major group, at the recommended number.
            // `MuscleGroup.allCases` is what "major" means in this app, as
            // shipped (spec §11.1).
            target.muscleTargets = Dictionary(
                uniqueKeysWithValues: MuscleGroup.allCases.map {
                    ($0.rawValue, recommendedWeeklySets)
                })

        case .recovery:
            target.stretchingExercises = max(1, current.stretchingExercises ?? 6)
            target.lissMinutes = max(15, current.lissMinutes ?? 150)

        case .bodyComposition:
            let now = current.bodyWeightLbs ?? defaultBodyWeightLbs
            target.bodyWeightRatePercent = bodyCompositionRatePercent
            target.bodyWeightLbs = projectedBodyWeight(
                from: now, ratePercent: bodyCompositionRatePercent,
                weeks: weeks, unit: unit)

        case .volume:
            target.volumeLbs = current.volumeLbs ?? (Double(weeks) * volumePerWeekLbs)

        case .benchmark:
            target.routineID = current.routineID
            let now = current.targetSeconds ?? defaultBenchmarkSeconds
            target.targetSeconds = max(60, Int((Double(now) * benchmarkImprovement).rounded()))
        }
        return target
    }

    /// The recommended weekly sets per group when nothing else says otherwise
    /// — the hypertrophy band's floor, which is what the generator holds a
    /// non-focus muscle at (`GeneratorScience.band(for:)`).
    ///
    /// Spec §11.1 leaves open whether `volume_targets` or the generator's
    /// bands are the number when both exist; the DOOR has no repository
    /// (global constraint 7), so it seeds from the band and the live builder
    /// reads whichever the block was actually built from.
    static var recommendedWeeklySets: Int {
        GeneratorScience.band(for: .hypertrophy).weeklySetsLow
    }

    /// About ten percent up, snapped to a loadable increment IN THE ATHLETE'S
    /// UNIT — the doctrine `Units.roundToIncrement` and
    /// `WeeklyGoalDetector.liftTarget` both follow — and never below one
    /// increment above where they are.
    static func raisedLoad(from currentLbs: Decimal?, unit: WeightUnit) -> Decimal {
        let base = currentLbs ?? 185
        let baseInUnit = Units.fromPounds(base, to: unit)
        let raised = Units.roundToIncrement(baseInUnit * strengthGainFactor, unit: unit)
        let floor = Units.roundToIncrement(baseInUnit + unit.displayIncrement, unit: unit)
        return Units.toPounds(max(raised, floor), from: unit)
    }

    /// `current × (1 + rate/100)^weeks`, snapped to the granularity a SCALE is
    /// read at (1 lb / 0.5 kg) rather than a plate's — `Units
    /// .formatBodyWeight`'s own rule: a person is not a barbell.
    static func projectedBodyWeight(from currentLbs: Decimal, ratePercent: Double,
                                    weeks: Int, unit: WeightUnit) -> Decimal {
        let step = unit == .kg ? 0.5 : 1.0
        let nowInUnit = double(Units.fromPounds(currentLbs, to: unit))
        let projected = nowInUnit * pow(1 + ratePercent / 100, Double(max(1, weeks)))
        let snapped = max(step, (projected / step).rounded() * step)
        return Units.toPounds(Decimal(snapped), from: unit)
    }

    /// The inverse: what weekly rate takes `current` to `target` over `weeks`.
    /// Used when the athlete steps the WEIGHT and the rate must follow, so the
    /// two readings on the body-composition card never contradict each other.
    static func impliedRatePercent(from currentLbs: Decimal, to targetLbs: Decimal,
                                   weeks: Int) -> Double {
        let now = double(currentLbs), goal = double(targetLbs)
        guard now > 0, goal > 0, weeks > 0 else { return 0 }
        return (pow(goal / now, 1.0 / Double(weeks)) - 1) * 100
    }

    /// The group a muscle goal is about — the one the athlete already trains
    /// most. Sorted rather than `max(by:)`, because a dictionary's maximum is
    /// not deterministic on a tie and a catalog frame must be.
    static func leadingGroup(_ target: GoalTarget) -> MuscleGroup? {
        guard let targets = target.muscleTargets, !targets.isEmpty else { return nil }
        let ranked = targets
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
        guard let first = ranked.first else { return nil }
        return MuscleGroup(rawValue: first.key)
    }

    // MARK: The edit

    /// The levers, applied to a draft. **A nil argument leaves that lever
    /// alone**; it never clears one, because every lever this card offers is
    /// bounded away from empty and "clear the date" is not a thing the card
    /// can ask for.
    ///
    /// THE METRIC IS NOT A PARAMETER. The levers change the milestone, never
    /// the metric — the one place a metric changes is the Strength card's
    /// `A MAX / REPS AT A LOAD` switch, and that RE-SEEDS through `draft(...)`
    /// with the other preset rather than mutating this one.
    static func applying(_ draft: BlockGoalDraft,
                         exerciseID: UUID? = nil,
                         targetWeightLbs: Decimal? = nil,
                         targetReps: Int? = nil,
                         loadLbs: Decimal? = nil,
                         muscleTargets: [String: Int]? = nil,
                         activity: String? = nil,
                         distance: Double? = nil,
                         days: Int? = nil,
                         sessionType: String? = nil,
                         sessions: Int? = nil,
                         lissMinutes: Int? = nil,
                         stretchingExercises: Int? = nil,
                         bodyWeightLbs: Decimal? = nil,
                         bodyWeightRatePercent: Double? = nil,
                         volumeLbs: Double? = nil,
                         routineID: UUID? = nil,
                         targetSeconds: Int? = nil,
                         byDate: Date? = nil) -> BlockGoalDraft {
        var edited = draft
        if let exerciseID { edited.target.exerciseID = exerciseID }
        if let targetWeightLbs { edited.target.targetWeightLbs = targetWeightLbs }
        if let targetReps { edited.target.targetReps = targetReps }
        if let loadLbs { edited.target.loadLbs = loadLbs }
        if let muscleTargets { edited.target.muscleTargets = muscleTargets }
        if let activity { edited.target.activity = activity }
        if let distance { edited.target.distance = distance }
        if let days { edited.target.days = days }
        if let sessionType { edited.target.sessionType = sessionType }
        if let sessions { edited.target.sessions = sessions }
        if let lissMinutes { edited.target.lissMinutes = lissMinutes }
        if let stretchingExercises { edited.target.stretchingExercises = stretchingExercises }
        if let bodyWeightLbs { edited.target.bodyWeightLbs = bodyWeightLbs }
        if let bodyWeightRatePercent { edited.target.bodyWeightRatePercent = bodyWeightRatePercent }
        if let volumeLbs { edited.target.volumeLbs = volumeLbs }
        if let routineID { edited.target.routineID = routineID }
        if let targetSeconds { edited.target.targetSeconds = targetSeconds }
        if let byDate { edited.byDate = byDate }
        return edited
    }

    // MARK: Coach's line

    /// Under the levers, first person (design rule 7), one line.
    ///
    /// Spec §5.2 gives it verbatim for Strength: **"You're at 205 now; that's
    /// about 6 weeks of work"**.
    ///
    /// WHEN THE BLOCK CANNOT MAKE THE DATE the line is REPLACED by B5's
    /// sentence (spec §3.2) and the primary still builds — the athlete picks:
    /// move the date, lower the target, or keep both. The ladder never lies
    /// about the gap.
    static func coachLine(preset: GoalPreset,
                          current: GoalTarget,
                          draft: BlockGoalDraft,
                          weeks: Int,
                          unit: WeightUnit,
                          reach: GoalBlockLength.Reach? = nil,
                          subject: String? = nil,
                          calendar: Calendar = .current) -> String {
        if let reach, !reach.reaches,
           let gap = GoalBlockLength.reachSentence(
               milestoneText: milestoneText(preset: preset, draft: draft,
                                            unit: unit, subject: subject),
               byDate: draft.byDate, reach: reach, calendar: calendar) {
            return gap
        }

        let span = weeks == 1 ? "1 week of work" : "\(weeks) weeks of work"

        if let reading = currentReading(preset: preset, current: current, unit: unit) {
            return "You're at \(reading) now; that's about \(span)."
        }

        if !preset.asksForDate {
            // Held for the block: there is no "where you are" to state, and
            // inventing a zero would be the exact failure the shipped strip
            // rule forbids ("never `0`").
            return weeks == 1 ? "I'll hold this for a week."
                              : "I'll hold this for \(weeks) weeks."
        }

        return "I haven't got a reading for this yet — I'll build to it over \(span)."
    }

    /// Where the athlete is now, in words, or nil when nothing has been
    /// measured. NEVER a zero standing in for an absent reading.
    static func currentReading(preset: GoalPreset, current: GoalTarget,
                               unit: WeightUnit) -> String? {
        switch preset {
        case .strength:
            guard let lbs = current.targetWeightLbs, lbs > 0 else { return nil }
            return Units.wholeNumber(pounds: lbs, unit: unit)

        case .repStrength:
            guard let reps = current.targetReps, reps > 0,
                  let load = current.loadLbs ?? current.targetWeightLbs else { return nil }
            return "\(reps) at \(Units.wholeNumber(pounds: load, unit: unit))"

        case .muscle:
            guard let group = leadingGroup(current),
                  let sets = current.muscleTargets?[group.rawValue], sets > 0 else { return nil }
            return "\(sets) \(group.rawValue) sets a week"

        case .endurance:
            guard let distance = current.distance, distance > 0 else { return nil }
            return "\(trimmed(distance)) \(WeeklyGoalProgressMath.distanceUnitLabel(unit)) a week"

        case .consistency:
            guard let days = current.days, days > 0 else { return nil }
            return days == 1 ? "1 day a week" : "\(days) days a week"

        case .conditioning:
            guard let sessions = current.sessions, sessions > 0 else { return nil }
            return sessions == 1 ? "1 session a week" : "\(sessions) sessions a week"

        case .maintenance, .recovery:
            // Held for the block. `coachLine` has its own sentence for these.
            return nil

        case .bodyComposition:
            guard let lbs = current.bodyWeightLbs, lbs > 0 else { return nil }
            return Units.formatBodyWeight(pounds: lbs, unit: unit)

        case .volume:
            guard let volume = current.volumeLbs, volume > 0 else { return nil }
            let inUnit = Units.fromPounds(volume, to: unit)
            return WeeklyGoalProgressMath.groupedNumber(inUnit) + " " + unit.label

        case .benchmark:
            guard let seconds = current.targetSeconds, seconds > 0 else { return nil }
            return WeeklyGoalProgressMath.clock(Double(seconds))
        }
    }

    /// The milestone as a phrase — "Bench 225", "12 chest sets", "45:00" —
    /// which is the head of the gap sentence and the card's own headline.
    ///
    /// `subject` is the lift's, group's or routine's NAME, which this file
    /// does not know: the view has the pickers, so it passes the word in.
    static func milestoneText(preset: GoalPreset, draft: BlockGoalDraft,
                              unit: WeightUnit, subject: String? = nil) -> String {
        let target = draft.target
        let named = { (tail: String) -> String in
            guard let subject, !subject.isEmpty else { return tail }
            return "\(subject) \(tail)"
        }
        switch preset {
        case .strength:
            return named(Units.wholeNumber(pounds: target.targetWeightLbs ?? 0, unit: unit))
        case .repStrength:
            let load = Units.wholeNumber(pounds: target.loadLbs ?? 0, unit: unit)
            return named("\(target.targetReps ?? 0) at \(load)")
        case .muscle:
            guard let group = leadingGroup(target),
                  let sets = target.muscleTargets?[group.rawValue] else { return "muscle sets" }
            return "\(sets) \(group.rawValue) sets"
        case .endurance:
            let label = WeeklyGoalProgressMath.distanceUnitLabel(unit)
            return "\(trimmed(target.distance ?? 0)) \(label) a week"
        case .consistency:
            let days = target.days ?? 0
            return days == 1 ? "1 day a week" : "\(days) days a week"
        case .conditioning:
            let count = target.sessions ?? 0
            let type = (target.sessionType ?? "").uppercased()
            return "\(count) \(type) a week"
        case .maintenance:
            return "the recommended volumes"
        case .recovery:
            return "\(target.stretchingExercises ?? 0) stretches a week"
        case .bodyComposition:
            return Units.formatBodyWeight(pounds: target.bodyWeightLbs ?? 0, unit: unit)
        case .volume:
            let inUnit = Units.fromPounds(target.volumeLbs ?? 0, to: unit)
            return WeeklyGoalProgressMath.groupedNumber(inUnit) + " " + unit.label
        case .benchmark:
            return named(WeeklyGoalProgressMath.clock(Double(target.targetSeconds ?? 0)))
        }
    }

    // MARK: Why the primary is disabled

    /// The `incompleteReason` idiom `WeeklyGoalEditorSheet.swift:711-724`
    /// already ships: a disabled button with no reason is a dead end.
    ///
    /// Only the three presets whose milestone names a THING can be
    /// under-specified — every other lever on every other card is seeded to a
    /// legal value and bounded away from zero.
    ///
    /// `hasRoutines` is the one thing a reason can depend on that is not in
    /// the draft: an athlete with NO SAVED ROUTINES who picks Benchmark used
    /// to get an empty picker and a permanently disabled primary reading
    /// "Pick the routine this goal is about." with nothing to pick — a dead
    /// end whose only exit is Back. A disabled button must say the thing the
    /// athlete can actually do about it.
    static func incompleteReason(preset: GoalPreset, draft: BlockGoalDraft,
                                 hasRoutines: Bool = true) -> String? {
        switch preset {
        case .strength, .repStrength:
            return draft.target.exerciseID == nil ? "Pick the lift this goal is about." : nil
        case .muscle:
            let hasTarget = draft.target.muscleTargets?.values.contains { $0 > 0 } ?? false
            return hasTarget ? nil : "Give the muscle group a weekly set target."
        case .benchmark:
            guard hasRoutines else { return noRoutinesReason }
            return draft.target.routineID == nil ? "Pick the routine this goal is about." : nil
        case .endurance, .consistency, .conditioning, .maintenance, .recovery,
             .bodyComposition, .volume:
            return nil
        }
    }

    /// One sentence, said in the same words wherever the state shows: on the
    /// milestone card in place of the picker, and under the primary as the
    /// reason it is disabled.
    static let noRoutinesReason =
        "You have no routines yet — build one first, or pick a workout from Discover."

    /// The goal screen's version — a tile has room for a note, not a
    /// sentence, and the card behind it says the rest.
    static let noRoutinesTileNote = "Needs a saved routine."


    // MARK: Small numbers

    /// One decimal at most, trailing ".0" trimmed — `Units.trimmed`'s rule for
    /// a value that is already in the display unit, for the readings that are
    /// `Double` rather than `Decimal`.
    static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded.rounded()))"
            : String(format: "%.1f", rounded)
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

// MARK: - GoalMilestoneView

struct GoalMilestoneView: View {

    let preset: GoalPreset
    /// What the athlete's log says right now, for the seeds and for Coach's
    /// line. Passed in, never fetched here.
    let current: GoalTarget
    /// The block's focus lifts first, then the catalog — the same ordering
    /// `WeeklyGoalEditorSheet.liftPicker` uses.
    let lifts: [WeeklyGoalEditorSheet.LiftOption]
    let routines: [Routine]
    /// Fixture clock for the catalog frames; `.now` in the app.
    var today: Date = .now
    var unitOverride: WeightUnit? = nil
    var onBuild: (BlockGoalDraft) -> Void

    /// The block length the weeks stepper opens on.
    ///
    /// ADDITIVE to the plan's signature, and it exists for the two cards whose
    /// ONLY lever is the block length (Maintenance and Recovery, spec §5.2):
    /// without it those cards would have a stepper the frame cannot pin, and
    /// `goal-milestone-recovery` is specified as a SIX-week block.
    var blockWeeks: Int = GoalBlockLength.defaultWeeks

    @Environment(\.gsTheme) private var theme

    /// The milestone as it stands. The primary hands over THIS — the edited
    /// draft, never the seed (task C3).
    @State private var draft: BlockGoalDraft
    /// The block length the WEEKS STEPPER holds — Maintenance's, Recovery's
    /// and Consistency's only lever (spec §5.2), and theirs alone.
    ///
    /// It is not `weeks`. On the eight date-bearing presets the block length
    /// is READ OFF THE DATE (see `weeks` below); this value is what the
    /// stepper writes for the three presets that have no date to read.
    @State private var heldWeeks: Int
    /// The Strength card's `A MAX / REPS AT A LOAD` switch — the one place a
    /// metric changes, and it re-seeds rather than mutating.
    @State private var repsAtALoad: Bool
    /// The Body composition card's `A WEIGHT / A RATE` switch. Both readings
    /// are always set and always agree; this only chooses which one is stepped.
    @State private var stepsTheRate = false
    /// The pickers' search text. The cap is on what is DRAWN, never on what is
    /// searched — `WeeklyGoalEditorSheet.liftPicker`'s own rule, and the
    /// reason a 1,300-row catalog is reachable from a card six rows tall.
    @State private var liftQuery = ""
    @State private var routineQuery = ""

    init(preset: GoalPreset,
         current: GoalTarget,
         lifts: [WeeklyGoalEditorSheet.LiftOption] = [],
         routines: [Routine] = [],
         today: Date = .now,
         unitOverride: WeightUnit? = nil,
         blockWeeks: Int = GoalBlockLength.defaultWeeks,
         onBuild: @escaping (BlockGoalDraft) -> Void) {
        self.preset = preset
        self.current = current
        self.lifts = lifts
        self.routines = routines
        self.today = today
        self.unitOverride = unitOverride
        self.blockWeeks = blockWeeks
        self.onBuild = onBuild

        // THE SEED ROUNDS IN `unitOverride ?? .lbs`, not in the athlete's live
        // unit, because a SwiftUI `View.init` is not `@MainActor`-isolated and
        // `ThemeStore` is — reading the store here is the kind of isolation
        // violation that only shows up in CI. Every READING and every STEP
        // below uses the athlete's own unit from the first render (the
        // computed `unit`), which is the same split `WeeklyGoalEditorSheet`
        // ships: it seeds a flat `225` and steps in kilograms.
        let seedUnit = unitOverride ?? .lbs
        let seeded = GoalMilestoneCopy.draft(preset: preset, current: current,
                                             today: today, unit: seedUnit,
                                             weeks: blockWeeks)
        _draft = State(initialValue: seeded)
        _heldWeeks = State(initialValue: max(GoalBlockLength.minimumWeeks,
                                             min(GoalBlockLength.maximumWeeks, blockWeeks)))
        _repsAtALoad = State(initialValue: preset == .repStrength)
    }

    // MARK: Reads

    /// One read of the unit setting for the whole card — `AnchorEntryView
    /// .unit`'s idiom, and the reason no label here spells "mi" or "lb"
    /// itself.
    private var unit: WeightUnit { unitOverride ?? ThemeStore.shared.weightUnit }

    /// The preset the DRAFT is for, which is the card's preset except on the
    /// Strength card in its second mode.
    private var activePreset: GoalPreset {
        preset == .strength && repsAtALoad ? .repStrength : preset
    }

    private var subject: String? {
        switch activePreset {
        case .strength, .repStrength:
            return lifts.first { $0.id == draft.target.exerciseID }?.name
        case .benchmark:
            return routines.first { $0.id == draft.target.routineID }?.name
        default:
            return nil
        }
    }

    /// The block length this card is working to.
    ///
    /// COMPUTED, NEVER STORED, on the eight date-bearing presets: the date is
    /// the lever, so everything downstream of the horizon — Coach's line, the
    /// rate↔weight conversion, the Strength mode switch's re-seed — moves the
    /// moment the athlete moves it.
    private var weeks: Int {
        GoalMilestoneCopy.weeks(preset: activePreset, byDate: draft.byDate,
                                heldWeeks: heldWeeks, today: today)
    }

    private var incompleteReason: String? {
        GoalMilestoneCopy.incompleteReason(preset: activePreset, draft: draft,
                                           hasRoutines: !routines.isEmpty)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                modeSwitch
                levers
                coachLine
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle(GoalScreenView.name(preset))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GoalScreenView.name(activePreset))
                .font(GSFont.heading(24, relativeTo: .title))
                .foregroundStyle(theme.text)
            // `repStrength` is not a tile, so it has no line of its own; it
            // borrows Strength's, which is the card it is a lever on.
            Text((GoalScreenView.copy[preset] ?? GoalScreenView.copy[.strength])?.line ?? "")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The two segmented switches

    @ViewBuilder
    private var modeSwitch: some View {
        switch preset {
        case .strength:
            segmented(labels: ["A MAX", "REPS AT A LOAD"],
                      selected: repsAtALoad ? 1 : 0) { index in
                repsAtALoad = index == 1
                reseed()
            }
        case .bodyComposition:
            segmented(labels: ["A WEIGHT", "A RATE"],
                      selected: stepsTheRate ? 1 : 0) { index in
                stepsTheRate = index == 1
            }
        default:
            EmptyView()
        }
    }

    /// Switching the Strength card's mode changes the METRIC, so it re-seeds
    /// through `GoalMilestoneCopy.draft` rather than editing the draft in
    /// place: `applying` may never change a metric, and a `liftRepsAtLoad`
    /// milestone carrying a `liftOneRepMax` target is a goal nothing can read.
    private func reseed() {
        let carried = draft.target.exerciseID
        var seeded = GoalMilestoneCopy.draft(preset: activePreset, current: current,
                                             today: today, unit: unit, weeks: weeks)
        seeded.target.exerciseID = carried ?? seeded.target.exerciseID
        if let existing = draft.byDate, seeded.byDate != nil { seeded.byDate = existing }
        draft = seeded
    }

    // MARK: The levers

    @ViewBuilder
    private var levers: some View {
        switch activePreset {
        case .strength:        strengthLevers
        case .repStrength:     repStrengthLevers
        case .muscle:          muscleLevers
        case .endurance:       enduranceLevers
        case .consistency:     consistencyLevers
        case .conditioning:    conditioningLevers
        case .maintenance:     maintenanceLevers
        case .recovery:        recoveryLevers
        case .bodyComposition: bodyCompositionLevers
        case .volume:          volumeLevers
        case .benchmark:       benchmarkLevers
        }
    }

    private var strengthLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            liftPicker
            loadStepper(title: "TARGET", pounds: draft.target.targetWeightLbs ?? 0) { next in
                draft = GoalMilestoneCopy.applying(draft, targetWeightLbs: next)
            }
            dateRow
        }
    }

    private var repStrengthLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            liftPicker
            loadStepper(title: "AT", pounds: draft.target.loadLbs ?? 0) { next in
                // Both, and they are the same number: `loadLbs` is what "reps
                // at a load" means, and `targetWeightLbs` is the column every
                // `lift`-kind reader already looks at (spec §4's mapping puts
                // `liftRepsAtLoad` on the `lift` kind with the load in
                // `targetWeightLbs`). Declaration order, because Swift wants
                // its arguments in the order the parameters were written.
                draft = GoalMilestoneCopy.applying(draft, targetWeightLbs: next,
                                                   loadLbs: next)
            }
            stepperRow(title: "REPS", value: draft.target.targetReps ?? 1,
                       suffix: (draft.target.targetReps ?? 1) == 1 ? "REP" : "REPS",
                       canDecrease: (draft.target.targetReps ?? 1) > 1,
                       canIncrease: (draft.target.targetReps ?? 1) < 30) { delta in
                let next = max(1, min(30, (draft.target.targetReps ?? 1) + delta))
                draft = GoalMilestoneCopy.applying(draft, targetReps: next)
            }
            // THE DATE IS HERE EVEN THOUGH THE PLAN'S LEVER TABLE STOPS AT THE
            // REP STEPPER: `GoalPreset.repStrength.asksForDate` is `true`
            // (Task 0, frozen), so this milestone HAS a date. A date the
            // athlete can neither see nor move is worse than one more row.
            dateRow
        }
    }

    private var muscleLevers: some View {
        let group = GoalMilestoneCopy.leadingGroup(draft.target) ?? .chest
        let sets = draft.target.muscleTargets?[group.rawValue] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            chipRow(options: MuscleGroup.allCases.map(\.rawValue),
                    selection: group.rawValue) { chosen in
                draft = GoalMilestoneCopy.applying(draft, muscleTargets: [chosen: max(1, sets)])
            }
            stepperRow(title: "PER WEEK", value: sets, suffix: "SETS",
                       canDecrease: sets > 1, canIncrease: sets < 40) { delta in
                draft = GoalMilestoneCopy.applying(
                    draft, muscleTargets: [group.rawValue: max(1, min(40, sets + delta))])
            }
            dateRow
        }
    }

    private var enduranceLevers: some View {
        let distance = draft.target.distance ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            chipRow(options: Self.activities, selection: draft.target.activity ?? "run") {
                draft = GoalMilestoneCopy.applying(draft, activity: $0)
            }
            stepperRow(title: "PER WEEK", value: Int(distance.rounded()),
                       suffix: WeeklyGoalProgressMath.distanceUnitLabel(unit).uppercased(),
                       canDecrease: distance > 1, canIncrease: distance < 200) { delta in
                draft = GoalMilestoneCopy.applying(
                    draft, distance: max(1, min(200, distance.rounded() + Double(delta))))
            }
            dateRow
        }
    }

    private var consistencyLevers: some View {
        let days = draft.target.days ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            stepperRow(title: "PER WEEK", value: days,
                       suffix: days == 1 ? "DAY" : "DAYS",
                       canDecrease: days > 1, canIncrease: days < 7) { delta in
                draft = GoalMilestoneCopy.applying(draft, days: max(1, min(7, days + delta)))
            }
            weeksStepper
        }
    }

    private var conditioningLevers: some View {
        let sessions = draft.target.sessions ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            chipRow(options: Self.sessionTypes,
                    selection: draft.target.sessionType ?? "hiit") {
                draft = GoalMilestoneCopy.applying(draft, sessionType: $0)
            }
            stepperRow(title: "PER WEEK", value: sessions,
                       suffix: sessions == 1 ? "SESSION" : "SESSIONS",
                       canDecrease: sessions > 1, canIncrease: sessions < 14) { delta in
                draft = GoalMilestoneCopy.applying(
                    draft, sessions: max(1, min(14, sessions + delta)))
            }
            dateRow
        }
    }

    /// THE BLOCK LENGTH ONLY (spec §5.2). The targets are the recommended
    /// numbers for every major group — read, shown, NOT edited.
    private var maintenanceLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            weeksStepper
            VStack(spacing: 6) {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    readOnlyRow(title: group.rawValue.uppercased(),
                                reading: "\(draft.target.muscleTargets?[group.rawValue] ?? 0) SETS")
                }
            }
            Text("These are the recommended weekly numbers. A maintenance block holds them; it does not chase them.")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recoveryLevers: some View {
        let stretches = draft.target.stretchingExercises ?? 1
        let liss = draft.target.lissMinutes ?? 15
        return VStack(alignment: .leading, spacing: 10) {
            weeksStepper
            stepperRow(title: "STRETCHES", value: stretches, suffix: "A WEEK",
                       canDecrease: stretches > 1, canIncrease: stretches < 21) { delta in
                draft = GoalMilestoneCopy.applying(
                    draft, stretchingExercises: max(1, min(21, stretches + delta)))
            }
            stepperRow(title: "EASY MINUTES", value: liss, suffix: "A WEEK",
                       canDecrease: liss > 15, canIncrease: liss < 600) { delta in
                draft = GoalMilestoneCopy.applying(
                    draft, lissMinutes: max(15, min(600, liss + delta * 15)))
            }
        }
    }

    private var bodyCompositionLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stepsTheRate { rateStepper } else { bodyWeightStepper }
            readOnlyRow(title: stepsTheRate ? "LANDS AT" : "THAT IS",
                        reading: stepsTheRate ? bodyWeightReading : rateReading)
            dateRow
        }
    }

    private var volumeLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepperRow(title: "THIS BLOCK", text: volumeReading,
                       canDecrease: (draft.target.volumeLbs ?? 0) > volumeStepLbs,
                       canIncrease: true) { delta in
                let next = (draft.target.volumeLbs ?? 0) + Double(delta) * volumeStepLbs
                draft = GoalMilestoneCopy.applying(draft, volumeLbs: max(volumeStepLbs, next))
            }
            dateRow
        }
    }

    private var benchmarkLevers: some View {
        let seconds = draft.target.targetSeconds ?? 60
        return VStack(alignment: .leading, spacing: 10) {
            if routines.isEmpty {
                // ONE PLAIN LINE where the picker would be, and the primary
                // below says the same thing as its reason. A picker with
                // nothing in it explains nothing.
                Text(GoalMilestoneCopy.noRoutinesReason)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            } else {
                routinePicker
            }
            stepperRow(title: "MINUTES", value: seconds / 60,
                       suffix: seconds / 60 == 1 ? "MINUTE" : "MINUTES",
                       canDecrease: seconds >= 120, canIncrease: seconds < 180 * 60) { delta in
                let next = max(60, min(180 * 60, seconds + delta * 60))
                draft = GoalMilestoneCopy.applying(draft, targetSeconds: next)
            }
            stepperRow(title: "SECONDS", value: seconds % 60, suffix: "SECONDS",
                       canDecrease: seconds % 60 >= 5, canIncrease: seconds % 60 <= 50) { delta in
                let next = max(60, seconds + delta * 5)
                draft = GoalMilestoneCopy.applying(draft, targetSeconds: next)
            }
            dateRow
        }
    }

    // MARK: Lever furniture
    //
    // Flat on `theme.surface` (design rule 1: furniture inside a card stays
    // flat), the same recipe `WeeklyGoalEditorSheet` uses for the same job.

    private static let activities = ["run", "bike", "row", "walk"]
    private static let sessionTypes = ["hiit", "mobility", "cardio", "class"]

    /// 2,500 lb a step (the plan's number); a kg athlete steps by a round
    /// 1,000 kg instead of by 1,134, because a step nobody would name is a
    /// step nobody can aim with.
    private var volumeStepLbs: Double {
        unit == .kg ? GoalMilestoneCopy.double(Units.toPounds(1_000, from: .kg)) : 2_500
    }

    private var volumeReading: String {
        let inUnit = Units.fromPounds(draft.target.volumeLbs ?? 0, to: unit)
        return WeeklyGoalProgressMath.groupedNumber(inUnit) + " " + unit.label.uppercased()
    }

    private var bodyWeightReading: String {
        Units.formatBodyWeight(pounds: draft.target.bodyWeightLbs ?? 0, unit: unit)
    }

    /// TWO DECIMALS, always. The stepper moves in quarter-points, so a
    /// one-decimal reading would round -0.75 to -0.8 and the card would print
    /// a rate the athlete cannot step to.
    private var rateReading: String {
        let rate = draft.target.bodyWeightRatePercent ?? 0
        let sign = rate > 0 ? "+" : ""
        return sign + String(format: "%.2f", rate) + " %/WK"
    }

    private var bodyWeightStep: Decimal { unit == .kg ? Decimal(0.5) : 1 }

    private var bodyWeightStepper: some View {
        stepperRow(title: "TARGET", text: bodyWeightReading,
                   canDecrease: Units.fromPounds(draft.target.bodyWeightLbs ?? 0,
                                                 to: unit) > bodyWeightStep,
                   canIncrease: true) { delta in
            let currentInUnit = Units.fromPounds(draft.target.bodyWeightLbs ?? 0, to: unit)
            let next = max(bodyWeightStep, currentInUnit + Decimal(delta) * bodyWeightStep)
            let pounds = Units.toPounds(next, from: unit)
            draft = GoalMilestoneCopy.applying(
                draft, bodyWeightLbs: pounds,
                bodyWeightRatePercent: GoalMilestoneCopy.impliedRatePercent(
                    from: current.bodyWeightLbs ?? pounds, to: pounds, weeks: weeks))
            // `weeks` is read off the date above, so a cut set today and a cut
            // set after moving the milestone a month out are different rates,
            // which is the whole point.
        }
    }

    private var rateStepper: some View {
        stepperRow(title: "RATE", text: rateReading,
                   canDecrease: (draft.target.bodyWeightRatePercent ?? 0) > -2,
                   canIncrease: (draft.target.bodyWeightRatePercent ?? 0) < 2) { delta in
            let next = max(-2, min(2, (draft.target.bodyWeightRatePercent ?? 0)
                                      + Double(delta) * 0.25))
            let landing = GoalMilestoneCopy.projectedBodyWeight(
                from: current.bodyWeightLbs ?? draft.target.bodyWeightLbs
                    ?? GoalMilestoneCopy.defaultBodyWeightLbs,
                ratePercent: next, weeks: weeks, unit: unit)
            draft = GoalMilestoneCopy.applying(draft, bodyWeightLbs: landing,
                                               bodyWeightRatePercent: next)
        }
    }

    /// The block length, for the two cards whose only lever it is — and for
    /// Consistency, whose milestone spec §2.3 gives as "days per week, HELD
    /// FOR N WEEKS".
    ///
    /// It renders ONLY for those three, which is exactly why `weeks` may not
    /// be this stepper's value on the other eight: there, nothing would ever
    /// write it.
    private var weeksStepper: some View {
        stepperRow(title: "BLOCK", value: heldWeeks,
                   suffix: heldWeeks == 1 ? "WEEK" : "WEEKS",
                   canDecrease: heldWeeks > GoalBlockLength.minimumWeeks,
                   canIncrease: heldWeeks < 24) { delta in
            heldWeeks = max(GoalBlockLength.minimumWeeks, min(24, heldWeeks + delta))
        }
    }

    private var dateRow: some View {
        HStack(spacing: 8) {
            Text("BY")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)

            Spacer(minLength: 6)

            DatePicker("", selection: byDateBinding, in: today...,
                       displayedComponents: .date)
                .labelsHidden()
                .tint(theme.accent)
                .font(GSFont.bold(14, relativeTo: .body))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
    }

    /// THE DATE IS THE HORIZON, so setting it does more than stamp a field:
    /// `weeks` is read off it, and on the body-composition card the reading
    /// the athlete is not holding has to follow it or the card contradicts
    /// itself.
    private var byDateBinding: Binding<Date> {
        Binding(
            get: { draft.byDate ?? GoalMilestoneCopy.milestoneDate(from: today, weeks: weeks) },
            set: { newDate in
                let moved = GoalMilestoneCopy.applying(draft, byDate: newDate)
                guard activePreset == .bodyComposition else { draft = moved; return }
                draft = GoalMilestoneCopy.rebalancedBodyComposition(
                    moved, startLbs: current.bodyWeightLbs,
                    weeks: GoalMilestoneCopy.weeks(preset: activePreset, byDate: newDate,
                                                   heldWeeks: heldWeeks, today: today),
                    stepsTheRate: stepsTheRate, unit: unit)
            })
    }

    private func loadStepper(title: String, pounds: Decimal,
                             onSet: @escaping (Decimal) -> Void) -> some View {
        stepperRow(title: title, text: Units.format(pounds: pounds, unit: unit),
                   canDecrease: Units.fromPounds(pounds, to: unit) > unit.displayIncrement,
                   canIncrease: true) { delta in
            let step = unit.displayIncrement
            let inUnit = Units.fromPounds(pounds, to: unit)
            let next = Units.roundToIncrement(inUnit + Decimal(delta) * step, unit: unit)
            onSet(Units.toPounds(max(step, next), from: unit))
        }
    }

    private func stepperRow(title: String, value: Int, suffix: String,
                            canDecrease: Bool, canIncrease: Bool,
                            onStep: @escaping (Int) -> Void) -> some View {
        stepperRow(title: title, text: "\(value) \(suffix)",
                   canDecrease: canDecrease, canIncrease: canIncrease, onStep: onStep)
    }

    private func stepperRow(title: String, text: String,
                            canDecrease: Bool, canIncrease: Bool,
                            onStep: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(text)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            stepButton(systemName: "minus", enabled: canDecrease) { onStep(-1) }
            stepButton(systemName: "plus", enabled: canIncrease) { onStep(1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(text)")
    }

    private func stepButton(systemName: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? theme.text : theme.neutral500)
                .frame(width: 30, height: 30)
                .background(theme.neutral300)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "plus" ? "Increase" : "Decrease")
    }

    private func readOnlyRow(title: String, reading: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 6)
            Text(reading)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
    }

    private func segmented(labels: [String], selected: Int,
                           onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                chip(label: label, selected: index == selected) { onSelect(index) }
            }
        }
    }

    private func chipRow(options: [String], selection: String,
                         onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                chip(label: option.uppercased(), selected: option == selection) {
                    onSelect(option)
                }
            }
        }
    }

    private func chip(label: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(selected ? theme.text : theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? theme.neutral300 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.pill))
                .overlay(
                    !selected
                        ? RoundedRectangle(cornerRadius: GSMetrics.pill)
                            .strokeBorder(theme.divider, lineWidth: 1)
                        : nil
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: The pickers

    /// EVERY LIFT THE HOST HANDED OVER — focus lifts first, then the catalog
    /// — in a search field over a bounded inner scroll.
    ///
    /// `WeeklyGoalEditorSheet.liftPicker` is the precedent, down to the cap:
    /// the list is capped at what is DRAWN (40 matched rows), never at what is
    /// SEARCHED, because the catalog is over 1,300 rows. The six-row cap this
    /// replaces was neither — it computed twelve options in the host and drew
    /// six, so an athlete with three focus lifts could see three compounds and
    /// set a strength goal on nothing else, with no scroll-past, no search and
    /// no "more".
    private var liftPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField("Search lifts", text: $liftQuery)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(visibleLifts) { option in
                        pickerRow(title: option.name, detail: option.detail,
                                  selected: option.id == draft.target.exerciseID) {
                            draft = GoalMilestoneCopy.applying(draft, exerciseID: option.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    /// The athlete's own routines — a much smaller list than the lift
    /// catalog, so the same bounded scroll is generous rather than necessary.
    /// The empty case never reaches here: `benchmarkLevers` says so in words
    /// instead.
    private var routinePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if routines.count > 6 {
                searchField("Search routines", text: $routineQuery)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(visibleRoutines) { routine in
                        pickerRow(title: routine.name,
                                  detail: (routine.description ?? "ROUTINE").uppercased(),
                                  selected: routine.id == draft.target.routineID) {
                            draft = GoalMilestoneCopy.applying(draft, routineID: routine.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    /// Focus lifts first, then everything else with the focus lifts removed so
    /// nothing appears twice, then the display cap —
    /// `WeeklyGoalEditorSheet.visibleLifts`' shape exactly.
    private var visibleLifts: [WeeklyGoalEditorSheet.LiftOption] {
        let query = liftQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = query.isEmpty ? lifts : lifts.filter { $0.name.lowercased().contains(query) }
        return Array(matched.prefix(40))
    }

    private var visibleRoutines: [Routine] {
        let query = routineQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = query.isEmpty
            ? routines
            : routines.filter { $0.name.lowercased().contains(query) }
        return Array(matched.prefix(40))
    }

    private func searchField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(GSFont.body(14, relativeTo: .body))
            .foregroundStyle(theme.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.divider, lineWidth: 1))
    }

    private func pickerRow(title: String, detail: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(1.0)
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            .overlay(
                selected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.accent, lineWidth: 1.5)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Coach's line, and the primary

    /// One line, first person (design rule 7), on a `surface` strip at 14 pt —
    /// a line that belongs to the card above it (rule 1).
    private var coachLine: some View {
        Text(GoalMilestoneCopy.coachLine(preset: activePreset, current: current,
                                         draft: draft, weeks: weeks, unit: unit,
                                         subject: subject))
            .font(GSFont.body(13, relativeTo: .subheadline))
            .foregroundStyle(theme.neutral700)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// `BUILD MY BLOCK` — accent, full width, the screen's ONE primary
    /// (design rule 4). Disabled with a stated reason when the card is
    /// incomplete, because a disabled button with no reason is a dead end.
    private var footer: some View {
        VStack(spacing: 8) {
            if let incompleteReason {
                Text(incompleteReason)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { onBuild(draft) } label: {
                Text("BUILD MY BLOCK")
                    .font(GSFont.bold(14, relativeTo: .body))
                    .tracking(1.0)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
            .disabled(incompleteReason != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(theme.bg)
    }
}
