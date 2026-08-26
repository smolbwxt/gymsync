import XCTest
@testable import GymSync

/// Standing rules end to end: the athlete says one in the consult, it
/// lands in public.training_rules, and it comes back out somewhere the
/// athlete can see what became of it.
///
/// WHY THIS FILE CHANGED ON 2026-08-26, and it is worth reading before
/// trusting any test here.
///
/// The previous version of this suite was fully green while the feature
/// was completely dead, in two independent ways:
///
///  1. Nothing ever reached the database. `training_rules.user_id` is
///     NOT NULL with no default, the insert payload carried only `rule`
///     and `source`, so every write threw Postgres 23502 - and the one
///     call site swallowed it with `try?`. The table held zero rows from
///     the day it shipped. No test touched the repository, so the only
///     broken link was the only untested one.
///
///  2. Even given a rule, the generator could not act on it. These tests
///     asserted rules land in `advisoryNotes`, and the file's own header
///     called that one of "the two places that can act on it". It is not.
///     A repo-wide grep for `advisoryNotes` returns writers only: no
///     branch, filter, sort or scoring function in `generate()` has ever
///     read it. Rules rendered as grey body text identical to notes
///     describing decisions Coach genuinely made.
///
/// Owner 2026-08-26: "I asked if I could have each one of my sets, super
/// set with push-ups and that request was silently ignored."
///
/// So the assertions now pin the HONEST behaviour: a rule the generator
/// has no lever for is carried as an un-honoured rule, kept apart from
/// the notes, and surfaced to the athlete as something heard and not
/// built. When the generator grows real levers, rules that hit one should
/// move OUT of `unhonoredRules` - and that move is what these tests
/// should then be updated to require.
///
/// NOT TESTED HERE, deliberately rather than by omission: that the insert
/// payload carries `user_id`. `Insert` is a private nested type and the
/// repository call needs a live Supabase client, so this suite cannot
/// reach it. The compiler is the guard instead - `add` takes `userID` as
/// a required parameter, so a call site that forgets it does not build.
final class StandingRulesTests: XCTestCase {

    func testARuleReachesTheGeneratorAsAnUnhonoredRule() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["pulls before arms"])
        XCTAssertTrue(inputs.unhonoredRules.contains("pulls before arms"),
                      "the rule never reached the program")
    }

    func testARuleIsNotPassedOffAsSomethingCoachDid() {
        // The whole defect in one assertion. advisoryNotes describes what
        // the generator DID; a rule it cannot act on must not sit there,
        // because the UI renders that list as decisions.
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["keep Saturdays light"])
        XCTAssertFalse(
            inputs.advisoryNotes.contains { $0.contains("keep Saturdays light") },
            "a rule Coach cannot act on is being displayed as a decision it made")
    }

    func testTheAthletesWordsAreKeptVerbatim() {
        // No "Your rule:" prefix any more. The destination quotes them
        // under a heading that already says who said it, so a prefix
        // would only get in the way of recognising their own sentence.
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["keep Saturdays light"])
        XCTAssertEqual(inputs.unhonoredRules, ["keep Saturdays light"])
    }

    func testEveryRuleSurvives() {
        let rules = ["pulls before arms", "keep Saturdays light", "no overhead barbell"]
        let inputs = TrainingProfile().generatorInputs(durationWeeks: 8, standingRules: rules)
        for rule in rules {
            XCTAssertTrue(inputs.unhonoredRules.contains(rule), "dropped: \(rule)")
        }
    }

    func testNoRulesAddsNothing() {
        let without = TrainingProfile().generatorInputs(durationWeeks: 8)
        let withEmpty = TrainingProfile().generatorInputs(durationWeeks: 8, standingRules: [])
        XCTAssertEqual(without.advisoryNotes, withEmpty.advisoryNotes)
        XCTAssertTrue(withEmpty.unhonoredRules.isEmpty)
    }

    func testRulesDoNotDisturbTheGeneratorsOwnNotes() {
        var profile = TrainingProfile()
        // A profile that earns a generated note of its own: a bodypart
        // split below four days gets told why it cannot have one.
        profile.split = .bro
        profile.daysPerWeek = 2
        let baseline = profile.generatorInputs(durationWeeks: 8).advisoryNotes
        let withRule = profile.generatorInputs(durationWeeks: 8,
                                               standingRules: ["pulls before arms"])
        XCTAssertEqual(withRule.advisoryNotes, baseline,
                       "a standing rule changed the notes the generator wrote")
    }

    func testTheBuiltProgramCarriesTheUnhonoredRuleOut() {
        // The link that makes it visible: whatever the generator could not
        // act on has to survive onto the Program, or the destination has
        // nothing to show and the athlete is back to silence.
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 8, standingRules: ["superset every set with push-ups"])
        let program = ProgramGenerator.generate(inputs: inputs, catalog: [])
        XCTAssertEqual(program.unhonoredRules, ["superset every set with push-ups"])
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
