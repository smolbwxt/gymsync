import XCTest
@testable import GymSync

/// The rotation strip's tile — plan task S2, spec §3.4 mode 2.
///
/// The drawing is proved by a frame. What a frame cannot prove is that a tile
/// WITHOUT a scale-down carries nothing rather than an empty string: the
/// difference between the two is whether the strip's baselines move on frames
/// 137-139, which constraint 14 freezes.
final class TurnStripTests: XCTestCase {

    private let sam = UUID(uuidString: "00000000-0000-0000-0000-0000000001a3") ?? UUID()
    private let lee = UUID(uuidString: "00000000-0000-0000-0000-0000000001a4") ?? UUID()

    /// Every tile built before this task omitted the argument entirely, and
    /// must keep meaning "no line".
    func testATileWithoutAScaleDownCarriesNothing() {
        let tile = TurnStrip.Tile(id: lee, label: "NEXT", name: "Lee", isNow: false)
        XCTAssertNil(tile.doing)
    }

    /// An EMPTY string is not the absent case — the view draws whatever it is
    /// handed, so an absence has to arrive as `nil`.
    func testAnEmptyLineIsNotTheSameAsNoLine() {
        let tile = TurnStrip.Tile(id: lee, label: "NEXT", name: "Lee",
                                  isNow: false, doing: "")
        XCTAssertNotNil(tile.doing)
        XCTAssertEqual(tile.doing, "")
    }

    func testATileWithAScaleDownNamesTheLiftTheyAreActuallyOn() {
        let tile = TurnStrip.Tile(id: sam, label: "NOW", name: "Sam",
                                  isNow: true, doing: "Goblet squat")
        XCTAssertEqual(tile.doing, "Goblet squat")
    }

    /// The speaking ring stays defaulted when only `doing` is supplied — the
    /// two are independent facts and the trailing default must not swallow
    /// the one before it.
    func testDoingDoesNotDisturbTheSpeakingRing() {
        let tile = TurnStrip.Tile(id: sam, label: "NOW", name: "Sam",
                                  isNow: true, doing: "Goblet squat")
        XCTAssertFalse(tile.isSpeaking)
    }

    // MARK: - The world the frame renders

    /// Frame 143: exactly one lifter is on something else, and nobody else's
    /// tile says anything at all. A frame with two scale-downs would read as
    /// an announcement, which is the one thing mode 2 is not.
    func testTheCatalogWorldScalesExactlyOneLifterDown() {
        let world = LiveFixtures.scaleDown
        let scaled = world.turn.filter { $0.doing != nil }
        XCTAssertEqual(scaled.count, 1)
        XCTAssertEqual(scaled.first?.name, "Sam")
        XCTAssertEqual(scaled.first?.doing, "Goblet squat")
        XCTAssertTrue(scaled.first?.isNow == true)
    }

    /// Frame 139 is frozen (constraint 14): the spotter world it renders must
    /// carry no `doing` at all, or its tiles grow a third line.
    func testTheFrozenSpotterWorldGainsNoLine() {
        XCTAssertTrue(LiveFixtures.spotter.turn.allSatisfy { $0.doing == nil })
    }
}
