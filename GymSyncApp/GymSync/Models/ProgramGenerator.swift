import Foundation

// MARK: - ProgramGenerator
//
// The COACH pipeline, pure and deterministic: same inputs + same catalog
// = the same program, byte for byte (ties break on stable catalog rank,
// never randomness — what makes the golden tests meaningful and a
// regenerated preview trustworthy). Every exercise in the output can
// answer "which slot, which rule, which budget line put you here."
//
// Science lives in GeneratorScience (evidence-cited constants); this
// file is the machinery: split → budget → slots → selection → wave.
enum ProgramGenerator {

    // MARK: Inputs

    struct Inputs {
        var focus: GeneratorScience.Focus
        var daysPerWeek: Int
        var durationWeeks: Int
        var experience: GeneratorScience.Experience
        var sex: GeneratorScience.Sex = .unspecified
        /// nil = ALL muscle groups (the owner's "hit all and don't think
        /// about it again"); otherwise the focus muscles.
        var focusMuscles: Set<String>? = nil
        /// Equipment classes available; nil = everything.
        var equipment: Set<String>? = nil
        /// Dedicated cardio days appended after the lifting split
        /// (owner 2026-08-14) — prescribed as zone + MINUTES.
        var cardioDays: Int = 0
        var cardioMinutes: Int = 30
    }

    struct CatalogExercise {
        let id: UUID
        let name: String
        let primaryMuscle: String
        let secondaryMuscles: [String]
        let category: String        // compound | isolation | ...
        let equipment: String
        let movementPattern: String // squat|hinge|lunge|push_horizontal|push_vertical|pull_horizontal|pull_vertical|isolation|other
        /// Stable order (catalog fetch order) — the deterministic tiebreak.
        let rank: Int
    }

    // MARK: Output

    struct Exercise: Equatable {
        let exerciseID: UUID
        let name: String
        var sets: Int
        var repsLow: Int
        var repsHigh: Int
        var restSeconds: Int
        var percentOfMax: Double?
        var isMain: Bool
        /// The slot that placed this exercise — carried so a reroll can
        /// re-run the SAME selection with the current pick excluded
        /// (deterministic next-best, never a shuffle).
        var slot: Slot? = nil
        /// Cardio prescriptions: zone + MINUTES instead of sets × reps.
        var cardioZone: Int? = nil
        var cardioMinutes: Int? = nil
    }

    struct Day: Equatable {
        let name: String
        var exercises: [Exercise]
    }

    struct Week: Equatable {
        let number: Int
        var volumeMultiplier: Double
        var intensityMultiplier: Double
        var isDeload: Bool
        var note: String?
    }

    struct Program: Equatable {
        var days: [Day]
        var weeks: [Week]
        var notes: [String]
    }

    // MARK: Pipeline

    static func generate(inputs: Inputs, catalog: [CatalogExercise]) -> Program {
        let band = GeneratorScience.band(for: inputs.focus)
        let split = GeneratorScience.split(daysPerWeek: inputs.daysPerWeek, focus: inputs.focus)
        let usable = catalog.filter { ex in
            inputs.equipment.map { $0.contains(ex.equipment) } ?? true
        }

        var notes: [String] = []

        // Weekly per-muscle set budget: focus band (beginner override),
        // sex ceiling nudge (soft, top only).
        let weekly: (low: Int, high: Int)
        if inputs.experience == .new {
            weekly = GeneratorScience.beginnerWeeklySets
        } else {
            let ceiling = Double(band.weeklySetsHigh)
                * GeneratorScience.weeklyVolumeCeilingMultiplier(sex: inputs.sex)
            weekly = (band.weeklySetsLow, Int(ceiling.rounded()))
        }
        let targetWeeklySets = (weekly.low + weekly.high) / 2

        // Days: fill each day's slot template, spending the weekly budget
        // across the split (rule 7: never all of a muscle's volume in one
        // session).
        let perDayBudget = max(2, targetWeeklySets / max(1, muscleFrequency(split: split)))

        var days: [Day] = []
        for (index, kind) in split.enumerated() {
            let name = dayName(kind: kind, index: index, split: split)
            var chosen: [Exercise] = []
            var alreadyChosen = Set<UUID>()
            for slot in slots(for: kind) {
                guard let pick = select(slot: slot, from: usable,
                                        excluding: alreadyChosen,
                                        focus: inputs.focus,
                                        focusMuscles: inputs.focusMuscles) else { continue }
                alreadyChosen.insert(pick.id)
                chosen.append(prescription(for: pick, slot: slot, band: band,
                                           inputs: inputs, setsPerExercise: setsPerSlot(slot: slot, perDayBudget: perDayBudget)))
            }
            days.append(Day(name: name, exercises: chosen))
        }

        // Dedicated cardio days (owner 2026-08-14): zone + MINUTES.
        // Conditioning prescribes intervals (zone 4); everything else
        // steady zone 2. Modality = first catalog cardio entry by rank
        // (deterministic), equipment-filtered like everything else.
        if inputs.cardioDays > 0 {
            let modality = usable.first { $0.category == "cardio" }
                ?? catalog.first { $0.category == "cardio" }
            if let modality {
                let zone = inputs.focus == .conditioning ? 4 : 2
                for n in 1...inputs.cardioDays {
                    let label = inputs.cardioDays > 1 ? "Cardio \(n)" : "Cardio"
                    days.append(Day(name: label, exercises: [
                        Exercise(exerciseID: modality.id, name: modality.name,
                                 sets: 1, repsLow: 0, repsHigh: 0,
                                 restSeconds: 0, percentOfMax: nil, isMain: false,
                                 slot: nil,
                                 cardioZone: zone,
                                 cardioMinutes: inputs.cardioMinutes),
                    ]))
                }
            }
        }

        // Wave: flat for 4 weeks (double progression carries it), ramp
        // with a ¾-mark deload for 8/12 (offered, never forced), and a
        // final-week taper look on strength (volume −50%, intensity held —
        // the peaking research).
        var weeks: [Week] = []
        let deloadWeek = inputs.durationWeeks >= 8
            ? Int((Double(inputs.durationWeeks) * 0.75).rounded()) : nil
        for n in 1...max(1, inputs.durationWeeks) {
            if n == deloadWeek {
                weeks.append(Week(number: n,
                                  volumeMultiplier: GeneratorScience.deloadVolumeMultiplier,
                                  intensityMultiplier: GeneratorScience.deloadIntensityMultiplier,
                                  isDeload: true,
                                  note: "Deload — move fast, leave fresh."))
            } else {
                let progress = Double(n - 1) / Double(max(1, inputs.durationWeeks - 1))
                weeks.append(Week(number: n,
                                  volumeMultiplier: 1.0,
                                  intensityMultiplier: 1.0 + progress * 0.05,
                                  isDeload: false,
                                  note: nil))
            }
        }
        if inputs.focus == .strength, inputs.durationWeeks >= 8, var last = weeks.last {
            last.volumeMultiplier = GeneratorScience.taperVolumeMultiplier
            last.note = "Peak week — half the volume, keep the bar heavy."
            weeks[weeks.count - 1] = last
        }

        if inputs.sex == .female {
            notes.append("Rep tops on accessory work sit one higher and accessory rests 15s shorter — women are measurably more fatigue-resistant at submaximal loads (Hunter 2014; Hoeger 1990). Zones, movements, and progression are identical by design (Roberts et al. 2020).")
        }
        if inputs.experience == .new {
            notes.append("Beginner volume (6–10 weekly sets per muscle) grows you just as fast — extra sets are cost without benefit in year one (Schoenfeld 2018).")
        }

        return Program(days: days, weeks: weeks, notes: notes)
    }

    // MARK: Slots (day templates — methodology doc)

    enum Slot: Equatable {
        case pattern(String, main: Bool)
        case isolation(String)      // primary muscle
    }

    static func slots(for kind: GeneratorScience.DayKind) -> [Slot] {
        switch kind {
        case .fullBody:
            return [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("push_horizontal", main: true), .pattern("pull_horizontal", main: true),
                    .isolation("shoulders"), .isolation("core")]
        case .upper:
            return [.pattern("push_horizontal", main: true), .pattern("pull_horizontal", main: true),
                    .pattern("push_vertical", main: false), .pattern("pull_vertical", main: false),
                    .isolation("biceps"), .isolation("triceps")]
        case .lower:
            return [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("lunge", main: false),
                    .isolation("hamstrings"), .isolation("calves")]
        case .push:
            return [.pattern("push_horizontal", main: true), .pattern("push_vertical", main: false),
                    .isolation("shoulders"), .isolation("triceps"), .isolation("chest")]
        case .pull:
            return [.pattern("pull_horizontal", main: true), .pattern("pull_vertical", main: false),
                    .isolation("shoulders"), .isolation("biceps"), .isolation("back")]
        case .legs:
            return [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("lunge", main: false),
                    .isolation("hamstrings"), .isolation("quads"), .isolation("calves")]
        }
    }

    // MARK: Selection (the 8 rules, deterministic)

    static func select(slot: Slot, from catalog: [CatalogExercise],
                       excluding: Set<UUID>,
                       focus: GeneratorScience.Focus,
                       focusMuscles: Set<String>?) -> CatalogExercise? {
        let candidates: [CatalogExercise]
        switch slot {
        case .pattern(let pattern, _):
            candidates = catalog.filter { $0.movementPattern == pattern && !excluding.contains($0.id) }
        case .isolation(let muscle):
            candidates = catalog.filter {
                $0.primaryMuscle == muscle && $0.category == "isolation" && !excluding.contains($0.id)
            }
        }
        guard !candidates.isEmpty else { return nil }
        // Rule 2 + 6: FOCUS-AWARE equipment ladder for mains (barbell-first
        // strength/hypertrophy, machine-first weight-loss/conditioning);
        // rule 8: rank tiebreak (stable order).
        let ladder = GeneratorScience.mainEquipmentLadder(focus: focus)
        let isMain: Bool
        if case .pattern(_, let main) = slot { isMain = main } else { isMain = false }
        return candidates.min { a, b in
            // Focus muscles first when a selection exists.
            if let focus = focusMuscles {
                let aFocus = focus.contains(a.primaryMuscle), bFocus = focus.contains(b.primaryMuscle)
                if aFocus != bFocus { return aFocus }
            }
            if isMain {
                let aLad = ladder[a.equipment] ?? 5, bLad = ladder[b.equipment] ?? 5
                if aLad != bLad { return aLad < bLad }
            } else {
                // Rule 5: accessories favor machine/cable (low systemic
                // fatigue, safe near failure).
                let inverse = ["machine": 0, "cable": 0, "dumbbell": 1, "bodyweight": 2, "barbell": 3]
                let aLad = inverse[a.equipment] ?? 4, bLad = inverse[b.equipment] ?? 4
                if aLad != bLad { return aLad < bLad }
            }
            return a.rank < b.rank
        }
    }

    // MARK: Prescription

    static func prescription(for ex: CatalogExercise, slot: Slot,
                             band: GeneratorScience.FocusBand,
                             inputs: Inputs, setsPerExercise: Int) -> Exercise {
        let isMain: Bool
        if case .pattern(_, let main) = slot { isMain = main } else { isMain = false }
        let repsLow = isMain ? band.mainRepsLow : band.accessoryRepsLow
        var repsHigh = isMain ? band.mainRepsHigh : band.accessoryRepsHigh
        repsHigh += GeneratorScience.repRangeTopBonus(sex: inputs.sex, repsHigh: repsHigh)
        var rest = isMain ? band.mainRestSeconds : band.accessoryRestSeconds
        if !isMain { rest = max(30, rest + GeneratorScience.accessoryRestDelta(sex: inputs.sex)) }
        // %1RM from the rep target's midpoint (reps-at-% table) — mains
        // only; accessories run double progression without a % anchor.
        let percent = isMain
            ? GeneratorScience.percentFor(reps: (repsLow + repsHigh) / 2) : nil
        return Exercise(exerciseID: ex.id, name: ex.name,
                        sets: setsPerExercise,
                        repsLow: repsLow, repsHigh: repsHigh,
                        restSeconds: rest,
                        percentOfMax: percent,
                        isMain: isMain,
                        slot: slot)
    }

    // MARK: Reroll (owner 2026-08-14: "allow people to reroll accessories
    // if they have an objection")
    //
    // Deterministic next-best, never a shuffle: the SAME slot selection
    // re-runs with everything already in the day PLUS the rejected pick
    // excluded — reroll twice and you walk the ranked candidate list.
    static func reroll(_ exercise: Exercise, in day: Day,
                       inputs: Inputs, catalog: [CatalogExercise]) -> Exercise? {
        guard let slot = exercise.slot else { return nil }
        let usable = catalog.filter { ex in
            inputs.equipment.map { $0.contains(ex.equipment) } ?? true
        }
        var excluded = Set(day.exercises.map(\.exerciseID))
        excluded.insert(exercise.exerciseID)
        guard let next = select(slot: slot, from: usable, excluding: excluded,
                                focus: inputs.focus,
                                focusMuscles: inputs.focusMuscles) else { return nil }
        var replacement = prescription(for: next, slot: slot,
                                       band: GeneratorScience.band(for: inputs.focus),
                                       inputs: inputs,
                                       setsPerExercise: exercise.sets)
        replacement.sets = exercise.sets
        return replacement
    }

    // MARK: Helpers

    private static func setsPerSlot(slot: Slot, perDayBudget: Int) -> Int {
        if case .pattern(_, true) = slot { return max(3, min(5, perDayBudget)) }
        return max(2, min(4, perDayBudget - 1))
    }

    private static func muscleFrequency(split: [GeneratorScience.DayKind]) -> Int {
        // How many times per week the split touches a typical muscle —
        // full-body = every day; UL/PPL = half the days.
        let fullBody = split.filter { $0 == .fullBody }.count
        if fullBody > 0 { return fullBody }
        return max(1, split.count / 2)
    }

    private static func dayName(kind: GeneratorScience.DayKind, index: Int,
                                split: [GeneratorScience.DayKind]) -> String {
        let sameKind = split.enumerated().filter { $0.element == kind }
        let ordinal = (sameKind.firstIndex { $0.offset == index } ?? 0) + 1
        let base: String
        switch kind {
        case .fullBody: base = "Full Body"
        case .upper: base = "Upper"
        case .lower: base = "Lower"
        case .push: base = "Push"
        case .pull: base = "Pull"
        case .legs: base = "Legs"
        }
        return sameKind.count > 1 ? "\(base) \(ordinal)" : base
    }
}
