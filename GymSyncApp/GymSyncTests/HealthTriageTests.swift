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

    func testAnySingleYesRefersOut() {
        // PAR-Q+ decision rule: one YES is enough. Test every question so
        // no future edit can quietly make one of them non-blocking.
        for question in HealthTriage.questions {
            var answers = Dictionary(uniqueKeysWithValues:
                HealthTriage.questions.map { ($0.id, false) })
            answers[question.id] = true
            XCTAssertEqual(HealthTriage.evaluate(answers: answers),
                           .referOut(flagged: [question.id]),
                           "a YES on \(question.id) must stop programming")
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
        XCTAssertEqual(HealthTriage.evaluate(answers: answers, delay: .pregnancy),
                       .delay(.pregnancy))
    }

    func testPregnancyRoutesToTheClinicianNotToAProgram() {
        // Both PAR-Q+ and ACOG put pregnancy in the practitioner's hands.
        // We must never self-clear it.
        guard case .delay(let reason) = HealthTriage.evaluate(answers: [:], delay: .pregnancy) else {
            return XCTFail("pregnancy must delay")
        }
        XCTAssertFalse(reason.copy.isEmpty)
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
