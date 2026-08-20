import XCTest
@testable import GymSync

/// The TrainingProfile foundation: deterministic goal weighting, tiered
/// generator mapping, split preference winning over the focus table, and
/// the antagonist-superset structure pass. Every field here must change
/// generator output when flipped — the no-dead-knobs law.
final class TrainingProfileTests: XCTestCase {

    // MARK: Goal weighting

    func testRankingBecomesNormalizedLinearDecayWeights() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy, .conditioning, .powerRFD]
        let weights = profile.goalWeights
        // 3 goals: shares 3/6, 2/6, 1/6.
        XCTAssertEqual(weights[.hypertrophy]!, 0.5, accuracy: 0.001)
        XCTAssertEqual(weights[.conditioning]!, 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(weights[.powerRFD]!, 1.0 / 6, accuracy: 0.001)
        XCTAssertEqual(weights.values.reduce(0, +), 1.0, accuracy: 0.001)
    }

    func testEmptyRankingFallsBackToHypertrophy() {
        var profile = TrainingProfile()
        profile.rankedGoals = []
        XCTAssertEqual(profile.dominantGoal, .hypertrophy)
        XCTAssertEqual(profile.goalWeights[.hypertrophy], 1.0)
    }

    // MARK: Tiered generator mapping

    func testDominantGoalPicksFocusAndPowerOverridesTheBand() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.powerRFD, .maxStrength]
        XCTAssertEqual(profile.generatorFocus, .strength,
                       "power rides the strength tables")
        XCTAssertNotNil(profile.bandOverride)
        XCTAssertEqual(profile.bandOverride?.mainRepsHigh, 5,
                       "submaximal speed work, never grinding")

        profile.rankedGoals = [.boneDensity]
        XCTAssertEqual(profile.generatorFocus, .strength,
                       "bone density's active ingredient is heavy axial loading")
        XCTAssertNil(profile.bandOverride)
        XCTAssertTrue(profile.wantsAxialLoading)
    }

    func testSecondaryGoalShowsUpInSelectionWeights() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.maxStrength, .conditioning]
        let tilt = profile.selectionWeights
        XCTAssertGreaterThan(tilt["strength"] ?? 0, tilt["conditioning"] ?? 0)
        XCTAssertGreaterThan(tilt["conditioning"] ?? 0, 0,
                             "the 1/3-weighted secondary goal is not invisible")
    }

    func testProfileRoundTripsThroughJSON() throws {
        var profile = TrainingProfile()
        profile.rankedGoals = [.powerRFD, .hypertrophy]
        profile.split = .bro
        profile.sessionStructure = .supersets
        profile.exclusions = [.init(exerciseID: UUID(),
                                    reasonClass: "injury_pain", joint: "shoulder")]
        profile.provenance = ["split": .stated, "rankedGoals": .personaDefault]
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(TrainingProfile.self, from: data)
        XCTAssertEqual(back, profile, "jsonb stability — the schema never migrates")
    }

    // MARK: Split preference (flip-the-field: preference changes output)

    func testExplicitSplitPreferenceWinsOverFocusTable() {
        // Weight loss forced full-body at ANY day count — the exact
        // "drive everyone the same direction" complaint. Preference wins.
        let bro = GeneratorScience.split(daysPerWeek: 5, focus: .weightLoss,
                                         preference: .bro)
        XCTAssertEqual(bro, [.chest, .back, .legs, .shoulders, .arms])
        let auto = GeneratorScience.split(daysPerWeek: 5, focus: .weightLoss)
        XCTAssertEqual(auto, Array(repeating: .fullBody, count: 5),
                       "auto keeps the science ladder")
    }

    func testBroBelowFourDaysFallsBackToScienceLadder() {
        let split = GeneratorScience.split(daysPerWeek: 3, focus: .hypertrophy,
                                           preference: .bro)
        XCTAssertEqual(split, [.fullBody, .fullBody, .fullBody],
                       "a 3-day bro split stops being one")
    }

    func testHybridGivesEveryMuscleASecondTouch() {
        let split = GeneratorScience.split(daysPerWeek: 5, focus: .hypertrophy,
                                           preference: .hybrid)
        XCTAssertEqual(split, [.upper, .lower, .chest, .back, .legs],
                       "U/L base = second weekly touch; bodypart days keep the bro feel")
    }

    func testStrengthFocusNeverEmptiesABodypartDay() {
        // The strength filter strips isolations — an arms day is nothing
        // BUT isolations, and the athlete chose this split knowingly.
        let slots = ProgramGenerator.slots(for: .arms, focus: .strength)
        XCTAssertFalse(slots.isEmpty, "bodypart days keep their template under every focus")
    }

    // MARK: The acceptance fixture (owner 2026-08-20)
    //
    // "The day the generator can produce a genuinely different program for
    // the 16-year-old footballer and the 50-year-old first-timer from the
    // same code path, the everyone-gets-driven-the-same-direction era is
    // over — and we'll have the test to prove it never comes back."

    private func acceptanceCatalog() -> [ProgramGenerator.CatalogExercise] {
        func ex(_ rank: Int, _ name: String, _ muscle: String, _ category: String,
                _ pattern: String, scores: [String: Int] = [:],
                spinal: Int = 0, explosive: Bool = false,
                complexity: Int = 2) -> ProgramGenerator.CatalogExercise {
            var c = ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
                name: name, primaryMuscle: muscle, secondaryMuscles: [],
                category: category, equipment: "barbell", movementPattern: pattern,
                rank: rank)
            c.focusScores = scores
            c.spinalLoad = spinal
            c.explosive = explosive
            c.complexity = complexity
            return c
        }
        return [
            ex(1, "Back Squat", "quads", "compound", "squat",
               scores: ["strength": 9, "hypertrophy": 8], spinal: 2, complexity: 3),
            ex(2, "Leg Press", "quads", "compound", "squat",
               scores: ["strength": 6, "hypertrophy": 8], spinal: 0),
            ex(3, "Trap Bar Jump", "quads", "compound", "squat",
               scores: ["strength": 7], spinal: 1, explosive: true, complexity: 3),
            ex(4, "Deadlift", "hamstrings", "compound", "hinge",
               scores: ["strength": 10], spinal: 2, complexity: 3),
            ex(5, "Hip Thrust", "glutes", "compound", "hinge",
               scores: ["strength": 6, "hypertrophy": 8], spinal: 0),
            ex(6, "Bench Press", "chest", "compound", "push_horizontal",
               scores: ["strength": 9, "hypertrophy": 8], spinal: 0),
            ex(7, "Overhead Press", "shoulders", "compound", "push_vertical",
               scores: ["strength": 8], spinal: 2, complexity: 3),
            ex(8, "Barbell Row", "back", "compound", "pull_horizontal",
               scores: ["strength": 8, "hypertrophy": 8], spinal: 1),
            ex(9, "Lat Pulldown", "lats", "compound", "pull_vertical",
               scores: ["hypertrophy": 8], spinal: 0),
            ex(10, "Walking Lunge", "quads", "compound", "lunge",
               scores: ["hypertrophy": 7], spinal: 1),
            ex(11, "Leg Curl", "hamstrings", "isolation", "isolation",
               scores: ["hypertrophy": 7]),
            ex(12, "Treadmill Walk", "quads", "cardio", "other"),
        ]
    }

    func testTwoAthletesOneCodePathGenuinelyDifferentPrograms() {
        let catalog = acceptanceCatalog()

        // The 16-year-old footballer: power first, in season.
        var footballer = TrainingProfile()
        footballer.trainingAge = .intermediate
        footballer.rankedGoals = [.powerRFD, .sportPrep, .hypertrophy]
        footballer.daysPerWeek = 3
        footballer.inSeason = true
        let footballProgram = ProgramGenerator.generate(
            inputs: footballer.generatorInputs(durationWeeks: 8), catalog: catalog)

        // The 50-year-old first-timer: bone density and heart health.
        var senior = TrainingProfile()
        senior.trainingAge = .novice
        senior.rankedGoals = [.boneDensity, .generalHealth, .mobility]
        senior.daysPerWeek = 3
        senior.cardioStyle = .steady
        let seniorProgram = ProgramGenerator.generate(
            inputs: senior.generatorInputs(durationWeeks: 8, cardioDays: 2,
                                           cardioMinutes: 30), catalog: catalog)

        // Footballer: power band (2-5 rep mains), everything capped
        // submaximal in season.
        let footballMains = footballProgram.days.flatMap(\.exercises).filter(\.isMain)
        XCTAssertFalse(footballMains.isEmpty)
        for main in footballMains {
            XCTAssertLessThanOrEqual(main.repsHigh, 5,
                                     "power band: submaximal speed work, never grinding")
            XCTAssertLessThanOrEqual(main.percentOfMax ?? 0, 80,
                                     "in season nothing goes near max")
        }

        // Senior: strength focus via bone density, novice-gated complexity,
        // dedicated steady-state cardio at zone 2.
        let seniorCardio = seniorProgram.days.flatMap(\.exercises).filter { $0.cardioZone != nil }
        XCTAssertTrue(seniorCardio.contains { $0.cardioZone == 2 },
                      "steady-state preference lands as zone-2 minutes")
        let seniorMains = seniorProgram.days.flatMap(\.exercises).filter(\.isMain)
        for main in seniorMains {
            XCTAssertLessThanOrEqual(main.percentOfMax ?? 0,
                                     GeneratorScience.mainIntensityCeiling(experience: .new),
                                     "a first-timer never opens near max")
        }

        // And they are genuinely DIFFERENT programs from one code path.
        XCTAssertNotEqual(footballMains.map(\.repsHigh), seniorMains.map(\.repsHigh),
                          "the same-direction era is over")
    }

    // MARK: Session structure — antagonist supersets

    private func cat(_ rank: Int, _ name: String, _ muscle: String,
                     _ category: String, _ pattern: String) -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
            name: name, primaryMuscle: muscle, secondaryMuscles: [],
            category: category, equipment: "barbell", movementPattern: pattern,
            rank: rank)
    }

    func testSupersetsPairAntagonistsAndLeaveOrphansStraight() {
        let bench = cat(1, "Bench", "chest", "compound", "push_horizontal")
        let row = cat(2, "Row", "back", "compound", "pull_horizontal")
        let curl = cat(3, "Curl", "biceps", "isolation", "isolation")
        let pushdown = cat(4, "Pushdown", "triceps", "isolation", "isolation")
        let squat = cat(5, "Squat", "quads", "compound", "squat")
        let catalog = [bench, row, curl, pushdown, squat]
        func entry(_ c: ProgramGenerator.CatalogExercise, main: Bool = false) -> ProgramGenerator.Exercise {
            ProgramGenerator.Exercise(exerciseID: c.id, name: c.name, sets: 3,
                                      repsLow: 8, repsHigh: 12, restSeconds: 90,
                                      percentOfMax: nil, isMain: main)
        }
        let day = ProgramGenerator.Day(name: "Upper", exercises: [
            entry(bench, main: true), entry(row, main: true),
            entry(squat), entry(curl), entry(pushdown),
        ])
        let paired = ProgramGenerator.assignSupersets(day: day, catalog: catalog)
        XCTAssertEqual(paired.exercises[0].supersetGroup, 1)
        XCTAssertEqual(paired.exercises[1].supersetGroup, 1,
                       "horizontal push pairs with horizontal pull")
        XCTAssertEqual(paired.exercises[3].supersetGroup, 2)
        XCTAssertEqual(paired.exercises[4].supersetGroup, 2,
                       "biceps pairs with triceps")
        XCTAssertNil(paired.exercises[2].supersetGroup,
                     "a squat with no hinge partner stays straight sets")
    }
}
