import XCTest
@testable import GymSync

/// Set STRUCTURE the generator prescribes: supersets that are actually
/// trainable, and circuits that do not eat their own volume.
///
/// Both bugs here shared a shape — the prescription looked right on the
/// page and degraded silently in the live session, with nothing anywhere
/// reporting the difference. Found by audit 2026-08-26.
final class GeneratedStructureTests: XCTestCase {

    private func cat(_ n: Int, _ name: String, _ muscle: String,
                     _ category: String, _ pattern: String)
    -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(), name: name, primaryMuscle: muscle,
            secondaryMuscles: [], category: category, equipment: "barbell",
            movementPattern: pattern, rank: n)
    }

    private func entry(_ c: ProgramGenerator.CatalogExercise, main: Bool = false)
    -> ProgramGenerator.Exercise {
        ProgramGenerator.Exercise(exerciseID: c.id, name: c.name, sets: 3,
                                  repsLow: 8, repsHigh: 12, restSeconds: 90,
                                  percentOfMax: nil, isMain: main)
    }

    /// THE BUG: pairing marked a partner at an earlier index and never
    /// moved anything, so a pair could sit two slots apart. The live
    /// session resolves a partner by probing one slot forward and one
    /// back — so a non-adjacent pair was prescribed as a superset and run
    /// as two separate straight-set exercises.
    func testAPairedSupersetEndsUpAdjacent() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let squat = cat(2, "Squat", "quads", "compound", "squat")
        let row = cat(3, "Row", "back", "compound", "pull_horizontal")
        let catalog = [bench, squat, row]
        // Deliberately interleaved: the partner for slot 0 sits at slot 2.
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(squat), entry(row, main: true),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        let groups = paired.exercises.map(\.supersetGroup)
        guard let first = groups.firstIndex(where: { $0 != nil }) else {
            return XCTFail("nothing paired — the fixture cannot test adjacency")
        }
        XCTAssertEqual(paired.exercises[first].supersetGroup,
                       paired.exercises[first + 1].supersetGroup,
                       "a prescribed superset must be adjacent or the live "
                     + "session runs it as two straight-set exercises")
    }

    func testTheReorderKeepsEveryExercise() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let squat = cat(2, "Squat", "quads", "compound", "squat")
        let row = cat(3, "Row", "back", "compound", "pull_horizontal")
        let curl = cat(4, "Curl", "biceps", "isolation", "isolation")
        let catalog = [bench, squat, row, curl]
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(squat),
            entry(row, main: true), entry(curl),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        XCTAssertEqual(paired.exercises.count, 4, "the reorder dropped a lift")
        XCTAssertEqual(Set(paired.exercises.map(\.exerciseID)),
                       Set(day.exercises.map(\.exerciseID)),
                       "the reorder changed WHICH lifts are in the day")
    }

    // MARK: The day ceiling (owner 2026-08-27: "Max volume: 25 sets per day")

    func testNoGeneratedDayExceedsTheDayCap() {
        // A stacked bro-split request is the reachable worst case the
        // audit measured (~17 direct chest sets); the cap holds the whole
        // SESSION at 25 working sets whatever the split does.
        let inputs = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 2, durationWeeks: 8,
            experience: .advanced)
        let catalog = (1...30).map { i in
            ProgramGenerator.CatalogExercise(
                id: UUID(), name: "Lift \(i)",
                primaryMuscle: ["chest", "back", "quads", "shoulders"][i % 4],
                secondaryMuscles: [], category: i % 3 == 0 ? "compound" : "isolation",
                equipment: "barbell",
                movementPattern: ["push_horizontal", "pull_horizontal",
                                  "squat", "push_vertical"][i % 4],
                rank: i)
        }
        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)
        for day in program.days {
            // Split into steps: the one-liner filter+map+reduce inside
            // XCTAssert sent Swift's type-checker over its time budget.
            let lifting = day.exercises.filter { $0.cardioZone == nil }
            let setCounts: [Int] = lifting.map(\.sets)
            let working: Int = setCounts.reduce(0, +)
            XCTAssertLessThanOrEqual(working, 25,
                "day carries \(working) working sets - the cap is 25")
        }
    }

    /// An already-adjacent pair must not be shuffled — the reorder is a
    /// repair, not a re-sort.
    func testAnAlreadyAdjacentPairIsLeftAlone() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let row = cat(2, "Row", "back", "compound", "pull_horizontal")
        let squat = cat(3, "Squat", "quads", "compound", "squat")
        let catalog = [bench, row, squat]
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(row, main: true), entry(squat),
        ])

        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)

        XCTAssertEqual(paired.exercises.map(\.name), ["Bench", "Row", "Squat"])
    }

    // MARK: The focus lift wins its main slot (consult picker, 2026-08-27)

    func testANamedFocusLiftLeadsItsPatternOutright() {
        // Two horizontal pushes; the lower-ranked, lower-scored one is the
        // athlete's focus lift. Scoring would pick the other. The promise
        // "which lift do you want to add weight to" means it MUST be in
        // the program, so priority beats the score.
        let favourite = cat(9, "Floor Press", "chest", "compound", "push_horizontal")
        let better = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let row = cat(2, "Row", "back", "compound", "pull_horizontal")
        let squat = cat(3, "Squat", "quads", "compound", "squat")
        let hinge = cat(4, "Deadlift", "hamstrings", "compound", "hinge")
        let catalog = [better, favourite, row, squat, hinge]
        var inputs = ProgramGenerator.Inputs(
            focus: .strength, daysPerWeek: 3, durationWeeks: 4,
            experience: .intermediate)
        inputs.focusExerciseIDs = [favourite.id]

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        let mains = program.days.flatMap(\.exercises).filter(\.isMain).map(\.exerciseID)
        XCTAssertTrue(mains.contains(favourite.id),
                      "the named focus lift is not a main lift anywhere in the week")
    }

    // MARK: An injured joint is an exclusion, not a preference (2026-08-27)

    func testAnInjuredJointKeepsEveryLiftThatLoadsItOutOfTheWeek() {
        func lift(_ n: Int, _ name: String, _ muscle: String, _ pattern: String,
                  joints: [String]) -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(), name: name, primaryMuscle: muscle,
                secondaryMuscles: [], category: "compound", equipment: "barbell",
                movementPattern: pattern, rank: n, jointStress: joints)
        }
        // Every squat and hinge in this catalog loads the hip. A caution
        // would still fill those slots (nothing else can); an injury
        // must leave them empty.
        let catalog = [
            lift(1, "Back Squat", "quads", "squat", joints: ["hip", "knee"]),
            lift(2, "Deadlift", "hamstrings", "hinge", joints: ["hip", "lower_back"]),
            lift(3, "Bench", "chest", "push_horizontal", joints: ["shoulder"]),
            lift(4, "Row", "back", "pull_horizontal", joints: ["elbow"]),
            lift(5, "Press", "shoulders", "push_vertical", joints: ["shoulder"]),
            lift(6, "Pull-Up", "back", "pull_vertical", joints: ["elbow"]),
        ]
        var inputs = ProgramGenerator.Inputs(
            focus: .strength, daysPerWeek: 3, durationWeeks: 4,
            experience: .intermediate)
        inputs.injuredJoints = ["hip"]

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        let hipLoaders = Set(catalog.filter { $0.jointStress.contains("hip") }.map(\.id))
        let prescribed = program.days.flatMap(\.exercises).map(\.exerciseID)
        XCTAssertTrue(hipLoaders.isDisjoint(with: prescribed),
                      "a lift that loads the injured hip was prescribed")
        XCTAssertTrue(program.notes.contains { $0.contains("Injured hip") },
                      "the block does not say why the hip lifts are missing")
    }

    func testACautionStillFillsTheSlotWhenNothingElseCan() {
        // The contrast: the same catalog with the hip as a CAUTION keeps
        // the squat slot filled - a caution is a preference, and a hole
        // would be a worse program than a deprioritized lift.
        func lift(_ n: Int, _ name: String, _ muscle: String, _ pattern: String,
                  joints: [String]) -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(), name: name, primaryMuscle: muscle,
                secondaryMuscles: [], category: "compound", equipment: "barbell",
                movementPattern: pattern, rank: n, jointStress: joints)
        }
        let squat = lift(1, "Back Squat", "quads", "squat", joints: ["hip", "knee"])
        let catalog = [
            squat,
            lift(2, "Deadlift", "hamstrings", "hinge", joints: ["hip", "lower_back"]),
            lift(3, "Bench", "chest", "push_horizontal", joints: ["shoulder"]),
            lift(4, "Row", "back", "pull_horizontal", joints: ["elbow"]),
        ]
        var inputs = ProgramGenerator.Inputs(
            focus: .strength, daysPerWeek: 3, durationWeeks: 4,
            experience: .intermediate)
        inputs.cautionJoints = ["hip"]

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        let prescribed = program.days.flatMap(\.exercises).map(\.exerciseID)
        XCTAssertTrue(prescribed.contains(squat.id),
                      "a cautioned (not injured) hip should not empty the squat slot")
    }

    // MARK: Focus means VOLUME (owner 2026-08-28: "make sure hypertrophy
    // actually means hypertrophy")

    func testAFocusMuscleOutVolumesEveryOtherMuscle() {
        func lift(_ n: Int, _ name: String, _ muscle: String,
                  _ category: String, _ pattern: String)
        -> ProgramGenerator.CatalogExercise {
            ProgramGenerator.CatalogExercise(
                id: UUID(), name: name, primaryMuscle: muscle,
                secondaryMuscles: [], category: category, equipment: "barbell",
                movementPattern: pattern, rank: n)
        }
        // Enough accessories per muscle that the balance pass has levers
        // in both directions.
        var catalog: [ProgramGenerator.CatalogExercise] = [
            lift(1, "Bench", "chest", "compound", "push_horizontal"),
            lift(2, "Row", "back", "compound", "pull_horizontal"),
            lift(3, "Squat", "quads", "compound", "squat"),
            lift(4, "Press", "shoulders", "compound", "push_vertical"),
            lift(5, "RDL", "hamstrings", "compound", "hinge"),
        ]
        for (i, muscle) in ["chest", "back", "quads", "shoulders", "hamstrings"].enumerated() {
            for j in 0..<3 {
                catalog.append(lift(10 + i * 3 + j, "\(muscle) iso \(j)",
                                    muscle, "isolation", "isolation"))
            }
        }
        var inputs = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 4, durationWeeks: 8,
            experience: .intermediate)
        inputs.focusMuscles = ["chest"]

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.primaryMuscle) })
        var sets: [String: Int] = [:]
        for ex in program.days.flatMap(\.exercises) where ex.cardioZone == nil {
            if let muscle = byID[ex.exerciseID] { sets[muscle, default: 0] += ex.sets }
        }
        let chest = sets["chest"] ?? 0
        XCTAssertGreaterThan(chest, 0, "the focus muscle got no work at all")
        for (muscle, count) in sets where muscle != "chest" {
            XCTAssertGreaterThan(chest, count,
                "focus promised chest the volume, but \(muscle) carries \(count) sets to chest's \(chest) - focus is still only a selection preference")
        }
        XCTAssertTrue(program.notes.contains { $0.contains("Focus volume") },
                      "the block does not tell the athlete the focus tilt happened")
    }

    // MARK: Audit 2026-08-28 - promises the code now keeps

    private func auditLift(_ n: Int, _ name: String, _ muscle: String,
                           _ category: String, _ pattern: String)
    -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(), name: name, primaryMuscle: muscle,
            secondaryMuscles: [], category: category, equipment: "barbell",
            movementPattern: pattern, rank: n)
    }

    func testWeightLossActuallyPrescribesCardio() {
        // Owner design 2026-08-13: weight loss buys out in LISS. Until
        // the audit, a weight-loss block with cardioDays=0 shipped zero
        // cardio - the goal's own modality was missing.
        var catalog = [
            auditLift(1, "Bench", "chest", "compound", "push_horizontal"),
            auditLift(2, "Row", "back", "compound", "pull_horizontal"),
            auditLift(3, "Squat", "quads", "compound", "squat"),
        ]
        var bike = auditLift(9, "Stationary Bike", "quads", "cardio", "other")
        catalog.append(bike)
        let inputs = ProgramGenerator.Inputs(
            focus: .weightLoss, daysPerWeek: 3, durationWeeks: 6,
            experience: .intermediate)

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        for day in program.days where day.exercises.contains(where: \.isMain) {
            let liss = day.exercises.filter { $0.cardioZone == 2 }
            XCTAssertFalse(liss.isEmpty,
                "\(day.name) is a weight-loss lifting day with no zone-2 buy-out")
            XCTAssertEqual(liss.first?.cardioMinutes, 15,
                "intermediate weight loss buys out at 15 minutes")
        }
        _ = bike
    }

    func testToFailureAppetiteMarksAccessoriesAndSparesMains() {
        var catalog = [
            auditLift(1, "Bench", "chest", "compound", "push_horizontal"),
            auditLift(2, "Row", "back", "compound", "pull_horizontal"),
            auditLift(3, "Squat", "quads", "compound", "squat"),
        ]
        for j in 0..<4 {
            catalog.append(auditLift(10 + j, "iso \(j)",
                                     ["chest", "back", "quads", "biceps"][j],
                                     "isolation", "isolation"))
        }
        var inputs = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 3, durationWeeks: 6,
            experience: .intermediate)
        inputs.effort = .toFailure

        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)

        let lifting = program.days.flatMap(\.exercises).filter { $0.cardioZone == nil }
        let accessories = lifting.filter { !$0.isMain && $0.setType == nil }
        XCTAssertFalse(accessories.isEmpty, "fixture produced no plain accessories")
        XCTAssertTrue(accessories.allSatisfy(\.targetFailure),
            "the failure appetite must reach the accessories the athlete sees")
        XCTAssertTrue(lifting.filter(\.isMain).allSatisfy { !$0.targetFailure },
            "mains must never be prescribed to failure")
    }
}
