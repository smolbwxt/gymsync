import XCTest
@testable import GymSync

/// `LiveFriendsLiveRepository`'s pure half (Stream A task A9) and the
/// shipping-default repository's contract.
///
/// The fetch itself is a `SECURITY DEFINER` RPC and is proven server-side by
/// `supabase/tests/friends_live_test.sql`, which runs against the live
/// project in the Backend workflow. What is testable here is the derivation
/// that has no column behind it.
final class FriendsLiveTests: XCTestCase {

    func testInitialsTakeTheFirstLetterOfTheFirstTwoWords() {
        XCTAssertEqual(LiveFriendsLiveRepository.initials("Sarah Connor"), "SC")
        XCTAssertEqual(LiveFriendsLiveRepository.initials("bob"), "B")
    }

    func testInitialsStopAtTwoLetters() {
        XCTAssertEqual(LiveFriendsLiveRepository.initials("Mary Jane Watson"), "MJ",
                       "the chip is two letters wide — a third would not fit")
    }

    func testInitialsAreUppercased() {
        XCTAssertEqual(LiveFriendsLiveRepository.initials("ada lovelace"), "AL")
    }

    func testInitialsOfAnEmptyNameAreEmptyNotACrash() {
        XCTAssertEqual(LiveFriendsLiveRepository.initials(""), "")
        XCTAssertEqual(LiveFriendsLiveRepository.initials("   "), "",
                       "a name of only spaces splits into no words")
    }

    /// The derivation must stay identical to `TrainingCalendarWidget
    /// .initials(_:)` (:287), which draws the same two-letter chip
    /// elsewhere on Home. That one is `private` to a SwiftUI view, so its
    /// rule is reproduced here and compared rather than called — the same
    /// shape of agreement test A4 uses for `daysThisWeek`.
    func testInitialsAgreeWithTheCalendarWidgetsOwnRule() {
        for name in ["Sarah Connor", "bob", "Mary Jane Watson", "",
                     "ada lovelace", "  Kyle   Reese "] {
            let widgetsAnswer = name.split(separator: " ").prefix(2)
                .map { String($0.prefix(1)).uppercased() }.joined()
            XCTAssertEqual(LiveFriendsLiveRepository.initials(name), widgetsAnswer,
                           "the two avatar chips on Home must spell a friend the same way")
        }
    }

    func testEmptyRepositoryIsTheAbsentStrip() async {
        let live = await EmptyFriendsLiveRepository().live()
        XCTAssertTrue(live.isEmpty,
                      "owner ruling 2: no friend lifting means no strip, not an empty one")
    }
}
