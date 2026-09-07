import XCTest
@testable import GymSync

/// Owner answer 3 — "Coach never overwrites a user-set goal" — as three
/// assertions. Plan: Stream A task A11.
///
/// This rule cannot live in a database trigger: every Coach write runs on
/// the athlete's own JWT, so the server sees one identity for both. It lives
/// here, and both write paths (`WeekBooker.book`, `ProgramBuilder.build`)
/// consult it through `LiveWeeklyGoalRepository.writeDetectedGoal`.
final class WeeklyGoalWriteRuleTests: XCTestCase {

    private let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    private let weekStart = "2026-09-06"

    private func goal(_ source: WeeklyGoalSource,
                      kind: WeeklyGoalKind = .muscleSets) -> WeeklyGoal {
        WeeklyGoal(userID: userID, weekStartString: weekStart, kind: kind,
                   params: WeeklyGoalParams(muscleTargets: ["chest": 12]),
                   source: source, setAt: Date(timeIntervalSince1970: 1_788_696_000))
    }

    func testNoRowYetIsWritable() {
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: nil,
                                                          detected: goal(.coach)),
                      "a week with no goal is exactly what detection exists to fill")
    }

    func testACoachRowIsWritable() {
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: goal(.coach),
                                                          detected: goal(.coach)),
                      "Coach may supersede its own earlier reading — a re-booked week re-derives")
    }

    func testAUserRowIsNotWritable() {
        XCTAssertFalse(WeeklyGoalWriteRule.shouldOverwrite(existing: goal(.user),
                                                           detected: goal(.coach)),
                       "owner answer 3: the athlete has spoken for this week")
    }

    func testProvenanceDecidesRegardlessOfWhatWasDetected() {
        // The rule is about WHO set it, never about which goal is "better".
        // A detected goal of a different kind, and one identical to the
        // athlete's own, are both refused against a user row.
        for detected in [goal(.coach, kind: .distance), goal(.coach, kind: .muscleSets)] {
            XCTAssertFalse(WeeklyGoalWriteRule.shouldOverwrite(existing: goal(.user),
                                                               detected: detected))
            XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: goal(.coach),
                                                              detected: detected))
        }
    }
}
