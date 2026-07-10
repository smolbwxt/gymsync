import SwiftUI

struct LogSetSheet: View {
    let exercise: Exercise
    let setIndex: Int
    let defaultReps: String?
    let defaultWeight: String?
    let onLog: (Int?, Decimal?, Decimal?, Bool, String?) -> Void
    // onLog(reps, weight, rpe, isFailed, note)

    @Environment(\.dismiss) private var dismiss
    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var rpe: Double = 7.0
    @State private var isFailed = false
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Set \(setIndex) · \(exercise.name)") {
                    LabeledContent("Reps") {
                        TextField("reps", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight (\(exercise.defaultUnit))") {
                        TextField("weight", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("RPE")
                            Spacer()
                            Text(String(format: "%.1f", rpe))
                        }
                        Slider(value: $rpe, in: 1...10, step: 0.5)
                    }
                    Toggle("Failed set", isOn: $isFailed)
                }
                Section("Note (optional)") {
                    TextField("Anything to remember?", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Log set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onLog(
                            Int(reps),
                            Decimal(string: weight),
                            Decimal(rpe),
                            isFailed,
                            note.isEmpty ? nil : note
                        )
                        dismiss()
                    }
                    .disabled(Int(reps) == nil && !isFailed)
                }
            }
            .onAppear {
                if reps.isEmpty { reps = defaultReps ?? "" }
                if weight.isEmpty { weight = defaultWeight ?? "" }
            }
        }
    }
}
