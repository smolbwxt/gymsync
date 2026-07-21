import SwiftUI

// MARK: - GSWatchTheme
//
// Phase W Task 1 (watch-hr design §1: "Design-system subset ported —
// GSTheme tokens + minimal type ramp — watch surfaces are tiny; no full
// GSComponents port"). A small, standalone port of ONLY the semantic
// tokens the Watch surfaces need (bg/surface/text/accent/divider) —
// deliberately NOT importing GymSync/DesignSystem/GSTheme.swift wholesale,
// since that file lives in the GymSync (iOS) target's `sources:` tree and
// target membership would drag UIKit-adjacent iOS design-system code into
// the watchOS target (a different platform SDK entirely — watchOS has no
// UIKit). Hex values transcribed verbatim from GSTheme.swift's four
// palettes — see that file's doc comment for their ultimate provenance
// (the canvas's `.gs-theme[data-palette=...]` CSS custom properties).
//
// Deliberately NOT ported: the full accent ramp (100/200/300/600/700/
// 800), the neutral ramp, and `isDark`. No theme picker or dark/light
// chrome switching exists on the Watch — none of the 4 Watch surfaces the
// design doc lists (whose-turn indicator, tap-to-log-set, soundboard,
// ledger glance) is a settings/appearance screen, and "Watch UI polish
// beyond system idioms" is explicitly deferred to Phase D. If/when a
// palette choice syncs from the phone (design §3, WatchConnectivity
// applicationContext), re-port GSPalettes' id->theme lookup from
// GSTheme.swift at that point (trimmed here as YAGNI — T1 review).
public struct GSWatchTheme {
    public let bg: Color
    public let surface: Color
    public let text: Color
    public let accent: Color
    public let divider: Color

    /// Onyx — the 2026-07-20 redesign's near-black default (values verbatim
    /// from GSTheme.onyx). Accent is the sky default: the phone's
    /// user-selected accent does NOT sync to the watch yet (no
    /// applicationContext plumbing for it) — wire alongside palette sync
    /// if/when that lands, per the note above.
    public static let onyx = GSWatchTheme(
        bg:      Color(hex: 0x0A0B0D),
        surface: Color(hex: 0x16181D),
        text:    Color(hex: 0xF3F5F8),
        accent:  Color(hex: 0x38BDF8),
        divider: Color.white.opacity(0.07)
    )

    public static let midnight = GSWatchTheme(
        bg:      Color(hex: 0x13161c),
        surface: Color(hex: 0x1e232c),
        text:    Color(hex: 0xeef2f7),
        accent:  Color(hex: 0x38bdf8),
        divider: Color.white.opacity(0.15)
    )

    // Trimmed per the T1 review's YAGNI adjudication: no arena/ink/modernist
    // and no id->theme lookup — zero call sites, no phone->watch palette
    // sync. Re-port from GSTheme.swift (GSPalettes) alongside whichever task
    // actually wires palette sync.
}

// MARK: - Hex Color initialiser (fileprivate)
//
// Identical in behavior to GSTheme.swift's own private initializer —
// duplicated rather than shared because the two files intentionally have
// zero target-membership overlap (see the top-of-file doc comment).

fileprivate extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >>  8) & 0xff) / 255.0
        let b = Double( hex        & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Environment

private struct GSWatchThemeKey: EnvironmentKey {
    static let defaultValue: GSWatchTheme = .onyx   // redesign default
}

public extension EnvironmentValues {
    var gsWatchTheme: GSWatchTheme {
        get { self[GSWatchThemeKey.self] }
        set { self[GSWatchThemeKey.self] = newValue }
    }
}
