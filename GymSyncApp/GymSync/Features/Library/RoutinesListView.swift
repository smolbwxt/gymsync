import SwiftUI

// Canvas: Library Routines tab — cards with title, exercise list preview body,
// accent+neutral tags (category · equipment), meta "N exercises · ~X min" kicker.
struct RoutinesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var routines: [Routine] = []
    @State private var routineExercises: [UUID: [RoutineExercise]] = [:]
    @State private var allExercises: [Exercise] = []
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

    // Canvas: GSCard with title + exercise-name preview + tags + meta row
    private func routineCard(_ routine: Routine) -> some View {
        let exercises = orderedExercises(for: routine)
        let names = exercises.compactMap { re in
            allExercises.first(where: { $0.id == re.exerciseID })?.name
        }
        let firstExercise = exercises.first.flatMap { re in
            allExercises.first(where: { $0.id == re.exerciseID })
        }

        return GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(routine.name)
                    .font(GSFont.heading(17, relativeTo: .headline))
                    .foregroundStyle(theme.text)

                if !names.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                        .lineLimit(2)
                }

                // Canvas: tag row — accent for compound/isolation category (from the
                // routine's first exercise), neutral for its equipment. Dropped
                // entirely when the routine has no exercises loaded yet (no fake tag).
                if let firstExercise {
                    HStack(spacing: 6) {
                        GSTag(text: firstExercise.category.capitalized, style: .accent)
                        GSTag(text: firstExercise.equipment.capitalized, style: .neutral)
                    }
                }

                // Canvas: card meta — real exercise count + duration estimate
                Text("\(exercises.count) exercises · ~\(StatMath.estimatedMinutes(exerciseCount: exercises.count)) min")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private func orderedExercises(for routine: Routine) -> [RoutineExercise] {
        (routineExercises[routine.id] ?? []).sorted { $0.position < $1.position }
    }

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do {
            let fetchedRoutines = try await RoutineRepository.fetchAll(ownerID: ownerID)
            routines = fetchedRoutines

            // Card body/tags/meta need each routine's exercises — fetch them
            // concurrently (best-effort per routine) alongside the shared
            // exercise catalog so names/category/equipment can be resolved.
            async let exercisesFetch: [Exercise] = (try? await ExerciseRepository.fetchAll()) ?? []
            async let perRoutineFetch: [UUID: [RoutineExercise]] = withTaskGroup(
                of: (UUID, [RoutineExercise]).self
            ) { group in
                for routine in fetchedRoutines {
                    group.addTask {
                        let result = try? await RoutineRepository.fetch(id: routine.id)
                        return (routine.id, result?.1 ?? [])
                    }
                }
                var map: [UUID: [RoutineExercise]] = [:]
                for await (id, exercises) in group {
                    map[id] = exercises
                }
                return map
            }
            allExercises = await exercisesFetch
            routineExercises = await perRoutineFetch
        }
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
