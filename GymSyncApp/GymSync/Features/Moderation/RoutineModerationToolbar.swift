import SwiftUI

// MARK: - RoutineModerationToolbar
//
// Phase L Task 3: extracted verbatim from Phase M Task 2's original
// `RoutineDetailChoice` (private to `Features/Library/RoutinesListView.
// swift`) so `DiscoverWorkoutDetailView` (a routine detail screen whose
// routine is NEVER the caller's own) can carry the exact same Report/Block
// menu instead of re-implementing it. `RoutinesListView.swift`'s
// `RoutineDetailChoice` was refactored to apply this modifier too — same
// behavior, same copy, single implementation, per this task's brief
// ("reuse the RoutineDetailChoice toolbar surface... cite + reuse the M
// implementation").
//
// Owns its own `showReportSheet`/`showBlockConfirm` sheet/dialog state (no
// caller wiring needed for those), but takes the inline error text as a
// `Binding` rather than owning it: `RoutineDetailChoice` renders
// `moderationErrorText` inline inside its own content `VStack` (above the
// routine summary card), and `DiscoverWorkoutDetailView` does the same in
// its own layout — a `ViewModifier` can't inject content into the middle of
// the content it wraps, so display stays the caller's responsibility while
// the write itself (`blockOwner()`) stays here, shared.
struct RoutineModerationToolbar: ViewModifier {
    let ownerID: UUID
    let routineID: UUID
    /// Hides the toolbar item entirely — same "hidden for your own routine"
    /// rule the original implementation established.
    let isOwnContent: Bool
    @Binding var moderationErrorText: String?

    @Environment(\.gsTheme) private var theme
    @State private var showReportSheet = false
    @State private var showBlockConfirm = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !isOwnContent {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                showReportSheet = true
                            } label: {
                                Label("Report Routine", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                showBlockConfirm = true
                            } label: {
                                Label("Block Owner", systemImage: "nosign")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .sheet(isPresented: $showReportSheet) {
                ReportSheet(reportedUserID: ownerID, contentType: .routine, contentID: routineID)
            }
            // Literal text per brief: "Block @username? You won't see their
            // messages or requests." — same "no username on hand" generic
            // title as ChatView's identical dialog (only the owner's id is
            // loaded here, not their Profile).
            .confirmationDialog(
                "Block this user?",
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) {
                    Task { await blockOwner() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see their messages or requests.")
            }
    }

    private func blockOwner() async {
        do {
            try await ModerationRepository.block(userID: ownerID)
            moderationErrorText = nil
        } catch let error as GymSyncError {
            moderationErrorText = error.errorDescription
        } catch {
            moderationErrorText = error.localizedDescription
        }
    }
}

extension View {
    /// Applies the Report Routine / Block Owner toolbar menu — see
    /// `RoutineModerationToolbar`'s type doc comment.
    func routineModerationToolbar(
        ownerID: UUID,
        routineID: UUID,
        isOwnContent: Bool,
        moderationErrorText: Binding<String?>
    ) -> some View {
        modifier(RoutineModerationToolbar(
            ownerID: ownerID,
            routineID: routineID,
            isOwnContent: isOwnContent,
            moderationErrorText: moderationErrorText
        ))
    }
}
