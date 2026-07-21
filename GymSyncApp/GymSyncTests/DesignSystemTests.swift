import XCTest
import UIKit
import SwiftUI
@testable import GymSync

final class DesignSystemTests: XCTestCase {

    // MARK: - Font bundling tests
    //
    // These prove that:
    //  (a) the Archivo TTFs are bundled in the app target, and
    //  (b) the UIAppFonts Info.plist key registered the PostScript names with
    //      Core Text so UIFont(name:size:) can resolve them.
    //
    // If any assertion fails, the test prints every available family name so
    // the PostScript name strings can be corrected without guessing.

    func testArchivoRegularLoads() {
        let font = UIFont(name: "Archivo-Regular", size: 12)
        if font == nil {
            XCTFail(fontDiagnostic(expected: "Archivo-Regular"))
        }
        XCTAssertNotNil(font, "Archivo-Regular must load from the app bundle")
    }

    func testArchivoMediumLoads() {
        let font = UIFont(name: "Archivo-Medium", size: 12)
        if font == nil {
            XCTFail(fontDiagnostic(expected: "Archivo-Medium"))
        }
        XCTAssertNotNil(font, "Archivo-Medium must load from the app bundle")
    }

    func testArchivoSemiBoldLoads() {
        let font = UIFont(name: "Archivo-SemiBold", size: 12)
        if font == nil {
            XCTFail(fontDiagnostic(expected: "Archivo-SemiBold"))
        }
        XCTAssertNotNil(font, "Archivo-SemiBold must load from the app bundle")
    }

    func testArchivoBoldLoads() {
        let font = UIFont(name: "Archivo-Bold", size: 12)
        if font == nil {
            XCTFail(fontDiagnostic(expected: "Archivo-Bold"))
        }
        XCTAssertNotNil(font, "Archivo-Bold must load from the app bundle")
    }

    // MARK: - Token colour tests

    /// midnight.accent should resolve to approximately #38bdf8.
    func testMidnightAccentColour() {
        let accentColor = GSTheme.midnight.accent
        let uiColor = UIColor(accentColor)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let expectedR = CGFloat(0x38) / 255.0  // 0.2196...
        let expectedG = CGFloat(0xbd) / 255.0  // 0.7412...
        let expectedB = CGFloat(0xf8) / 255.0  // 0.9725...
        let tolerance: CGFloat = 0.01

        XCTAssertEqual(r, expectedR, accuracy: tolerance, "accent red component mismatch")
        XCTAssertEqual(g, expectedG, accuracy: tolerance, "accent green component mismatch")
        XCTAssertEqual(b, expectedB, accuracy: tolerance, "accent blue component mismatch")
        XCTAssertEqual(a, 1.0,       accuracy: tolerance, "accent alpha must be 1.0")
    }

    // MARK: - Palette activation tests (Canvas Completion Task 5)
    //
    // Spot-checks bg/surface/accent for each new palette against the exact
    // hex values transcribed from the canvas's `.gs-theme[data-palette=...]`
    // CSS custom-property rules (`docs/design/Gym Sync App Designs.dc.html`).
    // `assertColor` reuses `testMidnightAccentColour`'s component-compare
    // approach rather than duplicating it three more times.

    func testArenaTokens() {
        assertColor(GSTheme.arena.bg,      hex: 0x101310, label: "arena.bg")
        assertColor(GSTheme.arena.surface, hex: 0x1b1f19, label: "arena.surface")
        assertColor(GSTheme.arena.accent,  hex: 0xb6f236, label: "arena.accent")
        XCTAssertTrue(GSTheme.arena.isDark, "arena is a near-black dark palette")
    }

    func testInkTokens() {
        assertColor(GSTheme.ink.bg,      hex: 0xf3efe6, label: "ink.bg")
        assertColor(GSTheme.ink.surface, hex: 0xe8e2d5, label: "ink.surface")
        assertColor(GSTheme.ink.accent,  hex: 0x22345c, label: "ink.accent")
        XCTAssertFalse(GSTheme.ink.isDark, "ink is a light (warm bone bg / dark navy text) palette")
    }

    func testModernistTokens() {
        assertColor(GSTheme.modernist.bg,      hex: 0xf3f2f2, label: "modernist.bg")
        assertColor(GSTheme.modernist.surface, hex: 0xeae9e9, label: "modernist.surface")
        assertColor(GSTheme.modernist.accent,  hex: 0xec3013, label: "modernist.accent")
        XCTAssertFalse(GSTheme.modernist.isDark, "modernist is a light (bone bg / near-black text) palette")
    }

    func testGSPalettesResolvesEachID() {
        XCTAssertEqual(GSPalettes.name(for: "midnight"), "Midnight")
        XCTAssertEqual(GSPalettes.name(for: "arena"), "Arena")
        XCTAssertEqual(GSPalettes.name(for: "ink"), "Ink")
        XCTAssertEqual(GSPalettes.name(for: "modernist"), "Modernist")
        // Unrecognized ids degrade to the midnight default rather than crash.
        XCTAssertEqual(GSPalettes.name(for: "not-a-palette"), "Midnight")
    }

    // MARK: - Onyx palette (redesign default)

    func testOnyxTokens() {
        assertColor(GSTheme.onyx.bg,      hex: 0x0A0B0D, label: "onyx.bg")
        assertColor(GSTheme.onyx.surface, hex: 0x16181D, label: "onyx.surface")
        assertColor(GSTheme.onyx.text,    hex: 0xF3F5F8, label: "onyx.text")
        XCTAssertTrue(GSTheme.onyx.isDark, "onyx is a near-black dark palette")
    }

    func testOnyxRegisteredAsDefault() {
        XCTAssertEqual(GSPalettes.all.first?.id, "onyx", "onyx leads the palette list")
        XCTAssertEqual(GSPalettes.name(for: "onyx"), "Onyx")
        assertColor(GSPalettes.theme(for: "onyx").bg, hex: 0x0A0B0D, label: "resolved onyx.bg")
    }

    // MARK: - GSAccent (decoupled user-selectable accent)

    func testAccentKnownPresetResolves() {
        XCTAssertEqual(GSAccents.accent(for: "amber").id, "amber")
        XCTAssertEqual(GSAccents.accent(for: "lime").name, "Lime")
        assertColor(GSAccents.sky.base, hex: 0x38BDF8, label: "sky.base")
    }

    func testAccentUnknownFallsBackToSky() {
        XCTAssertEqual(GSAccents.accent(for: "banana").id, "sky")
        XCTAssertEqual(GSAccents.accent(for: "").id, "sky")
    }

    func testAccentCustomHexParses() {
        let c = GSAccents.accent(for: "#7c9cff")
        XCTAssertEqual(c.id, "#7c9cff")
        assertColor(c.base, hex: 0x7C9CFF, label: "custom accent base")
    }

    func testAccentCustomHexRejectsMalformed() {
        // wrong length, missing '#', and non-hex all degrade to sky
        XCTAssertEqual(GSAccents.accent(for: "#7c9cf").id, "sky")
        XCTAssertEqual(GSAccents.accent(for: "7c9cff").id, "sky")
        XCTAssertEqual(GSAccents.accent(for: "#zzzzzz").id, "sky")
    }

    func testAccentOnAccentLuminanceSplit() {
        // A light custom accent gets dark ink text; a dark one gets near-white.
        assertColor(GSAccents.accent(for: "#f5f5f5").onAccent, hex: 0x0A0B0D, label: "onAccent on light custom")
        assertColor(GSAccents.accent(for: "#101010").onAccent, hex: 0xF3F5F8, label: "onAccent on dark custom")
    }

    // MARK: - Helpers

    /// Asserts `color` resolves to `hex` (24-bit RGB, alpha 1.0) within a
    /// small tolerance — same component-compare approach as
    /// `testMidnightAccentColour`, generalized so each new-palette test can
    /// spot-check multiple tokens in one line.
    private func assertColor(_ color: Color, hex: UInt32, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let expectedR = CGFloat((hex >> 16) & 0xff) / 255.0
        let expectedG = CGFloat((hex >>  8) & 0xff) / 255.0
        let expectedB = CGFloat( hex        & 0xff) / 255.0
        let tolerance: CGFloat = 0.01

        XCTAssertEqual(r, expectedR, accuracy: tolerance, "\(label) red component mismatch", file: file, line: line)
        XCTAssertEqual(g, expectedG, accuracy: tolerance, "\(label) green component mismatch", file: file, line: line)
        XCTAssertEqual(b, expectedB, accuracy: tolerance, "\(label) blue component mismatch", file: file, line: line)
        XCTAssertEqual(a, 1.0,       accuracy: tolerance, "\(label) alpha must be 1.0", file: file, line: line)
    }

    private func fontDiagnostic(expected: String) -> String {
        let families = UIFont.familyNames.sorted()
        var allFonts: [String] = []
        for family in families {
            allFonts.append("  Family: \(family)")
            for name in UIFont.fontNames(forFamilyName: family) {
                allFonts.append("    Font: \(name)")
            }
        }
        return """
        UIFont(name: "\(expected)", size: 12) returned nil.
        Available families and fonts:
        \(allFonts.joined(separator: "\n"))
        """
    }
}
