import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        Form {
            Section("Muscles") {
                LabeledContent("Primary", value: exercise.primaryMuscle.capitalized)
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secondary",
                                   value: exercise.secondaryMuscles
                                    .map(\.localizedCapitalized).joined(separator: ", "))
                }
            }
            Section("Equipment") {
                LabeledContent("Equipment", value: exercise.equipment.capitalized)
                LabeledContent("Category", value: exercise.category.capitalized)
            }
            if let url = exercise.demoVideoURL {
                Section("Demo") {
                    Link("Watch demo", destination: url)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
