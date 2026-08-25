import XCTest
@testable import GymSync

/// Standing rules end to end: the athlete says one in the consult, it
/// lands in public.training_rules, and it comes back out in the two
/// places that can act on it — the generator's advisory notes and Coach's
/// instruction rail.
///
/// The flow is worth a test of its own because every previous piece of it
/// existed in isolation: the table had no reader, generatorInputs derived
/// advisoryNotes fresh every call with no way to add one, and Coach had
/// no idea the athlete had ever asked for anything.
final class StandingRulesTests: XCTestCase {

    func testARuleReachesTheGeneratorAsAnAdvisoryNote() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["pulls before arms"])
        XCTAssertTrue(inputs.advisoryNotes.contains { $0.contains("pulls before arms") },
                      "the rule never reached the program")
    }

    func testTheRuleIsAttributedBackToTheAthlete() {
        // Prefixed so they recognise their own words coming back, rather
        // than reading it as something the app decided.
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["keep Saturdays light"])
        XCTAssertTrue(inputs.advisoryNotes.contains("Your rule: keep Saturdays light"))
    }

    func testEveryRuleSurvives() {
        let rules = ["pulls before arms", "keep Saturdays light", "no overhead barbell"]
        let inputs = TrainingProfile().generatorInputs(durationWeeks: 8, standingRules: rules)
        for rule in rules {
            XCTAssertTrue(inputs.advisoryNotes.contains { $0.contains(rule) },
                          "dropped: \(rule)")
        }
    }

    func testNoRulesAddsNoNotes() {
        // The generator writes its own advisory notes; rules must add to
        // them without disturbing them.
        let without = TrainingProfile().generatorInputs(durationWeeks: 8)
        let withEmpty = TrainingProfile().generatorInputs(durationWeeks: 8, standingRules: [])
        XCTAssertEqual(without.advisoryNotes, withEmpty.advisoryNotes)
    }

    func testRulesDoNotReplaceTheGeneratorsOwnNotes() {
        var profile = TrainingProfile()
        // A profile that earns a generated note of its own: a bodypart
        // split below four days gets told why it cannot have one.
        profile.split = .bro
        profile.daysPerWeek = 2
        let baseline = profile.generatorInputs(durationWeeks: 8).advisoryNotes
        let withRule = profile.generatorInputs(durationWeeks: 8,
                                               standingRules: ["pulls before arms"])
        XCTAssertTrue(baseline.allSatisfy { withRule.advisoryNotes.contains($0) },
                      "a standing rule displaced a note the generator wrote")
        XCTAssertEqual(withRule.advisoryNotes.count, baseline.count + 1)
    }

    // MARK: - What the consult hands over

    func testTheConsultOnlyHandsOverRulesWorthKeeping() {
        let answers = ConsultAnswers(["standing_rule": [
            "  pulls before arms  ",              // trimmed
            "   ",                                 // dropped
            String(repeating: "x", count: 281),    // over the column's CHECK
        ]])
        XCTAssertEqual(answers.standingRules, ["pulls before arms"])
    }

    func testARuleAtTheLengthLimitIsKept() {
        // 280 exactly — the boundary the column allows.
        let atLimit = String(repeating: "x", count: 280)
        XCTAssertEqual(ConsultAnswers(["standing_rule": [atLimit]]).standingRules, [atLimit])
    }
}
