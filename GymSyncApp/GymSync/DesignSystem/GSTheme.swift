import SwiftUI

// MARK: - GSTheme

/// The GymSync design-system token bag.
/// All midnight values are verbatim from the "Midnight tokens" table in the
/// 2026-07-12-design-adoption-midnight plan (Global Constraints section).
public struct GSTheme {

    // MARK: Surface & text
    public let bg: Color
    public let surface: Color
    public let text: Color
    public let divider: Color

    // MARK: Accent ramp
    public let accent: Color      // #38bdf8
    public let accent100: Color   // #0e2c3a
    public let accent200: Color   // #123a4d
    public let accent300: Color   // #17506b
    public let accent600: Color   // #22a6e4  (pressed / darker)
    public let accent700: Color   // #7dd3fc  (lighter tint)
    public let accent800: Color   // #bae6fd

    // MARK: Neutral ramp
    public let neutral100: Color  // #1a1e26
    public let neutral300: Color  // #2b3038
    public let neutral400: Color  // #3a414b
    public let neutral500: Color  // #6b7280
    public let neutral700: Color  // #9aa2ae
    public let neutral800: Color  // #cfd4db
    public let neutral900: Color  // #eef2f7

    // MARK: - Midnight palette

    public static let midnight = GSTheme(
        bg:         Color(hex: 0x13161c),
        surface:    Color(hex: 0x1e232c),
        text:       Color(hex: 0xeef2f7),
        divider:    Color.white.opacity(0.15),

        accent:     Color(hex: 0x38bdf8),
        accent100:  Color(hex: 0x0e2c3a),
        accent200:  Color(hex: 0x123a4d),
        accent300:  Color(hex: 0x17506b),
        accent600:  Color(hex: 0x22a6e4),
        accent700:  Color(hex: 0x7dd3fc),
        accent800:  Color(hex: 0xbae6fd),

        neutral100: Color(hex: 0x1a1e26),
        neutral300: Color(hex: 0x2b3038),
        neutral400: Color(hex: 0x3a414b),
        neutral500: Color(hex: 0x6b7280),
        neutral700: Color(hex: 0x9aa2ae),
        neutral800: Color(hex: 0xcfd4db),
        neutral900: Color(hex: 0xeef2f7)
    )
}

// MARK: - Hex Color initialiser (fileprivate)

fileprivate extension Color {
    /// Initialise a `Color` from a 24-bit RGB hex integer.
    /// Example: `Color(hex: 0x38bdf8)`
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >>  8) & 0xff) / 255.0
        let b = Double( hex        & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Environment

private struct GSThemeKey: EnvironmentKey {
    static let defaultValue: GSTheme = .midnight
}

public extension EnvironmentValues {
    var gsTheme: GSTheme {
        get { self[GSThemeKey.self] }
        set { self[GSThemeKey.self] = newValue }
    }
}
