import XCTest
@testable import GymSync

/// Hermetic tests for `WatchDisplayFormatting.initials(from:)`
/// (`GymSyncShared/WatchDisplayFormatting.swift` — Phase W Task 3, watch-hr
/// design §2 "Whose-turn home"). Pure string logic, no view/store/
/// WatchConnectivity involvement — this is the one piece of Task 3's
/// display logic that's genuinely a candidate for hermetic testing per the
/// task brief ("payload builders, initials derivation").
final class WatchDisplayFormattingTests: XCTestCase {

    func testSingleWordNameYieldsOneInitial() {
        // This app's names are usernames (e.g. "tommy"), not "First Last" —
        // the common case. One initial, not a fabricated second letter.
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "tommy"), "T")
    }

    func testTwoWordNameYieldsTwoInitials() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "Sam Reyes"), "SR")
    }

    func testLowercaseInputIsUppercased() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "jordan lee"), "JL")
    }

    func testThreeOrMoreWordsOnlyUsesFirstTwo() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "Mary Jane Watson"), "MJ")
    }

    func testExtraInternalWhitespaceIsIgnored() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "Sam   Reyes"), "SR")
    }

    func testLeadingAndTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "  tommy  "), "T")
    }

    func testEmptyStringYieldsEmptyInitials() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: ""), "")
    }

    func testWhitespaceOnlyStringYieldsEmptyInitials() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "   "), "")
    }

    func testSingleCharacterNameYieldsThatCharacter() {
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "x"), "X")
    }
}
