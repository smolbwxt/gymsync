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

    // MARK: - Helpers

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
