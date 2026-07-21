import SwiftUI

/// The user's personal accent — decoupled from the palette in the redesign so
/// it can be chosen independently and recolor the whole app (buttons, active
/// states, streak ring, PR flame, chart strokes, the "you" row). Distinct from
/// the surface/neutral system carried by `GSTheme` (`\.gsTheme`) and from group
/// identity colors (a separate, stable, per-group system). Consumed app-wide
/// via the `\.gsAccent` environment key, injected by `RootView` from
/// `ThemeStore.shared.accent`.
public struct GSAccent: Identifiable, Equatable {
    /// A preset id ('sky'|'violet'|'amber'|'lime'|'coral'|'rose'|'mono') or a
    /// '#rrggbb' custom hex — exactly what `user_settings.accent` persists.
    public let id: String
    public let name: String
    /// The accent hue itself (fills, strokes, emphasis).
    public let base: Color
    /// A low-alpha tint of the accent (soft backgrounds, rest-timer chip, etc.).
    public let soft: Color
    /// The text/glyph color placed ON a filled `base` (contrast-safe).
    public let onAccent: Color
}

public enum GSAccents {
    public static let sky    = GSAccent(id: "sky",    name: "Sky blue", base: .gsHex(0x38BDF8), soft: .gsHex(0x38BDF8, 0.15), onAccent: .gsHex(0x04222E))
    public static let violet = GSAccent(id: "violet", name: "Violet",   base: .gsHex(0xA78BFA), soft: .gsHex(0xA78BFA, 0.16), onAccent: .gsHex(0x1C1233))
    public static let amber  = GSAccent(id: "amber",  name: "Amber",    base: .gsHex(0xFFB020), soft: .gsHex(0xFFB020, 0.16), onAccent: .gsHex(0x2A1C04))
    public static let lime   = GSAccent(id: "lime",   name: "Lime",     base: .gsHex(0xB6F236), soft: .gsHex(0xB6F236, 0.15), onAccent: .gsHex(0x1C2A06))
    public static let coral  = GSAccent(id: "coral",  name: "Coral",    base: .gsHex(0xFF6B5E), soft: .gsHex(0xFF6B5E, 0.16), onAccent: .gsHex(0x2E0F0B))
    public static let rose   = GSAccent(id: "rose",   name: "Rose",     base: .gsHex(0xFB7BB5), soft: .gsHex(0xFB7BB5, 0.16), onAccent: .gsHex(0x2E0F20))
    public static let mono   = GSAccent(id: "mono",   name: "Mono",     base: .gsHex(0xF3F5F8), soft: .gsHex(0xF3F5F8, 0.12), onAccent: .gsHex(0x0A0B0D))

    /// Ordered preset list — drives the AccentPicker's swatch row (Plan 2).
    public static let all: [GSAccent] = [sky, violet, amber, lime, coral, rose, mono]

    /// Total resolver: a known preset id, else a parseable '#rrggbb' custom,
    /// else `sky`. Never fails — an unrecognized persisted value degrades to
    /// the default, matching `GSPalettes.theme(for:)`'s total contract.
    public static func accent(for id: String) -> GSAccent {
        if let preset = all.first(where: { $0.id == id }) { return preset }
        if let custom = customHex(id) { return custom }
        return sky
    }

    /// Parses '#rrggbb' into a `GSAccent`, choosing `onAccent` by the hue's
    /// perceived luminance (dark ink on a light accent, near-white on a dark
    /// one) so button labels stay legible on any custom color.
    private static func customHex(_ s: String) -> GSAccent? {
        guard s.hasPrefix("#"), s.count == 7,
              let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff)
        let g = Double((v >> 8) & 0xff)
        let b = Double(v & 0xff)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        return GSAccent(
            id: s, name: "Custom",
            base: .gsHex(v),
            soft: Color.gsHex(v, 0.15),
            onAccent: luminance > 0.6 ? .gsHex(0x0A0B0D) : .gsHex(0xF3F5F8)
        )
    }
}

public extension Color {
    /// 24-bit RGB hex + optional alpha. Public sibling of GSTheme.swift's own
    /// (fileprivate) `Color(hex:)`; named distinctly to avoid colliding with it.
    static func gsHex(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0,
            opacity: alpha
        )
    }
}

private struct GSAccentKey: EnvironmentKey {
    static let defaultValue: GSAccent = GSAccents.sky
}

public extension EnvironmentValues {
    var gsAccent: GSAccent {
        get { self[GSAccentKey.self] }
        set { self[GSAccentKey.self] = newValue }
    }
}
