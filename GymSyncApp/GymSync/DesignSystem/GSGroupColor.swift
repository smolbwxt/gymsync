import SwiftUI

/// Group identity colors — the second of the redesign's two independent color
/// systems (spec §4). Each group gets a **stable, deterministic** color drawn
/// from the Okabe-Ito colorblind-safe qualitative palette, keyed off its UUID.
/// Group colors NEVER change with the user's accent (a group's color is part
/// of its identity); collision handling lives on the accent side — the
/// Okabe-Ito set and the accent presets are mutually distinct by construction.
///
/// Deterministic across launches AND devices: derived from the UUID's raw
/// bytes, NOT `Hashable`/`Hasher` (Swift's Hasher is randomly seeded per
/// process, which would reshuffle every group's color on every launch).
///
/// A future `groups.color` override column (admin-picked wheel/hex) takes
/// precedence when present — pass it through `color(for:override:)`.
public enum GSGroupColor {

    /// Okabe-Ito qualitative palette (minus black/gray, which vanish on the
    /// near-black Onyx ground) — distinguishable under deuteranopia,
    /// protanopia, and tritanopia.
    public static let palette: [Color] = [
        .gsHex(0xE69F00),  // orange
        .gsHex(0x009E73),  // bluish green
        .gsHex(0xCC79A7),  // reddish purple
        .gsHex(0x0072B2),  // blue
        .gsHex(0xD55E00),  // vermilion
        .gsHex(0xF0E442),  // yellow
        .gsHex(0x56B4E9),  // sky (lighter than the accent preset's #38BDF8)
    ]

    /// The group's identity color: an admin override when set (a '#rrggbb'
    /// string, parsed leniently), else the stable palette pick.
    public static func color(for groupID: UUID, override: String? = nil) -> Color {
        if let override, override.hasPrefix("#"), override.count == 7,
           let v = UInt32(override.dropFirst(), radix: 16) {
            return .gsHex(v)
        }
        return palette[stableIndex(of: groupID)]
    }

    /// Ink to place ON a group-color fill (initials in an avatar tile). All
    /// current palette entries are mid-to-light hues, so near-black ink reads
    /// on every one; overrides get a luminance split.
    public static func onColor(for groupID: UUID, override: String? = nil) -> Color {
        if let override, override.hasPrefix("#"), override.count == 7,
           let v = UInt32(override.dropFirst(), radix: 16) {
            let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            return lum > 0.5 ? .gsHex(0x0A0B0D) : .gsHex(0xF3F5F8)
        }
        return .gsHex(0x0A0B0D)
    }

    /// Sums the UUID's 16 raw bytes — order-independent but stable, cheap,
    /// and evenly spread enough for a 7-entry palette.
    static func stableIndex(of id: UUID) -> Int {
        let b = id.uuid
        let sum = Int(b.0) + Int(b.1) + Int(b.2) + Int(b.3)
                + Int(b.4) + Int(b.5) + Int(b.6) + Int(b.7)
                + Int(b.8) + Int(b.9) + Int(b.10) + Int(b.11)
                + Int(b.12) + Int(b.13) + Int(b.14) + Int(b.15)
        return sum % palette.count
    }
}
