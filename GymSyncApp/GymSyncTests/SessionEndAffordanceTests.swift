import XCTest
@testable import GymSync

/// EVERY STYLE PAGE HAS A WAY OUT (ruling R-C-7, fix round 1 / B1).
///
/// The failure this pins is a real shipped one: `.freestyle`'s page mounted
/// neither of `showEndConfirmation`'s two setters, so a Freestyle session
/// could not be ended — no `complete()`, no recap, no week credit, and a row
/// left `in_progress`. It shipped for crew Freestyle in Phase B1 and became
/// everybody's when Phase C1 made every ad-hoc solo workout `.freestyle`.
/// (No STREAK credit either way: an ad-hoc session has never moved one —
/// `streak_on_session_state_change` returns on `scheduled_for IS NULL`.)
///
/// WHAT MAKES IT UNREPEATABLE, and it is two things together: the switch in
/// `SessionEndAffordance.mount(for:)` is exhaustive over `SessionStyle`, so a
/// fourth style is a compile error until somebody names its mount — and this
/// suite fails if what they name is `.none`.
final class SessionEndAffordanceTests: XCTestCase {

    func testEveryShippedStyleHasAnEndAffordance() {
        for style in SessionStyle.allCases {
            // Spelled in full: a case named `none` on a non-Optional enum is
            // unambiguous to the compiler but not to a reader.
            XCTAssertNotEqual(SessionEndAffordance.mount(for: style),
                              SessionEndAffordance.Mount.none,
                              "\(style.rawValue) has no way to end the session")
        }
    }

    func testTheLawCoversEVERYStyleTheRouterCanShow() {
        // `SessionInProgressView` switches on `session.style` with three
        // arms and no default, so the set of pages the router can show IS
        // `SessionStyle.allCases`. If that grows, this count is the second
        // place it has to be acknowledged.
        XCTAssertEqual(SessionStyle.allCases.count, 3)
    }

    func testRoundsEndsThroughTheHeaderRail() {
        // `myTurnFixedPage` mounts `turnHeaderRail`, whose ✕ is the setter;
        // the two crew pages are reachable only while somebody else holds
        // the turn.
        XCTAssertEqual(SessionEndAffordance.mount(for: .rounds), .headerRail)
    }

    func testFreestyleAndTogetherMountTheirOwn() {
        XCTAssertEqual(SessionEndAffordance.mount(for: .freestyle), .pageFoot)
        XCTAssertEqual(SessionEndAffordance.mount(for: .together), .pageFoot)
    }

    /// The reader `SessionLiveView` actually calls at both page call sites,
    /// exercised through the same function — so this is not a law with no
    /// caller (constraint 12's cautionary case).
    func testPageMountsItsOwnEndIsTrueForExactlyTheFootStyles() {
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.freestyle))
        XCTAssertTrue(SessionEndAffordance.pageMountsItsOwnEnd(.together))
        XCTAssertFalse(SessionEndAffordance.pageMountsItsOwnEnd(.rounds))
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
