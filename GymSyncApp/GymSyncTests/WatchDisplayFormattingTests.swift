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

    // MARK: - Emoji / grapheme-cluster correctness (fix wave 1, reviewer
    // finding MINOR 1)
    //
    // `initials(from:)` splits on whitespace and takes each word's `.first`
    // `Character` — Swift's `Character` is an EXTENDED GRAPHEME CLUSTER, not
    // a Unicode scalar, so a multi-scalar ZWJ (zero-width-joiner) emoji
    // sequence like the "family: man, woman, girl" emoji (U+1F468 U+200D
    // U+1F469 U+200D U+1F467) is exactly ONE `Character` — `.first` on that
    // word returns the WHOLE sequence, not a mangled fragment of it (a
    // scalar- or byte-basis implementation would split the joined emoji
    // apart). These tests exercise that guarantee directly, since it's easy
    // for a future refactor to silently regress from `Character`-basis to
    // `.unicodeScalars`/`utf8` without anything else in this suite catching
    // it (every other test here uses plain ASCII names).

    func testZWJEmojiWordWithTrailingNameYieldsGraphemeCorrectInitials() {
        // "👨‍👩‍👧" (family: man, woman, girl) is a single ZWJ-joined
        // grapheme cluster — `.first` on that word must hand back the
        // WHOLE emoji, not e.g. just "👨" (the first Unicode scalar).
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "👨‍👩‍👧 Family"), "👨‍👩‍👧F")
    }

    func testNameStartingWithEmojiYieldsEmojiAsFirstInitial() {
        // A name whose FIRST word is an emoji (not necessarily multi-
        // scalar) — the emoji itself is the first initial, `.uppercased()`
        // is a no-op on it (emoji have no case), and the second word's
        // first letter is still correctly uppercased.
        XCTAssertEqual(WatchDisplayFormatting.initials(from: "🔥 tommy"), "🔥T")
    }
}
