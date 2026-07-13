import SwiftUI

/// Full palette picker — Settings Hub's "Appearance" destination (T2 built
/// the placeholder; this fills it in for Canvas Completion Task 5, per proof
/// p33-theme-picker and its canvas markup — "Theme Picker" section of
/// `docs/design/Gym Sync App Designs.dc.html`). One row per `GSPalettes.all`
/// entry: a 66×40 bg/surface/accent swatch strip (1px divider border), the
/// palette's name (15pt Archivo-Bold — canvas `font-weight:800`) + subtitle,
/// and a trailing selection indicator. The selected row additionally gets a
/// 2px accent border (unselected rows get a 1px divider border) — matches
/// the canvas markup's `border:2px solid var(--color-accent)` vs. `border:1px
/// solid var(--color-divider)` exactly.
///
/// Tapping a row calls `ThemeStore.select(_:)`, which updates
/// `\.gsTheme`/`preferredColorScheme` immediately (RootView observes the same
/// singleton) — the whole app, including this screen, re-renders in the new
/// palette live, matching the canvas copy: "Pick a look. It applies
/// everywhere — tabs, live session, chat."
struct AppearanceView: View {
    @Environment(\.gsTheme) private var theme
    @State private var themeStore = ThemeStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick a look. It applies everywhere — tabs, live session, chat.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundColor(theme.neutral700)

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
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .strokeBorder(isSelected ? theme.accent : theme.divider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.name), \(option.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 3-square bg/surface/accent strip, 22×40 each (66×40 total), 1px
    /// divider border around the whole strip — transcribed from the canvas's
    /// `<span style="display:flex;...border:1px solid var(--color-divider);">`
    /// wrapper. Always previews the ROW's own palette colors, bordered in the
    /// screen's *ambient* theme.divider (not the previewed palette's own
    /// divider) so the swatch reads clearly regardless of which palette is
    /// currently active.
    private func swatch(for palette: GSTheme) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(palette.bg).frame(width: 22, height: 40)
            Rectangle().fill(palette.surface).frame(width: 22, height: 40)
            Rectangle().fill(palette.accent).frame(width: 22, height: 40)
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    /// Selected: 24×24 accent-filled square, checkmark in `theme.bg` (matches
    /// the canvas markup's `background:var(--color-accent);color:var(--color-
    /// bg)` — the check is NOT plain white, it's the palette's own bg color).
    /// Unselected: 24×24 outline only, 1.5px divider border, no fill.
    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Rectangle().fill(theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.bg)
            } else {
                Rectangle().strokeBorder(theme.divider, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}
