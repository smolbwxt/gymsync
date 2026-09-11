import SwiftUI
import XCTest
@testable import GymSync

// MARK: - LadderRowStyleTests
//
// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// task D1. `LadderPageView`'s body is not unit-testable — the three catalog
// captures (D7) are its proof. The status -> style mapping IS testable, and
// it is extracted for exactly that reason: a ladder that painted a missed
// week red would say the athlete failed, where design rule 2 says a missed
// week is a fact and red is errors only.
//
// The mapping takes its PALETTE rather than reading one. A static cannot see
// `@Environment(\.gsTheme)`, and defaulting it would let a caller silently
// draw midnight's muted grey on the ink palette; the view passes its own.
final class LadderRowStyleTests: XCTestCase {

    private let theme = GSTheme.midnight

    /// Every case of `RungStatus`, listed by hand: the enum is Task 0's
    /// frozen surface and does not conform to `CaseIterable`, so adding the
    /// conformance to make this array derivable would change a file this
    /// stream is forbidden to touch.
    private let everyStatus: [RungStatus] = [.ahead, .current, .met, .missed, .overridden]

    // MARK: - The mapping

    func testAMetRungIsTheOneGreen() {
        let style = LadderPageView.style(for: .met, theme: theme)
        XCTAssertEqual(style.ink, Color.gsSuccess,
                       "green means done, and a met rung is the only done a row has")
        XCTAssertNil(style.ring)
    }

    func testAMissedRungIsMutedBecauseItIsAFactNotAnError() {
        let style = LadderPageView.style(for: .missed, theme: theme)
        XCTAssertEqual(style.ink, theme.neutral500)
        XCTAssertNil(style.ring)
    }

    func testAnOverriddenRungIsMutedToo() {
        let style = LadderPageView.style(for: .overridden, theme: theme)
        XCTAssertEqual(style.ink, theme.neutral500)
        XCTAssertNil(style.ring)
    }

    func testTheCurrentRungIsRingedInAccent() {
        let style = LadderPageView.style(for: .current, theme: theme)
        XCTAssertEqual(style.ring, theme.accent,
                       "accent's 'current item in a pager' job, and the only accent on a row")
        XCTAssertEqual(style.ink, theme.text, "the ring marks it; the ink stays default")
    }

    func testAnAheadRungIsDefaultText() {
        let style = LadderPageView.style(for: .ahead, theme: theme)
        XCTAssertEqual(style.ink, theme.text)
        XCTAssertNil(style.ring)
    }

    /// Design rule 2: red is for errors only, and nothing on this page is an
    /// error. Asserted over EVERY branch rather than the two that could
    /// plausibly have reached for it.
    func testRedAppearsInNoBranch() {
        for status in everyStatus {
            let style = LadderPageView.style(for: status, theme: theme)
            XCTAssertNotEqual(style.ink, Color.red, "\(status) must not be red")
            XCTAssertNotEqual(style.ring, Color.red, "\(status) must not be ringed in red")
        }
    }

    /// Gold has exactly two jobs (the week-streak number and the check-in
    /// window) and neither is here — D1's "no gold anywhere on this page".
    func testGoldAppearsInNoBranch() {
        for status in everyStatus {
            let style = LadderPageView.style(for: status, theme: theme)
            XCTAssertNotEqual(style.ink, HomeV2Gold.top)
            XCTAssertNotEqual(style.ink, HomeV2Gold.bottom)
        }
    }

    // MARK: - The WEEK n kicker's own ink (review finding 4)

    /// Design rule 3: "Kickers are 10 to 11 pt caps with 0.1 to 0.13 em
    /// tracking and sit in `muted`; a kicker turns `text` only when it is the
    /// current one." The row's week number is a kicker by every measure the
    /// rule names, so it does not take the row's ink wholesale — an `ahead`
    /// rung in full-strength `text` made weeks 4, 5, 7 and 8 look exactly as
    /// loud as the current one.
    func testOnlyTheCurrentWeeksKickerTurnsText() {
        XCTAssertEqual(LadderPageView.kickerInk(for: .current, theme: theme), theme.text)
        for status in [RungStatus.ahead, .missed, .overridden] {
            XCTAssertEqual(LadderPageView.kickerInk(for: status, theme: theme),
                           theme.neutral500,
                           "\(status) is not the current rung and must not read as loud as it")
        }
    }

    /// `met` keeps the green: rule 2's "green means done" is a fair override
    /// of rule 3, because it is the one status whose colour IS the fact
    /// rather than a weight.
    func testAMetWeeksKickerKeepsTheOneGreen() {
        XCTAssertEqual(LadderPageView.kickerInk(for: .met, theme: theme), Color.gsSuccess)
    }

    /// The kicker law is the row law's sibling, not its copy — and neither of
    /// them is ever red or gold.
    func testTheKickerInkIsNeverRedOrGold() {
        for status in everyStatus {
            let ink = LadderPageView.kickerInk(for: status, theme: theme)
            XCTAssertNotEqual(ink, Color.red)
            XCTAssertNotEqual(ink, HomeV2Gold.top)
        }
    }

    // MARK: - The kicker beside the week number

    func testADeloadRowSaysSo() {
        XCTAssertEqual(LadderPageView.kicker(for: .ahead, isDeload: true), "DELOAD",
                       "spec 3.2: the ladder shows the deload as what it is")
    }

    func testAnOverriddenRowIsYours() {
        XCTAssertEqual(LadderPageView.kicker(for: .overridden, isDeload: false), "YOURS")
    }

    /// Both at once — the athlete overrode the deload week. DELOAD leads,
    /// because it is the fact about the WEEK and YOURS is the fact about who
    /// typed it; a row cannot wear two kickers and the block's own shape is
    /// the thing a reader is scanning for.
    func testADeloadTheAthleteOverrodeStillSaysDeload() {
        XCTAssertEqual(LadderPageView.kicker(for: .overridden, isDeload: true), "DELOAD")
    }

    func testEveryOtherRowCarriesNoKicker() {
        for status in [RungStatus.ahead, .current, .met, .missed] {
            XCTAssertEqual(LadderPageView.kicker(for: status, isDeload: false), "",
                           "\(status) has nothing extra to say")
        }
    }

    // MARK: - The status word on the right

    /// `overridden` says nothing on the right: the YOURS kicker beside the
    /// week number already said it, and two words for one fact reads as two
    /// facts.
    func testTheStatusWordNamesOnlyWhatTheKickerDoesNot() {
        XCTAssertEqual(LadderPageView.statusWord(for: .met), "MET")
        XCTAssertEqual(LadderPageView.statusWord(for: .missed), "MISSED")
        XCTAssertEqual(LadderPageView.statusWord(for: .current), "THIS WEEK")
        XCTAssertEqual(LadderPageView.statusWord(for: .ahead), "")
        XCTAssertEqual(LadderPageView.statusWord(for: .overridden), "")
    }

    // MARK: - The fixture the three captures render

    /// D7's `ladder-on-track` frame is `StubBlockGoalRepository.fixturePage`.
    /// Pinned here so a change to the stub that would redraw all three ladder
    /// captures fails a unit test before it reaches a screenshot diff.
    func testTheOnTrackFixtureHasExactlyOneCurrentRung() {
        let rows = StubBlockGoalRepository.fixturePage.rows
        XCTAssertEqual(rows.filter { $0.status == .current }.count, 1)
        XCTAssertEqual(rows.filter { $0.status == .met }.count, 2)
        XCTAssertEqual(rows.filter(\.isDeload).count, 1)
        XCTAssertTrue(StubBlockGoalRepository.fixturePage.reachesMilestone)
    }
}
