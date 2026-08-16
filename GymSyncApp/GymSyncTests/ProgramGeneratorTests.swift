import XCTest
@testable import GymSync

/// The COACH pipeline's contract, pinned: determinism, the frequency law,
/// sex-as-physiology (never selection), beginner volume, and the wave.
final class ProgramGeneratorTests: XCTestCase {

    // Small synthetic catalog — one exercise per pattern + isolations,
    // stable ranks (the deterministic tiebreak).
    private func catalog() -> [ProgramGenerator.CatalogExercise] {
        func ex(_ rank: Int, _ name: String, _ muscle: String, _ cat: String,
                _ equip: String, _ pattern: String) -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
                name: name, primaryMuscle: muscle, secondaryMuscles: [],
                category: cat, equipment: equip, movementPattern: pattern, rank: rank)
        }
        return [
            ex(1, "Back Squat", "quads", "compound", "barbell", "squat"),
            ex(2, "Leg Press", "quads", "compound", "machine", "squat"),
            ex(3, "Deadlift", "hamstrings", "compound", "barbell", "hinge"),
            ex(4, "Bench Press", "chest", "compound", "barbell", "push_horizontal"),
            ex(5, "Overhead Press", "shoulders", "compound", "barbell", "push_vertical"),
            ex(6, "Barbell Row", "back", "compound", "barbell", "pull_horizontal"),
            ex(7, "Lat Pulldown", "lats", "compound", "machine", "pull_vertical"),
            ex(8, "Walking Lunge", "quads", "compound", "bodyweight", "lunge"),
            ex(9, "Leg Curl", "hamstrings", "isolation", "machine", "isolation"),
            ex(10, "Calf Raise", "calves", "isolation", "machine", "isolation"),
            ex(11, "Lateral Raise", "shoulders", "isolation", "dumbbell", "isolation"),
            ex(12, "Biceps Curl", "biceps", "isolation", "dumbbell", "isolation"),
            ex(13, "Triceps Pushdown", "triceps", "isolation", "cable", "isolation"),
            ex(14, "Cable Crunch", "core", "isolation", "cable", "isolation"),
            ex(15, "Machine Fly", "chest", "isolation", "machine", "isolation"),
            ex(16, "Back Extension", "lower_back", "isolation", "bodyweight", "isolation"),
        ]
    }

    private func inputs(focus: GeneratorScience.Focus = .hypertrophy,
                        days: Int = 3, weeks: Int = 8,
                        experience: GeneratorScience.Experience = .intermediate,
                        sex: GeneratorScience.Sex = .unspecified) -> ProgramGenerator.Inputs {
        ProgramGenerator.Inputs(focus: focus, daysPerWeek: days,
                                durationWeeks: weeks, experience: experience, sex: sex)
    }

    func testDeterminism() {
        let a = ProgramGenerator.generate(inputs: inputs(), catalog: catalog())
        let b = ProgramGenerator.generate(inputs: inputs(), catalog: catalog())
        XCTAssertEqual(a, b, "same inputs + same catalog must be byte-identical")
    }

    func testThreeDaysIsFullBodyNotPPL() {
        // The frequency law: 3-day PPL trains each muscle once — banned.
        let program = ProgramGenerator.generate(inputs: inputs(days: 3), catalog: catalog())
        XCTAssertEqual(program.days.map(\.name), ["Full Body 1", "Full Body 2", "Full Body 3"])
    }

    func testSixDaysIsPPLTimesTwo() {
        let program = ProgramGenerator.generate(inputs: inputs(days: 6), catalog: catalog())
        XCTAssertEqual(program.days.count, 6)
        XCTAssertTrue(program.days[0].name.hasPrefix("Push"))
        XCTAssertTrue(program.days[5].name.hasPrefix("Legs"))
    }

    func testSexNeverChangesExerciseSelection() {
        // The strong do-not-change finding (Roberts et al. 2020): identical
        // movements, identical zones — physiology deltas only.
        let male = ProgramGenerator.generate(inputs: inputs(sex: .male), catalog: catalog())
        let female = ProgramGenerator.generate(inputs: inputs(sex: .female), catalog: catalog())
        XCTAssertEqual(male.days.map { $0.exercises.map(\.exerciseID) },
                       female.days.map { $0.exercises.map(\.exerciseID) })
    }

    func testFemaleAccessoryPhysiologyDeltas() {
        let male = ProgramGenerator.generate(inputs: inputs(sex: .male), catalog: catalog())
        let female = ProgramGenerator.generate(inputs: inputs(sex: .female), catalog: catalog())
        let maleAcc = male.days[0].exercises.first { !$0.isMain }!
        let femaleAcc = female.days[0].exercises.first { !$0.isMain }!
        XCTAssertEqual(femaleAcc.restSeconds, maleAcc.restSeconds - 15,
                       "accessory rests run 15s shorter (Hunter fatigue resistance)")
        XCTAssertEqual(femaleAcc.repsHigh, maleAcc.repsHigh + 1,
                       "high-rep tops sit one higher (Hoeger reps-at-%1RM)")
        // Main STRENGTH-zone work: untouched.
        let maleMain = male.days[0].exercises.first { $0.isMain }!
        let femaleMain = female.days[0].exercises.first { $0.isMain }!
        XCTAssertEqual(maleMain.percentOfMax, femaleMain.percentOfMax,
                       "%1RM zones identical by sex (strong finding)")
    }

    func testBeginnerVolumeOverride() {
        // Beginners: 6-10 weekly sets/muscle regardless of focus — the
        // per-day budget lands visibly below intermediate.
        let beginner = ProgramGenerator.generate(
            inputs: inputs(experience: .new), catalog: catalog())
        let intermediate = ProgramGenerator.generate(
            inputs: inputs(experience: .intermediate), catalog: catalog())
        let beginnerSets = beginner.days[0].exercises.reduce(0) { $0 + $1.sets }
        let intermediateSets = intermediate.days[0].exercises.reduce(0) { $0 + $1.sets }
        XCTAssertLessThan(beginnerSets, intermediateSets)
    }

    func testDeloadLandsAtThreeQuarterMark() {
        let program = ProgramGenerator.generate(inputs: inputs(weeks: 8), catalog: catalog())
        XCTAssertTrue(program.weeks[5].isDeload, "week 6 of 8 = the ¾ mark")
        XCTAssertEqual(program.weeks[5].volumeMultiplier, 0.5)
        XCTAssertFalse(program.weeks[4].isDeload)
    }

    func testStrengthFinalWeekPeaks() {
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, weeks: 8), catalog: catalog())
        let last = program.weeks.last!
        XCTAssertEqual(last.volumeMultiplier, 0.5, "taper: half volume, bar stays heavy")
        XCTAssertGreaterThanOrEqual(last.intensityMultiplier, 1.0)
    }

    func testFourWeekPlansHaveNoDeload() {
        let program = ProgramGenerator.generate(inputs: inputs(weeks: 4), catalog: catalog())
        XCTAssertFalse(program.weeks.contains(where: \.isDeload))
    }

    func testMainsPreferBarbellAccessoriesPreferMachines() {
        let program = ProgramGenerator.generate(inputs: inputs(days: 4), catalog: catalog())
        let upper = program.days[0]
        XCTAssertEqual(upper.exercises.first?.name, "Bench Press",
                       "main slot takes the barbell (specificity, loadability)")
        // Chest isolation exists as machine fly — accessory rule prefers it
        // over any barbell option for the same slot.
        let push = ProgramGenerator.generate(inputs: inputs(days: 6), catalog: catalog()).days[0]
        XCTAssertTrue(push.exercises.contains { $0.name == "Machine Fly" })
    }

    // MARK: - Focus-aware splits + equipment (owner 2026-08-14: "no
    // matter what options I pick, it always generates the same split")

    func testWeightLossIsFullBodyAtAnyDayCount() {
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .weightLoss, days: 4), catalog: catalog())
        XCTAssertEqual(program.days.count, 4)
        XCTAssertTrue(program.days.allSatisfy { $0.name.hasPrefix("Full Body") },
                      "weight loss trains full-body density, not bodypart splits")
    }

    func testConditioningMainsPreferMachines() {
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .conditioning, days: 2), catalog: catalog())
        let firstMain = program.days[0].exercises.first { $0.isMain }!
        XCTAssertEqual(firstMain.name, "Leg Press",
                       "conditioning runs machine-first mains — circuit-safe")
    }

    func testFocusVisiblyChangesSelection() {
        let strength = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 3), catalog: catalog())
        let conditioning = ProgramGenerator.generate(
            inputs: inputs(focus: .conditioning, days: 3), catalog: catalog())
        XCTAssertNotEqual(strength.days.map { $0.exercises.map(\.exerciseID) },
                          conditioning.days.map { $0.exercises.map(\.exerciseID) })
    }

    func testEquipmentFilterExcludesMissingClasses() {
        var noBarbell = inputs(focus: .strength, days: 3)
        noBarbell.equipment = ["machine", "dumbbell", "cable", "bodyweight"]
        let program = ProgramGenerator.generate(inputs: noBarbell, catalog: catalog())
        let allExercises = program.days.flatMap(\.exercises).map(\.name)
        XCTAssertFalse(allExercises.contains("Back Squat"),
                       "a gym without a barbell never gets barbell work")
        XCTAssertTrue(allExercises.contains("Leg Press"),
                      "the squat slot falls back down the equipment ladder")
    }

    // MARK: - Day range, cardio, reroll (owner 2026-08-14)

    func testOneAndSevenDaySplits() {
        let one = ProgramGenerator.generate(inputs: inputs(days: 1), catalog: catalog())
        XCTAssertEqual(one.days.count, 1)
        XCTAssertEqual(one.days[0].name, "Full Body")
        // Recovery ceiling (Meeusen 2013 consensus): a 7-day request gets
        // SIX hard days — day 7 converts to active recovery.
        let seven = ProgramGenerator.generate(inputs: inputs(days: 7), catalog: catalog())
        XCTAssertEqual(seven.days.count, 7)
        XCTAssertEqual(seven.days.last?.name, "Active Recovery")
        XCTAssertFalse(seven.days.last!.exercises.contains { $0.isMain })
        XCTAssertTrue(seven.notes.contains { $0.contains("Six hard days") })
    }

    func testCardioDaysAppendZoneAndMinutes() {
        var withCardio = inputs(focus: .weightLoss, days: 3)
        withCardio.cardioDays = 2
        withCardio.cardioMinutes = 30
        var cardioCatalog = catalog()
        cardioCatalog.append(ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "Cycling", primaryMuscle: "quads", secondaryMuscles: [],
            category: "cardio", equipment: "machine", movementPattern: "other", rank: 99))
        let program = ProgramGenerator.generate(inputs: withCardio, catalog: cardioCatalog)
        XCTAssertEqual(program.days.count, 5, "3 lifting + 2 cardio")
        let cardio = program.days.last!.exercises.first!
        XCTAssertEqual(cardio.cardioZone, 2, "steady zone 2 outside conditioning")
        XCTAssertEqual(cardio.cardioMinutes, 30)
    }

    func testConditioningCardioIsZoneFour() {
        var conditioning = inputs(focus: .conditioning, days: 2)
        conditioning.cardioDays = 1
        var cardioCatalog = catalog()
        cardioCatalog.append(ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "Cycling", primaryMuscle: "quads", secondaryMuscles: [],
            category: "cardio", equipment: "machine", movementPattern: "other", rank: 99))
        let program = ProgramGenerator.generate(inputs: conditioning, catalog: cardioCatalog)
        XCTAssertEqual(program.days.last?.exercises.first?.cardioZone, 4,
                       "conditioning cardio prescribes intervals")
    }

    func testRerollWalksTheRankedListDeterministically() {
        let program = ProgramGenerator.generate(inputs: inputs(days: 3), catalog: catalog())
        let day = program.days[0]
        let original = day.exercises[0]           // squat slot: Back Squat
        let rerolled = ProgramGenerator.reroll(original, in: day,
                                               inputs: inputs(days: 3), catalog: catalog())
        XCTAssertEqual(rerolled?.name, "Leg Press",
                       "next-best down the same slot's ranked list — never a shuffle")
        XCTAssertEqual(rerolled?.sets, original.sets, "prescription volume carries over")
        // Deterministic: same reroll twice = same answer.
        let again = ProgramGenerator.reroll(original, in: day,
                                            inputs: inputs(days: 3), catalog: catalog())
        XCTAssertEqual(rerolled?.exerciseID, again?.exerciseID)
    }

    // MARK: - Two-a-days + active recovery (owner 2026-08-14)

    private func cardioCatalog() -> [ProgramGenerator.CatalogExercise] {
        var list = catalog()
        list.append(ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000098")!,
            name: "Walking", primaryMuscle: "quads", secondaryMuscles: [],
            category: "cardio", equipment: "bodyweight", movementPattern: "other", rank: 98))
        list.append(ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000097")!,
            name: "Hamstring Stretch", primaryMuscle: "hamstrings", secondaryMuscles: [],
            category: "mobility", equipment: "bodyweight", movementPattern: "other", rank: 97))
        return list
    }

    func testOverflowCardioPairsAsTwoADays() {
        // 5 lifting + 4 cardio = 9 sessions in 7 days: 2 lifting days
        // carry PM cardio; 2 cardio days stand alone. Calendar total = 7.
        var inputs = inputs(days: 5)
        inputs.cardioDays = 4
        let program = ProgramGenerator.generate(inputs: inputs, catalog: cardioCatalog())
        XCTAssertEqual(program.days.count, 7)
        let pmDays = program.days.filter { $0.name.contains("PM Cardio") }
        XCTAssertEqual(pmDays.count, 2)
        XCTAssertTrue(pmDays.allSatisfy { $0.exercises.last?.cardioZone != nil })
        XCTAssertTrue(program.notes.contains { $0.contains("6+ hours") })
    }

    func testFillWeekAddsActiveRecovery() {
        var inputs = inputs(days: 3)
        inputs.fillWeekWithRecovery = true
        let program = ProgramGenerator.generate(inputs: inputs, catalog: cardioCatalog())
        XCTAssertEqual(program.days.count, 7, "3 lifting + 4 active recovery")
        let recovery = program.days.filter { $0.name.hasPrefix("Active Recovery") }
        XCTAssertEqual(recovery.count, 4)
        // A recovery day prescribes mobility + a zone-1 walk — never lifting.
        let day = recovery[0]
        XCTAssertTrue(day.exercises.contains { $0.name == "Hamstring Stretch" })
        XCTAssertTrue(day.exercises.contains { $0.cardioZone == 1 })
        XCTAssertFalse(day.exercises.contains { $0.isMain })
    }

    // MARK: - percentFor table

    func testPercentForAnchors() {
        XCTAssertEqual(GeneratorScience.percentFor(reps: 8), 80)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 4), 90)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 16), 60)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 2), 90, "below table floor clamps heavy")
        XCTAssertEqual(GeneratorScience.percentFor(reps: 20), 60, "above table ceiling clamps light")
    }

    // MARK: - Focus differentiation + variety + duration (owner 2026-08-15)

    /// catalog() plus a second option for two accessory slots — the pool
    /// cross-day rotation and the seed need room to move in.
    private func variedCatalog() -> [ProgramGenerator.CatalogExercise] {
        func ex(_ rank: Int, _ name: String, _ muscle: String,
                _ equip: String) -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
                name: name, primaryMuscle: muscle, secondaryMuscles: [],
                category: "isolation", equipment: equip,
                movementPattern: "isolation", rank: rank)
        }
        return catalog() + [
            ex(17, "Cable Lateral Raise", "shoulders", "cable"),
            ex(18, "Rope Crunch", "core", "cable"),
        ]
    }

    func testStrengthAndHypertrophyDifferInStructure() {
        let strength = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 4), catalog: catalog())
        let hyper = ProgramGenerator.generate(
            inputs: inputs(focus: .hypertrophy, days: 4), catalog: catalog())
        XCTAssertNotEqual(strength.days.map { $0.exercises.map(\.exerciseID) },
                          hyper.days.map { $0.exercises.map(\.exerciseID) },
                          "strength and hypertrophy are different programs now")
        XCTAssertLessThan(strength.days[0].exercises.count,
                          hyper.days[0].exercises.count,
                          "strength spends its budget on the bar - fewer accessories")
    }

    func testWeightLossAndConditioningDiffer() {
        let wl = ProgramGenerator.generate(
            inputs: inputs(focus: .weightLoss, days: 3), catalog: catalog())
        let cond = ProgramGenerator.generate(
            inputs: inputs(focus: .conditioning, days: 3), catalog: catalog())
        XCTAssertNotEqual(wl.days.map { $0.exercises.map(\.exerciseID) },
                          cond.days.map { $0.exercises.map(\.exerciseID) },
                          "weight loss trains density; conditioning holds a maintenance floor")
    }

    func testFullBodyDaysVaryAccessoriesAcrossTheWeek() {
        let program = ProgramGenerator.generate(inputs: inputs(days: 3), catalog: variedCatalog())
        let fb1 = program.days[0], fb2 = program.days[1]
        XCTAssertEqual(fb1.exercises.filter(\.isMain).map(\.exerciseID),
                       fb2.exercises.filter(\.isMain).map(\.exerciseID),
                       "mains repeat - the frequency law wants the lifts practiced")
        XCTAssertNotEqual(fb1.exercises.filter { !$0.isMain }.map(\.exerciseID),
                          fb2.exercises.filter { !$0.isMain }.map(\.exerciseID),
                          "accessories rotate across the week - no more identical days")
    }

    func testSeedShufflesWithinEquivalenceDeterministically() {
        let base = ProgramGenerator.generate(inputs: inputs(), catalog: variedCatalog())
        var shuffled = inputs()
        shuffled.seed = 1
        let b = ProgramGenerator.generate(inputs: shuffled, catalog: variedCatalog())
        XCTAssertNotEqual(base.days.map { $0.exercises.map(\.exerciseID) },
                          b.days.map { $0.exercises.map(\.exerciseID) },
                          "the seed rotates equivalent picks")
        let b2 = ProgramGenerator.generate(inputs: shuffled, catalog: variedCatalog())
        XCTAssertEqual(b.days.map { $0.exercises.map(\.exerciseID) },
                       b2.days.map { $0.exercises.map(\.exerciseID) },
                       "same seed = same program, byte for byte")
    }

    func testSessionMinutesTrimsAccessoriesNeverMains() {
        var capped = inputs(days: 4)
        capped.sessionMinutes = 45
        let program = ProgramGenerator.generate(inputs: capped, catalog: catalog())
        let uncapped = ProgramGenerator.generate(inputs: inputs(days: 4), catalog: catalog())
        XCTAssertLessThan(program.days[0].exercises.count,
                          uncapped.days[0].exercises.count,
                          "the cap trims the day")
        XCTAssertEqual(program.days[0].exercises.filter(\.isMain).count,
                       uncapped.days[0].exercises.filter(\.isMain).count,
                       "mains are never trimmed for time")
        XCTAssertTrue(program.notes.contains { $0.contains("45-minute") })
    }

    // MARK: - Trainer-audit rules (2026-08-16: 162-program corpus,
    // 30 reviewers — every rule below traces to a repeated finding)

    func testNoviceIntensityCeiling() {
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 3, experience: .new), catalog: catalog())
        for day in program.days {
            for ex in day.exercises where ex.isMain {
                if let pct = ex.percentOfMax {
                    XCTAssertLessThanOrEqual(pct, 72.5,
                        "a new lifter is never opened near max (audit critical)")
                }
            }
        }
    }

    func testPercentSupportsTheRepRangeTop() {
        // The 90%-beside-6-reps contradiction: the anchor must carry the
        // whole displayed range per the app's own reps-at-percent table.
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 3), catalog: catalog())
        let main = program.days[0].exercises.first { $0.isMain }!
        XCTAssertEqual(main.percentOfMax, GeneratorScience.percentFor(reps: main.repsHigh),
                       "anchor = percentFor(range top), under the experience ceiling")
    }

    func testAxialStaggerWithinASession() {
        let cat = catalog().map { c -> ProgramGenerator.CatalogExercise in
            var c = c
            if c.name == "Back Squat" || c.name == "Deadlift" { c.spinalLoad = 2 }
            return c
        }
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 4), catalog: cat)
        let lower = program.days[1]
        let axials = lower.exercises.filter { $0.isMain }.compactMap { $0.percentOfMax }
        XCTAssertGreaterThanOrEqual(axials.count, 2)
        XCTAssertEqual(axials[1], axials[0] - 10,
                       "only one heavy-axial main keeps the session top anchor")
    }

    func testWeeklyHeavyLightWave() {
        // 7-day strength = PPL x2 + FB: a lift third top exposure of the
        // week drops ~10% (heavy/light waving, not daily maxing).
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .strength, days: 7), catalog: catalog())
        var byLift: [UUID: [Double]] = [:]
        for day in program.days {
            for ex in day.exercises where ex.isMain {
                if let pct = ex.percentOfMax { byLift[ex.exerciseID, default: []].append(pct) }
            }
        }
        let tripled = byLift.values.first { $0.count >= 3 }
        XCTAssertNotNil(tripled, "the 7-day split repeats some main 3x")
        if let reps = tripled {
            XCTAssertLessThan(reps[2], reps[0],
                              "the third weekly exposure waves lighter")
        }
    }

    func testConditioningAlwaysCarriesZoneWork() {
        // GOAL-FAILURE class: conditioning with cardioDays=0 shipped zero
        // zone work. Every conditioning lifting day now ends in a zone-4
        // finisher.
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .conditioning, days: 3), catalog: cardioCatalog())
        for day in program.days where day.exercises.contains(where: { $0.isMain }) {
            XCTAssertEqual(day.exercises.last?.cardioZone, 4,
                           "the zone work IS the conditioning goal")
        }
        XCTAssertTrue(program.notes.contains { $0.contains("zone-4") })
    }

    func testRepWindowClampsTheBand() {
        let cat = catalog().map { c -> ProgramGenerator.CatalogExercise in
            var c = c
            if c.name == "Deadlift" { c.repMin = 1; c.repMax = 8 }
            return c
        }
        // Weight-loss band is 8-15; a deadlift-like window caps it at 8.
        let program = ProgramGenerator.generate(
            inputs: inputs(focus: .weightLoss, days: 3), catalog: cat)
        let deadlift = program.days.flatMap { $0.exercises }.first { $0.name == "Deadlift" }
        XCTAssertNotNil(deadlift)
        XCTAssertLessThanOrEqual(deadlift?.repsHigh ?? 99, 8,
                                 "no 15-rep deadlifts — the label window clamps the band")
    }

    func testUnilateralMainDerates() {
        var only = ProgramGenerator.CatalogExercise(
            id: UUID(), name: "Bulgarian Split Squat", primaryMuscle: "quads",
            secondaryMuscles: [], category: "compound", equipment: "dumbbell",
            movementPattern: "squat", rank: 1)
        only.unilateral = true
        let picked = ProgramGenerator.prescription(
            for: only, slot: .pattern("squat", main: true),
            band: GeneratorScience.band(for: .strength),
            inputs: ProgramGenerator.Inputs(focus: .strength, daysPerWeek: 3,
                                            durationWeeks: 8, experience: .advanced),
            setsPerExercise: 4)
        XCTAssertLessThanOrEqual(picked.percentOfMax ?? 100, 80,
            "a balance-demanding substitute never inherits a bilateral near-max anchor")
    }

    func testComplexityGatesByExperienceNeverPenalizes() {
        var complexLift = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000000001")!,
            name: "Snatch-Grip Deadlift", primaryMuscle: "hamstrings",
            secondaryMuscles: [], category: "compound", equipment: "barbell",
            movementPattern: "hinge", rank: 1)
        complexLift.complexity = 5
        complexLift.focusScores = ["strength": 9]
        var simpleLift = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000000002")!,
            name: "Machine Hip Hinge", primaryMuscle: "hamstrings",
            secondaryMuscles: [], category: "compound", equipment: "machine",
            movementPattern: "hinge", rank: 2)
        simpleLift.complexity = 2
        simpleLift.focusScores = ["strength": 7]
        let pool = [complexLift, simpleLift]
        let newbie = ProgramGenerator.select(
            slot: .pattern("hinge", main: true), from: pool, excluding: [],
            focus: .strength, focusMuscles: nil, experience: .new)
        XCTAssertEqual(newbie?.name, "Machine Hip Hinge",
                       "complexity 5 sits behind the gate for a new lifter")
        let advanced = ProgramGenerator.select(
            slot: .pattern("hinge", main: true), from: pool, excluding: [],
            focus: .strength, focusMuscles: nil, experience: .advanced)
        XCTAssertEqual(advanced?.name, "Snatch-Grip Deadlift",
                       "complex + effective RISES for the advanced lifter (owner law)")
        let onlyComplex = ProgramGenerator.select(
            slot: .pattern("hinge", main: true), from: [complexLift], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .new)
        XCTAssertNotNil(onlyComplex, "the gate is soft — it never leaves a hole")
    }

    func testFocusScoresOutrankEquipmentLadder() {
        var scoredCable = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000000003")!,
            name: "Cable Pull-Through", primaryMuscle: "glutes",
            secondaryMuscles: [], category: "compound", equipment: "cable",
            movementPattern: "hinge", rank: 5)
        scoredCable.focusScores = ["strength": 9]
        var barbellLow = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000000004")!,
            name: "Barbell Odd Lift", primaryMuscle: "hamstrings",
            secondaryMuscles: [], category: "compound", equipment: "barbell",
            movementPattern: "hinge", rank: 1)
        barbellLow.focusScores = ["strength": 3]
        let picked = ProgramGenerator.select(
            slot: .pattern("hinge", main: true), from: [scoredCable, barbellLow],
            excluding: [], focus: .strength, focusMuscles: nil, experience: .advanced)
        XCTAssertEqual(picked?.name, "Cable Pull-Through",
                       "effectiveness score outranks the equipment ladder now")
    }

    // MARK: - Selection demotions (owner field report 2026-08-15)

    /// The exact bug: "Assisted Pull-Up Machine" is alphabetically first
    /// among machine vertical pulls, so the rank tiebreak (fetch order =
    /// alphabetical) prescribed a REGRESSION to an advanced lifter. The
    /// penalty must beat both the rank AND the equipment ladder.
    func testAssistedVariantsNeverBeatCleanCandidates() {
        func ex(_ rank: Int, _ name: String, _ equip: String) -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
                name: name, primaryMuscle: "lats", secondaryMuscles: [],
                category: "compound", equipment: equip,
                movementPattern: "pull_vertical", rank: rank)
        }
        // Alphabetical reality: assisted ranks FIRST, and it's even on the
        // preferred equipment tier (machine) while pulldown is cable.
        let verticalPulls = [
            ex(1, "Assisted Pull-Up Machine", "machine"),
            ex(2, "Behind The Neck Pulldown", "machine"),
            ex(9, "Lat Pulldown", "cable"),
        ]
        let picked = ProgramGenerator.select(
            slot: .pattern("pull_vertical", main: true),
            from: verticalPulls, excluding: [],
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertEqual(picked?.name, "Lat Pulldown",
                       "assisted/behind-the-neck variants must not be default prescriptions")
    }

    func testSelectionPenaltyClasses() {
        XCTAssertGreaterThanOrEqual(GeneratorScience.selectionPenalty(name: "Assisted Dip Machine"), 10_000)
        XCTAssertGreaterThanOrEqual(GeneratorScience.selectionPenalty(name: "Behind The Neck Pulldown"), 2_000)
        XCTAssertGreaterThanOrEqual(GeneratorScience.selectionPenalty(name: "45-Degree Leg Press"), 500)
        XCTAssertEqual(GeneratorScience.selectionPenalty(name: "Lat Pulldown"), 0)
        XCTAssertEqual(GeneratorScience.selectionPenalty(name: "Back Squat"), 0)
    }

    /// A slot ONLY an assisted variant can fill still fills — demotion is
    /// a preference, never a hole in the program.
    func testAssistedFillsSlotWhenNothingCleanExists() {
        let only = ProgramGenerator.CatalogExercise(
            id: UUID(), name: "Assisted Pull-Up Machine", primaryMuscle: "lats",
            secondaryMuscles: [], category: "compound", equipment: "machine",
            movementPattern: "pull_vertical", rank: 1)
        let picked = ProgramGenerator.select(
            slot: .pattern("pull_vertical", main: true),
            from: [only], excluding: [], focus: .strength, focusMuscles: nil)
        XCTAssertEqual(picked?.name, "Assisted Pull-Up Machine")
    }

    // MARK: - Data bridge (weekSummaries + jsonb contract)

    func testWeekSummariesCarryTheWave() {
        // 8-week plan: deload at the 3/4 mark, one row per week, sets
        // halved on the deload against the plain weeks around it.
        let program = ProgramGenerator.generate(inputs: inputs(weeks: 8), catalog: catalog())
        let rows = ProgramGenerator.weekSummaries(program)
        XCTAssertEqual(rows.count, 8)
        let deloadIndexes = rows.enumerated().filter { $0.element.isDeload }.map(\.offset)
        XCTAssertEqual(deloadIndexes.count, 1, "one deload week in an 8-week wave")
        let deload = rows[deloadIndexes[0]]
        let plain = rows[0]
        XCTAssertLessThan(deload.sets, plain.sets, "deload halves volume")
        XCTAssertNotNil(deload.note)
    }

    func testWeekSummariesAreDeterministic() {
        let a = ProgramGenerator.weekSummaries(
            ProgramGenerator.generate(inputs: inputs(), catalog: catalog()))
        let b = ProgramGenerator.weekSummaries(
            ProgramGenerator.generate(inputs: inputs(), catalog: catalog()))
        XCTAssertEqual(a, b)
    }

    func testProgramWeekJSONRoundTripUsesSnakeCase() throws {
        // The program_template_weeks.weeks jsonb contract: snake_case keys,
        // optionals absent when nil, is_deload always present.
        let week = ProgramWeek(percentOfBaseline: 82.5, sets: 4, reps: 5,
                               isDeload: true, note: "Deload")
        let data = try JSONEncoder().encode([week])
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"percent_of_baseline\""))
        XCTAssertTrue(json.contains("\"is_deload\""))
        let decoded = try JSONDecoder().decode([ProgramWeek].self, from: data)
        XCTAssertEqual(decoded, [week])

        // Volume-driven week: percent + note absent entirely.
        let volume = ProgramWeek(sets: 3, reps: 10)
        let volumeJSON = String(data: try JSONEncoder().encode(volume), encoding: .utf8) ?? ""
        XCTAssertFalse(volumeJSON.contains("percent_of_baseline"))
        let volumeBack = try JSONDecoder().decode(
            ProgramWeek.self, from: try JSONEncoder().encode(volume))
        XCTAssertEqual(volumeBack, volume)
    }
}
