import XCTest
@testable import GymSync

/// The sport lens (corpus parameters, docs/science/sport-prep-parameters.md):
/// each sport's mechanism pinned as a no-dead-knobs proof.
final class SportPrepTests: XCTestCase {

    private func cat(_ rank: Int, _ name: String, pattern: String = "squat",
                     muscle: String = "quads", category: String = "compound",
                     unilateral: Bool = false, score: Int = 7)
        -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0007-%012d", rank))!,
            name: name, primaryMuscle: muscle, secondaryMuscles: [],
            category: category, equipment: "barbell", movementPattern: pattern,
            rank: rank)
        c.focusScores = ["strength": score, "sport_prep": score, "conditioning": score]
        c.complexity = 2
        c.unilateral = unilateral
        return c
    }

    func testWrestlingRanksUnilateralUp() {
        // The unilateral-first law: stance and shots are one-sided.
        let bilateral = cat(1, "Back Squattish")
        let split = cat(2, "Split Squattish", unilateral: true)
        let plain = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [bilateral, split],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate)
        XCTAssertEqual(plain?.name, "Back Squattish", "no lens: rank decides")
        let wrestler = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [bilateral, split],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate, sportLens: "wrestling")
        XCTAssertEqual(wrestler?.name, "Split Squattish")
    }

    func testFootballPrefersUnilateralLowerBodyOnly() {
        let bilateralRow = cat(1, "Rowish", pattern: "pull_horizontal", muscle: "back")
        let uniRow = cat(2, "One-Arm Rowish", pattern: "pull_horizontal",
                         muscle: "back", unilateral: true)
        let upper = ProgramGenerator.select(
            slot: .pattern("pull_horizontal", main: true), from: [bilateralRow, uniRow],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate, sportLens: "football")
        XCTAssertEqual(upper?.name, "Rowish",
                       "football's preference is lower-body unilateral, not everything")
        let bilateralSquat = cat(3, "Back Squattish")
        let uniSquat = cat(4, "Single-Leg Squattish", unilateral: true)
        let lower = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [bilateralSquat, uniSquat],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate, sportLens: "football")
        XCTAssertEqual(lower?.name, "Single-Leg Squattish")
    }

    func testBaseballShoulderAccessoryGoesCuffFirst() {
        let lateral = cat(1, "Lateral Raisish", pattern: "isolation",
                          muscle: "shoulders", category: "isolation", score: 8)
        let cuff = cat(2, "External Rotation-ish", pattern: "isolation",
                       muscle: "shoulders", category: "isolation", score: 8)
        let plain = ProgramGenerator.select(
            slot: .isolation("shoulders"), from: [lateral, cuff],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate)
        XCTAssertEqual(plain?.name, "Lateral Raisish")
        let thrower = ProgramGenerator.select(
            slot: .isolation("shoulders"), from: [lateral, cuff],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate, sportLens: "baseball")
        XCTAssertEqual(thrower?.name, "External Rotation-ish",
                       "arm care outranks delt aesthetics for throwers")
    }

    func testProphylaxisSlotsAppear() {
        // Wrestling adds a grip slot on pull-flavored days; baseball adds
        // a shoulders (cuff-first) slot on pressing days.
        var profile = TrainingProfile()
        profile.rankedGoals = [.sportPrep, .maxStrength]
        profile.sportPrepSport = "wrestling"
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.sportPrepSport, "wrestling")
        XCTAssertTrue(inputs.advisoryNotes.contains { $0.contains("Wrestling lens") })
        var catalog: [ProgramGenerator.CatalogExercise] = [
            cat(1, "Squatish"), cat(2, "Hingeish", pattern: "hinge", muscle: "hamstrings"),
            cat(3, "Pressish", pattern: "push_horizontal", muscle: "chest"),
            cat(4, "Rowish", pattern: "pull_horizontal", muscle: "back"),
            cat(5, "OHPish", pattern: "push_vertical", muscle: "shoulders"),
            cat(6, "Pulldownish", pattern: "pull_vertical", muscle: "lats"),
            cat(7, "Lungeish", pattern: "lunge", unilateral: true),
        ]
        var grip = cat(8, "Wrist Curlish", pattern: "isolation",
                       muscle: "forearms", category: "isolation")
        grip.unilateral = false
        catalog.append(grip)
        var upperInputs = inputs
        upperInputs.daysPerWeek = 4   // upper/lower alternation
        let program = ProgramGenerator.generate(inputs: upperInputs, catalog: catalog)
        let upperDay = program.days[0]
        XCTAssertTrue(upperDay.exercises.contains { $0.name == "Wrist Curlish" },
                      "the grip standing dose rides the upper day")
    }

    func testSportLensGatedOnRankedGoal() {
        // A stale sport choice never haunts a changed goal set.
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        profile.sportPrepSport = "wrestling"
        XCTAssertNil(profile.generatorInputs(durationWeeks: 8).sportPrepSport)
    }

    // Smith corpus pass (2026-08-22): the two selection consequences.
    func testSmithGatedFromNoviceButNotIntermediate() {
        let smith = cat(1, "Smith Machine Squattish", score: 8)
        let goblet = cat(2, "Goblet Squattish", score: 7)
        let novice = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [smith, goblet],
            excluding: [], focus: .strength, focusMuscles: nil, experience: .new)
        XCTAssertEqual(novice?.name, "Goblet Squattish",
                       "the rail loads positions a free bar refuses - not for day one")
        let intermediate = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [smith, goblet],
            excluding: [], focus: .strength, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(intermediate?.name, "Smith Machine Squattish",
                       "past novice the better scorer wins - the corpus backs the tool")
    }

    func testSportLensDemotesSmith() {
        let smithSplit = cat(1, "Smith Split Squattish", unilateral: true)
        let freeSplit = cat(2, "Split Squattish", unilateral: true)
        let wrestler = ProgramGenerator.select(
            slot: .pattern("squat", main: true), from: [smithSplit, freeSplit],
            excluding: [], focus: .strength, focusMuscles: nil,
            experience: .intermediate, sportLens: "wrestling")
        XCTAssertEqual(wrestler?.name, "Split Squattish",
                       "athletes need the instability the rail removes")
    }

    func testFootballGrantsBoundedExplosiveEmphasis() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.sportPrep]
        profile.sportPrepSport = "football"
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.personaLens?.explosiveEmphasis, true)
    }
}
