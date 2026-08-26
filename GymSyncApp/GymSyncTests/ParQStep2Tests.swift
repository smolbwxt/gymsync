import XCTest
@testable import GymSync

/// PAR-Q+ Step 2, and the bypass that sat underneath it.
///
/// Two defects in tension, which is why they had to land together:
///
///   OVER-REFER — Step 1 is a ROUTER, not a verdict. Its own rule: all
///   seven NO clears; any YES routes to the FOLLOW-UP pages or a
///   clinician. We shipped only the second branch, so one YES refused to
///   program someone forever. A person on levothyroxine got byte-identical
///   treatment to unstable angina.
///
///   BYPASS — a refused athlete has no cleared_at, so needsScreening is
///   true for them forever, and the gate checked THAT first. A refusal
///   handed the questions straight back and answering differently walked
///   through. Closing this alone would have made the over-refer permanent;
///   fixing over-refer alone would have left the bypass open.
final class ParQStep2Tests: XCTestCase {

    private let allClear: [String: Bool] = Dictionary(
        uniqueKeysWithValues: HealthTriage.questions.map { ($0.id, false) })

    private func answering(_ flag: String) -> [String: Bool] {
        var a = allClear
        a[flag] = true
        return a
    }

    /// Every condition follow-up answered the non-escalating way.
    private let controlledAndActive: [String: String] = [
        "control": "controlled", "symptoms": "none", "active_now": "active",
    ]

    // MARK: - Hard flags stay terminal

    func testChestPainRefersImmediatelyWithNoFollowUp() {
        // No self-reported answer can overturn chest pain, and asking six
        // more questions before refusing would be theatre.
        let outcome = HealthTriage.evaluate(answers: answering("chest_pain"))
        XCTAssertEqual(outcome, .referOut(flagged: ["chest_pain"]))
        XCTAssertTrue(HealthTriage.pendingFollowUps(
            answers: answering("chest_pain"), followUps: [:]).isEmpty)
    }

    func testEveryHardFlagIsTerminal() {
        for flag in HealthTriage.hardFlags {
            let outcome = HealthTriage.evaluate(answers: answering(flag))
            guard case .referOut = outcome else {
                return XCTFail("\(flag) did not refer")
            }
        }
    }

    func testAHardFlagOutranksASoftOneAnsweredWell() {
        var answers = answering("chest_pain")
        answers["medication"] = true
        let outcome = HealthTriage.evaluate(answers: answers,
                                            followUps: controlledAndActive)
        XCTAssertEqual(outcome, .referOut(flagged: ["chest_pain"]),
                       "a controlled condition cannot talk past chest pain")
    }

    // MARK: - Soft flags open a follow-up instead of refusing

    func testMedicationOpensAFollowUpRatherThanRefusing() {
        // THE over-refer defect, as a test.
        let outcome = HealthTriage.evaluate(answers: answering("medication"))
        guard case .incomplete(let next) = outcome else {
            return XCTFail("a controlled condition was refused outright: \(outcome)")
        }
        XCTAssertEqual(next.id, "control")
    }

    func testAControlledActiveAsymptomaticAthleteIsCleared() {
        // The person the follow-up pages exist to wave through.
        let outcome = HealthTriage.evaluate(answers: answering("medication"),
                                            followUps: controlledAndActive)
        XCTAssertEqual(outcome, .cleared)
    }

    func testAnUncontrolledConditionStillRefers() {
        // The corpus discriminator, verbatim: "difficulty controlling a
        // condition with prescribed medication or therapy escalates it
        // toward referral."
        var followUps = controlledAndActive
        followUps["control"] = "uncontrolled"
        let outcome = HealthTriage.evaluate(answers: answering("chronic_condition"),
                                            followUps: followUps)
        guard case .referOut = outcome else { return XCTFail("uncontrolled must refer") }
    }

    func testAnySymptomRefers() {
        var followUps = controlledAndActive
        followUps["symptoms"] = "any"
        guard case .referOut = HealthTriage.evaluate(answers: answering("chronic_condition"),
                                                     followUps: followUps) else {
            return XCTFail("a reported symptom must refer")
        }
    }

    func testACardiacAnswerStaysTerminalUntilTheCeilingExists() {
        // The corpus licenses clearing a controlled, asymptomatic, active
        // adult with diagnosed disease only for LIGHT-TO-MODERATE work,
        // and that row is hedged. We do not ship an intensity ceiling, so
        // clearing here would go further than the evidence allows.
        guard case .referOut = HealthTriage.evaluate(answers: answering("heart_or_bp"),
                                                     followUps: controlledAndActive) else {
            return XCTFail("cardiac must not be cleared without an intensity ceiling")
        }
    }

    func testAnInactiveAthleteWithADiagnosedConditionRefers() {
        var followUps = controlledAndActive
        followUps["active_now"] = "inactive"
        guard case .referOut = HealthTriage.evaluate(answers: answering("chronic_condition"),
                                                     followUps: followUps) else {
            return XCTFail("inactive + diagnosed needs clearance first")
        }
    }

    func testTheConditionFollowUpIsAskedOnceForBothFlags() {
        // Medication is a proxy for the condition, not an eighth condition.
        var answers = allClear
        answers["chronic_condition"] = true
        answers["medication"] = true
        let pending = HealthTriage.pendingFollowUps(answers: answers, followUps: [:])
        XCTAssertEqual(pending.map(\.id), HealthTriage.conditionFollowUps.map(\.id))
    }

    // MARK: - Musculoskeletal is a constraint, not a gate

    func testASoreShoulderDoesNotWithdrawTheProgram() {
        var followUps: [String: String] = ["msk_prohibited": "allowed",
                                           "msk_area": "shoulder"]
        XCTAssertEqual(HealthTriage.evaluate(answers: answering("musculoskeletal"),
                                             followUps: followUps),
                       .cleared)
        followUps.removeValue(forKey: "msk_area")
        // Still not a refusal while unanswered — just unfinished.
        guard case .incomplete = HealthTriage.evaluate(
            answers: answering("musculoskeletal"), followUps: followUps) else {
            return XCTFail("an unanswered constraint must not refuse")
        }
    }

    func testAJointADoctorSaidNotToTrainStillRefers() {
        let followUps = ["msk_prohibited": "prohibited"]
        guard case .referOut = HealthTriage.evaluate(
            answers: answering("musculoskeletal"), followUps: followUps) else {
            return XCTFail("an explicit medical prohibition must refer")
        }
    }

    func testTheNamedJointReachesTheGenerator() {
        // Every option must be a joint the catalog labels, or the answer
        // records cleanly and changes nothing.
        let areas = HealthTriage.constraintFollowUps
            .first { $0.id == "msk_area" }!.options.map(\.id)
        XCTAssertEqual(HealthTriage.cautionJoint(from: ["msk_area": "knee"]), "knee")
        XCTAssertTrue(areas.contains("lower_back"))
        XCTAssertFalse(areas.isEmpty)
    }

    // MARK: - The bypass

    func testARefusalIsNotHandedBackAsAFreshQuestionnaire() {
        // The bypass: needsScreening is true for a refused athlete, and
        // the gate checked it first, so a refusal re-asked immediately.
        var screening = HealthScreening(answers: answering("chest_pain"))
        XCTAssertTrue(screening.needsScreening,
                      "the condition that made the bypass possible still holds")
        XCTAssertTrue(screening.hasStandingRefusal,
                      "and it must now be outranked by the standing refusal")
        screening.clinicianCleared = true
        XCTAssertFalse(screening.hasStandingRefusal,
                       "a clinician's clearance is the way out")
    }

    func testANeverScreenedAthleteHasNoStandingRefusal() {
        // Empty answers evaluate as .cleared, so this must key off having
        // been asked at all — otherwise a new user would see a refusal.
        XCTAssertFalse(HealthScreening().hasStandingRefusal)
    }

    func testAPartFinishedScreeningDoesNotClearTheGate() {
        let screening = HealthScreening(answers: answering("medication"))
        XCTAssertFalse(screening.clearsTheGate,
                       "incomplete is neither cleared nor refused, and must not prescribe")
        XCTAssertFalse(screening.hasStandingRefusal,
                       "nor should it show a refusal card")
    }

    func testAnAthleteResumesAtTheQuestionTheyOwe() {
        var screening = HealthScreening(answers: answering("medication"))
        screening.followUps = ["control": "controlled"]
        guard case .incomplete(let next) = screening.outcome() else {
            return XCTFail("expected to resume")
        }
        XCTAssertEqual(next.id, "symptoms", "resumed at the wrong question")
    }

    // MARK: - The pre-screen

    func testACleanPreScreenRecordsTheSevenItStandsFor() {
        // Recorded as the seven all-NO answers rather than as a single
        // flag, so the stored screening has the same shape whichever route
        // the athlete took and evaluate() reads one thing, not two.
        let answers = HealthTriage.clearedByPreScreen()
        XCTAssertEqual(answers.count, HealthTriage.questions.count)
        XCTAssertTrue(answers.values.allSatisfy { $0 == false })
        XCTAssertEqual(HealthTriage.evaluate(answers: answers), .cleared)
        XCTAssertTrue(HealthScreening(answers: answers).clearsTheGate)
    }

    func testThePreScreenNamesEverySpecificTheSevenAskAbout() {
        // The whole risk of collapsing seven questions into one: PAR-Q+
        // works because it asks about things people do not file under "a
        // health condition" - undiagnosed exertional chest pain, dizziness
        // written off as standing up too fast, a medication so routine it
        // stopped counting. Ask it bare and the people the instrument
        // exists to catch answer no in good faith.
        //
        // So the clarifier has to carry every one of them. If a future
        // edit trims it for brevity, this fails.
        let clarifier = (HealthTriage.preScreen.clarifier ?? "").lowercased()
        for term in ["heart", "chest pain", "dizziness", "medication",
                     "joint", "supervised"] {
            XCTAssertTrue(clarifier.contains(term),
                          "the pre-screen must still name '\(term)'")
        }
    }

    func testThePreScreenIsNotOneOfTheSeven() {
        // It stands in FRONT of the instrument; it is not part of it.
        XCTAssertFalse(HealthTriage.questions.map(\.id)
                        .contains(HealthTriage.preScreen.id))
    }

    // MARK: - The manual clear (owner request)

    func testAClinicianClearanceIsRecordedAsItselfNotAsAnAnswer() {
        // The honest version of the bypass: what the athlete told us stays
        // exactly as they told it, and the clearance sits beside it in its
        // own field rather than overwriting the screening.
        var screening = HealthScreening(answers: answering("chronic_condition"))
        screening.clinicianCleared = true
        XCTAssertEqual(screening.answers["chronic_condition"], true,
                       "the original answer must not be rewritten")
        XCTAssertTrue(screening.clearsTheGate)
    }
}
