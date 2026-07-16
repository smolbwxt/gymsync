import SwiftUI

// Canvas: Library Routines tab — cards with title, exercise list preview body,
// accent+neutral tags (category · equipment), meta "N exercises · ~X min" kicker.
struct RoutinesListView: View {
    /// Optional Featured shelf rendered as the FIRST scrolling row of the
    /// routines list, so the whole screen (Featured + "Your routines")
    /// scrolls as one instead of the shelf pinning a cramped list below it.
    /// Passed from `LibraryTabView`, which owns the Featured data + clone
    /// actions; `nil` when there's nothing featured.
    var featuredHeader: AnyView? = nil

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
        // One List for the whole tab: Featured header (if any) scrolls with
        // the routines, and the "Your routines" section header carries a
        // prominent "+ New" button (the toolbar + alone was easy to miss).
        List {
            if let featuredHeader {
                featuredHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(theme.bg)
                    .listRowSeparator(.hidden)
            }

            Section {
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.vertical, 24)
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                } else if let errorText {
                    Text(errorText)
                        .font(GSFont.body(14)).foregroundStyle(.red)
                        .padding(.vertical, 16)
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                } else if routines.isEmpty {
                    emptyRoutinesRow
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } else {
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
            } header: {
                yourRoutinesHeader
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
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

    // "YOUR ROUTINES" kicker + a discoverable "+ New" button — the primary
    // way to add a routine, in-content rather than a lone corner glyph.
    private var yourRoutinesHeader: some View {
        HStack {
            Text("Your routines")
                .font(GSFont.bold(12, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.text.opacity(0.6))
                .textCase(nil)
            Spacer()
            Button {
                showingBuilder = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("New").font(GSFont.bold(13, relativeTo: .subheadline))
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var emptyRoutinesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No routines yet")
                .font(GSFont.heading(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text("Tap “New” above to build your first workout, or add a featured pack.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // Clear the spinner as soon as the routine list itself is in hand —
            // rows paint immediately with title/kicker; names/tags/meta below
            // populate progressively once the supplemental fetches resolve.
            loading = false

            // Card body/tags/meta need every visible routine's exercises plus the
            // shared exercise catalog. Fetch both concurrently: exercises via a
            // single bulk `.in(routine_id)` query (not N per-routine fetches) so
            // this stays one round trip regardless of list size. Best-effort —
            // a failure here just leaves cards without names/tags/meta.
            async let exercisesFetch: [Exercise] = (try? await ExerciseRepository.fetchAll()) ?? []
            async let bulkExercisesFetch: [RoutineExercise] = (try? await RoutineRepository.exercisesForRoutines(
                ids: fetchedRoutines.map(\.id)
            )) ?? []
            allExercises = await exercisesFetch
            routineExercises = Dictionary(grouping: await bulkExercisesFetch, by: \.routineID)
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
