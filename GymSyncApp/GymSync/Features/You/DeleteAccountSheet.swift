import SwiftUI

/// You-tab destination: typed-confirmation Delete Account flow (Phase M
/// Task 4, App Store 5.1.1). Sheet idiom mirrors `ReportSheet`
/// (self-contained `NavigationStack`, toolbar Cancel/destructive-action,
/// same "form sheet presented via `.sheet(...)`" shape this codebase
/// already established for compliance-surface sheets with no canvas
/// frame) — see `docs/design/accepted-deviations.json`'s "delete-account"
/// entry.
///
/// IRREVERSIBLE: the confirm button stays disabled until the user types
/// the exact string "DELETE" (case-sensitive, no surrounding whitespace
/// tolerance beyond a trim) — there is no other guard between a tap and
/// permanent data loss, so this typed check is load-bearing, not
/// decorative.
struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @Environment(AuthService.self) private var auth

    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var errorText: String?

    private static let confirmationPhrase = "DELETE"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    warningCard

                    GSSectionHeader("Type \(Self.confirmationPhrase) to confirm")
                        .padding(.top, 4)

                    TextField(Self.confirmationPhrase, text: $confirmationText)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .tint(theme.accent)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding(12)
                        .background(theme.surface)
                        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }

                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.accent)
                        .disabled(isDeleting)
                }
            }
        }
    }

    // MARK: - Warning

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("This can't be undone")
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .foregroundStyle(theme.text)
            }
            Text(
                "Deleting your account permanently removes your profile, friendships, " +
                "routines, and workout history. Sessions and groups you share with others " +
                "are preserved for them, with your name replaced by \"Deleted User.\""
            )
            .font(GSFont.body(13, relativeTo: .footnote))
            .foregroundStyle(theme.neutral700)
        }
        .padding(12)
        .background(theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(.red).frame(width: 3)
        }
    }

    // MARK: - Confirm

    /// Exact, trimmed match only — "delete", "DELETE ", "DELETE!" etc. all
    /// stay disabled. Trimming tolerates an autocomplete/autocorrect stray
    /// trailing space without weakening the check itself (the visible
    /// characters must still be exactly "DELETE").
    private var canDelete: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == Self.confirmationPhrase && !isDeleting
    }

    private var deleteButton: some View {
        Button {
            Task { await performDelete() }
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Text("Delete My Account")
                }
                Spacer(minLength: 0)
            }
            .font(GSFont.bold(16, relativeTo: .body))
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(canDelete ? Color.red : theme.neutral400)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canDelete)
        .padding(.top, 8)
    }

    private func performDelete() async {
        guard canDelete else { return }
        isDeleting = true
        defer { isDeleting = false }
        errorText = nil
        do {
            try await AccountDeletionRepository.deleteAccount()
            // Cascade succeeded server-side — sign out locally. RootView
            // switches on `AuthService.state`, so this alone tears down the
            // entire authenticated view hierarchy (including this sheet)
            // back to SignInView; no explicit `dismiss()` needed here.
            try await auth.signOut()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
