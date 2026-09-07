import XCTest
@testable import GymSync

/// `WeeklyGoalWriteRule`'s two questions, as assertions. Plan: Stream A task
/// A11; `shouldDetectOnRead` is the final review's finding 1.
///
/// Owner answer 3 — "Coach never overwrites a user-set goal" — cannot live in
/// a database trigger: every Coach write runs on the athlete's own JWT, so
/// the server sees one identity for both. It lives here, and every write path
/// (`WeekBooker.book`, `ProgramBuilder.build`, and Home's own detect-on-read)
/// consults it through `LiveWeeklyGoalRepository`.
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

    // MARK: - Detect on read (final review finding 1)

    func testAnEmptyCurrentWeekDetects() {
        XCTAssertTrue(WeeklyGoalWriteRule.shouldDetectOnRead(existing: nil,
                                                             weekStart: weekStart,
                                                             currentWeekStart: weekStart),
                      "rule 3 says a week is never empty — an empty read of THIS week is what detection fills")
    }

    func testAWeekThatAlreadyHasARowDoesNotDetect() {
        for source in [WeeklyGoalSource.coach, .user] {
            XCTAssertFalse(WeeklyGoalWriteRule.shouldDetectOnRead(existing: goal(source),
                                                                  weekStart: weekStart,
                                                                  currentWeekStart: weekStart),
                           "detection fills an absence; a \(source.rawValue) row is not one")
        }
    }

    func testAnotherWeekNeverDetectsFromARead() {
        // The half that matters: reading a week is not a reason to WRITE it.
        // A future week is `WeekBooker`'s to stamp when it books, and a past
        // week must not be back-filled by someone scrolling to it.
        for other in ["2026-09-13", "2026-08-30"] {
            XCTAssertFalse(WeeklyGoalWriteRule.shouldDetectOnRead(existing: nil,
                                                                  weekStart: other,
                                                                  currentWeekStart: weekStart),
                           "\(other) is not the week Home is rendering")
        }
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
