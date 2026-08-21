import XCTest
@testable import GymSync

/// The 20-athlete audit's remediation batch, each finding pinned as a
/// test so it can never quietly return: the Pendlay chain (novice
/// simplicity), the impotent session cap, the all-or-nothing explosive
/// lens, the dead intensity knob, and the graduation ramp.
final class RemediationTests: XCTestCase {

    private func cat(_ rank: Int, _ name: String, _ pattern: String,
                     equip: String = "barbell", complexity: Int = 2,
                     spinal: Int = 0, explosive: Bool = false,
                     score: Int = 7) -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0003-%012d", rank))!,
            name: name, primaryMuscle: "quads", secondaryMuscles: [],
            category: "compound", equipment: equip, movementPattern: pattern,
            rank: rank)
        c.focusScores = ["strength": score, "hypertrophy": score]
        c.complexity = complexity
        c.spinalLoad = spinal
        c.explosive = explosive
        return c
    }

    // MARK: The Pendlay chain

    func testNovicePrefersSimpleEvenAgainstAxialBoostedScore() {
        // The technical row outscores AND carries the axial boost — for a
        // novice the simple one must still win; for an intermediate the
        // boosted scorer keeps winning.
        let pendlay = cat(1, "Pendlay-ish Row", "pull_horizontal",
                          complexity: 3, spinal: 2, score: 8)
        let cable = cat(2, "Cable Row-ish", "pull_horizontal",
                        equip: "cable", complexity: 2, spinal: 1, score: 6)
        let slot = ProgramGenerator.Slot.pattern("pull_horizontal", main: true)
        let novice = ProgramGenerator.select(
            slot: slot, from: [pendlay, cable], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .new,
            axialBoost: true)
        XCTAssertEqual(novice?.name, "Cable Row-ish",
                       "day one: simpler wins; no boost promotes a technical lift")
        let intermediate = ProgramGenerator.select(
            slot: slot, from: [pendlay, cable], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .intermediate,
            axialBoost: true)
        XCTAssertEqual(intermediate?.name, "Pendlay-ish Row",
                       "past novice, the axial-boosted scorer wins as before")
    }

    func testNoviceStrengthMainsOpenAtFiveNotThree() {
        var profile = TrainingProfile()
        profile.trainingAge = .novice
        profile.rankedGoals = [.maxStrength]
        profile.daysPerWeek = 3
        let catalog = [cat(1, "Squat", "squat"), cat(2, "Hinge", "hinge"),
                       cat(3, "Press", "push_horizontal"), cat(4, "Row", "pull_horizontal")]
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 8), catalog: catalog)
        for main in program.days.flatMap(\.exercises).filter(\.isMain) {
            XCTAssertGreaterThanOrEqual(main.repsLow, 5,
                                        "triples are a skill — fives teach the pattern")
            XCTAssertLessThanOrEqual(main.percentOfMax ?? 100, 67.5,
                                     "the novice ceiling eased to 67.5")
        }
    }

    // MARK: The dead knob lives

    func testIntensityAppetiteShiftsTheAnchorWithCeilingLastWord() {
        var conservative = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 3, durationWeeks: 8,
            experience: .intermediate)
        conservative.intensityAppetite = "conservative"
        var standard = conservative
        standard.intensityAppetite = "standard"
        let catalog = [cat(1, "Squat", "squat"), cat(2, "Hinge", "hinge"),
                       cat(3, "Press", "push_horizontal"), cat(4, "Row", "pull_horizontal")]
        let cMain = ProgramGenerator.generate(inputs: conservative, catalog: catalog)
            .days[0].exercises.first(where: \.isMain)
        let sMain = ProgramGenerator.generate(inputs: standard, catalog: catalog)
            .days[0].exercises.first(where: \.isMain)
        XCTAssertEqual((cMain?.percentOfMax ?? 0), (sMain?.percentOfMax ?? 0) - 5,
                       "conservative eases the anchor by 5 points")
    }

    // MARK: The explosive lens, bounded

    func testExplosiveClaimsExactlyOneMainSlotPerDay() {
        // Both patterns offer an explosive lift that WOULD win with the
        // boost — only the first main slot may take it.
        let catalog = [
            cat(1, "Jump Squat", "squat", complexity: 3, explosive: true, score: 7),
            cat(2, "Back Squat", "squat", complexity: 3, score: 8),
            cat(3, "Explosive Hinge", "hinge", complexity: 3, explosive: true, score: 7),
            cat(4, "RDL", "hinge", complexity: 3, score: 8),
            cat(5, "Press", "push_horizontal", score: 8),
            cat(6, "Row", "pull_horizontal", score: 8),
        ]
        var profile = TrainingProfile()
        profile.rankedGoals = [.powerRFD]
        profile.daysPerWeek = 3
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 8), catalog: catalog)
        for day in program.days {
            let explosiveMains = day.exercises.filter { $0.isMain && $0.name.contains("Jump") }
                + day.exercises.filter { $0.isMain && $0.name.contains("Explosive") }
            XCTAssertEqual(explosiveMains.count, 1,
                           "power grants the boost, bounded to one main per day (\(day.name))")
        }
    }

    func testExplosivePercentRules() {
        // The hop owns the squat slot; the barbell jump is the ONLY hinge,
        // so both explosive-percent rules get exercised in one day.
        let hop = cat(1, "Cone Hop", "squat", equip: "bodyweight",
                      explosive: true, score: 9)
        let jumpSquat = cat(2, "Weighted Jump Squat", "hinge",
                            explosive: true, score: 9)
        var profile = TrainingProfile()
        profile.rankedGoals = [.powerRFD]
        profile.daysPerWeek = 1
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 4),
            catalog: [hop, jumpSquat,
                      cat(4, "Press", "push_horizontal"),
                      cat(5, "Row", "pull_horizontal")])
        let mains = program.days[0].exercises.filter(\.isMain)
        let hopMain = mains.first { $0.name == "Cone Hop" }
        XCTAssertNotNil(hopMain)
        XCTAssertNil(hopMain?.percentOfMax, "a cone hop has no meaningful 1RM")
        let jumpMain = mains.first { $0.name == "Weighted Jump Squat" }
        XCTAssertNotNil(jumpMain)
        XCTAssertLessThanOrEqual(jumpMain?.percentOfMax ?? 100, 60,
                                 "power lives at 30-60% — a heavy explosive lift is a slow lift")
    }

    // MARK: The cap gets teeth

    func testSessionCapReducesMainSetsWhenAccessoriesAreGone() {
        var inputs = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 2, durationWeeks: 8,
            experience: .intermediate)
        inputs.sessionMinutes = 40
        inputs.sessionStructure = .minimalist
        let catalog = [cat(1, "Squat", "squat"), cat(2, "Hinge", "hinge"),
                       cat(3, "Press", "push_horizontal"), cat(4, "Row", "pull_horizontal")]
        let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)
        for day in program.days {
            let estimate = day.exercises.reduce(0) {
                $0 + $1.sets * 2 + $1.sets * $1.restSeconds / 60 + 2
            }
            XCTAssertLessThanOrEqual(estimate, 48,
                "the 40-minute parent gets ~40 minutes (floor-3 sets bound the residual), not 75 (\(day.name))")
            for main in day.exercises.filter(\.isMain) {
                XCTAssertGreaterThanOrEqual(main.sets, 3,
                                            "reduction floors at 3 — never a token single")
            }
        }
    }

    // MARK: Round 2 — explosive as a tier, both directions

    func testHouseConditioningAthleteGetsRealLiftsNotPlyoMains() {
        // A25: conditioning's own scores made cone hops the desk worker's
        // squat main. Without the lens, explosive DEMOTES in main slots —
        // even against a lower conditioning score.
        let hop = cat(1, "Cone Hop", "squat", equip: "bodyweight",
                      explosive: true, score: 9)
        let goblet = cat(2, "Goblet Squat", "squat", equip: "dumbbell", score: 7)
        let slot = ProgramGenerator.Slot.pattern("squat", main: true)
        let pick = ProgramGenerator.select(
            slot: slot, from: [hop, goblet], excluding: [],
            focus: .conditioning, focusMuscles: nil)
        XCTAssertEqual(pick?.name, "Goblet Squat",
                       "plyo is a specialist tool — nobody's default squat main")
    }

    func testPowerDominantWinsExplosiveEvenAgainstHigherScore() {
        // A01: the +3 bump lost narrowly to the strength scorer; the tier
        // cannot lose.
        let jump = cat(1, "Jump Squat", "squat", explosive: true, score: 5)
        let squat = cat(2, "Back Squat", "squat", score: 9)
        var profile = TrainingProfile()
        profile.rankedGoals = [.powerRFD]
        profile.daysPerWeek = 1
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 4),
            catalog: [jump, squat,
                      cat(3, "Hinge", "hinge"), cat(4, "Press", "push_horizontal"),
                      cat(5, "Row", "pull_horizontal")])
        let squatMain = program.days[0].exercises.first { $0.slot == .pattern("squat", main: true) }
        XCTAssertEqual(squatMain?.name, "Jump Squat",
                       "the power athlete's granted slot prefers explosive outright")
    }

    func testBodyweightMainsCarryNoPercentAnchor() {
        let dip = cat(1, "Chest Dip", "push_horizontal", equip: "bodyweight", score: 9)
        var inputs = ProgramGenerator.Inputs(
            focus: .hypertrophy, daysPerWeek: 3, durationWeeks: 8,
            experience: .intermediate)
        inputs.equipment = ["bodyweight"]
        let program = ProgramGenerator.generate(
            inputs: inputs,
            catalog: [dip, cat(2, "Inverted Row", "pull_horizontal",
                               equip: "bodyweight", score: 8)])
        for main in program.days.flatMap(\.exercises).filter(\.isMain) {
            XCTAssertNil(main.percentOfMax,
                         "no meaningful %1RM exists for a bodyweight main")
        }
    }

    func testThirtyMinuteCapDropsWholeMainsNeverBelowTwo() {
        // A31: four 180s-rest mains met a 30-minute cap; set floors alone
        // left 68-minute sessions. The final lever drops mains to two.
        var profile = TrainingProfile()
        profile.trainingAge = .novice
        profile.rankedGoals = [.boneDensity, .mobility]
        profile.daysPerWeek = 2
        profile.sessionMinutes = 30
        let catalog = [cat(1, "Leg Press", "squat", equip: "machine", complexity: 2),
                       cat(2, "Hip Machine", "hinge", equip: "machine", complexity: 2),
                       cat(3, "Chest Machine", "push_horizontal", equip: "machine", complexity: 2),
                       cat(4, "Row Machine", "pull_horizontal", equip: "machine", complexity: 2)]
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 8), catalog: catalog)
        for day in program.days {
            let mains = day.exercises.filter(\.isMain)
            XCTAssertGreaterThanOrEqual(mains.count, 2, "never below two lifts")
            let estimate = day.exercises.reduce(0) {
                $0 + $1.sets * 2 + $1.sets * $1.restSeconds / 60 + 2
            }
            XCTAssertLessThanOrEqual(estimate, 36,
                "two 180s-rest mains at floor sets ≈ 34 min — the honest best for this cap (\(day.name))")
        }
    }

    func testUnhonorableWishesGetSaidOutLoud() {
        var bro = TrainingProfile()
        bro.split = .bro
        bro.daysPerWeek = 3
        XCTAssertTrue(bro.generatorInputs(durationWeeks: 8).advisoryNotes
            .contains { $0.contains("bodypart split needs 4+") },
            "the Golden Era client with 3 days hears WHY the week looks different")
        var mobility = TrainingProfile()
        mobility.rankedGoals = [.mobility]
        XCTAssertTrue(mobility.generatorInputs(durationWeeks: 8).advisoryNotes
            .contains { $0.contains("Mobility leads") },
            "a thin modality is named, never silently substituted")
    }

    // MARK: Orphaned-muscle coverage (owner: something beats nothing)

    func testExcludedPatternsStillLeaveAChestDose() {
        // A29: excluding both push patterns silently zeroed the chest.
        var fly = ProgramGenerator.CatalogExercise(
            id: UUID(), name: "Machine Fly", primaryMuscle: "chest",
            secondaryMuscles: [], category: "isolation", equipment: "machine",
            movementPattern: "isolation", rank: 50)
        fly.focusScores = ["hypertrophy": 8]
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        profile.daysPerWeek = 3
        profile.excludedPatterns = ["push_horizontal", "push_vertical"]
        let catalog = [fly,
                       cat(1, "Squat", "squat"), cat(2, "Hinge", "hinge"),
                       cat(3, "Bench", "push_horizontal"),
                       cat(4, "Row", "pull_horizontal")]
        let program = ProgramGenerator.generate(
            inputs: profile.generatorInputs(durationWeeks: 8), catalog: catalog)
        let flyEntry = program.days.flatMap(\.exercises).first { $0.name == "Machine Fly" }
        XCTAssertNotNil(flyEntry, "the orphaned chest gets a small direct dose")
        XCTAssertEqual(flyEntry?.sets, 2, "a dose, not a bodypart day")
        XCTAssertTrue(program.notes.contains { $0.contains("Coverage dose") })
        XCTAssertNil(program.days.flatMap(\.exercises).first { $0.name == "Bench" },
                     "the exclusion itself still holds absolutely")
    }

    // MARK: The ramp

    func testGraduationProbeRequiresNoviceAndAdherence() {
        var outcome = BlockReview.Outcome()
        outcome.adherence = 0.85
        var novice = TrainingProfile(); novice.trainingAge = .novice
        let signal = DriftDetector.graduationSignal(profile: novice, blockOutcome: outcome)
        XCTAssertEqual(signal?.kind, "graduation")
        XCTAssertTrue(signal!.probe.contains("Ready to graduate"),
                      "offered, never imposed")
        var intermediate = TrainingProfile(); intermediate.trainingAge = .intermediate
        XCTAssertNil(DriftDetector.graduationSignal(profile: intermediate,
                                                    blockOutcome: outcome))
        outcome.adherence = 0.4
        XCTAssertNil(DriftDetector.graduationSignal(profile: novice,
                                                    blockOutcome: outcome),
                     "a half-attended block has not earned the barbell yet")
    }

    // MARK: Sex reaches the generator through the profile

    func testProfileSexMapsThroughToInputs() {
        var profile = TrainingProfile()
        profile.sex = .female
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.sex, .female,
                       "the evidence-scaled female adjustments need the field to arrive")
    }
}
