import SwiftUI

struct ExercisesListView: View {
    @State private var exercises: [Exercise] = []
    @State private var searchText: String = ""
    @State private var muscleFilter: String? = nil
    @State private var loading = false
    @State private var errorText: String?

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (muscleFilter == nil || ex.primaryMuscle == muscleFilter)
            && (searchText.isEmpty
                || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var muscles: [String] {
        Array(Set(exercises.map(\.primaryMuscle))).sorted()
    }

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterChip(label: "All", selected: muscleFilter == nil) {
                        muscleFilter = nil
                    }
                    ForEach(muscles, id: \.self) { m in
                        filterChip(label: m.capitalized, selected: muscleFilter == m) {
                            muscleFilter = (muscleFilter == m) ? nil : m
                        }
                    }
                }
                .padding(.horizontal)
            }
            if loading {
                ProgressView()
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else {
                List(filtered) { ex in
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body)
                            Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            }
        }
        .task { await load() }
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground),
                            in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
                .font(.caption.weight(.medium))
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do { exercises = try await ExerciseRepository.fetchAll() }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
