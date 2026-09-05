import XCTest
@testable import GymSync

/// `ThemeStore.launchPin(from:)` is the seam behind `-gsPalette` /
/// `-gsAccent`, the launch arguments `ScreenshotTests.launchApp()` sets so
/// the 16 signed-in captures render the owner's onyx+sky look instead of the
/// CI account's persisted palette.
///
/// Pure-dictionary tests, no `ThemeStore` instance: the seam takes the
/// argument-domain dictionary as a parameter precisely so tests never touch
/// the process-wide `NSArgumentDomain` (`setVolatileDomain(_:forName:)`
/// raises when the domain already exists, and that one always does) — the
/// same shape as `OneShotFlagsTests`' launch-argument coverage.
final class ThemeStoreLaunchPinTests: XCTestCase {

    /// The keys are a CONTRACT with a target that can't import them: the UI
    /// test bundle runs out-of-process and writes these as string literals.
    /// A rename that skipped this assertion would leave the capture suite
    /// silently unpinned — back to the CI account's palette, with a green run.
    func testArgumentKeysMatchWhatTheUITestSuiteWrites() {
        XCTAssertEqual(ThemeLaunchArgument.palette, "gsPalette")
        XCTAssertEqual(ThemeLaunchArgument.accent, "gsAccent")
    }

    func testBothArgumentsPresentPinBoth() {
        let pin = ThemeStore.launchPin(from: ["gsPalette": "onyx", "gsAccent": "sky"])
        XCTAssertEqual(pin.palette, "onyx")
        XCTAssertEqual(pin.accent, "sky")
    }

    func testOnlyPaletteSuppliedPinsOnlyPalette() {
        let pin = ThemeStore.launchPin(from: ["gsPalette": "arena"])
        XCTAssertEqual(pin.palette, "arena")
        XCTAssertNil(pin.accent, "a missing key must not invent an accent")
    }

    func testOnlyAccentSuppliedPinsOnlyAccent() {
        let pin = ThemeStore.launchPin(from: ["gsAccent": "lime"])
        XCTAssertNil(pin.palette, "a missing key must not invent a palette")
        XCTAssertEqual(pin.accent, "lime")
    }

    /// `GSPalettes.theme(for:)` and `GSAccents.accent(for:)` are TOTAL — they
    /// degrade an unknown id to midnight/sky rather than failing. Resolving a
    /// typo through them would silently pin the wrong look and read as a
    /// palette bug, so the seam rejects unknown names and lets the seed stand.
    func testUnknownNamesAreIgnoredPerKey() {
        let pin = ThemeStore.launchPin(from: ["gsPalette": "onxy", "gsAccent": "chartreuse"])
        XCTAssertNil(pin.palette)
        XCTAssertNil(pin.accent)

        let mixed = ThemeStore.launchPin(from: ["gsPalette": "onyx", "gsAccent": "chartreuse"])
        XCTAssertEqual(mixed.palette, "onyx", "one bad key must not discard the other")
        XCTAssertNil(mixed.accent)
    }

    func testEmptyDictionaryPinsNothing() {
        let pin = ThemeStore.launchPin(from: [:])
        XCTAssertNil(pin.palette)
        XCTAssertNil(pin.accent)
    }

    /// Every id offered by the pickers is pinnable — a palette that shipped
    /// without joining this seam would be uncapturable.
    func testEveryRegisteredPaletteAndAccentIDIsPinnable() {
        for option in GSPalettes.all {
            XCTAssertEqual(ThemeStore.launchPin(from: ["gsPalette": option.id]).palette, option.id)
        }
        for accent in GSAccents.all {
            XCTAssertEqual(ThemeStore.launchPin(from: ["gsAccent": accent.id]).accent, accent.id)
        }
    }

    /// Launch arguments arrive as strings; surrounding whitespace from a
    /// hand-typed `xcodebuild` invocation shouldn't cost a 25-minute run.
    func testValuesAreTrimmed() {
        let pin = ThemeStore.launchPin(from: ["gsPalette": " onyx ", "gsAccent": "sky\n"])
        XCTAssertEqual(pin.palette, "onyx")
        XCTAssertEqual(pin.accent, "sky")
    }

    /// Non-string values (a real `Bool`/`NSNumber` in the domain) are not
    /// palette names — ignore rather than stringify.
    func testNonStringValuesAreIgnored() {
        let pin = ThemeStore.launchPin(from: ["gsPalette": 1, "gsAccent": true])
        XCTAssertNil(pin.palette)
        XCTAssertNil(pin.accent)
    }
}
