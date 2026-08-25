import XCTest
@testable import GymSync

/// Rules encoded from published position stands (corpus area
/// 'guideline'). These are the two the 2026-08-25 research settled, and
/// both close defects the 40-persona stress test found: a 13-year-old
/// inheriting adult ceilings, and a returning lifter inheriting their own
/// pre-layoff training age.
final class GuidelineRulesTests: XCTestCase {

    // MARK: - NSCA youth intensity ceilings

    func testYouthCeilingsSitUnderAdultCeilings() {
        for experience in GeneratorScience.Experience.allCases {
            let youth = GeneratorScience.mainIntensityCeiling(experience: experience, isYouth: true)
            let adult = GeneratorScience.mainIntensityCeiling(experience: experience, isYouth: false)
            XCTAssertLessThanOrEqual(youth, adult,
                "a youth ceiling must never exceed the adult one (\(experience))")
        }
    }

    func testYouthCeilingsTakeTheStricterOfTheTwoSources() {
        // NSCA Table 2 tops each youth band at 70 / 80 / 85% 1RM. Our own
        // trainer audit had already pulled the ADULT novice ceiling to
        // 67.5, which is stricter than NSCA's youth novice number — so the
        // youth rule is a floor, not a substitution.
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .new, isYouth: true), 67.5,
                       "our stricter novice ceiling wins over NSCA's 70")
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .intermediate, isYouth: true), 80,
                       "NSCA binds here — 80 is below our adult 87.5")
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .advanced, isYouth: true), 85,
                       "NSCA binds here — 85 is well below our adult 92.5")
    }

    func testAdvancedYouthIsCappedWellBelowAdvancedAdult() {
        // The specific defect: a 16-year-old with a year of training used
        // to inherit 92.5%.
        let youth = GeneratorScience.mainIntensityCeiling(experience: .advanced, isYouth: true)
        let adult = GeneratorScience.mainIntensityCeiling(experience: .advanced, isYouth: false)
        XCTAssertEqual(youth, 85)
        XCTAssertEqual(adult, 92.5)
        XCTAssertGreaterThan(adult - youth, 5)
    }

    func testAdultCeilingsUnchangedByTheYouthAddition() {
        // Regression guard: adding the youth branch must not move the
        // adult numbers the 2026-08-16 trainer audit set.
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .new), 67.5)
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .intermediate), 87.5)
        XCTAssertEqual(GeneratorScience.mainIntensityCeiling(experience: .advanced), 92.5)
    }

    // MARK: - Training-age decay on layoff

    func testLongLayoffResetsAnAdvancedLifterToNovice() {
        // NSCA: novice includes "an individual who has not trained for
        // several months", regardless of what they once were.
        let decayed = GeneratorScience.decayedExperience(stated: .advanced,
                                                         daysSinceLastSession: 400)
        XCTAssertEqual(decayed, .new)
    }

    func testLayoffAtTheThresholdResets() {
        let decayed = GeneratorScience.decayedExperience(
            stated: .advanced, daysSinceLastSession: GeneratorScience.layoffResetDays)
        XCTAssertEqual(decayed, .new)
    }

    func testShortLayoffDoesNotDemote() {
        // Deliberate: shorter returns are governed by LOAD (return at
        // RPE 5-6), not by re-labelling the lifter. Demoting here would be
        // interpolation dressed as a guideline.
        let decayed = GeneratorScience.decayedExperience(stated: .advanced,
                                                         daysSinceLastSession: 30)
        XCTAssertEqual(decayed, .advanced)
    }

    func testUnknownLastSessionLeavesTheStatedValueAlone() {
        // A lifter with no logged history yet must not be silently
        // demoted — absence of data is not evidence of a layoff.
        XCTAssertEqual(GeneratorScience.decayedExperience(stated: .intermediate,
                                                          daysSinceLastSession: nil),
                       .intermediate)
    }

    func testDecayIsIdempotentForANovice() {
        XCTAssertEqual(GeneratorScience.decayedExperience(stated: .new,
                                                          daysSinceLastSession: 999),
                       .new)
    }
}
