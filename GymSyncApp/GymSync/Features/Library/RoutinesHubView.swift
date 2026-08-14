import SwiftUI

// The Routines hub (owner 2026-08-13: "Routines might need a P3") — the
// single home for everything routine-shaped, entered from the You tab's
// ROUTINES widget. Four wide sections:
//
//   YOUR ROUTINES — the five-slot collection (Monetization.freeRoutineLimit)
//     rendered as visible slots: filled ones open the routine, empty ones
//     are extruded "build" invitations (which quietly advertises the cap).
//   COACH — the program generator's front door; a dimmed teaser until the
//     four-dial wizard ships behind it (generator design doc, phase 3).
//   BUILDER — build-your-own, the existing RoutineBuilderView.
//   DISCOVER — community routines, moved in from the You grid (routine
//     discovery belongs where routines live).
//
// One List so the slot rows keep swipe-to-delete (the same gesture
// RoutinesListView owned); every row wears the gs3D language.
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
        List {
            // ── YOUR ROUTINES: the slot collection ──
            Section {
                if loading && routines.isEmpty {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.vertical, 24)
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                } else if let errorText, routines.isEmpty {
                    Text(errorText)
                        .font(GSFont.body(14)).foregroundStyle(.red)
                        .padding(.vertical, 16)
                        .listRowBackground(theme.bg).listRowSeparator(.hidden)
                } else {
                    ForEach(ownRoutines) { routine in
                        NavigationLink {
                            RoutineDetailChoice(routine: routine,
                                                onEdited: { Task { await load() } })
                        } label: {
                            filledSlot(routine)
                        }
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onDelete(perform: delete)

                    // Prescriptions (trainer arm): outside the slots, tagged.
                    ForEach(prescribedRoutines) { routine in
                        NavigationLink {
                            RoutineDetailChoice(routine: routine,
                                                onEdited: { Task { await load() } })
                        } label: {
                            filledSlot(routine)
                        }
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }

                    // Empty slots render as build invitations up to the free
                    // cap; past the cap (PRO, or dormant paywall) a single
                    // "+ new" row keeps the door open.
                    if ownRoutines.count < slotLimit {
                        ForEach(ownRoutines.count..<slotLimit, id: \.self) { index in
                            emptySlot(number: index + 1)
                                .listRowBackground(theme.bg)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } else {
                        addAnotherRow
                            .listRowBackground(theme.bg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                }
            } header: {
                sectionHeader("Your routines",
                              trailing: routines.isEmpty ? nil : "\(min(ownRoutines.count, slotLimit)) of \(slotLimit) slots")
            }

            // ── COACH · BUILDER · DISCOVER ──
            Section {
                coachCard
                    .listRowBackground(theme.bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                builderRow
                    .listRowBackground(theme.bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                discoverRow
                    .listRowBackground(theme.bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            } header: {
                sectionHeader("More ways in", trailing: nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

    // MARK: - Rows

    private func filledSlot(_ routine: Routine) -> some View {
        let exercises = (routineExercises[routine.id] ?? []).sorted { $0.position < $1.position }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(routine.name)
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                if routine.prescribedBy != nil {
                    GSTag(text: "Prescribed", style: .accent)
                }
            }
            if exercises.isEmpty {
                Text("Empty routine — add exercises")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                Text("\(exercises.count) exercises · ~\(StatMath.estimatedMinutes(exercises: exercises)) min")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // Static depth, matching RoutinesListView's card rationale: these
        // rows live in a List whose swipe-to-delete owns the gestures.
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// An open slot IS the invitation — extruded, tappable, honest about
    /// the cap without a paywall in your face.
    private func emptySlot(number: Int) -> some View {
        Button {
            guard canAddRoutine else { showPaywall = true; return }
            showingBuilder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build a routine")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Slot \(number) is open")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    private var addAnotherRow: some View {
        Button {
            guard canAddRoutine else { showPaywall = true; return }
            showingBuilder = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("New routine")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    /// The generator's front door — LIVE (the four-dial wizard ships
    /// behind it, backed by the evidence-cited ProgramGenerator core).
    private var coachCard: some View {
        NavigationLink {
            CoachWizardView(onCreated: { Task { await load() } })
                .background(theme.bg)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("COACH")
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                Text("Tell me your goal, days, time, and experience — I'll build your program.")
                    .font(GSFont.bodyMedium(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
    }

    private var builderRow: some View {
        Button {
            guard canAddRoutine else { showPaywall = true; return }
            showingBuilder = true
        } label: {
            hubRow(icon: "hammer", title: "Builder",
                   subtitle: "Build your own from the exercise catalog")
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Builder")
    }

    private var discoverRow: some View {
        NavigationLink {
            DiscoverView()
                .background(theme.bg)
                .navigationTitle("Discover")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            hubRow(icon: "globe", title: "Discover",
                   subtitle: "Community workouts & leaderboards")
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discover")
    }

    private func hubRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text(subtitle)
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

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title)
                .font(GSFont.bold(12, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.text.opacity(0.6))
                .textCase(nil)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .textCase(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
