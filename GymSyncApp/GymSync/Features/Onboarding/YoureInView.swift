import SwiftUI

/// Onboarding step 4: "You're in, @username."
/// Canvas: accent checkmark square, big 40px heading, two nav action rows,
/// sticky bottom bar with Primary "Enter Gym Sync".
struct YoureInView: View {
    let username: String
    var onEnter: () -> Void

    @Environment(\.gsTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Accent checkmark square
                    ZStack {
                        theme.accent
                            .frame(width: 60, height: 60)
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(theme.bg)
                    }
                    .padding(.top, 52)
                    .padding(.horizontal, 24)

                    // Heading
                    Text("You're in,\n@\(username).")
                        .font(GSFont.bold(40, relativeTo: .largeTitle))
                        .foregroundColor(theme.text)
                        .lineSpacing(2)
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    // Sub copy
                    Text("Build a routine, then invite friends to take turns on the bar. Here's where to start:")
                        .font(GSFont.body(15, relativeTo: .body))
                        .foregroundColor(theme.neutral700)
                        .padding(.top, 14)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 280, alignment: .leading)

                    // Action rows
                    VStack(spacing: 8) {
                        ActionRow(
                            icon: "square.grid.2x2",
                            title: "Build your first routine",
                            subtitle: "Pick exercises, set targets",
                            theme: theme
                        )
                        ActionRow(
                            icon: "person.2",
                            title: "Add your friends",
                            subtitle: "Find them by username",
                            theme: theme
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    Spacer().frame(height: 100)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sticky bottom CTA
            VStack(spacing: 0) {
                GSDivider()
                Button("Enter Gym Sync", action: onEnter)
                    .buttonStyle(GSPrimaryButtonStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .padding(.bottom, 22)
            }
            .background(theme.bg)
        }
    }
}

// MARK: - Action row

private struct ActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let theme: GSTheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(theme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Text(subtitle)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.neutral700)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }
}
