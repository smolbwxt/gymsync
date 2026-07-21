import SwiftUI

// MARK: - GSTheme

/// The GymSync design-system token bag.
/// Midnight values are verbatim from the "Midnight tokens" table in the
/// 2026-07-12-design-adoption-midnight plan (Global Constraints section).
/// Arena/Ink/Modernist values (Canvas Completion Task 5) are transcribed
/// verbatim from the committed canvas's `<style>` block —
/// `docs/design/Gym Sync App Designs.dc.html`, the `.gs-theme[data-palette=
/// "arena"|"ink"|"modernist"]` CSS custom-property rules. Every `--color-*`
/// var maps 1:1 to the property of the same name below (e.g. `--color-
/// accent-600` → `accent600`); nothing is "corrected" even where a ramp
/// looks unusual (ink's `accent700` and `accent800` are identically
/// `#16233d` in the source CSS — kept as written).
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

    /// Drives `.preferredColorScheme` — `true` for midnight/arena (near-black
    /// backgrounds, light text), `false` for ink/modernist (light backgrounds,
    /// dark text). Determined from each palette's `bg`/`text` hex luminance,
    /// corroborated by the canvas's own shadow-token grouping (ink and
    /// modernist share the light-surface `color-mix(in srgb,#2d2b2b ...)`
    /// shadow formula; midnight and arena share the dark-surface plain
    /// `rgba(0,0,0,...)` formula) — see task-5-report.md for the full
    /// determination.
    public let isDark: Bool

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
        neutral900: Color(hex: 0xeef2f7),

        isDark: true
    )

    // MARK: - Onyx palette (redesign default) — near-black surfaces.
    //
    // The redesign decouples the accent from the palette: the user's accent is
    // applied separately via `\.gsAccent` (GSAccent.swift), so the accent ramp
    // below is a placeholder (reused midnight cyan values) present only to
    // satisfy the `GSTheme` initializer. Redesigned components read `\.gsAccent`,
    // never `theme.accent`. neutral100/300 intentionally equal surface/surface2
    // (#16181D / #1E222A) so existing `neutral*`-keyed chrome lands on the new
    // elevated surfaces.
    public static let onyx = GSTheme(
        bg:         Color(hex: 0x0A0B0D),
        surface:    Color(hex: 0x16181D),
        text:       Color(hex: 0xF3F5F8),
        divider:    Color.white.opacity(0.07),

        accent:     Color(hex: 0x38BDF8),   // placeholder; UI reads \.gsAccent
        accent100:  Color(hex: 0x0E2C3A),
        accent200:  Color(hex: 0x123A4D),
        accent300:  Color(hex: 0x17506B),
        accent600:  Color(hex: 0x22A6E4),
        accent700:  Color(hex: 0x7DD3FC),
        accent800:  Color(hex: 0xBAE6FD),

        neutral100: Color(hex: 0x16181D),
        neutral300: Color(hex: 0x1E222A),
        neutral400: Color(hex: 0x3A414B),
        neutral500: Color(hex: 0x5C616B),
        neutral700: Color(hex: 0x868B95),
        neutral800: Color(hex: 0xCFD4DB),
        neutral900: Color(hex: 0xF3F5F8),

        isDark: true
    )

    // MARK: - Arena palette
    // Canvas: .gs-theme[data-palette="arena"] — "Near-black · volt lime".

    public static let arena = GSTheme(
        bg:         Color(hex: 0x101310),
        surface:    Color(hex: 0x1b1f19),
        text:       Color(hex: 0xeef3e8),
        divider:    Color.white.opacity(0.14),

        accent:     Color(hex: 0xb6f236),
        accent100:  Color(hex: 0x1e2a0e),
        accent200:  Color(hex: 0x2b3d13),
        accent300:  Color(hex: 0x3c541b),
        accent600:  Color(hex: 0xa3e01f),
        accent700:  Color(hex: 0xcdf76a),
        accent800:  Color(hex: 0xdcfb9a),

        neutral100: Color(hex: 0x1a1e17),
        neutral300: Color(hex: 0x2c312a),
        neutral400: Color(hex: 0x3c423a),
        neutral500: Color(hex: 0x6f766a),
        neutral700: Color(hex: 0x9ba295),
        neutral800: Color(hex: 0xced3c8),
        neutral900: Color(hex: 0xeef3e8),

        isDark: true
    )

    // MARK: - Ink palette
    // Canvas: .gs-theme[data-palette="ink"] — "Warm bone · deep navy".
    // NOTE: light theme (bg is a light cream, text is dark navy) despite the
    // dark-sounding accent color — see `isDark`'s doc comment.

    public static let ink = GSTheme(
        bg:         Color(hex: 0xf3efe6),
        surface:    Color(hex: 0xe8e2d5),
        text:       Color(hex: 0x1b2540),
        divider:    Color(hex: 0x1b2540).opacity(0.26),

        accent:     Color(hex: 0x22345c),
        accent100:  Color(hex: 0xe3e6ee),
        accent200:  Color(hex: 0xc8cfdf),
        accent300:  Color(hex: 0xa9b3ca),
        accent600:  Color(hex: 0x1a2947),
        accent700:  Color(hex: 0x16233d),
        accent800:  Color(hex: 0x16233d),

        neutral100: Color(hex: 0xefe9dd),
        neutral300: Color(hex: 0xd3ccbd),
        neutral400: Color(hex: 0xb4ab98),
        neutral500: Color(hex: 0x8b8371),
        neutral700: Color(hex: 0x4c4638),
        neutral800: Color(hex: 0x353026),
        neutral900: Color(hex: 0x211d16),

        isDark: false
    )

    // MARK: - Modernist palette
    // Canvas: .gs-theme[data-palette="modernist"] — "Bone · signal red".

    public static let modernist = GSTheme(
        bg:         Color(hex: 0xf3f2f2),
        surface:    Color(hex: 0xeae9e9),
        text:       Color(hex: 0x201e1d),
        divider:    Color(hex: 0x201e1d).opacity(0.4),

        accent:     Color(hex: 0xec3013),
        accent100:  Color(hex: 0xfff2ef),
        accent200:  Color(hex: 0xffe0d9),
        accent300:  Color(hex: 0xffc4b8),
        accent600:  Color(hex: 0xdd2b0f),
        accent700:  Color(hex: 0xae1800),
        accent800:  Color(hex: 0x7c1405),

        neutral100: Color(hex: 0xf8f4f4),
        neutral300: Color(hex: 0xd7d3d3),
        neutral400: Color(hex: 0xbab6b6),
        neutral500: Color(hex: 0x9b9797),
        neutral700: Color(hex: 0x605d5d),
        neutral800: Color(hex: 0x444141),
        neutral900: Color(hex: 0x2d2b2b),

        isDark: false
    )

    // MARK: - Accent override (redesign)

    /// Returns a copy of this palette with its accent ramp replaced by the
    /// user's chosen `GSAccent`. The redesign decouples accent from palette:
    /// `RootView` injects `current.withAccent(themeStore.accent)` as `\.gsTheme`,
    /// so every existing component that reads `theme.accent*` transparently
    /// picks up the user's accent without being individually rewired.
    /// `bg`/`surface`/`neutral*` are untouched — only the accent ramp changes.
    /// `bg` (which the button styles use as the on-accent text color) stays the
    /// palette's ground; on Onyx that near-black reads correctly on every bright
    /// preset accent. The ramp steps collapse to base/soft because `GSAccent`
    /// carries a single hue (base) + one tint (soft), not a full 100–900 scale.
    public func withAccent(_ accent: GSAccent) -> GSTheme {
        GSTheme(
            bg: bg, surface: surface, text: text, divider: divider,
            accent: accent.base,
            accent100: accent.soft,
            accent200: accent.soft,
            accent300: accent.soft,
            accent600: accent.base,
            accent700: accent.base,
            accent800: accent.base,
            neutral100: neutral100, neutral300: neutral300, neutral400: neutral400,
            neutral500: neutral500, neutral700: neutral700, neutral800: neutral800,
            neutral900: neutral900,
            isDark: isDark
        )
    }
}

// MARK: - GSPalettes
//
// Metadata (id/name/subtitle) for every palette, keyed by the exact string
// `user_settings.palette` persists (the migration's CHECK constraint values:
// midnight/arena/ink/modernist). Single source of truth for AppearanceView's
// row list, YouTabView's Settings Hub value preview, and ThemeStore's
// id → GSTheme resolution — name/subtitle text transcribed verbatim from the
// canvas's Theme Picker markup (proof p33-theme-picker).

public struct GSPaletteOption: Identifiable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let theme: GSTheme
}

public enum GSPalettes {
    public static let all: [GSPaletteOption] = [
        GSPaletteOption(id: "onyx",      name: "Onyx",      subtitle: "Near-black · your accent", theme: .onyx),
        GSPaletteOption(id: "midnight",  name: "Midnight",  subtitle: "Charcoal · electric cyan", theme: .midnight),
        GSPaletteOption(id: "arena",     name: "Arena",     subtitle: "Near-black · volt lime",    theme: .arena),
        GSPaletteOption(id: "ink",       name: "Ink",       subtitle: "Warm bone · deep navy",     theme: .ink),
        GSPaletteOption(id: "modernist", name: "Modernist", subtitle: "Bone · signal red",         theme: .modernist),
    ]

    /// Falls back to `.midnight` for any unrecognized id (matches
    /// `UserSettings.defaults`' own "midnight" default, and keeps this total
    /// rather than failable/optional — an unrecognized persisted value
    /// should degrade to the default look, not crash or show nothing).
    public static func theme(for id: String) -> GSTheme {
        all.first { $0.id == id }?.theme ?? .midnight
    }

    public static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? "Midnight"
    }
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
    static let defaultValue: GSTheme = .onyx   // redesign default
}

public extension EnvironmentValues {
    var gsTheme: GSTheme {
        get { self[GSThemeKey.self] }
        set { self[GSThemeKey.self] = newValue }
    }
}
