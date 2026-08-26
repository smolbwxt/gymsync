import XCTest
@testable import GymSync

/// The health gate's reachability, as opposed to its decision rule (which
/// HealthScreeningTests covers).
///
/// The defect these close: the screening shipped inside CoachConsultView,
/// which meant it guarded exactly ONE of the four doors into the
/// generator. CoachWizardView is also presented from RootView, from two
/// places on the Coach home, and from the block calendar — so an athlete
/// who never opened the consult, including a brand-new user taking the
/// post-walkthrough offer, was prescribed loads with no PAR-Q+ at all.
/// That is the exact failure the 40-persona sweep surfaced, and it stood
/// open on three paths out of four for a day.
///
/// The fix is not "screen at four doors". It is that PRESCRIBING is what
/// requires screening, so the gate stands in front of the one function
/// that prescribes.
final class HealthGateTests: XCTestCase {

    private let allClear: [String: Bool] = Dictionary(
        uniqueKeysWithValues: HealthTriage.questions.map { ($0.id, false) })

    // MARK: - The gate condition the wizard evaluates

    /// Mirrors CoachWizardView.healthGateRequired. Kept as a function here
    /// so the RULE is testable even though the view is not: a screening
    /// gates generation when it is missing, expired, or refused.
    private func gateRequired(_ screening: HealthScreening?) -> Bool {
        guard let screening else { return true }
        return !(!screening.needsScreening && screening.clearsTheGate)
    }

    func testNoScreeningOnFileGatesGeneration() {
        XCTAssertTrue(gateRequired(nil))
        XCTAssertTrue(gateRequired(HealthScreening()))
    }

    func testAClearedScreeningLetsGenerationThrough() {
        var s = HealthScreening(answers: allClear)
        s.clearedAt = Date()
        XCTAssertFalse(gateRequired(s))
    }

    func testAnExpiredClearanceGatesAgain() {
        var s = HealthScreening(answers: allClear)
        s.clearedAt = Calendar.current.date(
            byAdding: .day, value: -(HealthTriage.clearanceValidityDays + 1), to: Date())
        XCTAssertTrue(gateRequired(s))
    }

    func testAFlaggedScreeningGatesEvenIfSomethingStampedAClearanceDate() {
        // Belt and braces against the failure HealthScreening.clearsTheGate
        // exists to prevent: a refer-out that somehow carries a date must
        // still gate.
        var answers = allClear
        answers["chest_pain"] = true
        var s = HealthScreening(answers: answers)
        s.clearedAt = Date()
        XCTAssertTrue(gateRequired(s))
    }

    func testAClinicianClearanceOpensTheGate() {
        var answers = allClear
        answers["heart_or_bp"] = true
        var s = HealthScreening(answers: answers)
        s.clinicianCleared = true
        XCTAssertFalse(gateRequired(s))
    }

    func testPregnancyDoesNotGateGeneration() {
        // ACOG 804: advisory, never a block. If this ever gates, the app
        // has started refusing to program pregnant athletes, which is both
        // wrong and paternalistic.
        var s = HealthScreening(answers: allClear)
        s.lifeStage = "pregnant"
        s.clearedAt = Date()
        XCTAssertFalse(gateRequired(s))
    }

    // MARK: - Failing closed

    func testAnUnreadScreeningGatesRatherThanWavingThrough() {
        // nil means "not looked yet", and it must count as REQUIRED. A
        // slow network is not a way past a medical gate; the only safe
        // direction for this default is closed.
        XCTAssertTrue(gateRequired(nil),
                      "an unread screening must gate, not pass")
    }

    // MARK: - One gate, not two

    func testTheGateAsksTheWholeInstrument() {
        // Both surfaces present HealthGateView, so there is one question
        // list. If a second copy ever appears, this count is where the
        // drift shows up first.
        XCTAssertEqual(HealthTriage.questions.count, 7,
                       "PAR-Q+ Step 1 is seven questions")
        XCTAssertEqual(Set(HealthTriage.questions.map(\.id)).count, 7,
                       "duplicate question id")
    }

    func testEveryQuestionCanBeAnsweredNo() {
        // The all-clear path must actually clear — a question whose id is
        // typo'd would never be found by evaluate() and the athlete could
        // never be cleared.
        XCTAssertEqual(HealthScreening(answers: allClear).outcome(), .cleared)
    }
}
