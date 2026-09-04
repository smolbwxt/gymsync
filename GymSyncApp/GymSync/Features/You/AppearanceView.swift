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
/// Restyled to the Onyx language: rounded (GSMetrics) card rows, no
/// zero-radius chrome. gs3D pass (2026-09-03, P2): the accent card is a
/// static extruded widget and the palette rows are sinking extruded rows —
/// the flat `surface` fills and the divider strokes they wore retired.
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
                // gs3D pass (2026-09-03, P2): the accent card is a static
                // widget the user reads (GSAccentPicker owns the taps
                // inside it), so it takes the extruded face/lip container —
                // the flat surface fill + cornerRadius retire.
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)

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
            .overlay(
                isSelected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.accent, lineWidth: 2)
                    : nil
            )
            .contentShape(Rectangle())
        }
        // gs3D pass (2026-09-03, P2): a palette row is tappable, so it sits
        // proud and sinks. The label sheds its own surface fill and its
        // divider stroke — the lip delineates now — and selection reads as
        // the 2pt accent ring overlay (HomeView pickCard precedent). The
        // swatch strip and the selectionIndicator keep their own borders:
        // that's artwork, not card chrome.
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
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
