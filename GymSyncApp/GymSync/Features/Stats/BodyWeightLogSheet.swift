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

    // Units sweep (2026-07-27): the field is typed and labeled in the
    // user's unit (`user_settings.unit_system` via ThemeStore's cached
    // row); STORAGE stays canonical pounds with unit "lbs", same doctrine
    // as every other weight column — one unit in the table keeps the trend
    // chart and headline math unit-free.
    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    @State private var weight: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                stepperCell(
                    theme: theme,
                    label: "Weight (\(unit.label))",
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
        // Phase O Task 2: `Decimal.parseUserInput(_:)` (Models/Decimal+
        // ParseUserInput.swift) instead of the bare `Decimal(string:)`
        // initializer — accepts a comma decimal separator (what a
        // `.decimalPad` keyboard shows on comma-locale devices) as well as
        // a period, so this field is submittable regardless of device
        // locale. Parse-side only — `value` is stored identically either way.
        guard let value = Decimal.parseUserInput(weight) else { return false }
        return value > 0 && !isSubmitting
    }

    private func submit() async {
        guard let typed = Decimal.parseUserInput(weight), typed > 0 else { return }
        // Typed in the user's unit → canonical pounds for storage (the row's
        // `unit` column stays "lbs" — see the doctrine note on `unit` above).
        let value = Units.toPounds(typed, from: unit)
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await BodyWeightLogRepository.log(weight: value, unit: "lbs")
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
