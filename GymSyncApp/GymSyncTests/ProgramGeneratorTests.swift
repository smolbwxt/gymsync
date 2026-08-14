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

    // MARK: - percentFor table

    func testPercentForAnchors() {
        XCTAssertEqual(GeneratorScience.percentFor(reps: 8), 80)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 4), 90)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 16), 60)
        XCTAssertEqual(GeneratorScience.percentFor(reps: 2), 90, "below table floor clamps heavy")
        XCTAssertEqual(GeneratorScience.percentFor(reps: 20), 60, "above table ceiling clamps light")
    }
}
