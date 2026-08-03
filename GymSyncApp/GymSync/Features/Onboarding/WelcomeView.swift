import SwiftUI

/// "You're set" — the final onboarding screen (Dossier §A.7, canvas screen 4,
/// canvas lines 1053-1129). No STEP indicator row on this screen.
struct WelcomeView: View {
    let profile: Profile

    /// Completes onboarding — sets `appState.currentProfile`. Threaded in by
    /// `OnboardingCoordinator` (the existing completion mechanism).
    var onComplete: () -> Void

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    badge
                        .padding(.horizontal, 20)
                        .padding(.top, 72)

                    Text("You're in,\n@\(profile.username).")
                        .font(GSFont.bold(40, relativeTo: .largeTitle))
                        .foregroundColor(theme.text)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    Text("Build a routine, then invite friends to take turns on the bar. Here's where to start:")
                        .font(GSFont.body(15, relativeTo: .subheadline))
                        .foregroundColor(theme.neutral700)
                        .frame(maxWidth: 280, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    VStack(spacing: 10) {
                        shortcutRow(
                            icon: "square.grid.2x2",
                            title: "Build your first routine",
                            subtitle: "Pick exercises, set targets"
                        ) {
                            // Four-tab reorientation: routines live under the
                            // You tab's widget grid now (ROUTINES widget).
                            appState.selectedTab = .you
                            onComplete()
                        }

                        shortcutRow(
                            icon: "person.2",
                            title: "Add your friends",
                            subtitle: "Find them by username"
                        ) {
                            appState.selectedTab = .social
                            onComplete()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                    Spacer().frame(height: 100)
                }
            }

            footer
        }
    }

    // MARK: - Badge

    private var badge: some View {
        ZStack {
            Rectangle().fill(theme.accent).frame(width: 60, height: 60)
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(theme.bg)
        }
    }

    // MARK: - Shortcut row

    private func shortcutRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(theme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                        .foregroundColor(theme.text)
                    Text(subtitle)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.neutral500)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // Footprint: face floor 38 + 6pt lip = the old 44pt row.
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        // 3D pass (2026-08 sweep): tappable shortcut card — extruded face +
        // lip + press-sink, replacing the flat surface fill and its outline.
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            GSDivider()
            Button {
                onComplete()
            } label: {
                Text("Enter Gym Sync")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle())
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }
}
