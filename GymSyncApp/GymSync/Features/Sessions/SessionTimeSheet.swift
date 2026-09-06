import SwiftUI

// MARK: - SessionTimeSheet
//
// The change-time control, extracted from `LobbyView.changeTimeSheet`
// (:755-784 before this commit) so that the lobby and the calendar &
// scheduling page render THE SAME sheet rather than two of them. Same move
// as task D1's `TrainingMonthField`: the second implementation is deleted,
// not added to.
//
// Chrome only, deliberately. The host owns what SAVE means, because the two
// hosts have different follow-up: the lobby reloads itself and syncs its
// EventKit event with the routine info it has already loaded; the calendar
// page re-reads the week. Both go through the SAME repository call,
// `SessionRepository.reschedule(sessionID:to:)` — one `UPDATE sessions SET
// scheduled_for` on the existing row, which is what makes a move a move: the
// session keeps its id, its participants, its `session_commitments`, its
// chat, its room code and its `series_id`.
//
// Every value below is copied from the lobby's sheet unchanged — the `Form`
// section on `theme.surface`, the `Date()...` lower bound, the accent tint,
// the hidden scroll background, `Change Time` inline, and the two toolbar
// buttons with their exact fonts and colours — so Manage → Change time
// renders identically to the frame that shipped before it.

struct SessionTimeSheet: View {
    @Environment(\.gsTheme) private var theme

    @Binding var date: Date
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "New time",
                        selection: $date,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .tint(theme.accent)
                }
                .listRowBackground(theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Change Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(theme.neutral700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(theme.accent700)
                }
            }
        }
    }
}
