import XCTest
@testable import GymSync

/// The window that keeps a returning lifter on novice ceilings after
/// their first session back.
///
/// This exists because the layoff rule had a hole big enough to drive the
/// original defect straight back through: `decayedExperience` guarded on
/// days since the LAST SESSION, so a lifter two years away reset to
/// novice — and then trained once, which made that number zero, which
/// handed them advanced ceilings in week one. The safety rule lasted
/// exactly one session.
final class ReacquisitionTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * day)
    }

    // MARK: - The hole this closes

    func testALifterBackOneSessionIsStillANovice() {
        // The defect, stated as a test: trained once yesterday after two
        // years away. Days since last session is 1, which used to be all
        // the rule looked at.
        let experience = GeneratorScience.decayedExperience(
            stated: .advanced, daysSinceLastSession: 1, daysSinceReturn: 1)
        XCTAssertEqual(experience, .new,
                       "one session back must not restore advanced ceilings")
    }

    func testTheWindowExpiresAndTheirTrainingAgeComesBack() {
        // They are not demoted forever — muscle memory is real and they
        // climb fast. The window governs where they START.
        let experience = GeneratorScience.decayedExperience(
            stated: .advanced, daysSinceLastSession: 2,
            daysSinceReturn: GeneratorScience.reacquisitionWeeks * 7)
        XCTAssertEqual(experience, .advanced)
    }

    func testTheLastDayInsideTheWindowStillHolds() {
        let experience = GeneratorScience.decayedExperience(
            stated: .advanced, daysSinceLastSession: 2,
            daysSinceReturn: GeneratorScience.reacquisitionWeeks * 7 - 1)
        XCTAssertEqual(experience, .new)
    }

    func testStillAwayOutranksEverything() {
        let experience = GeneratorScience.decayedExperience(
            stated: .advanced, daysSinceLastSession: 400, daysSinceReturn: nil)
        XCTAssertEqual(experience, .new)
    }

    func testNoLayoffMeansNoDemotion() {
        // Absence of a return is not evidence of a layoff.
        XCTAssertEqual(
            GeneratorScience.decayedExperience(stated: .advanced,
                                               daysSinceLastSession: 3,
                                               daysSinceReturn: nil),
            .advanced)
    }

    func testTheOldCallSignatureStillBehaves() {
        // daysSinceReturn defaults to nil, so every existing caller keeps
        // the behaviour it was written against.
        XCTAssertEqual(
            GeneratorScience.decayedExperience(stated: .advanced,
                                               daysSinceLastSession: 400),
            .new)
        XCTAssertEqual(
            GeneratorScience.decayedExperience(stated: .advanced,
                                               daysSinceLastSession: 10),
            .advanced)
    }

    // MARK: - Finding the return in the log

    func testTheReturnIsFoundWithoutAsking() {
        // "When did you come back" is a question the app can answer for
        // itself, and an athlete mid-comeback is the least likely person
        // to answer it accurately.
        let dates = [daysAgo(900), daysAgo(880), daysAgo(10), daysAgo(3)]
        XCTAssertEqual(GeneratorScience.daysSinceReturn(sessionDates: dates, now: now), 10)
    }

    func testAnUnbrokenLogHasNoReturn() {
        let dates = (0..<20).map { daysAgo($0 * 3) }
        XCTAssertNil(GeneratorScience.daysSinceReturn(sessionDates: dates, now: now))
    }

    func testTheMostRecentLayoffWins() {
        // Someone who has come back twice is judged on the latest return.
        let dates = [daysAgo(1400), daysAgo(1000), daysAgo(700), daysAgo(5)]
        XCTAssertEqual(GeneratorScience.daysSinceReturn(sessionDates: dates, now: now), 5)
    }

    func testASingleSessionCannotDefineAGap() {
        XCTAssertNil(GeneratorScience.daysSinceReturn(sessionDates: [daysAgo(2)], now: now))
        XCTAssertNil(GeneratorScience.daysSinceReturn(sessionDates: [], now: now))
    }

    func testAGapJustUnderTheThresholdIsNotALayoff() {
        let dates = [daysAgo(300), daysAgo(300 - GeneratorScience.layoffResetDays + 1)]
        XCTAssertNil(GeneratorScience.daysSinceReturn(sessionDates: dates, now: now))
    }

    func testSameDaySessionsCollapse() {
        // Two sessions on one day are one training day, same as cadence.
        let dates = [daysAgo(400), daysAgo(400), daysAgo(2), daysAgo(2)]
        XCTAssertEqual(GeneratorScience.daysSinceReturn(sessionDates: dates, now: now), 2)
    }

    // MARK: - What the returner actually gets

    func testAReturnerStartsOnNoviceCeilings() {
        var profile = TrainingProfile()
        profile.trainingAge = .advanced
        let inputs = profile.generatorInputs(durationWeeks: 8,
                                             daysSinceLastSession: 2,
                                             daysSinceReturn: 3)
        XCTAssertEqual(inputs.experience, .new)
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: inputs.experience),
                       67.5)
    }

    func testUndershootingVolumeOnReturnIsDeliberateNotADefect() {
        // The corpus is explicit and rates it STRONG: "when resuming after
        // a layoff, undershoot rather than overshoot volume and load —
        // undershooting still yields the protective repeated-bout
        // adaptation, while overshooting raises fatigue, soreness, and
        // hurts near-term performance." A returner landing on the beginner
        // set budget is the rule working, not the rule failing.
        var profile = TrainingProfile()
        profile.trainingAge = .advanced
        let inputs = profile.generatorInputs(durationWeeks: 8,
                                             daysSinceLastSession: 2,
                                             daysSinceReturn: 3)
        XCTAssertEqual(inputs.experience, .new,
                       "the beginner volume override is keyed off this")
    }
}
