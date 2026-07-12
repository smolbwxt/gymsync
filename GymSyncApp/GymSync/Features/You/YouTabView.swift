import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.gsTheme) private var theme
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GSDivider()

                    // ── Appearance ──────────────────────────────────────────────
                    GSSectionHeader("Appearance")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                    appearanceRow

                    GSDivider()
                        .padding(.vertical, 16)

                    // ── Account ─────────────────────────────────────────────────
                    GSSectionHeader("Account")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    signOutButton

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 32)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Rows

    private var appearanceRow: some View {
        HStack {
            Text("Theme")
                .font(GSFont.bodyMedium(15, relativeTo: .body))
                .foregroundStyle(theme.text)
            Spacer()
            Text("Midnight")
                .font(GSFont.bodyMedium(15, relativeTo: .body))
                .foregroundStyle(theme.neutral700)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(
            Rectangle().strokeBorder(theme.neutral300, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var signOutButton: some View {
        Button {
            Task {
                do { try await auth.signOut() }
                catch { errorText = ErrorMapping.map(error).errorDescription }
            }
        } label: {
            Text("Sign Out")
        }
        .buttonStyle(GSSecondarySignOutButtonStyle())
        .padding(.horizontal, 16)
    }
}

// MARK: - Sign-Out variant of Secondary (accent700 text colour per canvas)

private struct GSSecondarySignOutButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(16, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.accent600 : theme.accent700)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(configuration.isPressed ? theme.accent100 : Color.clear)
        .cornerRadius(0)
        .overlay(
            Rectangle()
                .strokeBorder(
                    configuration.isPressed ? theme.accent600 : theme.neutral300,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
