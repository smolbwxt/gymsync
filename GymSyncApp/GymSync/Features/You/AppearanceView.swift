import SwiftUI

/// Appearance — Settings Hub destination. Redesign (2026-07-20 visual-language
/// spec §4): two independent color systems live here —
///   1. **Your accent** (`GSAccentPicker`): the personal accent, applied
///      app-wide via `ThemeStore.selectAccent(_:)` → `\.gsAccent` + the
///      accent-overridden `\.gsTheme`. Default sky.
///   2. **Palette** rows: the surface system (Onyx default + the legacy
///      palettes), one row per `GSPalettes.all` entry — swatch strip, name +
///      subtitle, selection indicator. Tapping calls `ThemeStore.select(_:)`.
/// Both apply live and persist best-effort ("Pick a look. It applies
/// everywhere — tabs, live session, chat.").
///
/// Restyled to the Onyx language: rounded (GSMetrics) card rows on `surface`,
/// no zero-radius chrome.
struct AppearanceView: View {
    @Environment(\.gsTheme) private var theme
    @State private var themeStore = ThemeStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick a look. It applies everywhere — tabs, live session, chat.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundColor(theme.neutral700)

                // ── Your accent ────────────────────────────────────────────
                GSSectionHeader("Your accent")
                VStack(alignment: .leading, spacing: 10) {
                    GSAccentPicker()
                    Text("Recolors buttons, tabs, and highlights. Tap the wheel for a custom color. Group colors never change with your accent.")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundColor(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusMd)

                // ── Palette ────────────────────────────────────────────────
                GSSectionHeader("Palette")
                    .padding(.top, 6)
                ForEach(GSPalettes.all) { option in
                    paletteRow(option)
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .gsHidesDock()
    }

    // MARK: - Row

    @ViewBuilder
    private func paletteRow(_ option: GSPaletteOption) -> some View {
        let isSelected = themeStore.paletteID == option.id
        Button {
            themeStore.select(option.id)
        } label: {
            HStack(spacing: 12) {
                swatch(for: option.theme)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(GSFont.bold(15, relativeTo: .subheadline))
                        .foregroundColor(theme.text)
                    Text(option.subtitle)
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundColor(theme.neutral700)
                }

                Spacer(minLength: 0)

                selectionIndicator(isSelected: isSelected)
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                    .strokeBorder(isSelected ? theme.accent : theme.divider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.name), \(option.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 3-square bg/surface/accent strip, 22×40 each (66×40 total), rounded and
    /// clipped as one piece, bordered in the screen's *ambient* theme.divider
    /// (not the previewed palette's own divider) so the swatch reads clearly
    /// regardless of which palette is currently active.
    private func swatch(for palette: GSTheme) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(palette.bg).frame(width: 22, height: 40)
            Rectangle().fill(palette.surface).frame(width: 22, height: 40)
            Rectangle().fill(palette.accent).frame(width: 22, height: 40)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.divider, lineWidth: 1))
    }

    /// Selected: 24×24 accent-filled rounded square, checkmark in `theme.bg`.
    /// Unselected: outline only, 1.5px divider border, no fill.
    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 7).fill(theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.bg)
            } else {
                RoundedRectangle(cornerRadius: 7).strokeBorder(theme.divider, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}
