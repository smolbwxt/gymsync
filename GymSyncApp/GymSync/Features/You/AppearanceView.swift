import SwiftUI

/// Placeholder destination for the Settings Hub's "Appearance" row
/// (new-canvas-section.diff's "Settings Hub" frame, Canvas Completion
/// Task 2). `user_settings.palette` already persists the selected palette
/// server-side and the DC's `<x-dc>` prop lists the 4 valid values
/// (midnight/arena/ink/modernist per the migration's CHECK constraint), but
/// the actual picker UI is a future task (T5). This stub exists so
/// `YouTabView` has a real, stable navigation destination today rather than
/// a throwaway sheet — T5 fills in the picker UI here without touching the
/// Settings Hub row's wiring.
struct AppearanceView: View {
    @Environment(\.gsTheme) private var theme

    /// Capitalized display name of the currently-persisted palette (e.g.
    /// "Midnight") — shown so the placeholder isn't misleadingly blank.
    let currentPaletteName: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "paintpalette")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(theme.accent)
            Text("Coming with palettes")
                .font(GSFont.heading(18, relativeTo: .title3))
                .foregroundColor(theme.text)
            Text("Currently \(currentPaletteName). The picker for Arena, Ink, and Modernist arrives in a future update.")
                .font(GSFont.body(13, relativeTo: .footnote))
                .foregroundColor(theme.neutral700)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .gsHidesDock()
    }
}
