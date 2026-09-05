import SwiftUI

/// Home's header — the greeting, the date, the `?` help button and the avatar.
///
/// A re-creation of production's `HomeView.greetingHeader` (:251) on fixture
/// strings: it is chrome, not logic, and production's version reads
/// `AppState.currentProfile` and `Date.now`, neither of which a catalog
/// capture may depend on (this build takes no `AppState` and makes no
/// repository call). Geometry, fonts and colours are production's, verbatim.
struct HomeV2GreetingHeader: View {
    @Environment(\.gsTheme) private var theme

    /// e.g. `Good afternoon, Smola`.
    let greeting: String
    /// e.g. `Friday, September 5`.
    let dateLine: String
    /// Avatar initials, e.g. `SM`.
    let initials: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(GSFont.heading(24, relativeTo: .largeTitle))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dateLine)
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 0)

            // The anti-onboarding: help lives at the moment of confusion.
            // Tap → the FAQ / walkthrough sheet.
            Button {} label: {
                Text("?")
                    .font(GSFont.bold(16, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                               cornerRadius: 10, lipHeight: 4))
            .accessibilityLabel("Help")

            // Tap → the You tab.
            Button {} label: {
                Circle()
                    .fill(theme.surface)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(theme.divider, lineWidth: 1))
                    .overlay(
                        Text(initials)
                            .font(GSFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}
