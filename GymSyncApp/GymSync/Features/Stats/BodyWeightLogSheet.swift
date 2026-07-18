import SwiftUI

/// Body weight entry sheet — reachable from the Stats "Body Weight" card's
/// "+ Log" button (Phase H Task 3). No canvas frame exists for this screen
/// (system-designed) — see `docs/design/accepted-deviations.json`'s
/// "body-weight-log" entry.
///
/// Sheet idiom mirrors `ReportSheet` (Features/Moderation/ReportSheet.swift)
/// — self-contained `NavigationStack`, toolbar Cancel/confirm — this
/// codebase's established "small form sheet" shape. The weight field itself
/// reuses `LogSetSheet`'s shared `stepperCell`/`incrementDecimal`/
/// `decrementDecimal` helpers (Features/Workout/LogSetSheet.swift:190-261 —
/// `internal`, not `private`, specifically so other files can reuse them)
/// rather than a bespoke TextField, so weight entry here looks and behaves
/// identically to every other weight input already in the app
/// (RoutineBuilderView, LogSetSheet, GroupSessionLiveView).
struct BodyWeightLogSheet: View {
    var onLogged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    // No unit-preference setting exists anywhere in `profiles`/
    // `user_settings` today — grepped both before this task, confirmed
    // absent. "lbs" is the task brief's documented default (not a read of a
    // per-user setting) and is not user-facing as a picker in v1; if a unit
    // preference ships later, this constant is the single place to wire it
    // in behind a real read.
    private let unit = "lbs"

    @State private var weight: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                stepperCell(
                    theme: theme,
                    label: "Weight (\(unit))",
                    value: $weight,
                    borderColor: theme.accent,
                    valueColor: theme.accent700,
                    keyboard: .decimalPad,
                    onDecrement: { decrementDecimal(&weight) },
                    onIncrement: { incrementDecimal(&weight) }
                )
                .padding(.horizontal, 16)
                .padding(.top, 20)

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .background(theme.bg)
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(canSubmit ? theme.accent : theme.neutral500)
                        .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        guard let value = Decimal(string: weight) else { return false }
        return value > 0 && !isSubmitting
    }

    private func submit() async {
        guard let value = Decimal(string: weight), value > 0 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await BodyWeightLogRepository.log(weight: value, unit: unit)
            errorText = nil
            onLogged?()
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
