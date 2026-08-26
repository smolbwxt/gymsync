import XCTest
@testable import GymSync

/// The gate that decides whether Coach may program at all. The 40-persona
/// stress test found the app would program someone post-cardiac-event
/// because nothing asked; these tests are the guarantee that it now
/// refuses.
final class HealthTriageTests: XCTestCase {

    func testAllNoClears() {
        let answers = Dictionary(uniqueKeysWithValues:
            HealthTriage.questions.map { ($0.id, false) })
        XCTAssertEqual(HealthTriage.evaluate(answers: answers), .cleared)
    }

    func testAnySingleYesStopsTheClearance() {
        // UPDATED 2026-08-26, deliberately, and this is not a stale test
        // being waved through. It used to assert that any YES produced
        // .referOut - and making three of them non-blocking was the POINT
        // of the Step-2 work. PAR-Q+ Step 1 ROUTES, it does not decide:
        // its own rule sends a YES to the follow-up condition pages OR to
        // a clinician, and we had shipped only the second branch, refusing
        // a levothyroxine taker forever.
        //
        // What must still hold, and what this now guards: a YES on ANY
        // question stops the CLEARANCE. It may route to a follow-up, but
        // it can never come back cleared without answering one.
        for question in HealthTriage.questions {
            var answers = Dictionary(uniqueKeysWithValues:
                HealthTriage.questions.map { ($0.id, false) })
            answers[question.id] = true
            switch HealthTriage.evaluate(answers: answers) {
            case .cleared, .clearedWithAdvisory:
                XCTFail("a YES on \(question.id) cleared without a follow-up")
            case .referOut, .incomplete, .delay:
                break
            }
        }
    }

    func testEveryHardFlagStillRefusesOutright() {
        // The half of the old assertion that must NOT soften: no
        // self-reported follow-up can overturn chest pain, syncope, a
        // supervision instruction, or a cardiac diagnosis.
        for id in HealthTriage.hardFlags {
            var answers = Dictionary(uniqueKeysWithValues:
                HealthTriage.questions.map { ($0.id, false) })
            answers[id] = true
            XCTAssertEqual(HealthTriage.evaluate(answers: answers),
                           .referOut(flagged: [id]),
                           "\(id) must refer with no follow-up offered")
        }
    }

    func testUnansweredIsTreatedAsNotFlagged() {
        // An empty questionnaire clears — the gate is only meaningful once
        // it has been ASKED, which is the consult's job, not this type's.
        XCTAssertEqual(HealthTriage.evaluate(answers: [:]), .cleared)
    }

    func testDelayOutranksEverything() {
        let answers = Dictionary(uniqueKeysWithValues:
            HealthTriage.questions.map { ($0.id, false) })
        XCTAssertEqual(HealthTriage.evaluate(answers: answers, delay: .acuteIllness),
                       .delay(.acuteIllness))
    }

    func testPregnancyStillGetsAProgram() {
        // Corrected 2026-08-25. ACOG ENCOURAGES lifting and cardio during
        // pregnancy; blocking it was both wrong and paternalistic. The
        // practitioner conversation rides along with the program, it does
        // not stand in front of it.
        let answers = Dictionary(uniqueKeysWithValues:
            HealthTriage.questions.map { ($0.id, false) })
        guard case .clearedWithAdvisory(let copy) =
                HealthTriage.evaluate(answers: answers, stage: .pregnant) else {
            return XCTFail("pregnancy must still be programmed for")
        }
        XCTAssertTrue(copy.lowercased().contains("practitioner"))
    }

    func testPostpartumIsANormalReturn() {
        let answers = Dictionary(uniqueKeysWithValues:
            HealthTriage.questions.map { ($0.id, false) })
        guard case .clearedWithAdvisory = HealthTriage.evaluate(answers: answers,
                                                                stage: .postpartum) else {
            return XCTFail("postpartum must still be programmed for")
        }
    }

    func testARealFlagStillOutranksLifeStage() {
        // Pregnant AND reporting chest pain must still refer out.
        var answers = Dictionary(uniqueKeysWithValues:
            HealthTriage.questions.map { ($0.id, false) })
        answers["chest_pain"] = true
        XCTAssertEqual(HealthTriage.evaluate(answers: answers, stage: .pregnant),
                       .referOut(flagged: ["chest_pain"]))
    }

    func testCardiacFlagShapesTheCopy() {
        let copy = HealthTriage.referralCopy(flagged: ["chest_pain"])
        XCTAssertTrue(copy.lowercased().contains("heart"))
        XCTAssertTrue(copy.lowercased().contains("doctor"))
    }

    func testReferralCopyNeverLeavesTheAthleteWithNothing() {
        let copy = HealthTriage.referralCopy(flagged: ["medication"])
        XCTAssertTrue(copy.lowercased().contains("still works"),
                      "a refusal must offer what the app CAN do")
    }

    func testClearanceExpires() {
        let old = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        XCTAssertTrue(HealthTriage.clearanceExpired(clearedAt: old))
        let recent = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        XCTAssertFalse(HealthTriage.clearanceExpired(clearedAt: recent))
        XCTAssertTrue(HealthTriage.clearanceExpired(clearedAt: nil),
                      "never screened is not the same as cleared")
    }
}
