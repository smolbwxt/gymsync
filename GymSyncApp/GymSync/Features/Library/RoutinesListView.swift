import SwiftUI

// Canvas: Library Routines tab — cards with title, exercise list preview body,
// accent+neutral tags (category · equipment), meta "N exercises · ~X min" kicker.
struct RoutinesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var routines: [Routine] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingBuilder = false
    @State private var editing: Routine?

    var body: some View {
        Group {
            if loading {
                VStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                    .background(theme.bg)
            } else if let errorText {
                VStack { Spacer()
                    Text(errorText).font(GSFont.body(14)).foregroundStyle(.red).padding()
                    Spacer()
                }.background(theme.bg)
            } else if routines.isEmpty {
                ContentUnavailableView(
                    "No routines yet",
                    systemImage: "list.clipboard",
                    description: Text("Tap + to build your first workout.")
                )
                .background(theme.bg)
            } else {
                // Keep List so onDelete swipe continues to work (plan constraint)
                List {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineDetailChoice(routine: routine,
                                               onEdited: { Task { await load() } })
                        } label: {
                            routineCard(routine)
                        }
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.bg)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingBuilder = true
                } label: { Image(systemName: "plus") }
                    .tint(theme.accent)
            }
        }
        .sheet(isPresented: $showingBuilder) {
            NavigationStack {
                RoutineBuilderView(editing: nil) { _ in
                    showingBuilder = false
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    // Canvas: GSCard with title + body text + tags + meta row
    private func routineCard(_ routine: Routine) -> some View {
        GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(routine.name)
                    .font(GSFont.heading(17, relativeTo: .headline))
                    .foregroundStyle(theme.text)

                if let desc = routine.description, !desc.isEmpty {
                    Text(desc)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                        .lineLimit(2)
                }

                // Canvas: tag row — accent for compound type, neutral for equipment
                HStack(spacing: 6) {
                    GSTag(text: "Routine", style: .accent)
                }

                // Canvas: card meta — exercise count
                Text("\(0) exercises")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
        }
    }

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { routines = try await RoutineRepository.fetchAll(ownerID: ownerID) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            for idx in offsets {
                let r = routines[idx]
                try? await RoutineRepository.delete(id: r.id)
            }
            await load()
        }
    }
}

// MARK: - Routine Detail Choice

private struct RoutineDetailChoice: View {
    let routine: Routine
    let onEdited: () -> Void

    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var routineExercises: [RoutineExercise] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else if let errorText {
                    Text(errorText)
                        .font(GSFont.body(14))
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    // Routine summary header
                    GSCard(bordered: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(routine.name)
                                .font(GSFont.heading(22, relativeTo: .title2))
                                .foregroundStyle(theme.text)
                            Text("\(routineExercises.count) exercise\(routineExercises.count == 1 ? "" : "s")")
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral700)
                        }
                        .padding(14)
                    }

                    // Canvas: Start Workout — primary CTA
                    NavigationLink {
                        WorkoutSessionView(routine: routine,
                                           routineExercises: routineExercises,
                                           allExercises: exercises)
                    } label: {
                        Text("Start Workout")
                    }
                    .buttonStyle(GSPrimaryButtonStyle())

                    // Canvas: Edit routine — secondary
                    NavigationLink {
                        RoutineBuilderView(editing: routine) { _ in onEdited() }
                    } label: {
                        Text("Edit Routine")
                    }
                    .buttonStyle(GSSecondaryButtonStyle())
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            exercises = try await ExerciseRepository.fetchAll()
            if let (_, exs) = try await RoutineRepository.fetch(id: routine.id) {
                routineExercises = exs
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
