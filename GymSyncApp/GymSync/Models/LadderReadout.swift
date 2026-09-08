import Foundation

// MARK: - LadderReadout
//
// Spec §3.2 and §3.3. THE LADDER IS A READ-OUT of the block, projected onto
// the goal's metric — "so the ladder and the plan cannot disagree" (§3.1).
//
// PURE, and it takes the `Program` rather than fetching one: the generator is
// deterministic and synchronous, and a projection of it has to be too or the
// tests stop being able to state what the ladder IS.
enum LadderReadout {

    /// Week `k`'s rung for a strength goal: the top working load the block
    /// prescribes for the goal lift's MAIN slot (spec §3.2), which is
    ///     baselineE1RM × percentOfMax(slot) × intensityMultiplier(week k)
    /// and the e1RM that set implies.
    ///
    /// The DELOAD IS A RUNG (§3.2): the wave's lower week appears as the lower
    /// number it is, labelled, rather than smoothed away.
    ///
    /// nil when the block prescribes no `percentOfMax` for the lift — a
    /// bodyweight or explosive main carries none on purpose
    /// (`ProgramGenerator.swift:1657-1665`), and a ladder that invented one
    /// would print a load nobody prescribed.
    static func strengthRungs(program: ProgramGenerator.Program,
                              exerciseID: UUID,
                              baselineE1RMLbs: Decimal,
                              unit: WeightUnit) -> [GoalTarget]? {
        guard let slot = mainSlot(program: program, exerciseID: exerciseID),
              let percent = slot.percentOfMax, percent > 0,
              baselineE1RMLbs > 0 else { return nil }
        let base = NSDecimalNumber(decimal: baselineE1RMLbs).doubleValue * percent / 100

        return program.weeks.map { week in
            let raw = base * week.intensityMultiplier
            let loadLbs = Units.toPounds(
                Units.roundToIncrement(Units.fromPounds(Decimal(raw), to: unit), unit: unit),
                from: unit)
            var target = GoalTarget(exerciseID: exerciseID)
            target.targetWeightLbs = loadLbs
            // The reps the block prescribes for that slot, so the rung can be
            // read as "3 × 5 at 190" rather than as a bare number.
            target.targetReps = slot.repsLow
            return target
        }
    }

    /// A rep-strength rung: the same prescribed loading, but the goal's LOAD is
    /// fixed and the TOP-SET REP TARGET is the rung (spec §2.3, "Rep strength").
    static func repStrengthRungs(program: ProgramGenerator.Program,
                                 exerciseID: UUID,
                                 loadLbs: Decimal,
                                 currentReps: Int,
                                 targetReps: Int) -> [GoalTarget]? {
        guard mainSlot(program: program, exerciseID: exerciseID) != nil,
              targetReps > currentReps, !program.weeks.isEmpty else { return nil }
        let span = Double(targetReps - currentReps)
        let weeks = program.weeks.count
        return program.weeks.enumerated().map { index, week in
            var target = GoalTarget(exerciseID: exerciseID, targetReps: targetReps,
                                    loadLbs: loadLbs)
            let progress = Double(index + 1) / Double(weeks)
            let reps = currentReps + Int((span * progress).rounded())
            // A deload week does not ask for more reps at the same load.
            target.targetReps = week.isDeload
                ? Swift.max(currentReps, reps - 1)
                : reps
            target.targetWeightLbs = loadLbs
            return target
        }
    }

    /// Muscle and Maintenance: the WEEK'S PLANNED EFFECTIVE SETS per group ARE
    /// the rungs (spec §3.3), after `balanceWeeklyVolume`, scaled by the wave's
    /// own `volumeMultiplier` so a deload week reads as the lighter week it is.
    ///
    /// THE ROLLUP IS `MuscleGroup.credit`, not
    /// `ProgramGenerator.weeklyMuscleSets`. Those two accountings differ and
    /// the divergence is a documented open item (global constraint 12); the
    /// strip renders SIX GROUPS with capped secondary credit, and a rung the
    /// strip cannot render is not a rung. The ladder therefore reads the
    /// block's own `sets` through the strip's arithmetic — one number, one
    /// meaning, on both surfaces.
    static func muscleRungs(program: ProgramGenerator.Program,
                            catalog: [UUID: Exercise],
                            groups: [MuscleGroup]) -> [GoalTarget] {
        var perGroup: [MuscleGroup: Double] = [:]
        for day in program.days {
            for exercise in day.exercises where exercise.cardioZone == nil {
                guard let row = catalog[exercise.exerciseID] else { continue }
                let credit = MuscleGroup.credit(primary: row.primaryMuscle,
                                                secondaries: row.secondaryMuscles)
                for (group, share) in credit {
                    perGroup[group, default: 0] += share * Double(exercise.sets)
                }
            }
        }
        let wanted = groups.isEmpty ? MuscleGroup.allCases : groups
        return program.weeks.map { week in
            var targets: [String: Int] = [:]
            for group in wanted {
                let sets = Int(((perGroup[group] ?? 0) * week.volumeMultiplier).rounded())
                if sets > 0 { targets[group.rawValue] = sets }
            }
            return GoalTarget(muscleTargets: targets)
        }
    }

    /// The block's main-slot prescription for one lift, or nil when the block
    /// does not train it as a main. Days are searched in order and the FIRST
    /// main wins — the same lift appearing as an accessory later does not
    /// describe the goal.
    static func mainSlot(program: ProgramGenerator.Program,
                         exerciseID: UUID) -> ProgramGenerator.Exercise? {
        for day in program.days {
            if let match = day.exercises.first(where: {
                $0.exerciseID == exerciseID && $0.isMain && $0.cardioZone == nil
            }) { return match }
        }
        return nil
    }

    /// `LadderConstraints` from the block the generator produced — the deload
    /// and taper weeks every ramp rule has to respect.
    static func constraints(program: ProgramGenerator.Program,
                            unit: WeightUnit) -> LadderConstraints {
        var deloads: Set<Int> = []
        var tapers: Set<Int> = []
        for (index, week) in program.weeks.enumerated() {
            if week.isDeload { deloads.insert(index) }
            if week.volumeMultiplier < 1.0 && !week.isDeload { tapers.insert(index) }
        }
        return LadderConstraints(deloadWeeks: deloads, taperWeeks: tapers, unit: unit)
    }

    /// "3 × 5 at 190" and its implication "≈ 222 e1RM" — spec §3.2's own
    /// wording, built once so the ladder page, the schedule card and Coach's
    /// line cannot spell one rung three ways.
    ///
    /// BOTH NUMBERS GO THROUGH `Units.wholeNumber`, which is the app's one
    /// derived-weight display path, and that is a deliberate correction to the
    /// plan's snippet rather than a style preference. It wrote
    /// `NSDecimalNumber(decimal:).intValue` twice, which (a) TRUNCATES where
    /// every other derived-weight display in the app rounds, and (b) is the
    /// exact call `Decimal.displayInt`'s doc comment records returning **0**
    /// for some full-mantissa decimals — and `StatMath.estimatedOneRepMax`
    /// produces precisely such a value here (190 × 35/30 is a repeating
    /// decimal). `Units.wholeNumber` converts through the double, as the
    /// 2026-08-21 hardening sweep requires.
    ///
    /// THE NUMBER THIS PRODUCES IS EPLEY'S, and the spec's prose is not the
    /// authority on it. `StatMath.estimatedOneRepMax` is the app's single 1RM
    /// formula — `weight × (1 + reps/30)` — so 190 × 5 implies **222**, not the
    /// 214 the design document quotes (which is Brzycki's 36/(37−r)). One
    /// formula, one number, everywhere; the ladder does not get its own.
    static func strengthRungText(_ target: GoalTarget, sets: Int,
                                 unit: WeightUnit) -> (text: String, implication: String?) {
        guard let lbs = target.targetWeightLbs, let reps = target.targetReps else {
            return ("—", nil)
        }
        let load = Units.wholeNumber(pounds: lbs, unit: unit)
        let text = "\(sets) × \(reps) at \(load)"
        let implied = StatMath.estimatedOneRepMax(weight: lbs, reps: reps)
        return (text, "≈ \(Units.wholeNumber(pounds: implied, unit: unit)) e1RM")
    }
}

// MARK: - The block's shape, read off the enrollment's own template (task A11)
//
// `strengthRungs(program:…)` above takes the generator's `Program`, which is
// what Stream B holds AT BUILD TIME. The repository does not: a block is
// persisted as a `program_enrollments` row plus the template it names, and
// re-running `ProgramGenerator.generate` months later — against a changed
// catalog, a changed profile and a changed titration — would be a SECOND
// OPINION about a block that already happened. So the read-out has a second
// door, onto facts the block actually stored.
//
// `ProgramTemplate.bySlug` resolves BOTH the bundled templates and a
// Coach-generated block (`ProgramTemplate`'s own extension rebuilds the latter
// from its persisted rows), so this door covers every enrollment.
extension LadderReadout {

    /// The deload weeks the template records, 0-based.
    ///
    /// `taperWeeks` is empty here, and that is honest rather than lazy:
    /// `ProgramWeek` carries `isDeload` and nothing else about volume, so a
    /// taper is not a fact this door can see. The ramps only need the deload.
    static func constraints(template: ProgramTemplate?,
                            unit: WeightUnit) -> LadderConstraints {
        var deloads: Set<Int> = []
        for (index, week) in (template?.weeks ?? []).enumerated() where week.isDeload {
            deloads.insert(index)
        }
        return LadderConstraints(deloadWeeks: deloads, taperWeeks: [], unit: unit)
    }

    /// The block's own decision-log line for a week, keyed 0-based — spec §6's
    /// "so the ladder says why a week is what it is".
    static func notesByWeek(template: ProgramTemplate?) -> [Int: String] {
        var out: [Int: String] = [:]
        for (index, week) in (template?.weeks ?? []).enumerated() {
            if let note = week.note, !note.isEmpty { out[index] = note }
        }
        return out
    }

    /// Strength rungs from the template's OWN percent-of-baseline weeks, through
    /// `ProgramMath.targetWeight` — THE SAME FUNCTION THE PROGRAM CARD PRINTS,
    /// so the ladder and the card cannot show one week two loads.
    ///
    /// nil for a volume-driven block (no week carries a percent) and for no
    /// baseline: a ladder that invented a load would print a number nobody
    /// prescribed, which is the same refusal `strengthRungs(program:…)` makes
    /// for a main with no `percentOfMax`.
    static func strengthRungs(template: ProgramTemplate?, exerciseID: UUID,
                              baselineE1RMLbs: Decimal) -> [GoalTarget]? {
        guard let weeks = template?.weeks, !weeks.isEmpty, baselineE1RMLbs > 0,
              weeks.contains(where: { $0.percentOfBaseline != nil }) else { return nil }
        var previous: Decimal?
        return weeks.map { week in
            var target = GoalTarget(exerciseID: exerciseID)
            if let percent = week.percentOfBaseline,
               let pounds = ProgramMath.targetWeight(percentOfBaseline: percent,
                                                     baseline: baselineE1RMLbs) {
                previous = Decimal(pounds)
            }
            // A TEST WEEK CARRIES NO PERCENT (`march-to-1rm`'s week 8, "work up
            // to a new heavy single"). It holds the last prescribed load rather
            // than printing nothing, because the week IS "at least this".
            target.targetWeightLbs = previous
            target.targetReps = week.reps
            return target
        }
    }
}
