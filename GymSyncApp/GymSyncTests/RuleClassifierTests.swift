import XCTest
@testable import GymSync

/// Reading a typed rule into something the generator can act on.
///
/// The model call itself is not testable here — CI runs an Xcode where
/// `canImport(FoundationModels)` is false, so on this machine every
/// classification returns `.unknown`. What IS testable, and what actually
/// decides whether an athlete's rule reaches their program, is the parse,
/// the catalog resolution, and the buildability registry. All three live
/// behind pure functions for exactly that reason.
///
/// The bias under test throughout: when in doubt, `.unknown`. A rule read
/// wrongly silently reshapes someone's training and gives them no reason
/// to suspect the rule was why; a rule read as unknown just gets asked
/// about. So every ambiguous case here asserts the cautious answer.
final class RuleClassifierTests: XCTestCase {

    // Same fixture shape as ConsultFocusTests.
    private func ex(_ name: String) -> Exercise {
        Exercise(id: UUID(), name: name, slug: name.lowercased(),
                 category: "compound", primaryMuscle: "chest",
                 secondaryMuscles: [], equipment: "bodyweight",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private lazy var catalog: [Exercise] = [
        ex("Push-Up"), ex("Bench Press"), ex("Row"),
        ex("Single-Arm Dumbbell Row"), ex("Leg Extension"), ex("Hack Squat"),
    ]

    // MARK: The owner's rule

    func testPairResolvesTheOwnersActualRequest() {
        let reading = RuleClassifier.parse("PAIR push-ups", catalog: catalog)
        XCTAssertEqual(reading.intent, .pairWith)
        XCTAssertEqual(reading.slots["exercise_name"], "Push-Up",
                       "\"push-ups\" has to find \"Push-Up\" or the lever "
                     + "points at nothing")
        XCTAssertTrue(reading.intent.isBuildable(slots: reading.slots))
    }

    // MARK: Resolution has to be conservative

    func testAnExactNameBeatsALongerContainingOne() {
        // "Row" must not resolve to "Single-Arm Dumbbell Row" — avoiding
        // the wrong lift is a silent, wrong change to their program.
        let reading = RuleClassifier.parse("AVOID row", catalog: catalog)
        XCTAssertEqual(reading.slots["exercise_name"], "Row")
    }

    func testAnUnknownExerciseIsNotGuessedAt() {
        // A lever pointed at no exercise is worse than no lever: it would
        // read as honoured and do nothing.
        let reading = RuleClassifier.parse("PAIR zercher carries", catalog: catalog)
        XCTAssertEqual(reading.intent, .unknown)
        XCTAssertTrue(reading.slots.isEmpty)
    }

    // MARK: The shapes the grammar wave found

    func testSwapNeedsBothSidesToResolve() {
        let ok = RuleClassifier.parse("SWAP bench press FOR push-ups", catalog: catalog)
        XCTAssertEqual(ok.intent, .swap)
        XCTAssertEqual(ok.slots["from_name"], "Bench Press")
        XCTAssertEqual(ok.slots["to_name"], "Push-Up")
        XCTAssertTrue(ok.intent.isBuildable(slots: ok.slots))

        // Half a swap is not a swap: excluding a lift without naming a
        // replacement would quietly shrink the program.
        let half = RuleClassifier.parse("SWAP bench press FOR zercher carries",
                                        catalog: catalog)
        XCTAssertEqual(half.intent, .unknown)
    }

    func testSwappingSomethingForItselfIsRefused() {
        let same = RuleClassifier.parse("SWAP row FOR row", catalog: catalog)
        XCTAssertEqual(same.intent, .unknown, "a no-op swap would exclude and "
                     + "star the same lift, which cancels to nothing")
    }

    func testVolumeBoundsCarryAMuscleAndANumber() {
        let cap = RuleClassifier.parse("CAP chest 20", catalog: catalog)
        XCTAssertEqual(cap.intent, .capVolume)
        XCTAssertEqual(cap.slots["muscle"], "chest")
        XCTAssertEqual(cap.slots["number"], "20")
        XCTAssertTrue(cap.intent.isBuildable(slots: cap.slots))

        let floor = RuleClassifier.parse("FLOOR back 12", catalog: catalog)
        XCTAssertEqual(floor.intent, .floorVolume)
        XCTAssertTrue(floor.intent.isBuildable(slots: floor.slots))
    }

    func testAnImplausibleSetCountIsRefused() {
        // 400 sets a week is a misparse, not a rule. Building it would
        // hand someone an unrunnable week.
        for line in ["CAP chest 400", "CAP chest 0", "FLOOR back -3",
                     "CAP chest many"] {
            XCTAssertEqual(RuleClassifier.parse(line, catalog: catalog).intent,
                           .unknown, "accepted an implausible bound: \(line)")
        }
    }

    func testOrderNeedsTwoDifferentMuscles() {
        let ok = RuleClassifier.parse("ORDER back biceps", catalog: catalog)
        XCTAssertEqual(ok.intent, .orderBefore)
        XCTAssertTrue(ok.intent.isBuildable(slots: ok.slots))

        XCTAssertEqual(RuleClassifier.parse("ORDER back back", catalog: catalog).intent,
                       .unknown, "ordering a muscle before itself is a misparse")
    }

    // MARK: The condition dimension

    func testAConditionIsCapturedAndBlocksTheLever() {
        // The wave's central finding: `conditional` is not a predicate,
        // it is a modifier on other predicates. Coach can read the rule
        // precisely and still not act, because it cannot check elbows.
        let reading = RuleClassifier.parse(
            "SWAP bench press FOR push-ups WHEN elbows hurt", catalog: catalog)
        XCTAssertEqual(reading.intent, .swap, "the predicate still parses")
        XCTAssertEqual(reading.slots["condition"], "elbows hurt")
        XCTAssertFalse(reading.intent.isBuildable(slots: reading.slots),
                       "a condition Coach cannot evaluate must block the lever")
    }

    func testTheReadingSaysWhichPartCannotBeChecked() {
        let reading = RuleClassifier.parse("AVOID leg extension WHEN knees ache",
                                           catalog: catalog)
        let sentence = reading.intent.reading(slots: reading.slots)
        XCTAssertTrue(sentence.contains("knees ache"),
                      "the athlete has to see the condition Coach read")
        XCTAssertTrue(sentence.lowercased().contains("cannot check"),
                      "and has to be told it is the part Coach cannot act on")
    }

    func testAConditionOnGarbageStaysUnknown() {
        // A trigger does not rescue a predicate that did not parse.
        let reading = RuleClassifier.parse("MAYBE something WHEN tired",
                                           catalog: catalog)
        XCTAssertEqual(reading.intent, .unknown)
        XCTAssertNil(reading.slots["condition"])
    }

    // MARK: Everything else falls to unknown, on purpose

    func testGarbageIsNotForcedIntoAnIntent() {
        for line in ["", "   ", "PAIR", "ORDER back", "LIGHT", "SWAP",
                     "SWAP bench press", "CUE", "please superset my pushups"] {
            XCTAssertEqual(RuleClassifier.parse(line, catalog: catalog).intent,
                           .unknown, "forced an intent out of: \(line)")
        }
    }

    // MARK: The registry

    func testBuildabilityIsKeyedOnSlotsNotOnTheNameAlone() {
        // The correction the grammar wave forced. `avoid` was typed for an
        // exercise; the corpus overwhelmingly says avoid(activity) — "don't
        // let your form degrade". Same predicate name, no exercise to
        // exclude. A name-keyed registry would report itself complete
        // while failing on that input.
        XCTAssertTrue(RuleIntent.avoid.isBuildable(
            slots: ["exercise_id": UUID().uuidString]))
        XCTAssertFalse(RuleIntent.avoid.isBuildable(
            slots: ["activity": "letting your form degrade"]))
        XCTAssertFalse(RuleIntent.avoid.isBuildable(slots: nil))
    }

    func testTheStillUnbuildableCasesSayNoRegardlessOfSlots() {
        // Both are blocked for STRUCTURAL reasons, not missing code:
        // lightDay needs weekday identity the generator does not have,
        // and cue needs a render site because RoutineExercise.notes is
        // carried everywhere and displayed nowhere.
        XCTAssertFalse(RuleIntent.lightDay.isBuildable(slots: ["muscle": "Saturday"]))
        XCTAssertFalse(RuleIntent.cue.isBuildable(
            slots: ["exercise_id": UUID().uuidString, "technique": "control it"]))
        XCTAssertFalse(RuleIntent.unknown.isBuildable(slots: [:]))
    }

    func testAnUnconfirmedReadingNeverCountsAsBuilt() {
        // The confirmation gate. A reading the athlete has not agreed to
        // must not fire a lever, however confident the model was.
        var rule = TrainingRule(id: UUID(), rule: "superset with push-ups")
        rule.intent = .pairWith
        rule.slots = ["exercise_id": UUID().uuidString]
        rule.confirmed = false
        XCTAssertFalse(rule.isWaitingToBeBuilt)
        XCTAssertTrue(rule.needsConfirmation)

        rule.confirmed = true
        XCTAssertTrue(rule.isWaitingToBeBuilt)
        XCTAssertFalse(rule.needsConfirmation)
    }

    func testUnderstoodButUnbuildableIsItsOwnState() {
        // The state that most needs saying out loud: a confirmed reading
        // implies action, so "I understood you, you agreed, and I did
        // nothing" is worse than an honest unknown.
        var rule = TrainingRule(id: UUID(), rule: "keep Saturdays light")
        rule.intent = .lightDay
        rule.slots = ["muscle": "Saturday"]
        rule.confirmed = true
        XCTAssertTrue(rule.understoodButUnbuildable)
        XCTAssertFalse(rule.isWaitingToBeBuilt)
    }
}
