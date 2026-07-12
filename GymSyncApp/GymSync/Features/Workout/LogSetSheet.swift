import SwiftUI

// Canvas: Log Set card — bottom sheet with:
//   • Reps stepper  (−  value  +)  border: divider color
//   • Weight stepper (−  value  +)  border: accent color when PR candidate
//   • RPE segmented bar (10 cells, filled up to selection in accent200, active cell in accent)
//   • Fail + Save Set action row
// Slider is replaced by the segmented-bar per canvas design.
// All bindings, onLog callback, and isFailed toggle are UNCHANGED.
struct LogSetSheet: View {
    let exercise: Exercise
    let setIndex: Int
    let defaultReps: String?
    let defaultWeight: String?
    let onLog: (Int?, Decimal?, Decimal?, Bool, String?) -> Void
    // onLog(reps, weight, rpe, isFailed, note) — UNCHANGED

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var rpe: Double = 7.0
    @State private var isFailed = false
    @State private var note: String = ""

    // Canvas RPE labels — "Very easy" .. "Max effort"
    private static let rpeLabels: [Double: String] = [
        1: "Very easy", 2: "Easy", 3: "Moderate", 4: "Somewhat hard",
        5: "Hard", 6: "Hard+", 7: "Very hard", 8: "Very hard+",
        9: "Very hard", 10: "Max effort"
    ]

    private var rpeLabel: String {
        Self.rpeLabels[rpe] ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Canvas: drag handle pill
                    HStack { Spacer()
                        Rectangle()
                            .fill(theme.neutral400)
                            .frame(width: 36, height: 4)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                    // Canvas: "Exercise name  |  Set N" header row
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .font(GSFont.heading(22, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("Set \(setIndex)")
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                    // Canvas: Reps + Weight stepper row side by side
                    HStack(spacing: 10) {
                        stepperCell(
                            label: "Reps",
                            value: $reps,
                            borderColor: theme.divider,
                            valueColor: theme.text,
                            keyboard: .numberPad,
                            onDecrement: { decrementInt(&reps) },
                            onIncrement: { incrementInt(&reps) }
                        )

                        stepperCell(
                            label: "Weight (\(exercise.defaultUnit))",
                            value: $weight,
                            borderColor: theme.accent,        // Canvas: accent border on weight
                            valueColor: theme.accent700,      // Canvas: accent700 for weight value
                            keyboard: .decimalPad,
                            onDecrement: { decrementDecimal(&weight) },
                            onIncrement: { incrementDecimal(&weight) }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Canvas: RPE row — "RPE · how hard" label  /  "9 · Very hard" value
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("RPE · how hard")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                            Spacer()
                            Text("\(Int(rpe)) · \(rpeLabel)")
                                .font(GSFont.heading(12, relativeTo: .caption))
                                .foregroundStyle(theme.accent700)
                        }

                        // Canvas: 10-segment bar — filled in accent200 up to selection,
                        // selected segment in accent with white label, empty in surface+divider border
                        RPESegmentBar(value: $rpe, theme: theme)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Canvas: Failed set toggle row
                    HStack {
                        Text("Failed set")
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Toggle("", isOn: $isFailed)
                            .labelsHidden()
                            .tint(theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    GSDivider().padding(.horizontal, 16).padding(.bottom, 10)

                    // Canvas: Note field (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTE")
                            .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral500)
                        TextField("Anything to remember?", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Canvas: Fail + Save Set action row
                    HStack(spacing: 8) {
                        Button("Fail") {
                            isFailed = true
                            commitLog()
                        }
                        .buttonStyle(GSSecondaryButtonStyle())
                        .frame(width: 80)

                        Button("Save Set") {
                            commitLog()
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .disabled(Int(reps) == nil && !isFailed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
            .background(theme.bg)
            .navigationBarHidden(true)
            .onAppear {
                if reps.isEmpty { reps = defaultReps ?? "" }
                if weight.isEmpty { weight = defaultWeight ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden) // using our own handle pill
    }

    // MARK: - Sub-views

    // Canvas: stepper cell — label kicker / "−  value  +" row with borders
    private func stepperCell(
        label: String,
        value: Binding<String>,
        borderColor: Color,
        valueColor: Color,
        keyboard: UIKeyboardType,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)

            // Canvas: bordered row — minus button | value | plus button, height 48
            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Text("−")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.neutral700)
                        .frame(width: 40, height: 48)
                        .contentShape(Rectangle())
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(borderColor.opacity(0.6)).frame(width: 1)
                }

                TextField("", text: value)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(valueColor)
                    .frame(maxWidth: .infinity, minHeight: 48)

                Button(action: onIncrement) {
                    Text("+")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.accent)
                        .frame(width: 40, height: 48)
                        .contentShape(Rectangle())
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(borderColor.opacity(0.6)).frame(width: 1)
                }
            }
            .overlay(Rectangle().strokeBorder(borderColor, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stepper arithmetic (integers & decimals)

    private func decrementInt(_ s: inout String) {
        let v = max(0, (Int(s) ?? 0) - 1)
        s = "\(v)"
    }
    private func incrementInt(_ s: inout String) {
        let v = (Int(s) ?? 0) + 1
        s = "\(v)"
    }
    private func decrementDecimal(_ s: inout String) {
        let v = max(0, (Double(s) ?? 0) - 2.5)
        s = v.truncatingRemainder(dividingBy: 1) == 0
               ? "\(Int(v))" : String(format: "%.1f", v)
    }
    private func incrementDecimal(_ s: inout String) {
        let v = (Double(s) ?? 0) + 2.5
        s = v.truncatingRemainder(dividingBy: 1) == 0
               ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func commitLog() {
        onLog(
            Int(reps),
            Decimal(string: weight),
            Decimal(rpe),
            isFailed,
            note.isEmpty ? nil : note
        )
        dismiss()
    }
}

// MARK: - RPE Segment Bar
// Canvas: 10 horizontal equal segments — accent200 fill up to (not including) selected,
// accent fill on selected cell with bg-colored number label, surface+divider for unvisited.

private struct RPESegmentBar: View {
    @Binding var value: Double
    let theme: GSTheme

    private let steps: [Double] = Array(stride(from: 1.0, through: 10.0, by: 1.0))

    var body: some View {
        HStack(spacing: 3) {
            ForEach(steps, id: \.self) { step in
                segment(for: step)
                    .onTapGesture { value = step }
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private func segment(for step: Double) -> some View {
        let isSelected = Int(step) == Int(value)
        let isFilled   = step < value

        ZStack {
            if isSelected {
                theme.accent
            } else if isFilled {
                theme.accent200
            } else {
                theme.surface
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
            }

            if isSelected {
                Text("\(Int(step))")
                    .font(GSFont.heading(13, relativeTo: .caption))
                    .foregroundStyle(theme.bg)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
