import XCTest
@testable import GymSync

/// The stored side of the health gate. HealthTriage's decision rule was
/// already tested; what was untested — because it did not exist — is
/// whether the app REMEMBERS the decision, and whether a flagged athlete
/// can be silently waved through later.
final class HealthScreeningTests: XCTestCase {

    private let allClear: [String: Bool] = Dictionary(
        uniqueKeysWithValues: HealthTriage.questions.map { ($0.id, false) })

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - When we must ask

    func testAnAthleteWhoHasNeverBeenScreenedMustBe() {
        XCTAssertTrue(HealthScreening().needsScreening)
    }

    func testRecentClearanceIsNotReAsked() {
        var s = HealthScreening(answers: allClear)
        s.clearedAt = daysAgo(30)
        XCTAssertFalse(s.needsScreening)
    }

    func testClearanceExpiresAtTwelveMonths() {
        // PAR-Q+ clearance is not permanent.
        var s = HealthScreening(answers: allClear)
        s.clearedAt = daysAgo(HealthTriage.clearanceValidityDays + 1)
        XCTAssertTrue(s.needsScreening)
    }

    func testAClinicianClearanceSurvivesExpiry() {
        // Deliberate: making someone re-answer the PAR-Q+ every year after
        // their doctor already signed off trains them to click through it.
        var s = HealthScreening()
        s.clinicianCleared = true
        s.clearedAt = daysAgo(900)
        XCTAssertFalse(s.needsScreening)
    }

    // MARK: - The gate

    func testAllNoClearsTheGate() {
        XCTAssertTrue(HealthScreening(answers: allClear).clearsTheGate)
        XCTAssertEqual(HealthScreening(answers: allClear).outcome(), .cleared)
    }

    func testASingleFlagClosesTheGate() {
        // The persona-sweep defect: the app would have programmed someone
        // post-cardiac-event.
        var answers = allClear
        answers["heart_or_bp"] = true
        let s = HealthScreening(answers: answers)
        XCTAssertFalse(s.clearsTheGate)
        XCTAssertEqual(s.outcome(), .referOut(flagged: ["heart_or_bp"]))
    }

    func testASoftFlagOpensAFollowUpAndStillDoesNotClear() {
        // PAR-Q+ Step 1 routes; it does not decide. A chronic condition
        // now opens a follow-up instead of refusing forever — but an
        // unfinished screening must never read as a clearance.
        let s = HealthScreening(answers: allClear.merging(["medication": true]) { _, b in b })
        guard case .incomplete = s.outcome() else {
            return XCTFail("a controlled condition was refused outright")
        }
        XCTAssertFalse(s.clearsTheGate)
    }

    func testAReferOutNeverStampsAClearanceClock() {
        // The rule this whole property exists for: if a flagged screening
        // stamped cleared_at, the athlete's NEXT visit would find a valid
        // clearance and wave them straight through.
        var answers = allClear
        answers["chest_pain"] = true
        var s = HealthScreening(answers: answers)
        s.clearedAt = Date()          // even if something set it
        XCTAssertFalse(s.clearsTheGate, "a flagged screening must not read as cleared")
    }

    func testAStandingFlagSurvivesAndStillNeedsScreening() {
        // Coach does not forget what it was told between launches.
        var answers = allClear
        answers["supervised_only"] = true
        let s = HealthScreening(answers: answers)
        XCTAssertTrue(s.needsScreening)
        if case .referOut = s.outcome() {} else {
            XCTFail("a stored flag must still refer out")
        }
    }

    // MARK: - The way back in

    func testAClinicianClearanceReopensTheGateDespiteFlags() {
        // A refer-out is not a dead end — it is a conversation Coach asked
        // them to have.
        var answers = allClear
        answers["heart_or_bp"] = true
        var s = HealthScreening(answers: answers)
        s.clinicianCleared = true
        XCTAssertTrue(s.clearsTheGate)
        XCTAssertEqual(s.outcome(), .cleared)
    }

    // MARK: - Life stage is advisory, never a block

    func testPregnancyClearsWithAnAdvisory() {
        // Corrected 2026-08-25: the first pass read PAR-Q+'s "talk to your
        // practitioner" as a stop sign. ACOG 804 encourages training.
        var s = HealthScreening(answers: allClear)
        s.lifeStage = "pregnant"
        XCTAssertTrue(s.clearsTheGate)
        XCTAssertEqual(s.outcome(), .clearedWithAdvisory(HealthTriage.pregnancyAdvisory))
    }

    func testPostpartumClearsWithAnAdvisory() {
        var s = HealthScreening(answers: allClear)
        s.lifeStage = "postpartum"
        XCTAssertTrue(s.clearsTheGate)
        XCTAssertEqual(s.outcome(), .clearedWithAdvisory(HealthTriage.postpartumAdvisory))
    }

    func testARealFlagStillOutranksLifeStage() {
        // Pregnancy does not make a heart condition go away.
        var answers = allClear
        answers["heart_or_bp"] = true
        var s = HealthScreening(answers: answers)
        s.lifeStage = "pregnant"
        XCTAssertFalse(s.clearsTheGate)
    }

    func testAnUnknownLifeStageIsSimplyNoStage() {
        var s = HealthScreening(answers: allClear)
        s.lifeStage = "nonsense"
        XCTAssertNil(s.stage)
        XCTAssertEqual(s.outcome(), .cleared)
    }

    // MARK: - Copy

    func testTheAdvisoriesReadAsSentencesNotAsSourceLayout() {
        // These render straight into a Text view at a sensitive moment; a
        // run of spaces mid-sentence is a visible defect, and the multi-
        // line literals had exactly that until it was caught.
        for copy in [HealthTriage.pregnancyAdvisory, HealthTriage.postpartumAdvisory] {
            XCTAssertFalse(copy.contains("  "), "stray space run in: \(copy)")
            XCTAssertFalse(copy.isEmpty)
        }
    }

    func testTheReferralNamesTheHeartWhenTheHeartIsWhyWeStopped() {
        let copy = HealthTriage.referralCopy(flagged: ["heart_or_bp"])
        XCTAssertTrue(copy.contains("your heart"))
        // Never leaves them with nothing.
        XCTAssertTrue(copy.contains("still works"))
    }

    func testTheReferralStaysVagueWhenTheFlagIsNotCardiac() {
        let copy = HealthTriage.referralCopy(flagged: ["musculoskeletal"])
        XCTAssertFalse(copy.contains("your heart"),
                       "naming the heart for a knee would imply a diagnosis")
    }
}
