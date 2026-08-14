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
    /// Pro gate (dormant until Monetization.paywallEnabled).
    @State private var showPaywall = false

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
                // Loading/error rows only while the list is EMPTY — `.task`
                // re-fires on pop-back from a routine detail push, and letting
                // `loading` swap the populated rows for a spinner resets
                // scroll to the top (ExercisesListView's afbb415 fix).
                if loading && routines.isEmpty {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.vertical, 24)
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                } else if let errorText, routines.isEmpty {
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
        // Dock clearance — on the List directly, not LibraryTabView's Group
        // (the Group cascade inflated Exercises' chips row; see that view).
        .contentMargins(.bottom, 88, for: .scrollContent)
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .unlimitedRoutines) }
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
                // Pro gate (dormant): free tier caps owned routines.
                guard routines.count < Monetization.freeRoutineLimit
                        || Monetization.allows(.unlimitedRoutines, profile: appState.currentProfile) else {
                    showPaywall = true
                    return
                }
                showingBuilder = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("New").font(GSFont.bold(13, relativeTo: .subheadline))
                }
                // First-visit spotlight target — the tip itself is attached
                // at the You-grid push site; preferences travel up the tree.
                .gsSpotlightTarget(.library)
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 12)
                .frame(height: 26)
            }
            // Extruded like every tappable (design law) — compact gs3D
            // accent anatomy, same as Stats' + Log and MyRackView's RACK.
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 10, lipHeight: 5))
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

        // gs3D pass (2026-08-13): the bordered flat card joins the extruded
        // language. STATIC depth (.gs3DCard, not the sinking style) on
        // purpose — these rows live in a List whose swipe-to-delete owns
        // the gesture plumbing; the NavigationLink still navigates.
        return Group {
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
                Text("\(exercises.count) exercises · ~\(StatMath.estimatedMinutes(exercises: exercises)) min")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    private func orderedExercises(for routine: Routine) -> [RoutineExercise] {
        (routineExercises[routine.id] ?? []).sorted { $0.position < $1.position }
    }

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        errorText = nil
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
// Internal (was private) since the Routines hub's slot rows push it too —
// one detail screen, whichever surface the routine was opened from.

struct RoutineDetailChoice: View {
    let routine: Routine
    let onEdited: () -> Void

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var exercises: [Exercise] = []
    @State private var routineExercises: [RoutineExercise] = []
    /// Redesign (2026-07-23): best PR per exercise, feeding the projected
    /// working-weight line on each row. Absent PR = no estimate (honest).
    @State private var prByExercise: [UUID: PersonalRecord] = [:]
    @State private var loading = false
    @State private var errorText: String?

    // Phase M Task 2 (moderation/compliance): Report/Block-owner on routine
    // detail, now via the shared `routineModerationToolbar` modifier (Phase L
    // Task 3 extracted this exact menu/sheet/dialog out to
    // `Features/Moderation/RoutineModerationToolbar.swift` so
    // `DiscoverWorkoutDetailView` — a routine detail screen whose routine is
    // NEVER the caller's own — can carry the identical surface instead of
    // duplicating it). `RoutinesListView`'s only current navigation path here
    // always passes an OWNED routine (`RoutineRepository.fetchAll(ownerID:
    // appState.currentProfile.id)`) — the featured/public-routine shelf in
    // LibraryTabView renders cards only, with no detail navigation of its
    // own. `isOwnRoutine` below keeps the menu correctly inert on this
    // screen's only reachable path.
    //
    // Deliberately separate from `errorText` above: that state gates the
    // whole screen (loading/error/content branches below) — reusing it for
    // a failed block attempt would replace the routine content with a bare
    // error message instead of surfacing a small inline notice.
    @State private var moderationErrorText: String?

    private var isOwnRoutine: Bool { routine.ownerID == appState.currentProfile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Full-screen loading/error only while the exercise list is
                // EMPTY — `.task` re-fires when popping back from an exercise
                // detail / session push (ExercisesListView's afbb415 fix).
                if loading && routineExercises.isEmpty {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else if let errorText, routineExercises.isEmpty {
                    Text(errorText)
                        .font(GSFont.body(14))
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    if let moderationErrorText {
                        Text(moderationErrorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }

                    // Routine summary header (gs3D pass 2026-08-13)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(routine.name)
                            .font(GSFont.heading(22, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                        Text("\(routineExercises.count) exercise\(routineExercises.count == 1 ? "" : "s")")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .gs3DCard(cornerRadius: GSMetrics.radiusMd)

                    // Redesign (2026-07-23): routine CONTENTS — the exercise
                    // list, Discover-detail style, each row navigating to the
                    // exercise's own page, with a projected working weight
                    // from the user's best PR when one exists.
                    if !routineExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            GSSectionHeader("Exercises")
                            VStack(spacing: 8) {
                                ForEach(routineExercises.sorted { $0.position < $1.position }) { re in
                                    routineExerciseRow(re)
                                }
                            }
                        }
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
        .routineModerationToolbar(
            ownerID: routine.ownerID,
            routineID: routine.id,
            isOwnContent: isOwnRoutine,
            moderationErrorText: $moderationErrorText
        )
        .task { await load() }
    }

    // MARK: - Exercise rows (redesign 2026-07-23)

    @ViewBuilder
    private func routineExerciseRow(_ re: RoutineExercise) -> some View {
        let ex = exercises.first { $0.id == re.exerciseID }
        let pr = prByExercise[re.exerciseID]
        let targetReps = re.targetReps.flatMap { Int($0.prefix(while: { $0.isNumber })) }
        let projected = pr.flatMap { StatMath.projectedWeight(prWeight: $0.weight, prReps: $0.reps, targetReps: targetReps) }
        let rowContent = HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? "Exercise")
                    .font(GSFont.heading(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                if let ex {
                    Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let parts: [String] = [
                    re.targetSets.map { "\($0) sets" },
                    re.targetReps.flatMap { $0.isEmpty ? nil : $0 },
                    // Set structures (20260814000003): the prescription
                    // rides the meta line — "drop 2×20%", "burnout",
                    // "to failure".
                    re.setType == "drop"
                        ? "drop \(re.dropSteps ?? 2)×\(NSDecimalNumber(decimal: re.dropPercent ?? 20).intValue)%"
                        : (re.setType == "burnout" ? "burnout" : nil),
                    re.targetFailure ? "to failure" : nil,
                    re.supersetGroup != nil ? "superset" : nil
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                if let projected {
                    // Units sweep: projection is a 5-lb-grid Int in lbs —
                    // re-snap in the user's unit grid for display.
                    Text("~\(Units.format(pounds: Decimal(projected), unit: ThemeStore.shared.weightUnit)) for you")
                        .font(GSFont.bold(11.5, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                }
            }
            if ex != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusSm)
        .contentShape(Rectangle())

        if let ex {
            NavigationLink { ExerciseDetailView(exercise: ex) } label: { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            exercises = try await ExerciseRepository.fetchAll()
            if let (_, exs) = try await RoutineRepository.fetch(id: routine.id) {
                routineExercises = exs
            }
            // Best PR per exercise (max weight) — same recents-window idiom
            // ExerciseDetailView.load() uses. Best-effort: no PRs, no lines.
            if let userID = appState.currentProfile?.id,
               let recents = try? await PersonalRecordRepository.recent(userID: userID, limit: 500) {
                var best: [UUID: PersonalRecord] = [:]
                for pr in recents where (best[pr.exerciseID]?.weight ?? 0) < pr.weight {
                    best[pr.exerciseID] = pr
                }
                prByExercise = best
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
