import XCTest
@testable import GymSync

/// Accessory variety as a FLAVOUR, not a prescription.
///
/// Owner 2026-08-26: "variation in accessories is good. Some hit the same
/// secondary in different complimentary ways. Make it so. Some people like
/// static routines, some like it when it varies. Let it be a flavor call
/// that we probe for."
///
/// Framing it as a preference is also what makes it defensible. An earlier
/// design proposed an unconditional rotation cadence and was rejected,
/// because the corpus row it leaned on reads: accessories rotate roughly
/// every 3-4 weeks OR WHEN PROGRESS STALLS, and rotating too often is a
/// common beginner error. An app imposing rotation contradicts that row.
/// An athlete choosing it does not.
final class AccessoryVarietyTests: XCTestCase {

    private func cat(_ n: Int, _ name: String, _ primary: String,
                     secondaries: [String] = [],
                     equipment: String = "machine",
                     pattern: String = "isolation") -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
            name: name, primaryMuscle: primary, secondaryMuscles: secondaries,
            category: "isolation", equipment: equipment,
            movementPattern: pattern, rank: n)
    }

    // MARK: - The preference reaches the generator

    func testTheDefaultIsSteadySoNobodysProgramChangesSilently() {
        // Changing everyone's program without asking is precisely what a
        // flavour call is not.
        XCTAssertEqual(TrainingProfile().accessoryVariety, .steady)
        XCTAssertFalse(TrainingProfile().generatorInputs(durationWeeks: 8)
                        .preferVariedAccessories)
    }

    func testChoosingVarietyReachesTheGenerator() {
        var profile = TrainingProfile()
        profile.accessoryVariety = .varied
        XCTAssertTrue(profile.generatorInputs(durationWeeks: 8).preferVariedAccessories)
    }

    func testTheConsultAnswerLandsOnTheProfile() {
        let after = ConsultAnswers(["accessory_variety": ["varied"]])
            .apply(to: TrainingProfile())
        XCTAssertEqual(after.accessoryVariety, .varied)
        XCTAssertEqual(after.provenance["accessoryVariety"], .stated)
    }

    func testAnUnrecognisedAnswerLeavesThePreferenceAlone() {
        var before = TrainingProfile()
        before.accessoryVariety = .varied
        let after = ConsultAnswers(["accessory_variety": ["nonsense"]]).apply(to: before)
        XCTAssertEqual(after.accessoryVariety, .varied)
    }

    func testTheProbeOffersBothFlavoursAndTunesSomethingReal() {
        let probe = ConsultProbe.bank.first { $0.id == "accessory_variety" }
        XCTAssertNotNil(probe)
        XCTAssertEqual(Set(probe!.options.map(\.id)), ["steady", "varied"])
        for key in probe!.tunes {
            XCTAssertTrue(ConsultProbe.knownTunables.contains(key),
                          "the probe claims to tune '\(key)', which nothing reads")
        }
    }

    // MARK: - What variety actually does to selection

    func testVarietyPrefersALiftThatBringsAFreshSecondary() {
        // Two candidates for the same primary. One duplicates a secondary
        // the day already covers; the other brings something new. With
        // variety on, the fresh one should win.
        let duplicate = cat(1, "Duplicate Curl", "biceps", secondaries: ["forearms"])
        let complement = cat(2, "Complement Curl", "biceps", secondaries: ["brachialis"])
        let pick = ProgramGenerator.select(
            slot: .isolation("biceps"), from: [duplicate, complement],
            excluding: [], coveredSecondaries: ["forearms"],
            preferComplementary: true,
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertEqual(pick?.name, "Complement Curl")
    }

    func testSteadyIgnoresTheCoverageEntirely() {
        // With the preference off, the same inputs must select exactly as
        // they always did - catalog rank order decides.
        let duplicate = cat(1, "Duplicate Curl", "biceps", secondaries: ["forearms"])
        let complement = cat(2, "Complement Curl", "biceps", secondaries: ["brachialis"])
        let pick = ProgramGenerator.select(
            slot: .isolation("biceps"), from: [duplicate, complement],
            excluding: [], coveredSecondaries: ["forearms"],
            preferComplementary: false,
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertEqual(pick?.name, "Duplicate Curl",
                       "steady must reproduce the previous behaviour exactly")
    }

    func testVarietyIsATiltAndNeverLeavesASlotEmpty() {
        // The discipline every other tilt in select() follows: it may
        // reorder equals, it may never filter. If the ONLY candidate
        // duplicates a covered secondary, it still gets picked.
        let onlyOption = cat(1, "Only Curl", "biceps", secondaries: ["forearms"])
        let pick = ProgramGenerator.select(
            slot: .isolation("biceps"), from: [onlyOption],
            excluding: [], coveredSecondaries: ["forearms"],
            preferComplementary: true,
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertNotNil(pick, "a soft tilt must never starve a slot")
    }

    func testALiftWithNoSecondariesIsNeverPenalised() {
        // "Brings nothing new" is about DUPLICATION. A pure isolation lift
        // that trains one muscle and nothing else is not a duplicate of
        // anything, and docking it would quietly bias variety toward
        // compound-ish accessories.
        let pure = cat(1, "Pure Curl", "biceps")
        let dup = cat(2, "Dup Curl", "biceps", secondaries: ["forearms"])
        let pick = ProgramGenerator.select(
            slot: .isolation("biceps"), from: [pure, dup],
            excluding: [], coveredSecondaries: ["forearms"],
            preferComplementary: true,
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertEqual(pick?.name, "Pure Curl")
    }

    func testMainsAreNeverAffected() {
        // The other half of the same corpus row: a main has to sit still
        // long enough to be progressed. Variety is an ACCESSORY flavour.
        // The movement pattern has to MATCH the slot, or selection returns
        // nil for a reason that has nothing to do with variety.
        let dupMain = cat(1, "Bench", "chest", secondaries: ["triceps"],
                          equipment: "barbell", pattern: "push_horizontal")
        let pick = ProgramGenerator.select(
            slot: .pattern("push_horizontal", main: true), from: [dupMain],
            excluding: [], coveredSecondaries: ["triceps"],
            preferComplementary: true,
            focus: .hypertrophy, focusMuscles: nil)
        XCTAssertEqual(pick?.name, "Bench",
                       "a main is chosen on its own merits either way")
    }
}
