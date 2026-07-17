import SwiftUI

/// Report sheet — fixed reason categories + freeform details, inserting a
/// `user_reports` row (Phase M Task 2, App Store compliance). Reachable from
/// any profile/content context: Friends rows, GroupView Members rows,
/// ChatView message context menu, routine detail.
///
/// Sheet idiom mirrors `CreateGroupView` (self-contained `NavigationStack`,
/// bordered fields, toolbar Cancel/Submit) — that's this codebase's
/// established "form sheet presented via `.sheet(...)`" shape. No canvas
/// frame exists for this screen (system-designed, App Store compliance
/// gate) — see `docs/design/accepted-deviations.json`'s "report-sheet"
/// entry.
struct ReportSheet: View {
    /// The user being reported. For a profile report this equals
    /// `contentID`; for a chat message/routine report it's that content's
    /// author/owner (see `ModerationRepository.report`'s doc comment).
    let reportedUserID: UUID
    let contentType: ReportedContentType
    let contentID: UUID

    var onSubmitted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var selectedReason: ReportReason = .harassment
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if didSubmit {
                    confirmation
                } else {
                    form
                }
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
                if !didSubmit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await submit() } }
                            .font(GSFont.bold(14, relativeTo: .body))
                            .foregroundStyle(isSubmitting ? theme.neutral500 : theme.accent)
                            .disabled(isSubmitting)
                    }
                }
            }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Reason")
                .padding(.top, 16)

            VStack(spacing: 0) {
                ForEach(ReportReason.allCases) { reason in
                    reasonRow(reason)
                }
            }
            .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

            GSSectionHeader("Details (optional)")
                .padding(.top, 20)

            TextField("Add any details that might help", text: $details, axis: .vertical)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .tint(theme.accent)
                .lineLimit(3...6)
                .padding(12)
                .background(theme.surface)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

            if let errorText {
                Text(errorText)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        let isSelected = selectedReason == reason
        return Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason.rawValue)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if reason != ReportReason.allCases.last {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirmation

    @ViewBuilder
    private var confirmation: some View {
        GSEmptyState(
            icon: "checkmark.circle",
            title: "Report submitted",
            message: "Thanks — our team will review this."
        )
        .padding(.top, 60)
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = trimmedDetails.isEmpty
            ? selectedReason.rawValue
            : "\(selectedReason.rawValue): \(trimmedDetails)"
        do {
            try await ModerationRepository.report(
                userID: reportedUserID,
                contentType: contentType,
                contentID: contentID,
                reason: reasonText
            )
            errorText = nil
            didSubmit = true
            onSubmitted?()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
