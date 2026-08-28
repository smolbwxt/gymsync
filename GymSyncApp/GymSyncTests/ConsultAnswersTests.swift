import XCTest
@testable import GymSync

/// The consult's applier: answers in, a tuned profile out. These tests
/// exist because the mapping is a set of PRODUCT decisions — what "FORGE
/// THE BODY" actually builds, whether a symptom may overwrite a stated
/// goal, whether a joint named last block stays named — and product
/// decisions buried in a view cannot be argued with or defended.
final class ConsultAnswersTests: XCTestCase {

    private func profile() -> TrainingProfile { TrainingProfile() }

    // MARK: - The six doors

    func testEveryOpenerDoorProducesAGoal() {
        for option in ConsultProbe.opener.options {
            let goals = ConsultAnswers.goals(forOpener: option.id)
            XCTAssertFalse(goals.isEmpty, "the '\(option.id)' door produces no goal")
        }
    }

    func testForgeIsRankedRecompositionNotABlend() {
        // The corpus is consistent that chasing size and fat loss at once
        // stalls both. Ranking is the mechanism the block planner
        // alternates on, so the ORDER is the data.
        let goals = ConsultAnswers.goals(forOpener: "forge")
        XCTAssertEqual(goals, [.hypertrophy, .fatLoss])
        XCTAssertEqual(goals.first, .hypertrophy, "size must lead; fat loss rides second")
    }

    func testTheDateDoorLeadsWithSportPrep() {
        XCTAssertEqual(ConsultAnswers.goals(forOpener: "date").first, .sportPrep)
    }

    func testAnUnknownDoorFallsBackToMaintenanceRatherThanCrashing() {
        XCTAssertEqual(ConsultAnswers.goals(forOpener: "nonsense"), [.generalHealth])
    }

    // MARK: - Refines, never resets

    func testAnUnansweredConsultChangesNothing() {
        // The five doors give coarse adjustment; the consult refines. An
        // empty consult must be a no-op, or every skipped question would
        // silently reset a field the athlete set by hand.
        var before = profile()
        before.daysPerWeek = 5
        before.sessionMinutes = 75
        before.repAppetite = "heavy_low"
        before.cautionJoints = ["shoulder"]
        XCTAssertEqual(ConsultAnswers().apply(to: before), before)
    }

    func testAnsweringOneProbeLeavesEveryOtherFieldAlone() {
        var before = profile()
        before.daysPerWeek = 5
        before.sessionMinutes = 75
        let after = ConsultAnswers(["rep_appetite": ["heavy_low"]]).apply(to: before)
        XCTAssertEqual(after.repAppetite, "heavy_low")
        XCTAssertEqual(after.daysPerWeek, 5)
        XCTAssertEqual(after.sessionMinutes, 75)
    }

    // MARK: - Provenance (the whole point)

    func testEveryFieldTheConsultWritesBecomesStated() {
        // This is what stops Coach re-asking, and what stops a persona
        // default overwriting an answer. A written field with unchanged
        // provenance is a silent regression.
        let answers = ConsultAnswers([
            "opener": ["size"],
            "days": ["4"],
            "session_length": ["60"],
            "equipment": ["dumbbell"],
            "rep_appetite": ["moderate"],
            "climb_rate": ["aggressive"],
            "cautions": ["shoulder"],
        ])
        let after = answers.apply(to: profile())
        for key in ["rankedGoals", "daysPerWeek", "sessionMinutes", "equipment",
                    "repAppetite", "intensityAppetite", "cautionJoints"] {
            XCTAssertEqual(after.provenance[key], .stated, "\(key) was written but not stated")
        }
    }

    func testAFieldTheConsultDidNotWriteKeepsItsProvenance() {
        var before = profile()
        before.provenance["daysPerWeek"] = .personaDefault
        let after = ConsultAnswers(["opener": ["size"]]).apply(to: before)
        XCTAssertEqual(after.provenance["daysPerWeek"], .personaDefault)
    }

    // MARK: - Focus areas

    func testFocusIsCappedAtThreeBecauseTheQuestionPromisesUpToThree() {
        // The probe says "pick up to three - they get the top of the
        // week's volume". Honoring five would spread the volume back out;
        // the UI caps the selection at three so nothing is dropped, and
        // this prefix is the safety net behind it (2026-08-28, raised
        // from two when focus became a real volume lever).
        let answers = ConsultAnswers(["focus_areas": ["chest", "back", "quads", "biceps"]])
        XCTAssertEqual(answers.focusMuscles?.count, 3)
    }

    func testFocusIsFilteredToTheVocabularyTheCoverageCheckUses() {
        // One list, two readers — GeneratorScience.majorMuscles. A focus
        // the coverage check has never heard of would silently do nothing.
        let answers = ConsultAnswers(["focus_areas": ["forearms", "chest"]])
        XCTAssertEqual(answers.focusMuscles, ["chest"])
    }

    func testNoFocusAnswerMeansNoFocusRatherThanAnEmptySet() {
        // nil and [] mean different things downstream: nil is "no
        // preference", empty is "prefer nothing", which would zero the
        // standing bonus for every exercise.
        XCTAssertNil(ConsultAnswers().focusMuscles)
        XCTAssertNil(ConsultAnswers(["focus_areas": ["kneecaps"]]).focusMuscles)
    }

    // MARK: - The symptom branch

    func testASymptomSetsTheGoalItImplies() {
        let after = ConsultAnswers(["opener": ["running"], "whats_off": ["stiffness"]])
            .apply(to: profile())
        XCTAssertEqual(after.rankedGoals, [.mobility])
    }

    func testBreathAlsoSetsTheCardioStyle() {
        let after = ConsultAnswers(["opener": ["running"], "whats_off": ["breath"]])
            .apply(to: profile())
        XCTAssertEqual(after.cardioStyle, .steady)
    }

    func testTheExplicitEngineQuestionOutranksTheInferredStyle() {
        let after = ConsultAnswers(["engine_kind": ["intervals"], "whats_off": ["breath"]])
            .apply(to: profile())
        XCTAssertEqual(after.cardioStyle, .intervals,
                       "an explicit answer must beat an inference")
    }

    // MARK: - Constraints accumulate

    // The contract flipped 2026-08-27 with the injury-severity work: the
    // cautions probe is asked EVERY consult with the known joints
    // pre-selected, so an answered probe is a statement about all of
    // them. Silence (the probe skipped) still heals nothing.
    func testAJointNamedLastBlockIsNotHealedBySilence() {
        var before = profile()
        before.cautionJoints = ["shoulder"]
        let after = ConsultAnswers([:]).apply(to: before)
        XCTAssertEqual(after.cautionJoints, ["shoulder"])
    }

    func testAnAnsweredCautionsProbeIsTheWholeList() {
        // The athlete saw "shoulder" pre-selected, unticked it and ticked
        // "knee". Keeping the shoulder would override what they just did
        // on screen.
        var before = profile()
        before.cautionJoints = ["shoulder"]
        let after = ConsultAnswers(["cautions": ["knee"]]).apply(to: before)
        XCTAssertEqual(after.cautionJoints, ["knee"])
    }

    func testExcludedPatternsAccumulateToo() {
        var before = profile()
        before.excludedPatterns = ["push_vertical"]
        let after = ConsultAnswers(["wont_do": ["hinge"]]).apply(to: before)
        XCTAssertEqual(Set(after.excludedPatterns), ["push_vertical", "hinge"])
    }

    func testConstraintsDoNotDuplicateOnRepeatConsults() {
        var before = profile()
        before.cautionJoints = ["shoulder"]
        let after = ConsultAnswers(["cautions": ["shoulder"]]).apply(to: before)
        XCTAssertEqual(after.cautionJoints, ["shoulder"])
    }

    // MARK: - Parsing

    func testDurationReadsTheWeeksOutOfFreeText() {
        XCTAssertEqual(ConsultAnswers(["the_date": ["12 weeks out"]]).durationWeeks, 12)
    }

    func testAnImplausibleDurationIsRefusedRatherThanClamped() {
        // Clamping 400 to 52 would silently build a year-long block for
        // someone who mistyped. Refusing leaves the door's value standing.
        XCTAssertNil(ConsultAnswers(["the_date": ["400"]]).durationWeeks)
        XCTAssertNil(ConsultAnswers(["the_date": ["next spring"]]).durationWeeks)
    }

    func testOnlySportsWithARealLensAreClaimed() {
        // There is no generic "sport mode". Claiming one would put a
        // football prescription in front of a swimmer.
        XCTAssertEqual(ConsultAnswers.sport(in: "state wrestling meet in march"), "wrestling")
        XCTAssertNil(ConsultAnswers.sport(in: "my swim meet"))
    }

    func testAnUnknownSportLeavesTheExistingOneAlone() {
        var before = profile()
        before.sportPrepSport = "football"
        let after = ConsultAnswers(["the_date": ["triathlon in june"]]).apply(to: before)
        XCTAssertEqual(after.sportPrepSport, "football")
    }

    func testEquipmentIsFilteredToClassesTheCatalogKnows() {
        let after = ConsultAnswers(["equipment": ["dumbbell", "kettlebell", "cable"]])
            .apply(to: profile())
        XCTAssertEqual(after.equipment, ["dumbbell", "cable"])
    }

    func testNoRecognisedEquipmentLeavesTheProfileUntouched() {
        // Writing an empty set would tell the generator this athlete owns
        // nothing, and it would return an empty program.
        let after = ConsultAnswers(["equipment": ["kettlebell"]]).apply(to: profile())
        XCTAssertNil(after.equipment)
    }

    func testAnchorsParseIntoWeights() {
        let anchors = ConsultAnswers(["anchor_lifts": ["bench=135", "squat=185"]]).liftAnchors
        XCTAssertEqual(anchors["bench"], Decimal(135))
        XCTAssertEqual(anchors["squat"], Decimal(185))
    }

    func testMalformedAnchorsAreDroppedNotZeroed() {
        // A zero anchor would seed the whole progression at nothing.
        let anchors = ConsultAnswers(["anchor_lifts": ["bench=", "squat=0", "ohp=abc"]])
            .liftAnchors
        XCTAssertTrue(anchors.isEmpty)
    }

    func testStandingRulesAreTrimmedAndBounded() {
        let rules = ConsultAnswers(["standing_rule": [
            "  pulls before arms  ", "", String(repeating: "x", count: 400),
        ]]).standingRules
        XCTAssertEqual(rules, ["pulls before arms"])
    }

    // MARK: - Comfort (derived experience)

    func testComfortRecordsTheWholeLadderNotJustTheYeses() {
        // The cap's coherent-prefix rule needs the nos as well as the
        // yeses, and an empty dictionary reads as "never asked".
        let after = ConsultAnswers(["gym_comfort": ["goblet-squat"]]).apply(to: profile())
        XCTAssertEqual(after.comfortAnswers?.count, GeneratorScience.comfortProbes.count)
        XCTAssertEqual(after.comfortAnswers?["goblet-squat"], true)
        XCTAssertEqual(after.comfortAnswers?["power-clean"], false)
    }

    func testComfortableWithNothingIsAnAnswerNotASilence() {
        // The defect this closes: a day-one lifter who recognises none of
        // the lifts would otherwise write nothing, leaving the guessed
        // training age standing. "None of these" must reach the floor.
        let after = ConsultAnswers(["gym_comfort": []]).apply(to: profile())
        XCTAssertEqual(after.derivedComplexityCap, 2,
                       "nothing comfortable must derive the honest floor")
    }

    func testNotAnsweringComfortLeavesTheCapAlone() {
        var before = profile()
        before.derivedComplexityCap = 4
        XCTAssertEqual(ConsultAnswers().apply(to: before).derivedComplexityCap, 4)
    }

    func testComfortDerivesTheCapFromTheLadder() {
        let after = ConsultAnswers(["gym_comfort": ["goblet-squat", "deadlift"]])
            .apply(to: profile())
        XCTAssertEqual(after.derivedComplexityCap, 3)
    }

    func testBravadoCannotSkipRungs() {
        // Comfortable at 4 but not at 3 reads as 3-below.
        let after = ConsultAnswers(["gym_comfort": ["goblet-squat", "weighted-pullup"]])
            .apply(to: profile())
        XCTAssertEqual(after.derivedComplexityCap, 2)
    }

    // MARK: - Commitment

    func testCommittingWritesTheNumberTheAthleteWasShown() {
        let after = ConsultAnswers(["commitment": ["commit", "4"]]).apply(to: profile())
        XCTAssertEqual(after.daysPerWeek, 4)
    }

    func testKeepingTheCurrentCadenceDoesNotChangeTheDays() {
        // The honest trade is a longer block, not a broken promise.
        var before = profile()
        before.daysPerWeek = 2
        let after = ConsultAnswers(["commitment": ["current"]]).apply(to: before)
        XCTAssertEqual(after.daysPerWeek, 2)
    }

    // MARK: - Rendered questions

    func testTheCommitmentQuestionReadsItsNumbers() {
        var context = ConsultProbe.Context()
        context.recommendedDaysPerWeek = 4
        context.loggedDaysPerWeek = 2
        let probe = ConsultProbe.bank.first { $0.id == "commitment" }!
        let asked = ConsultProbe.ask(probe, in: context)
        XCTAssertTrue(asked.contains("4 days a week"), asked)
        XCTAssertTrue(asked.contains("2 a week"), asked)
        XCTAssertFalse(asked.contains("{"), "a token reached the screen: \(asked)")
    }

    func testAFractionalCadenceIsShownAsItself() {
        var context = ConsultProbe.Context()
        context.recommendedDaysPerWeek = 4
        context.loggedDaysPerWeek = 2.5
        let probe = ConsultProbe.bank.first { $0.id == "commitment" }!
        XCTAssertTrue(ConsultProbe.ask(probe, in: context).contains("2.5 a week"))
    }

    func testAnUnknownNumberFallsBackToATrueSentence() {
        // "{days} days a week" reaching a real screen is worse than a
        // vaguer sentence, and inventing a number is worse than both.
        let probe = ConsultProbe.bank.first { $0.id == "commitment" }!
        let asked = ConsultProbe.ask(probe, in: ConsultProbe.Context())
        XCTAssertFalse(asked.contains("{"), asked)
        XCTAssertFalse(asked.contains("days a week."), "invented a number: \(asked)")
    }

    func testProbesWithoutTokensAreLeftExactlyAsWritten() {
        for probe in ConsultProbe.bank where !probe.ask.contains("{") {
            XCTAssertEqual(ConsultProbe.ask(probe, in: ConsultProbe.Context()), probe.ask)
        }
    }
}
