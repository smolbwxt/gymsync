import SwiftUI

// The Routines hub (owner 2026-08-13: "Routines might need a P3"; layout
// revised 2026-08-16: "Coach at the very top, in a wide, tall extruded
// button… a widget tall enough to house exactly 5 routines, sitting
// separately from the builder") — the single home for everything
// routine-shaped, entered from the You tab's ROUTINES widget:
//
//   COACH — the generator's front door, wide + tall + extruded, top.
//   BUILDER — build-your-own, THE create path (the old duplicate
//     "new routine" rows are gone; empty slots are quiet shortcuts).
//   YOUR ROUTINES — one card housing exactly five slots (the free
//     collection): filled rows open the routine, empty rows are quiet
//     "Slot N · open" markers that shortcut to the builder. PRO past the
//     cap grows the card with its extra routines.
//   PRESCRIBED — trainer-written routines, outside the five slots.
//   DISCOVER — community routines.
//
// ScrollView + one extruded card per section (the HelpSheet idiom) —
// the List went with the swipe-to-delete gesture; deletion now rides a
// long-press context menu (the crew-member-removal precedent).
struct RoutinesHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var routines: [Routine] = []
    @State private var routineExercises: [UUID: [RoutineExercise]] = [:]
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingBuilder = false
    @State private var showPaywall = false

    private var slotLimit: Int { Monetization.freeRoutineLimit }

    /// Slot math counts OWN routines only — prescriptions (trainer arm
    /// T2) live outside the five slots by design.
    private var ownRoutines: [Routine] { routines.filter { $0.prescribedBy == nil } }
    private var prescribedRoutines: [Routine] { routines.filter { $0.prescribedBy != nil } }

    /// May this user add another routine right now? (Dormant paywall:
    /// always yes today — same guard RoutinesListView used.)
    private var canAddRoutine: Bool {
        ownRoutines.count < slotLimit
            || Monetization.allows(.unlimitedRoutines, profile: appState.currentProfile)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                coachCard

                builderButton

                sectionHeader("Your routines",
                              trailing: routines.isEmpty ? nil : "\(min(ownRoutines.count, slotLimit)) of \(slotLimit) slots")
                    .padding(.top, 8)
                collectionCard

                if !prescribedRoutines.isEmpty {
                    sectionHeader("Prescribed", trailing: nil)
                        .padding(.top, 8)
                    prescribedCard
                }

                exercisesRow
                    .padding(.top, 8)

                discoverRow

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
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

    // MARK: - COACH (wide, tall, extruded — the top of the hub)

    private var coachCard: some View {
        NavigationLink {
            CoachWizardView(onCreated: { Task { await load() } })
                .background(theme.bg)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("COACH")
                        .font(GSFont.bold(22, relativeTo: .title3))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Text("Tell me your goal, days, equipment, and experience — I'll build your week from the evidence.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Text("THE PROGRAM GENERATOR")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach — the program generator")
    }

    // MARK: - BUILDER (the one create path)

    private var builderButton: some View {
        Button {
            guard canAddRoutine else { showPaywall = true; return }
            showingBuilder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hammer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BUILDER")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Text("Build your own from the exercise catalog")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Builder")
    }

    // MARK: - The five-slot collection (one card, exactly five rows free)

    private var collectionCard: some View {
        VStack(spacing: 0) {
            if loading && routines.isEmpty {
                HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                    .frame(height: CGFloat(slotLimit) * Self.slotRowHeight)
            } else {
                // Filled slots — every own routine (PRO past the cap grows
                // the card); then quiet open-slot markers pad the free
                // collection to exactly five rows.
                ForEach(Array(ownRoutines.enumerated()), id: \.element.id) { index, routine in
                    filledRow(routine)
                    if index < ownRoutines.count - 1 || ownRoutines.count < slotLimit {
                        GSDivider().padding(.horizontal, 12)
                    }
                }
                if ownRoutines.count < slotLimit {
                    ForEach(ownRoutines.count..<slotLimit, id: \.self) { index in
                        emptyRow(number: index + 1)
                        if index < slotLimit - 1 {
                            GSDivider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// One slot's fixed height — five of these IS the widget's height.
    private static let slotRowHeight: CGFloat = 56

    private func filledRow(_ routine: Routine) -> some View {
        let exercises = (routineExercises[routine.id] ?? []).sorted { $0.position < $1.position }
        return NavigationLink {
            RoutineDetailChoice(routine: routine,
                                onEdited: { Task { await load() } })
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(GSFont.heading(15, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(exercises.isEmpty
                         ? "Empty routine — add exercises"
                         : "\(exercises.count) exercises · ~\(StatMath.estimatedMinutes(exercises: exercises)) min")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.slotRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await delete(routine) }
            } label: {
                Label("Delete routine", systemImage: "trash")
            }
        }
    }

    /// Quiet + tappable (owner 2026-08-16): the slot reads as state —
    /// BUILDER above is the create path — but tapping one still shortcuts
    /// to the builder.
    private func emptyRow(number: Int) -> some View {
        Button {
            guard canAddRoutine else { showPaywall = true; return }
            showingBuilder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral400)
                Text("Slot \(number) · open")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: Self.slotRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prescribed (outside the slots)

    private var prescribedCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(prescribedRoutines.enumerated()), id: \.element.id) { index, routine in
                NavigationLink {
                    RoutineDetailChoice(routine: routine,
                                        onEdited: { Task { await load() } })
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(routine.name)
                                    .font(GSFont.heading(15, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                GSTag(text: "Prescribed", style: .accent)
                            }
                            let exercises = (routineExercises[routine.id] ?? [])
                            Text(exercises.isEmpty
                                 ? "Empty routine"
                                 : "\(exercises.count) exercises · ~\(StatMath.estimatedMinutes(exercises: exercises)) min")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Self.slotRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < prescribedRoutines.count - 1 {
                    GSDivider().padding(.horizontal, 12)
                }
            }
        }
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    // MARK: - Exercises (moved in from the You grid, owner 2026-08-16:
    // "the exploratory exercises widget should live in Routines")

    private var exercisesRow: some View {
        NavigationLink {
            ExercisesListView()
                .background(theme.bg)
                .navigationTitle("Exercises")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXERCISES")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Text("Browse the full catalog — form demos and how-tos")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .gsDiscovery(.libraryDiscover, cornerRadius: GSMetrics.radiusMd)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercises")
    }

    // MARK: - Discover

    private var discoverRow: some View {
        NavigationLink {
            DiscoverView()
                .background(theme.bg)
                .navigationTitle("Discover")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DISCOVER")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Text("Community workouts & leaderboards")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discover")
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title)
                .font(GSFont.bold(12, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.text.opacity(0.6))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let fetched = try await RoutineRepository.fetchAll(ownerID: ownerID)
            routines = fetched
            loading = false
            // One bulk fetch for every slot's meta line (count + ~min) —
            // same single-round-trip shape as RoutinesListView.load().
            let bulk = (try? await RoutineRepository.exercisesForRoutines(ids: fetched.map(\.id))) ?? []
            routineExercises = Dictionary(grouping: bulk, by: \.routineID)
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func delete(_ routine: Routine) async {
        try? await RoutineRepository.delete(id: routine.id)
        await load()
    }
}
