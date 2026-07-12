import SwiftUI

struct ExercisesListView: View {
    @State private var exercises: [Exercise] = []
    @State private var searchText: String = ""
    @State private var muscleFilter: String? = nil
    @State private var loading = false
    @State private var errorText: String?

    @Environment(\.gsTheme) private var theme

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
        VStack(spacing: 0) {
            // Muscle filter chips — canvas: horizontal scroll row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", selected: muscleFilter == nil) {
                        muscleFilter = nil
                    }
                    ForEach(muscles, id: \.self) { m in
                        filterChip(label: m.capitalized, selected: muscleFilter == m) {
                            muscleFilter = (muscleFilter == m) ? nil : m
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(theme.bg)

            GSDivider()

            if loading {
                Spacer()
                ProgressView().tint(theme.accent)
                Spacer()
            } else if let errorText {
                Spacer()
                Text(errorText)
                    .font(GSFont.body(14))
                    .foregroundStyle(.red)
                    .padding()
                Spacer()
            } else {
                // Canvas: exercise rows — name (heading) + "Muscle · Equipment" kicker
                List(filtered) { ex in
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        exerciseRow(ex)
                    }
                    .listRowBackground(theme.surface)
                    .listRowSeparatorTint(theme.divider)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.bg)
                .searchable(text: $searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search exercises")
            }
        }
        .background(theme.bg)
        .task { await load() }
    }

    // Canvas: exercise row — bold name top line, "Muscle · Equipment" muted kicker below
    private func exerciseRow(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ex.name)
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(theme.text)
            Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
        }
        .padding(.vertical, 2)
    }

    // Canvas: filter chip — filled accent when selected, neutral surface when not
    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(selected ? theme.bg : theme.neutral700)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? theme.accent : theme.neutral300)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do { exercises = try await ExerciseRepository.fetchAll() }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
