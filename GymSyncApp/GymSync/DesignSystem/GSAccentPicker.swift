import SwiftUI
import UIKit

/// The personal-accent picker — the control that lets a lifter recolor the
/// whole app. Its home is the You tab's Appearance section (Plan 3) and the
/// first-run flow. A row of the `GSAccents` presets plus a custom color well
/// (wheel / hex). Selecting drives `ThemeStore.selectAccent(_:)`, which applies
/// live app-wide (via `\.gsAccent`) and persists to `user_settings.accent`.
///
/// Self-contained and non-breaking: it reads the foundation (GSAccent /
/// ThemeStore) but modifies no existing component.
public struct GSAccentPicker: View {
    @Environment(\.gsTheme) private var theme
    // `@State` singleton reference mirrors RootView's `themeStore` — the
    // @Observable ThemeStore must be read through a tracked property so a
    // selectAccent(_:) elsewhere re-renders this picker's selection ring.
    @State private var store = ThemeStore.shared
    @State private var customColor: Color = .clear

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(GSAccents.all) { accent in
                swatch(accent)
            }
            customWell
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func swatch(_ accent: GSAccent) -> some View {
        let selected = store.accentID == accent.id
        Button {
            store.selectAccent(accent.id)
        } label: {
            Circle()
                .fill(accent.base)
                .frame(width: 32, height: 32)
                // Mono is near-white, so it needs a hairline to read on a dark
                // ground; the others don't.
                .overlay(
                    accent.id == "mono"
                        ? Circle().strokeBorder(theme.divider, lineWidth: 1)
                        : nil
                )
                // Selection ring sits OUTSIDE the swatch (negative padding) so
                // it never overlaps the color itself.
                .overlay(
                    Circle()
                        .strokeBorder(theme.text, lineWidth: selected ? 2 : 0)
                        .padding(-4)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// The custom hue path — a native `ColorPicker` wheel that persists the
    /// chosen color as a '#rrggbb' string. Guarded by `\.gsAccent` law: once
    /// the user picks deliberately here, their choice owns the result (we stop
    /// guarding accent/group collisions — spec §4).
    private var customWell: some View {
        ColorPicker("", selection: $customColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32, height: 32)
            .overlay(
                store.accentID.hasPrefix("#")
                    ? Circle().strokeBorder(theme.text, lineWidth: 2).padding(-4)
                    : nil
            )
            .accessibilityLabel("Custom accent color")
            .onChange(of: customColor) { _, newValue in
                if let hex = newValue.gsHexString {
                    store.selectAccent(hex)
                }
            }
    }
}

public extension Color {
    /// Serializes to a lowercase '#rrggbb' string, or `nil` if the color can't
    /// resolve to RGB (e.g. a pattern/dynamic color). Round-trips with
    /// `GSAccents.customHex` (the wire format `user_settings.accent` persists).
    var gsHexString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp: (CGFloat) -> Int = { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }
}
