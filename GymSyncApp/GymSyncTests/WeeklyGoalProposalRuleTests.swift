import XCTest
@testable import GymSync

/// Owner answer 3's ASKING half, as assertions — final review finding 2.
///
/// `WeeklyGoalWriteRule` says Coach may never write over a `source = user`
/// row; this rule says when Coach has something worth saying about one. The
/// thresholds are the controller's: a different kind, muscle-set targets
/// ≥ 2 sets apart on any group, or a distance/lift target ≥ 10 % apart.
final class WeeklyGoalProposalRuleTests: XCTestCase {

    private let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    private let weekStart = "2026-09-06"
    private let setAt = Date(timeIntervalSince1970: 1_788_696_000)

    private func goal(_ kind: WeeklyGoalKind,
                      _ params: WeeklyGoalParams,
                      source: WeeklyGoalSource = .user) -> WeeklyGoal {
        WeeklyGoal(userID: userID, weekStartString: weekStart, kind: kind,
                   params: params, source: source, setAt: setAt)
    }

    private func muscles(_ targets: [String: Int]) -> WeeklyGoal {
        goal(.muscleSets, WeeklyGoalParams(muscleTargets: targets))
    }

    // MARK: - Kind

    func testADifferentKindIsAlwaysWorthSaying() {
        let mine = muscles(["chest": 12])
        let theirs = goal(.distance, WeeklyGoalParams(activity: "run", distanceTarget: 15))
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(user: mine, coach: theirs))
    }

    // MARK: - muscleSets: ≥ 2 sets on any group

    func testOneSetApartIsNoise() {
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12, "back": 12]),
            coach: muscles(["chest": 13, "back": 11])))
    }

    func testTwoSetsApartOnOneGroupIsEnough() {
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12, "back": 12]),
            coach: muscles(["chest": 14, "back": 12])))
    }

    func testAGroupOnlyOneSideHasCountsAsItsWholeTarget() {
        // Coach adding legs at 10, and Coach dropping a group the athlete
        // set, are both differences of 10 — well over the threshold.
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12]),
            coach: muscles(["chest": 12, "legs": 10])))
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12, "legs": 10]),
            coach: muscles(["chest": 12])))
        // …but a group added at 1 set is still noise.
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12]),
            coach: muscles(["chest": 12, "legs": 1])))
    }

    func testIdenticalTargetsSayNothing() {
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: muscles(["chest": 12, "back": 12, "legs": 12, "arms": 8]),
            coach: muscles(["arms": 8, "legs": 12, "back": 12, "chest": 12])))
    }

    // MARK: - distance and lift: ≥ 10 %

    private func run(_ target: Double) -> WeeklyGoal {
        goal(.distance, WeeklyGoalParams(activity: "run", distanceTarget: target))
    }

    func testDistanceUnderTenPercentIsNoise() {
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(user: run(15), coach: run(16)))
    }

    func testDistanceAtTenPercentIsEnough() {
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(user: run(15), coach: run(16.5)))
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(user: run(15), coach: run(13.5)))
    }

    func testNoTargetOfYourOwnMakesAnyTargetADifference() {
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(
            user: goal(.distance, WeeklyGoalParams(activity: "run")),
            coach: run(15)))
        // And nothing on either side is not a difference — never a divide by
        // zero, never a sentence about nothing.
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: goal(.distance, WeeklyGoalParams(activity: "run")),
            coach: goal(.distance, WeeklyGoalParams(activity: "run"))))
    }

    private let squat = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!
    private let bench = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!

    private func lift(_ exercise: UUID, _ lbs: Decimal) -> WeeklyGoal {
        goal(.lift, WeeklyGoalParams(exerciseID: exercise, targetWeightLbs: lbs))
    }

    func testLiftUnderTenPercentIsNoise() {
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(user: lift(squat, 225),
                                                           coach: lift(squat, 235)))
    }

    func testLiftAtTenPercentIsEnough() {
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(user: lift(squat, 225),
                                                          coach: lift(squat, 250)))
    }

    func testADifferentLiftIsADifferentGoal() {
        XCTAssertTrue(WeeklyGoalProposalRule.isMeaningful(user: lift(squat, 225),
                                                          coach: lift(bench, 225)))
    }

    // MARK: - The two kinds with no same-kind threshold

    func testDaysAndSessionsOnlyDifferByKind() {
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: goal(.days, WeeklyGoalParams()),
            coach: goal(.days, WeeklyGoalParams())))
        XCTAssertFalse(WeeklyGoalProposalRule.isMeaningful(
            user: goal(.sessionsOfType, WeeklyGoalParams(sessionType: "hiit", count: 3)),
            coach: goal(.sessionsOfType, WeeklyGoalParams(sessionType: "cardio", count: 5))))
    }

    // MARK: - The sentence

    func testEverySentenceOpensWithCoachSuggests() {
        let all: [WeeklyGoal] = [
            muscles(["chest": 12, "back": 12, "legs": 10]),
            run(15),
            goal(.sessionsOfType, WeeklyGoalParams(sessionType: "cardio", count: 3)),
            goal(.days, WeeklyGoalParams()),
            lift(squat, 225),
        ]
        for candidate in all {
            for unit in WeightUnit.allCases {
                let sentence = WeeklyGoalProposalRule.sentence(for: candidate, unit: unit)
                XCTAssertTrue(sentence.hasPrefix("Coach suggests "),
                              "\(candidate.kind.rawValue): \(sentence)")
                XCTAssertTrue(sentence.hasSuffix("."), sentence)
            }
        }
    }

    func testTheSentenceNamesTheNumbersInTheAthletesOwnUnit() {
        XCTAssertEqual(WeeklyGoalProposalRule.sentence(for: run(15), unit: .lbs),
                       "Coach suggests 15 mi of running this week.")
        XCTAssertEqual(WeeklyGoalProposalRule.sentence(for: run(15), unit: .kg),
                       "Coach suggests 15 km of running this week.")
        // Canonical pounds, printed in the athlete's unit — never raw.
        XCTAssertEqual(WeeklyGoalProposalRule.sentence(for: lift(squat, 220), unit: .lbs),
                       "Coach suggests a lift target of 220 lbs this week.")
        XCTAssertEqual(WeeklyGoalProposalRule.sentence(for: lift(squat, 220), unit: .kg),
                       "Coach suggests a lift target of 99.8 kg this week.")
    }

    func testTheMuscleSentenceIsStableAcrossDictionaryOrder() {
        let targets = ["chest": 12, "back": 12, "legs": 10, "arms": 8]
        let first = WeeklyGoalProposalRule.sentence(for: muscles(targets), unit: .lbs)
        for _ in 0..<20 {
            XCTAssertEqual(WeeklyGoalProposalRule.sentence(for: muscles(targets), unit: .lbs),
                           first)
        }
        XCTAssertEqual(first,
                       "Coach suggests a muscle-sets week — back 12, chest 12, legs 10.")
    }
}
