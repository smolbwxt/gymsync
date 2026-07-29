import XCTest
@testable import GymSync

/// Rep targets are FREE TEXT (`routine_exercises.target_reps`) and the app's
/// own routine builder seeds every new item with a range ("8-12"). A bare
/// `Int("8-12")` is nil, which shipped two live defects: Save Set was
/// disabled on the default routine, and tapping "+" reset the field to 1.
/// These pin the parser that fixes both.
final class RepTargetTests: XCTestCase {

    func testLeadingIntParsesTheCommonTargetShapes() {
        XCTAssertEqual(leadingInt("12"), 12)
        XCTAssertEqual(leadingInt("8-12"), 8, "a range resolves to its low end")
        XCTAssertEqual(leadingInt("8–12"), 8, "en dash, as typed on iOS")
        XCTAssertEqual(leadingInt("5+"), 5)
        XCTAssertEqual(leadingInt(" 10 "), 10)
        XCTAssertEqual(leadingInt("3x5"), 3)
    }

    func testLeadingIntReturnsNilWhenThereIsNoNumber() {
        XCTAssertNil(leadingInt(""))
        XCTAssertNil(leadingInt("AMRAP"))
        XCTAssertNil(leadingInt("failure"))
    }

    /// The destructive case: `(Int(s) ?? 0) + 1` turned the shipped "8-12"
    /// default into "1" on the first tap of the stepper.
    func testIncrementStepsFromTheRangeRatherThanWipingIt() {
        var s = "8-12"
        incrementInt(&s)
        XCTAssertEqual(s, "9")

        var plain = "10"
        incrementInt(&plain)
        XCTAssertEqual(plain, "11")

        var empty = ""
        incrementInt(&empty)
        XCTAssertEqual(empty, "1", "an empty field still starts at 1")
    }
}
