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
            // Redesign (user feedback 2026-07-23: "large blank space between
            // the muscle groups and exercise list") — the old `.searchable(
            // placement: .navigationBarDrawer)` reserved a drawer under the
            // now-hidden nav bar. Replaced with an in-content search field.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
                TextField("Search exercises", text: $searchText)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.neutral500)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Muscle filter chips — horizontal scroll row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", selected: muscleFilter == nil) {
                        muscleFilter = nil
                    }
                    ForEach(muscles, id: \.self) { m in
                        filterChip(label: m.replacingOccurrences(of: "_", with: " ").capitalized, selected: muscleFilter == m) {
                            muscleFilter = (muscleFilter == m) ? nil : m
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            // Root cause of the "large gap" (2026-07-23 screenshot): a
            // ScrollView is greedy in BOTH axes even when horizontal-only, so
            // this row was splitting the leftover height with the List below.
            // Pin it to its content height.
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.bg)

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

    // Redesign: capsule filter chips — filled accent when selected.
    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(selected ? theme.bg : theme.neutral700)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? theme.accent : theme.neutral300)
                .clipShape(Capsule())
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
