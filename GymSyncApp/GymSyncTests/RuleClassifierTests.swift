import XCTest
@testable import GymSync

/// Reading a typed rule into something the generator can act on.
///
/// The model call itself is not testable here — CI runs an Xcode where
/// `canImport(FoundationModels)` is false, so on this machine every
/// classification returns `.unknown`. What IS testable, and what actually
/// decides whether an athlete's rule reaches their program, is the parse
/// and the catalog resolution. Both live behind `parse(_:catalog:)` for
/// exactly that reason.
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
        ex("Single-Arm Dumbbell Row"), ex("Leg Extension"),
    ]

    // MARK: The owner's rule

    func testPairResolvesTheOwnersActualRequest() {
        let reading = RuleClassifier.parse("PAIR push-ups", catalog: catalog)
        XCTAssertEqual(reading.intent, .pairWith)
        XCTAssertEqual(reading.slots["exercise_name"], "Push-Up",
                       "\"push-ups\" has to find \"Push-Up\" or the lever "
                     + "points at nothing")
        XCTAssertNotNil(reading.slots["exercise_id"])
    }

    func testAvoidResolvesToTheSameCatalogRow() {
        let reading = RuleClassifier.parse("AVOID leg extension", catalog: catalog)
        XCTAssertEqual(reading.intent, .avoid)
        XCTAssertEqual(reading.slots["exercise_name"], "Leg Extension")
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

    // MARK: Everything else falls to unknown, on purpose

    func testUnknownStaysUnknown() {
        XCTAssertEqual(RuleClassifier.parse("UNKNOWN", catalog: catalog).intent,
                       .unknown)
    }

    func testGarbageIsNotForcedIntoAnIntent() {
        for line in ["", "   ", "PAIR", "ORDER back", "LIGHT",
                     "please superset my pushups", "MAYBE push-ups"] {
            XCTAssertEqual(RuleClassifier.parse(line, catalog: catalog).intent,
                           .unknown, "forced an intent out of: \(line)")
        }
    }

    func testOrderAndLightAreReadButNotBuildable() {
        // Both are real asks the generator has no lever for. They must
        // still classify — that is what puts them in the queue of levers
        // worth building — while reporting themselves as not buildable.
        let order = RuleClassifier.parse("ORDER back biceps", catalog: catalog)
        XCTAssertEqual(order.intent, .orderBefore)
        XCTAssertFalse(order.intent.isBuildable)

        let light = RuleClassifier.parse("LIGHT Saturday", catalog: catalog)
        XCTAssertEqual(light.intent, .lightDay)
        XCTAssertFalse(light.intent.isBuildable)
    }

    // MARK: The registry

    func testOnlyTheLeversThatExistReportBuildable() {
        // This is the registry the whole design turns on: buildability is
        // a property of THIS build, so a lever shipping later upgrades
        // every rule ever recorded with that intent. If you add a lever,
        // this assertion is the one to update.
        XCTAssertTrue(RuleIntent.pairWith.isBuildable)
        XCTAssertTrue(RuleIntent.avoid.isBuildable)
        XCTAssertFalse(RuleIntent.orderBefore.isBuildable)
        XCTAssertFalse(RuleIntent.lightDay.isBuildable)
        XCTAssertFalse(RuleIntent.unknown.isBuildable)
    }

    func testAnUnconfirmedReadingNeverCountsAsBuilt() {
        // The confirmation gate. A reading the athlete has not agreed to
        // must not fire a lever, however confident the model was.
        var rule = TrainingRule(id: UUID(), rule: "superset with push-ups")
        rule.intent = .pairWith
        rule.confirmed = false
        XCTAssertFalse(rule.isWaitingToBeBuilt)
        XCTAssertTrue(rule.needsConfirmation)

        rule.confirmed = true
        XCTAssertTrue(rule.isWaitingToBeBuilt)
        XCTAssertFalse(rule.needsConfirmation)
    }
}
