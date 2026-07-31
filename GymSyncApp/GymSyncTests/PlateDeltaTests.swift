import XCTest
@testable import GymSync

/// Pure-function coverage for `PlateDelta` — the spectator prep card's
/// STRIP/ADD math. Standard plates [45, 35, 25, 10, 5, 2.5], bar 45.
final class PlateDeltaTests: XCTestCase {

    func testSameWeightIsNoChange() {
        let d = PlateDelta.delta(fromWeight: 225, toWeight: 225)
        XCTAssertTrue(d.isNoChange)
        XCTAssertEqual(PlateDelta.headline(d), "BAR MATCHES")
    }

    func testAddOnly() {
        // 225 = bar + 2×45/side · 245 = bar + (2×45 + 10)/side
        let d = PlateDelta.delta(fromWeight: 225, toWeight: 245)
        XCTAssertEqual(d.strip, [])
        XCTAssertEqual(d.add, [PlateDelta.Change(plate: 10, count: 1)])
        XCTAssertEqual(PlateDelta.headline(d), "ADD 10")
    }

    func testStripAndAdd() {
        // 385/side = 170 → 45×3 + 35 · 415/side = 185 → 45×4 + 5
        let d = PlateDelta.delta(fromWeight: 385, toWeight: 415)
        XCTAssertEqual(d.strip, [PlateDelta.Change(plate: 35, count: 1)])
        XCTAssertEqual(d.add, [PlateDelta.Change(plate: 45, count: 1),
                               PlateDelta.Change(plate: 5, count: 1)])
        XCTAssertEqual(PlateDelta.headline(d), "STRIP 35 · ADD 45 + 5")
    }

    func testMultipleOfOnePlateCollapses() {
        // Empty bar → 225 = 2×45 per side.
        let d = PlateDelta.delta(fromWeight: 45, toWeight: 225)
        XCTAssertEqual(d.add, [PlateDelta.Change(plate: 45, count: 2)])
        XCTAssertEqual(PlateDelta.headline(d), "ADD 2×45")
    }

    func testFractionalPlates() {
        // 100/side = 27.5 → 25 + 2.5 · 105/side = 30 → 25 + 5
        let d = PlateDelta.delta(fromWeight: 100, toWeight: 105)
        XCTAssertEqual(d.strip, [PlateDelta.Change(plate: Decimal(string: "2.5")!, count: 1)])
        XCTAssertEqual(d.add, [PlateDelta.Change(plate: 5, count: 1)])
        XCTAssertEqual(PlateDelta.headline(d), "STRIP 2.5 · ADD 5")
    }

    func testCustomInventoryOrderIsRespected() {
        // Only 45s and 10s in the gym: 65→245 needs 2×45 + 1×10 per side.
        let plates: [Decimal] = [45, 10]
        let d = PlateDelta.delta(fromWeight: 65, toWeight: 245, plates: plates)
        XCTAssertEqual(d.strip, [])
        XCTAssertEqual(d.add, [PlateDelta.Change(plate: 45, count: 2)])
        // 65/side = 10 → one 10; 245/side = 100 → 2×45 + 10: the 10 stays.
        XCTAssertEqual(PlateDelta.headline(d), "ADD 2×45")
    }
}
