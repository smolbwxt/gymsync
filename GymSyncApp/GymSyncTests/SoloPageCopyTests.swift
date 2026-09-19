import XCTest
@testable import GymSync

/// WHAT THE LIVE PAGE SAYS TO A LIFTER WITH NO CREW (proof frames 155-157).
///
/// The rendered frames showed a crew page wearing a solo session's data:
/// "FREESTYLE / Own pace" with the lift being logged named nowhere, a card
/// headed "THE CREW · SETS DONE" over an empty bar, and a button reading
/// "LOG SET & PASS" with nobody to pass to. Every assertion below is red on
/// those strings.
///
/// Pure copy laws, so they are asserted where the decision is made rather
/// than through a SwiftUI body. The gate that reads them is the page's own
/// three-valued `SoloSessionShape.hidesCrewFurniture`, which answers true
/// only for a PROVED party of one — `.unknown` keeps the crew's behaviour,
/// which is what keeps every crew frame still.
final class SoloPageCopyTests: XCTestCase {

    // MARK: - The header (item 1)

    /// The kicker names the routine being run: with the rail's lifter rows
    /// hidden, nothing else on a solo page said what this workout is.
    func testTheSoloKickerIsTheRoutinesName() {
        XCTAssertEqual(RoundCopy.freestyleSoloKicker(routineName: "Push A"), "PUSH A")
        XCTAssertEqual(RoundCopy.freestyleSoloKicker(routineName: "leg day"), "LEG DAY")
    }

    /// A freeform workout has no routine to name, so it keeps the style's own
    /// word — the wording it already had.
    func testWithNoRoutineTheKickerKeepsTheStylesOwnWord() {
        XCTAssertEqual(RoundCopy.freestyleSoloKicker(routineName: ""), "FREESTYLE")
        XCTAssertEqual(RoundCopy.freestyleSoloKicker(routineName: "   "), "FREESTYLE")
    }

    /// The title is the lift the lifter is about to pick up — and the page
    /// hands in the EFFECTIVE name, so a swapped slot reads as the substitute
    /// (frame 157 must say "Goblet squat", never "Back squat").
    func testTheSoloTitleIsTheLiftBeingLogged() {
        XCTAssertEqual(RoundCopy.freestyleSoloTitle(exerciseName: "Back squat"), "Back squat")
        XCTAssertEqual(RoundCopy.freestyleSoloTitle(exerciseName: "Goblet squat"), "Goblet squat")
    }

    /// No current row — a freeform session with nothing logged — keeps "Own
    /// pace" rather than inventing a lift.
    func testWithNoCurrentExerciseTheTitleKeepsOwnPace() {
        XCTAssertEqual(RoundCopy.freestyleSoloTitle(exerciseName: nil), "Own pace")
        XCTAssertEqual(RoundCopy.freestyleSoloTitle(exerciseName: "  "), "Own pace")
        XCTAssertEqual(RoundCopy.freestyleSoloTitle(exerciseName: nil), RoundCopy.freestyleTitle)
    }

    // MARK: - The rail card, read as one lifter's own progress (item 2)

    func testTheSoloRailCardSaysNothingAboutACrew() {
        XCTAssertEqual(RoundCopy.freestyleSoloRailKicker, "SETS DONE")
        XCTAssertFalse(RoundCopy.freestyleSoloRailKicker.lowercased().contains("crew"))
        XCTAssertEqual(RoundCopy.freestyleRailKicker, "THE CREW · SETS DONE",
                       "and the crew's own card is untouched")
    }

    /// The crew's card carries a denominator under four markers; with one
    /// lifter the numerator is the whole point, and nothing else on the card
    /// says it.
    func testTheSoloCountSaysHowManyOfTheRoutineAreDone() {
        XCTAssertEqual(RoundCopy.freestyleSoloProgress(done: 3, total: 13), "3 OF 13")
        XCTAssertEqual(RoundCopy.freestyleSoloProgress(done: 0, total: 13), "0 OF 13")
        XCTAssertEqual(RoundCopy.freestyleOfTotal(13), "OF 13",
                       "the crew's spelling is unchanged")
    }

    // MARK: - The log control's verb (item 3)

    /// "& PASS" is the rotation's word. Only `.rounds` has a rotation, and
    /// only a crew has somebody at the other end of it.
    func testOnlyACrewRotationPassesTheTurn() {
        XCTAssertEqual(
            RoundCopy.logControlTitle(style: .rounds, isSolo: false, isFailed: false, isLogging: false),
            "LOG SET & PASS")
        XCTAssertEqual(
            RoundCopy.logControlTitle(style: .rounds, isSolo: false, isFailed: true, isLogging: false),
            "LOG FAIL & PASS")
    }

    /// Freestyle and Together never had a turn to pass — `LogFollowUp
    /// .calls(for:)` is empty for both, so the log IS the whole transaction —
    /// and they wore the rotation's verb anyway. This is the crew Freestyle
    /// correction as well as the solo one.
    func testAStyleWithNoTurnNeverPassesEvenForACrew() {
        for style in [SessionStyle.freestyle, .together] {
            XCTAssertEqual(
                RoundCopy.logControlTitle(style: style, isSolo: false, isFailed: false, isLogging: false),
                "LOG SET", "\(style) has no turn to pass")
            XCTAssertEqual(
                RoundCopy.logControlTitle(style: style, isSolo: false, isFailed: true, isLogging: false),
                "LOG FAIL")
        }
    }

    /// A rotation of one is still a rotation, and there is still nobody to
    /// pass to — the scheduled solo `.rounds` session, which is the case that
    /// needs both halves of the rule.
    func testARosterOfOneNeverPassesInANYStyle() {
        for style in SessionStyle.allCases {
            XCTAssertEqual(
                RoundCopy.logControlTitle(style: style, isSolo: true, isFailed: false, isLogging: false),
                "LOG SET", "\(style), alone")
            XCTAssertEqual(
                RoundCopy.logControlTitle(style: style, isSolo: true, isFailed: true, isLogging: false),
                "LOG FAIL", "\(style), alone")
        }
    }

    /// Every style, both shapes: exactly one of the six says "PASS", and it
    /// is the crew rotation. A style added later has to decide here.
    func testExactlyOneOfEveryStyleAndShapePasses() {
        var passing: [String] = []
        for style in SessionStyle.allCases {
            for isSolo in [true, false] {
                let title = RoundCopy.logControlTitle(style: style, isSolo: isSolo,
                                                      isFailed: false, isLogging: false)
                if title.contains("PASS") { passing.append("\(style)/\(isSolo ? "solo" : "crew")") }
            }
        }
        XCTAssertEqual(passing, ["rounds/crew"])
    }

    /// The in-flight label is the one state that says neither.
    func testLoggingSaysOnlyThat() {
        for style in SessionStyle.allCases {
            for isSolo in [true, false] {
                XCTAssertEqual(
                    RoundCopy.logControlTitle(style: style, isSolo: isSolo,
                                              isFailed: false, isLogging: true),
                    "LOGGING…")
            }
        }
    }
}
