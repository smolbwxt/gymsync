import XCTest
@testable import GymSync

/// EVERY PAGE THE ROUTER CAN SHOW HAS A WAY OUT (ruling R-C-7; fix round 1 /
/// B1, re-keyed in fix round 2 / N10).
///
/// The failures this pins are both real and both shipped. `.freestyle`'s page
/// mounted neither setter of `showEndConfirmation`, so a Freestyle session
/// could not be ended — no `complete()`, no recap, no week credit, and a row
/// left `in_progress`. And `roundWaitPage` / `spotterPage` mounted neither
/// either: `RoundWaitView` and `SpotterView` draw no header rail, and
/// `bottomChrome` renders `turnChrome` only when `!showsCrewPage`, so a crew
/// lifter whose turn-holder walked out sat there with no leave and no end.
/// (No STREAK credit in any of this either way: an ad-hoc session has never
/// moved one — `streak_on_session_state_change` returns on
/// `scheduled_for IS NULL`.)
///
/// WHAT MAKES IT UNREPEATABLE, and it is three things together: `pages(for:)`
/// is exhaustive over `SessionStyle`, so a fourth style must name its pages;
/// `mount(for:)` is exhaustive over `Page`, so a sixth page must name where
/// its end lives; and this suite fails if what either names is `.none`.
///
/// THE FIRST VERSION WAS KEYED ON STYLE, and that is exactly why it passed
/// while two of five pages had no way out: `.rounds` answered `.headerRail`
/// for all three of its pages, which was true of one of them.
final class SessionEndAffordanceTests: XCTestCase {

    // MARK: - Every page, and every style's pages

    func testEveryPageTheRouterCanShowHasAnEndAffordance() {
        for page in SessionEndAffordance.Page.allCases {
            // Spelled in full: a case named `none` on a non-Optional enum is
            // unambiguous to the compiler but not to a reader.
            XCTAssertNotEqual(SessionEndAffordance.mount(for: page),
                              SessionEndAffordance.Mount.none,
                              "\(page.rawValue) has no way to end the session")
        }
    }

    func testEVERYStyleNamesAtLeastOnePage() {
        for style in SessionStyle.allCases {
            XCTAssertFalse(SessionEndAffordance.pages(for: style).isEmpty,
                           "\(style.rawValue) shows no page at all")
        }
    }

    /// The two enums must describe the same five screens. A page nobody can
    /// route to is dead, and a page a style can show but that is missing from
    /// `Page` would slip past `testEveryPageTheRouterCanShow…` entirely.
    func testTheStylesPagesAreEXACTLYThePagesThatExist() {
        let reachable = Set(SessionStyle.allCases.flatMap {
            SessionEndAffordance.pages(for: $0)
        })
        XCTAssertEqual(reachable, Set(SessionEndAffordance.Page.allCases))
    }

    /// `SessionLiveView.arenaBase`'s switch has five arms. If a sixth page is
    /// ever added there, this is the second place that has to be told.
    func testTheRouterShowsFivePages() {
        XCTAssertEqual(SessionEndAffordance.Page.allCases.count, 5)
        XCTAssertEqual(SessionStyle.allCases.count, 3)
    }

    func testNoPageIsClaimedByTwoStyles() {
        let all = SessionStyle.allCases.flatMap { SessionEndAffordance.pages(for: $0) }
        XCTAssertEqual(all.count, Set(all).count)
    }

    // MARK: - Where each one's end lives

    func testOnlyTheMyTurnPageEndsThroughTheHeaderRail() {
        // It is the one page that draws `turnHeaderRail`, whose dismiss glyph
        // is the setter. The other four draw no rail at all.
        XCTAssertEqual(SessionEndAffordance.mount(for: .roundsMyTurn), .headerRail)
        for page in SessionEndAffordance.Page.allCases where page != .roundsMyTurn {
            XCTAssertEqual(SessionEndAffordance.mount(for: page), .pageFoot,
                           "\(page.rawValue) draws no header rail, so it owes its own door")
        }
    }

    func testTheTWOCREWPagesMountTheirOwn() {
        // N10's finding, as an assertion: the `.rounds` arm of the old
        // style-keyed law said `.headerRail` for these, which was false.
        XCTAssertEqual(SessionEndAffordance.mount(for: .roundsRoundWait), .pageFoot)
        XCTAssertEqual(SessionEndAffordance.mount(for: .roundsSpotter), .pageFoot)
    }

    /// The reader `SessionLiveView.endAction(for:)` actually calls, exercised
    /// through the same function — so this is not a law with no caller
    /// (constraint 12's cautionary case).
    func testPageMountsItsOwnEndIsTrueForExactlyTheFootPages() {
        XCTAssertFalse(SessionEndAffordance.pageMountsItsOwnEnd(.roundsMyTurn))
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.roundsRoundWait))
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.roundsSpotter))
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.freestyleRail))
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.togetherClock))
    }

    func testRoundsShowsThreePagesAndTheOtherTwoShowOne() {
        XCTAssertEqual(SessionEndAffordance.pages(for: .rounds),
                       [.roundsMyTurn, .roundsRoundWait, .roundsSpotter])
        XCTAssertEqual(SessionEndAffordance.pages(for: .freestyle), [.freestyleRail])
        XCTAssertEqual(SessionEndAffordance.pages(for: .together), [.togetherClock])
    }

    // MARK: - The words

    func testASoloLifterIsFinishingAWorkoutNotLeavingAnyone() {
        let dialog = SessionEndCopy.dialog(isSolo: true, isLastPresent: true)
        XCTAssertEqual(dialog.title, "Finish this workout?")
        XCTAssertEqual(dialog.soloPrimary, "Finish workout")
        XCTAssertFalse(dialog.message.lowercased().contains("crew"))
        XCTAssertFalse(dialog.message.lowercased().contains("everyone"))
        XCTAssertFalse(dialog.message.lowercased().contains("rotation"))
    }

    func testTheSoloWordsDoNotDependOnTheLastPresentCount() {
        // A party of one is always the last one present, so that flag must
        // not produce two different solo sentences.
        XCTAssertEqual(SessionEndCopy.dialog(isSolo: true, isLastPresent: true),
                       SessionEndCopy.dialog(isSolo: true, isLastPresent: false))
    }

    func testACrewKeepsItsShippedWordsOnBothBranches() {
        let last = SessionEndCopy.dialog(isSolo: false, isLastPresent: true)
        XCTAssertEqual(last.title, "Leave the session?")
        XCTAssertNil(last.soloPrimary, "a crew keeps two actions that mean different things")
        XCTAssertEqual(last.message,
                       "You're the last one lifting — leaving completes the session.")

        let notLast = SessionEndCopy.dialog(isSolo: false, isLastPresent: false)
        XCTAssertEqual(notLast.title, "Leave the session?")
        XCTAssertNil(notLast.soloPrimary)
        XCTAssertEqual(notLast.message,
                       "Leaving removes you from the rotation; the crew keeps lifting.")
    }

    func testSoloAndCrewNeverShareASentence() {
        let solo = SessionEndCopy.dialog(isSolo: true, isLastPresent: true)
        let crew = SessionEndCopy.dialog(isSolo: false, isLastPresent: true)
        XCTAssertNotEqual(solo.title, crew.title)
        XCTAssertNotEqual(solo.message, crew.message)
    }
}
