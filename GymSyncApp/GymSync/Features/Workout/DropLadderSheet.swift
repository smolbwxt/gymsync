import SwiftUI

// MARK: - DropLadderSheet
//
// The drop ladder (set structures phase B): presented right after the TOP
// set of a drop-prescribed exercise logs. Each rung prefills at the
// prescribed cut from the rung above (successive −X%), editable — the
// lifter grabs whatever bells the rack actually has. Logging writes
// `set_log_segments` rows; the parent set already logged normally.
struct DropLadderSheet: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let topWeightPounds: Decimal
    let steps: Int
    let dropPercent: Decimal
    let unit: WeightUnit
    /// Called with the completed rungs (weight in canonical POUNDS, reps).
    let onLog: ([(weight: Decimal, reps: Int)]) -> Void

    @State private var weights: [String] = []
    @State private var reps: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top set logged at \(Units.format(pounds: topWeightPounds, unit: unit, rounded: false)). Strip the bar and keep going — no rest between rungs.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(0..<steps, id: \.self) { index in
                        rungRow(index)
                    }

                    Button {
                        logLadder()
                    } label: {
                        Text("Log Drop Ladder")
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .padding(.top, 6)

                    Button {
                        dismiss()
                    } label: {
                        Text("Skip — top set only")
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
                .padding(16)
            }
            .background(theme.bg)
            .navigationTitle("Drop Set")
            .navigationBarTitleDisplayMode(.inline)
            .task { prefill() }
        }
        .presentationDetents([.medium, .large])
    }

    private func rungRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Text("DROP \(index + 1)")
                .font(GSFont.bold(11, relativeTo: .caption))
                .tracking(0.8)
                .foregroundStyle(theme.neutral500)
                .frame(width: 62, alignment: .leading)
            fieldBox(label: unit.label.uppercased(),
                     text: bindingFor(index, in: $weights),
                     keyboard: .decimalPad)
            fieldBox(label: "REPS",
                     text: bindingFor(index, in: $reps),
                     keyboard: .numberPad)
        }
    }

    private func fieldBox(label: String, text: Binding<String>,
                          keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .font(GSFont.heading(16, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
            .strokeBorder(theme.divider, lineWidth: 1))
    }

    private func bindingFor(_ index: Int, in array: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { index < array.wrappedValue.count ? array.wrappedValue[index] : "" },
            set: { newValue in
                while array.wrappedValue.count <= index { array.wrappedValue.append("") }
                array.wrappedValue[index] = newValue
            }
        )
    }

    /// Successive cuts from the top bell, shown in the user's unit.
    private func prefill() {
        guard weights.isEmpty else { return }
        var current = topWeightPounds
        let keep = 1 - dropPercent / 100
        for _ in 0..<steps {
            current = current * keep
            weights.append(Units.format(pounds: current, unit: unit,
                                        rounded: true, includeUnit: false))
            reps.append("")
        }
    }

    private func logLadder() {
        var rungs: [(weight: Decimal, reps: Int)] = []
        for index in 0..<steps {
            guard index < weights.count,
                  let pounds = Units.parseToPounds(weights[index], unit: unit), pounds > 0,
                  index < reps.count, let r = Int(reps[index]), r > 0 else { continue }
            rungs.append((pounds, r))
        }
        onLog(rungs)
        dismiss()
    }
}
