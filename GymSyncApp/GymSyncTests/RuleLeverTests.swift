import XCTest
@testable import GymSync

/// Do the standing-rule levers actually reach the generator's inputs?
///
/// WHY THIS FILE EXISTS. On 2026-08-26 three levers shipped — avoid,
/// swap and pairWith — and an adversarial verification pass found that
/// two of them were destroyed a few dozen lines after they were set:
///
///   TrainingProfile.generatorInputs inserted the avoided/swapped-from
///   exercise into `excludedExerciseIDs`, then reassigned that whole set
///   from the profile's own exclusions with `=`.
///
///   CoachWizardView inserted the swapped-TO exercise into
///   `starredExerciseIDs`, then reassigned that set from starred routines
///   with `=`.
///
/// Every test in the suite was green. `StandingRulesTests` builds rules
/// through a fixture that leaves `intent` as `.unknown`, so it never
/// exercised a live lever at all, and `RuleClassifierTests` stops at the
/// parse. The levers were verified as far as the classifier and no
/// further.
///
/// That is the repo's signature defect wearing a confirmation dialog: an
/// athlete typed "never overhead barbell", saw Coach read it back,
/// pressed YES BUILD IT, and got overhead barbell anyway — with an
/// `applied_at` row asserting the rule had been honoured.
///
/// So these tests assert the END of the chain, not the middle. Every one
/// of them fails against the code as it shipped this morning.
final class RuleLeverTests: XCTestCase {

    private func rule(_ intent: RuleIntent,
                      _ slots: [String: String],
                      confirmed: Bool = true) -> TrainingRule {
        var r = TrainingRule(id: UUID(), rule: "a rule the athlete typed")
        r.intent = intent
        r.slots = slots
        r.confirmed = confirmed
        return r
    }

    // MARK: The lever that was silently discarded

    func testAnAvoidedExerciseSurvivesToTheGeneratorInputs() {
        let banned = UUID()
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.avoid, ["exercise_id": banned.uuidString])])
        XCTAssertTrue(inputs.excludedExerciseIDs.contains(banned),
                      "the avoided exercise was dropped before the generator "
                    + "ever saw it — and the athlete was told it was applied")
    }

    func testAProfileExclusionAndARuleExclusionCoexist() {
        // The bug was an assignment where a union belonged. Both sources
        // are real; neither may silently win.
        let fromRule = UUID()
        var profile = TrainingProfile()
        let fromProfile = UUID()
        profile.exclusions = [TrainingProfile.Exclusion(exerciseID: fromProfile)]
        let inputs = profile.generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.avoid, ["exercise_id": fromRule.uuidString])])
        XCTAssertTrue(inputs.excludedExerciseIDs.contains(fromRule),
                      "the rule's exclusion lost to the profile's")
        XCTAssertTrue(inputs.excludedExerciseIDs.contains(fromProfile),
                      "the profile's exclusion lost to the rule's")
    }

    // MARK: Swap needs BOTH halves to survive

    func testSwapExcludesTheOldLiftAndPrefersTheNew() {
        let from = UUID(), to = UUID()
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.swap, ["from_id": from.uuidString,
                                         "to_id": to.uuidString])])
        XCTAssertTrue(inputs.excludedExerciseIDs.contains(from),
                      "swap did not exclude the lift being replaced")
        XCTAssertTrue(inputs.starredExerciseIDs.contains(to),
                      "swap did not prefer the replacement")
    }

    // MARK: The other levers reach their knobs

    func testPairWithReachesItsKnob() {
        let partner = UUID()
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.pairWith, ["exercise_id": partner.uuidString])])
        XCTAssertEqual(inputs.supersetEveryWith, partner)
    }

    func testVolumeBoundsReachTheirKnobs() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [
                rule(.capVolume, ["muscle": "Chest", "number": "20"]),
                rule(.floorVolume, ["muscle": "Back", "number": "12"]),
            ])
        XCTAssertEqual(inputs.volumeCaps["chest"], 20, "muscle keys are lowercased")
        XCTAssertEqual(inputs.volumeFloors["back"], 12)
    }

    func testOrderReachesItsKnob() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.orderBefore, ["muscle": "Back",
                                                "after_muscle": "Biceps"])])
        XCTAssertEqual(inputs.orderMuscleBefore?.first, "back")
        XCTAssertEqual(inputs.orderMuscleBefore?.then, "biceps")
    }

    // MARK: The two gates

    func testAnUnconfirmedRuleFiresNothing() {
        let banned = UUID()
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.avoid, ["exercise_id": banned.uuidString],
                                 confirmed: false)])
        XCTAssertFalse(inputs.excludedExerciseIDs.contains(banned),
                       "a reading the athlete never agreed to reshaped their "
                     + "training")
        XCTAssertEqual(inputs.unhonoredRules.count, 1,
                       "and it must still be reported rather than vanish")
    }

    func testAConditionedRuleFiresNothingAndIsReported() {
        let banned = UUID()
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.avoid, ["exercise_id": banned.uuidString,
                                          "condition": "my knees ache"])])
        XCTAssertFalse(inputs.excludedExerciseIDs.contains(banned),
                       "Coach cannot read the athlete's knees and must not "
                     + "pretend otherwise")
        XCTAssertEqual(inputs.unhonoredRules.count, 1)
    }

    func testAnUnbuildableIntentIsReportedNotDropped() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8,
            standingRules: [rule(.lightDay, ["muscle": "Saturday"])])
        XCTAssertEqual(inputs.unhonoredRules.count, 1,
                       "an intent with no lever must reach the athlete as "
                     + "heard-not-built, never silence")
    }
}
