import Foundation

// MARK: - WeeklyGoalDetector
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B ("Detection"). Plan: Stream A task A10.
//
// When a week starts with no `weekly_goals` row, Coach derives one. THE LAW
// IS THAT IT NEVER RETURNS NIL: the design's last rule is "nothing known →
// `days` at the streak's own number", so every athlete has a goal on Home
// from their first week, and the strip's `kind == nil` invitation is only
// ever the pre-first-detection state.
//
// PURE. Every input is passed in — the enrollment, the week's routines, the
// catalog, the profile, the titration's volume targets, the athlete's
// weekly-days number, even the clock and the calendar. Nothing here fetches,
// so every branch below is a unit test rather than a fixture world.
//
// `source` is ALWAYS `.coach` on a detected goal. That is what makes owner
// answer 3 enforceable at the write path (task A11): a row this function
// produced may be overwritten by the next detection, and a row the athlete
// saved may not.

enum WeeklyGoalDetector {

    /// Miles per training day behind a detected `distance` goal, and
    /// kilometres per training day for a metric athlete.
    ///
    /// A STARTING POINT COACH PROPOSES, not a prescription — the athlete
    /// edits it in the editor and the goal becomes `source = .user`, after
    /// which detection never touches it again. Round numbers on purpose: a
    /// derived 14.3 mi reads as precision this has no basis for.
    static let milesPerTrainingDay = 3.0
    static let kilometresPerTrainingDay = 5.0

    /// The progression a detected `lift` goal asks for: +5 % on the block's
    /// baseline, rounded to something the athlete can actually load.
    static let liftTargetMultiplier: Decimal = 1.05

    // MARK: - The three rules

    /// The design's rules, in order. Falls through 1 → 2 → 3, and 3 always
    /// answers.
    ///
    /// SIGNATURE NOTE. The plan writes this as `detect(enrollment:
    /// weekRoutines:routineExercises:catalog:trainingProfile:
    /// effectiveWeeklyGoal:weekStart:)`. Three parameters are added, each
    /// forced: `userID` and `now`, because a `WeeklyGoal` cannot be
    /// constructed without a `userID` and a `setAt`; and `volumeTargets`,
    /// because the controller's ruling makes the titration the FIRST source
    /// of muscle-set targets and a pure function cannot fetch it.
    /// `focusLiftBaselineLbs` and `unit` are defaulted and explained at
    /// their use sites.
    static func detect(userID: UUID,
                       enrollment: ProgramEnrollment?,
                       weekRoutines: [Routine],
                       routineExercises: [UUID: [RoutineExercise]],
                       catalog: [UUID: Exercise],
                       trainingProfile: TrainingProfile?,
                       volumeTargets: [VolumeTarget],
                       effectiveWeeklyGoal: Int,
                       weekStart: String,
                       focusLiftBaselineLbs: Decimal? = nil,
                       unit: WeightUnit = .lbs,
                       now: Date = .now,
                       calendar: Calendar = .current) -> WeeklyGoal {

        func goal(_ kind: WeeklyGoalKind, _ params: WeeklyGoalParams) -> WeeklyGoal {
            WeeklyGoal(userID: userID, weekStartString: weekStart, kind: kind,
                       params: params, source: .coach, setAt: now)
        }

        // ── Rule 1: an active block decides ──────────────────────────────
        // `endedAt != nil` is a finished block, which is no block at all.
        if let enrollment, enrollment.endedAt == nil {
            let dominant = trainingProfile?.dominantGoal
            let strengthFlavoured = dominant == .hypertrophy
                || dominant == .maxStrength
                || enrollment.focus.muscleGroup != nil

            if strengthFlavoured {
                // A focus lift WITH a baseline is the more specific case and
                // is checked first: it is exactly what the `lift` kind
                // exists for, and falling into `muscleSets` would throw away
                // the one number the block already committed to.
                if let exerciseID = enrollment.focus.exerciseIDs?.first,
                   let baseline = enrollment.baselineValue(for: exerciseID) {
                    return goal(.lift, WeeklyGoalParams(
                        exerciseID: exerciseID,
                        targetWeightLbs: liftTarget(fromBaselineLbs: baseline, unit: unit),
                        byDate: blockEnd(enrollment, calendar: calendar)))
                }
                return goal(.muscleSets, muscleSetParams(
                    volumeTargets: volumeTargets, weekRoutines: weekRoutines,
                    routineExercises: routineExercises, catalog: catalog))
            }

            let conditioningFlavoured = dominant == .conditioning
                || dominant == .fatLoss
                || isMostlyCardio(weekRoutines: weekRoutines,
                                  routineExercises: routineExercises,
                                  catalog: catalog)
            if conditioningFlavoured {
                return goal(.sessionsOfType, WeeklyGoalParams(
                    sessionType: "cardio",
                    count: trainingProfile?.daysPerWeek ?? effectiveWeeklyGoal))
            }
            // A block with an intent this rule does not recognise (mobility,
            // bone density, sport prep) falls through rather than being
            // forced into a kind that would misdescribe it.
        }

        // ── Rule 2: no block, but a profile ──────────────────────────────
        if let profile = trainingProfile {
            switch profile.dominantGoal {
            case .maxStrength:
                // "The profile's focus lift IF IT NAMES ONE" — and if a
                // baseline for it is known. Without a number to chase, a
                // `lift` goal renders no meter and no fraction
                // (`WeeklyGoalProgressMath.liftProgress` returns chrome for
                // exactly that shape), so `muscleSets` is the better answer
                // rather than a strictly-literal but empty one.
                if let exerciseID = profile.focusExerciseIDs?.first,
                   let baseline = focusLiftBaselineLbs {
                    return goal(.lift, WeeklyGoalParams(
                        exerciseID: exerciseID,
                        targetWeightLbs: liftTarget(fromBaselineLbs: baseline, unit: unit)))
                }
                return goal(.muscleSets, muscleSetParams(
                    volumeTargets: volumeTargets, weekRoutines: weekRoutines,
                    routineExercises: routineExercises, catalog: catalog))

            case .hypertrophy:
                return goal(.muscleSets, muscleSetParams(
                    volumeTargets: volumeTargets, weekRoutines: weekRoutines,
                    routineExercises: routineExercises, catalog: catalog))

            case .conditioning, .fatLoss:
                let perDay = unit == .lbs ? milesPerTrainingDay : kilometresPerTrainingDay
                return goal(.distance, WeeklyGoalParams(
                    activity: "run",
                    distanceTarget: Double(profile.daysPerWeek) * perDay))

            case .powerRFD, .boneDensity, .mobility, .sportPrep, .generalHealth:
                return goal(.days, WeeklyGoalParams(count: effectiveWeeklyGoal))
            }
        }

        // ── Rule 3: nothing known ────────────────────────────────────────
        return goal(.days, WeeklyGoalParams(count: effectiveWeeklyGoal))
    }

    // MARK: - muscleSets targets

    /// The muscle-set targets, and where they came from.
    ///
    /// **THE TITRATION IS READ FIRST** (controller ruling, 2026-09-06).
    /// `volume_targets` is "what the search has settled on, per muscle"
    /// (`RecoveryProbeRepository.swift:145-190`) — what the athlete's body
    /// answered, as opposed to what a routine prescribed. When any row
    /// exists, its muscles roll up into groups, their `weeklySets` SUM per
    /// group, and `targetSource` records `"titration"`.
    ///
    /// Only with no rows at all does this fall back to the week's routines'
    /// `targetSets` through `MuscleGroup.credit`, recording `"routines"`.
    /// The two are not blended: a half-titrated athlete whose chest came
    /// from the search and whose back came from a template would be reading
    /// one strip built from two different things, with nothing on it saying
    /// so.
    ///
    /// Top six by target, ties broken by `MuscleGroup.allCases` order — a
    /// cap that cannot bind today (there are exactly six groups) but that
    /// keeps the promise `WeeklyGoalParams.muscleTargets` documents.
    static func muscleSetParams(volumeTargets: [VolumeTarget],
                                weekRoutines: [Routine],
                                routineExercises: [UUID: [RoutineExercise]],
                                catalog: [UUID: Exercise]) -> WeeklyGoalParams {
        let titrated = titratedTargets(volumeTargets)
        if !titrated.isEmpty {
            return WeeklyGoalParams(muscleTargets: topSix(titrated),
                                    targetSource: "titration")
        }
        return WeeklyGoalParams(
            muscleTargets: topSix(routineTargets(weekRoutines: weekRoutines,
                                                 routineExercises: routineExercises,
                                                 catalog: catalog)),
            targetSource: "routines")
    }

    /// `volume_targets` rows -> per-group weekly sets. Muscles the six
    /// groups do not cover (`neck`) contribute nothing, exactly as they
    /// contribute nothing to progress.
    static func titratedTargets(_ volumeTargets: [VolumeTarget]) -> [MuscleGroup: Int] {
        var byGroup: [MuscleGroup: Int] = [:]
        for target in volumeTargets {
            guard let group = MuscleGroup.group(target.muscle) else { continue }
            byGroup[group, default: 0] += target.weeklySets
        }
        return byGroup
    }

    /// The week's routines' `targetSets`, summed through the same
    /// six-group credit rule progress is measured with — so a target and
    /// the number chasing it are the same arithmetic. A row with no
    /// `targetSets` (a cardio prescription, which carries minutes instead)
    /// contributes nothing.
    static func routineTargets(weekRoutines: [Routine],
                               routineExercises: [UUID: [RoutineExercise]],
                               catalog: [UUID: Exercise]) -> [MuscleGroup: Int] {
        var byGroup: [MuscleGroup: Double] = [:]
        for routine in weekRoutines {
            for row in routineExercises[routine.id] ?? [] {
                guard let sets = row.targetSets, sets > 0,
                      let exercise = catalog[row.exerciseID] else { continue }
                let perSet = MuscleGroup.credit(primary: exercise.primaryMuscle,
                                                secondaries: exercise.secondaryMuscles)
                for (group, credit) in perSet {
                    byGroup[group, default: 0] += credit * Double(sets)
                }
            }
        }
        return byGroup.compactMapValues { value in
            let rounded = Int(value.rounded())
            return rounded > 0 ? rounded : nil
        }
    }

    /// The six largest, keyed by `MuscleGroup.rawValue` for the jsonb.
    private static func topSix(_ targets: [MuscleGroup: Int]) -> [String: Int] {
        let order = Dictionary(uniqueKeysWithValues:
            MuscleGroup.allCases.enumerated().map { ($0.element, $0.offset) })
        let ranked = targets
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (order[lhs.key] ?? 0) < (order[rhs.key] ?? 0)
            }
            .prefix(6)
        return Dictionary(uniqueKeysWithValues:
            ranked.map { ($0.key.rawValue, $0.value) })
    }

    // MARK: - Helpers

    /// Is the week's work mostly cardio? Half or more of the week's
    /// prescribed exercises carrying `category == "cardio"` — the same
    /// half-threshold, and the same reasoning, as
    /// `WeeklyGoalProgressMath.sessionCounts`.
    static func isMostlyCardio(weekRoutines: [Routine],
                               routineExercises: [UUID: [RoutineExercise]],
                               catalog: [UUID: Exercise]) -> Bool {
        let categories = weekRoutines
            .flatMap { routineExercises[$0.id] ?? [] }
            .compactMap { catalog[$0.exerciseID]?.category.lowercased() }
        guard !categories.isEmpty else { return false }
        let cardio = categories.filter { $0 == "cardio" }.count
        return Double(cardio) >= Double(categories.count) / 2.0
    }

    /// Baseline + 5 %, rounded to something the athlete can load, returned
    /// in CANONICAL POUNDS.
    ///
    /// The round trip through the athlete's unit is deliberate:
    /// `displayIncrement` is 5 lb OR 2.5 kg, so rounding a pounds figure to
    /// a kilogram step (or the reverse) would land on a number no rack in
    /// that gym can build. Convert, round in the unit the plates are marked
    /// in, convert back.
    static func liftTarget(fromBaselineLbs baseline: Decimal,
                           unit: WeightUnit) -> Decimal {
        let inUnit = Units.fromPounds(baseline, to: unit) * liftTargetMultiplier
        return Units.toPounds(Units.roundToIncrement(inUnit, unit: unit), from: unit)
    }

    /// The block's last day: its start plus `weeks` weeks. `endedAt` is nil
    /// for the active block this reads, so the end has to be computed
    /// rather than looked up.
    static func blockEnd(_ enrollment: ProgramEnrollment,
                         calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: enrollment.weeks * 7,
                      to: enrollment.startedOn)
    }
}
