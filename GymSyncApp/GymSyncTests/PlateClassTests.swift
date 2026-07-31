import XCTest
@testable import GymSync

/// Pure-function coverage for `PlateClass` — the plate dock's
/// duration → denomination bands under the 5-second sound cap.
final class PlateClassTests: XCTestCase {

    func testBandBoundaries() {
        XCTAssertEqual(PlateClass.forDuration(ms: nil), .five)
        XCTAssertEqual(PlateClass.forDuration(ms: 800), .five)
        XCTAssertEqual(PlateClass.forDuration(ms: 1500), .five)
        XCTAssertEqual(PlateClass.forDuration(ms: 1501), .ten)
        XCTAssertEqual(PlateClass.forDuration(ms: 2500), .ten)
        XCTAssertEqual(PlateClass.forDuration(ms: 2501), .twentyFive)
        XCTAssertEqual(PlateClass.forDuration(ms: 4000), .twentyFive)
        XCTAssertEqual(PlateClass.forDuration(ms: 4001), .fortyFive)
        XCTAssertEqual(PlateClass.forDuration(ms: 5000), .fortyFive)
    }

    func testPilotMapping() {
        // The four demo plates from the locked design (composite v5).
        XCTAssertEqual(PlateClass.forDuration(ms: 980), .five)        // HELL NAW
        XCTAssertEqual(PlateClass.forDuration(ms: 2030), .ten)        // HOORAY
        XCTAssertEqual(PlateClass.forDuration(ms: 3520), .twentyFive) // IBUPROFEN
        XCTAssertEqual(PlateClass.forDuration(ms: 5000), .fortyFive)  // GIGACHAD ✂
    }

    func testCooldownGrowsWithClass() {
        let ordered: [PlateClass] = [.five, .ten, .twentyFive, .fortyFive]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(a.cooldown, b.cooldown)
        }
    }

    func testDenominations() {
        XCTAssertEqual(PlateClass.five.denomination, 5)
        XCTAssertEqual(PlateClass.ten.denomination, 10)
        XCTAssertEqual(PlateClass.twentyFive.denomination, 25)
        XCTAssertEqual(PlateClass.fortyFive.denomination, 45)
    }
}
