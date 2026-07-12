import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.gsTheme) private var theme
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                // ── Appearance ──────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Theme")
                            .font(GSFont.body(16, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("Midnight")
                            .font(GSFont.bodyMedium(16, relativeTo: .body))
                            .foregroundStyle(theme.neutral700)
                    }
                } header: {
                    GSSectionHeader("Appearance")
                }

                // ── Account ─────────────────────────────────────────────────
                Section {
                    Button("Sign Out") {
                        Task {
                            do { try await auth.signOut() }
                            catch { errorText = ErrorMapping.map(error).errorDescription }
                        }
                    }
                    .foregroundStyle(.red)
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("You")
        }
    }
}
