import XCTest
@testable import GymSync

// Pure-function coverage for `Decimal.parseUserInput(_:)` (Models/Decimal+
// ParseUserInput.swift, Phase O Task 2) — no network/auth/UI dependency,
// same "hermetic derivation" idiom as `PlateMathTests`/`StatDerivationTests`.
final class DecimalParsingTests: XCTestCase {

    // MARK: - Period separator (the pre-existing, always-worked case)

    func testParsesPeriodSeparator() {
        XCTAssertEqual(Decimal.parseUserInput("72.5"), Decimal(string: "72.5"))
    }

    func testParsesPlainInteger() {
        XCTAssertEqual(Decimal.parseUserInput("135"), 135)
    }

    // MARK: - Comma separator (the bug this helper fixes — a `.decimalPad`
    // keyboard shows a comma as its decimal key on comma-locale devices)

    func testParsesCommaSeparator() {
        XCTAssertEqual(Decimal.parseUserInput("72,5"), Decimal(string: "72.5"))
    }

    func testCommaAndPeriodProduceTheIdenticalValue() {
        // The whole point: same numeric value in, regardless of which
        // separator character the device's keyboard produced.
        XCTAssertEqual(Decimal.parseUserInput("72,5"), Decimal.parseUserInput("72.5"))
    }

    func testParsesCommaSeparatorWithTrailingZero() {
        XCTAssertEqual(Decimal.parseUserInput("45,0"), Decimal(string: "45.0"))
    }

    // MARK: - Invalid cases

    func testEmptyStringIsInvalid() {
        XCTAssertNil(Decimal.parseUserInput(""))
    }

    func testNonNumericStringIsInvalid() {
        XCTAssertNil(Decimal.parseUserInput("abc"))
    }

    func testDoubleSeparatorIsInvalid() {
        // Thousands-grouped input ("1,234.5" / "1.234,5") is explicitly out
        // of scope for a single weight/count field — reject rather than
        // guess which separator is the "real" decimal point.
        XCTAssertNil(Decimal.parseUserInput("1,234.5"))
        XCTAssertNil(Decimal.parseUserInput("1.234,5"))
    }

    func testTwoCommasIsInvalid() {
        XCTAssertNil(Decimal.parseUserInput("1,2,3"))
    }

    func testTwoPeriodsIsInvalid() {
        XCTAssertNil(Decimal.parseUserInput("1.2.3"))
    }

    func testWhitespaceOnlyIsInvalid() {
        XCTAssertNil(Decimal.parseUserInput("   "))
    }

    func testTabOnlyIsInvalid() {
        // Same bug class as the space-only case: `Decimal(string:locale:)`
        // parses ANY whitespace-only string as 0 rather than failing — the
        // fix trims via `.whitespacesAndNewlines`, which covers tabs too.
        XCTAssertNil(Decimal.parseUserInput("\t"))
    }

    func testLoneSeparatorAfterTrimIsInvalid() {
        // A string that trims down to just a separator with no digits
        // (" . " -> ".") must still fail — trimming doesn't change this.
        XCTAssertNil(Decimal.parseUserInput(" . "))
    }

    // MARK: - Incidental leading/trailing whitespace around real digits
    // (deliberately ACCEPTED after trimming — see the helper's own
    // "WHITESPACE FIX" doc comment for why: trimmed "5" is an unambiguous
    // user intent, no reason to reject it just because of stray whitespace)

    func testLeadingAndTrailingWhitespaceAroundDigitsIsAccepted() {
        XCTAssertEqual(Decimal.parseUserInput(" 5 "), 5)
    }

    // MARK: - Zero / negative pass-through (this helper only parses — the
    // "> 0" business rule stays each call site's own responsibility, same
    // as before this fix)

    func testParsesZero() {
        XCTAssertEqual(Decimal.parseUserInput("0"), 0)
    }

    func testParsesNegativeValue() {
        // Not expected from a `.decimalPad` in practice, but the parser
        // itself has no opinion on sign — callers already gate on `> 0`.
        XCTAssertEqual(Decimal.parseUserInput("-5"), -5)
    }
}
