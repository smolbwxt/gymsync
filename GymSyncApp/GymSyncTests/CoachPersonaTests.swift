import XCTest
@testable import GymSync

/// The persona contract: coaches shape METHOD, never facts. Same goal +
/// different coach = genuinely different program; athlete statements
/// survive every coach switch; stances act only through label-space
/// lenses inside the one shared generator.
final class CoachPersonaTests: XCTestCase {

    func testRosterIntegrity() {
        XCTAssertEqual(CoachPersona.all.count, 6)
        XCTAssertEqual(Set(CoachPersona.all.map(\.slug)).count, 6, "slugs unique")
        for persona in CoachPersona.all {
            XCTAssertFalse(persona.philosophy.isEmpty)
            XCTAssertTrue(persona.isPro, "personalities are PRO; the house coach is free")
        }
        XCTAssertNil(CoachPersona.bySlug("the-imposter"))
    }

    func testPersonaSeedsOnlyUnstatedFields() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        profile.split = .upperLower
        profile.provenance["split"] = .stated   // the athlete SAID this
        let coached = CoachPersona.bySlug("the-golden-era")!.apply(to: profile)
        XCTAssertEqual(coached.split, .upperLower,
                       "a stated split survives any coach — athlete facts win")
        XCTAssertEqual(coached.sessionStructure, .supersets,
                       "unstated method fields take the coach's preset")
        XCTAssertEqual(coached.provenance["sessionStructure"], .personaDefault)
        XCTAssertEqual(coached.persona, "the-golden-era")
        XCTAssertEqual(coached.rankedGoals, [.hypertrophy],
                       "goals are the athlete's alone — unreachable by construction")
    }

    func testSwitchingCoachesReseedsDefaultsButNeverFacts() {
        var profile = TrainingProfile()
        profile.exclusions = [.init(exerciseID: UUID(),
                                    reasonClass: "injury_pain", joint: "shoulder")]
        let golden = CoachPersona.bySlug("the-golden-era")!.apply(to: profile)
        XCTAssertEqual(golden.split, .bro)
        let purist = CoachPersona.bySlug("the-strength-purist")!.apply(to: golden)
        XCTAssertEqual(purist.split, .auto,
                       "the old coach's default re-seeds on switch")
        XCTAssertEqual(purist.repAppetite, "heavy_low")
        XCTAssertEqual(purist.exclusions.count, 1,
                       "hard constraints pass through every coach untouched")
    }

    // MARK: Lenses change selection (the flip-the-field law for stances)

    private func cat(_ rank: Int, _ name: String, _ equip: String,
                     fatigue: Int = 3, stretch: Bool = false,
                     explosive: Bool = false,
                     score: Int = 7) -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
            name: name, primaryMuscle: "quads", secondaryMuscles: [],
            category: "compound", equipment: equip, movementPattern: "squat",
            rank: rank)
        c.focusScores = ["hypertrophy": score, "strength": score]
        c.fatigueCost = fatigue
        c.lengthenedBias = stretch
        c.explosive = explosive
        return c
    }

    func testFatigueAverseLensFlipsAnOtherwiseTiedPick() {
        // The grinder outscores by a point but costs 5 fatigue to the
        // machine's 2 — the neutral coach takes the score, the Scientist
        // takes the stimulus-per-fatigue trade.
        let grinder = cat(1, "Heavy Squat", "barbell", fatigue: 5, score: 8)
        let easy = cat(2, "Hack Squat Machine", "machine", fatigue: 2)
        let slot = ProgramGenerator.Slot.pattern("squat", main: true)
        let neutral = ProgramGenerator.select(
            slot: slot, from: [grinder, easy], excluding: [],
            focus: .hypertrophy, focusMuscles: nil)
        let averse = ProgramGenerator.select(
            slot: slot, from: [grinder, easy], excluding: [],
            focus: .hypertrophy, focusMuscles: nil,
            lens: CoachPersona.bySlug("the-scientist")!.lens)
        XCTAssertEqual(averse?.name, "Hack Squat Machine",
                       "the Scientist docks systemic drain")
        XCTAssertNotEqual(neutral?.name, averse?.name,
                          "the stance genuinely changes the pick")
    }

    func testBarbellFirstLensFlipsAccessoryEquipment() {
        let cable = cat(1, "Cable Squat Thing", "cable")
        let barbell = cat(2, "Barbell Split Squat", "barbell")
        let slot = ProgramGenerator.Slot.pattern("squat", main: false)
        let neutral = ProgramGenerator.select(
            slot: slot, from: [cable, barbell], excluding: [],
            focus: .strength, focusMuscles: nil)
        XCTAssertEqual(neutral?.equipment, "cable",
                       "default accessories favor machines/cables")
        let purist = ProgramGenerator.select(
            slot: slot, from: [cable, barbell], excluding: [],
            focus: .strength, focusMuscles: nil,
            lens: CoachPersona.bySlug("the-strength-purist")!.lens)
        XCTAssertEqual(purist?.equipment, "barbell",
                       "the Purist's accessories prefer the bar")
    }

    func testExplosiveLensBoostsFieldWork() {
        let slow = cat(1, "Leg Press", "machine", score: 8)
        let fast = cat(2, "Trap Bar Jump", "barbell", explosive: true, score: 7)
        let slot = ProgramGenerator.Slot.pattern("squat", main: true)
        let hybrid = ProgramGenerator.select(
            slot: slot, from: [slow, fast], excluding: [],
            focus: .strength, focusMuscles: nil,
            lens: CoachPersona.bySlug("the-hybrid-athlete")!.lens)
        XCTAssertEqual(hybrid?.name, "Trap Bar Jump",
                       "+3 explosive bonus outweighs a 1-point score gap")
    }

    // MARK: Same goal, different coach, one code path

    func testSameGoalDifferentCoachDifferentProgram() {
        var base = TrainingProfile()
        base.rankedGoals = [.hypertrophy]
        base.daysPerWeek = 5
        let catalog: [ProgramGenerator.CatalogExercise] = [
            cat(1, "Back Squat", "barbell", fatigue: 5),
            cat(2, "Leg Press", "machine", fatigue: 2),
            cat(3, "Bench Press", "barbell"),
            cat(4, "Row", "barbell"),
        ]
        let goldenProfile = CoachPersona.bySlug("the-golden-era")!.apply(to: base)
        let scientistProfile = CoachPersona.bySlug("the-scientist")!.apply(to: base)
        let golden = ProgramGenerator.generate(
            inputs: goldenProfile.generatorInputs(durationWeeks: 8), catalog: catalog)
        let scientist = ProgramGenerator.generate(
            inputs: scientistProfile.generatorInputs(durationWeeks: 8), catalog: catalog)
        XCTAssertEqual(Array(golden.days.map(\.name).prefix(2)), ["Chest", "Back"],
                       "the Golden Era runs bodypart days")
        XCTAssertNotEqual(golden.days.map(\.name), scientist.days.map(\.name),
                          "same goal, different coach, genuinely different week")
    }
}
