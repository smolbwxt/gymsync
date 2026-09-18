import XCTest
@testable import GymSync

/// The reaction vocabulary is emoji only — plan task S12 (spec §5, §9.1).
///
/// `ChatView.visibleReactionCounts(from:)` is the law that keeps a
/// `snd:`-prefixed row (there will be none after D5's drop, but a client may
/// still hold one in a stale cache) from ever rendering — "renders
/// `snd:airhorn` as a chip" is exactly the defect a naive removal would ship.
final class ChatReactionVocabularyTests: XCTestCase {

    func testEmojiRowsPassThrough() {
        let rows = ChatView.visibleReactionCounts(from: ["🔥": 3, "👍": 1])
        XCTAssertEqual(rows.map(\.emoji), ["👍", "🔥"])
        XCTAssertEqual(rows.first(where: { $0.emoji == "🔥" })?.count, 3)
    }

    /// A cached `snd:`-prefixed row is SKIPPED entirely — never rendered as
    /// text, and never counted alongside the emoji it sits next to.
    func testASoundPrefixedRowIsSkippedEntirely() {
        let rows = ChatView.visibleReactionCounts(from: ["🔥": 2, "snd:airhorn": 5])
        XCTAssertEqual(rows.map(\.emoji), ["🔥"])
    }

    func testAllSoundPrefixedRowsYieldsNothing() {
        XCTAssertTrue(ChatView.visibleReactionCounts(from: ["snd:airhorn": 1, "snd:bell": 2]).isEmpty)
    }

    func testAnEmptyInputYieldsNothing() {
        XCTAssertTrue(ChatView.visibleReactionCounts(from: [:]).isEmpty)
    }

    /// Sorted by emoji — a stable order across renders.
    func testRowsAreSortedByEmoji() {
        let rows = ChatView.visibleReactionCounts(from: ["😂": 1, "👍": 1, "💪": 1])
        XCTAssertEqual(rows.map(\.emoji), ["👍", "💪", "😂"])
    }
}
