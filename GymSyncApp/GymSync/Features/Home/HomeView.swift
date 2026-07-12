import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var groups: [GymGroup] = []
    @State private var showScheduleSheet = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joinedSession: WorkoutSession?
    @State private var navigateToJoined = false

    // MARK: - Canvas content state (Task 5)
    @State private var historySessions: [WorkoutSession] = []
    @State private var ownedRoutines: [Routine] = []
    @State private var allExercises: [Exercise] = []
    @State private var recentPRs: [PersonalRecord] = []
    @State private var prsThisMonth: Int = 0
    @State private var profile: Profile?
    @State private var todaysRoutine: Routine?
    @State private var todaysRoutineExercises: [RoutineExercise] = []
    @State private var showRoutinePicker = false
    @State private var routinePickerPreselected: Routine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    startSoloWorkoutButton
                    if let pr = recentPRs.first {
                        prCardView(pr)
                    }
                    if let routine = todaysRoutine {
                        todaysRoutineCardView(routine)
                    }
                    statTileRow
                    GSDivider()
                    scheduleButton
                    GSDivider()
                    upcomingSection
                    GSDivider()
                    joinWithCodeSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .refreshable { await refresh() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await refresh() }
            }
            .sheet(isPresented: $showScheduleSheet) {
                ScheduleSessionView { newSession in
                    upcomingSessions.insert(newSession, at: 0)
                }
            }
            .sheet(isPresented: $showRoutinePicker) {
                RoutinePickerSheet(routines: ownedRoutines, initialRoutine: routinePickerPreselected)
            }
            .navigationDestination(isPresented: $navigateToJoined) {
                if let session = joinedSession {
                    LobbyView(session: session)
                }
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home")
                .font(GSFont.heading(28, relativeTo: .largeTitle))
                .foregroundStyle(theme.text)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Start Solo Workout CTA (Task 5 — canvas content)

    private var startSoloWorkoutButton: some View {
        Button {
            routinePickerPreselected = nil
            showRoutinePicker = true
        } label: {
            Text("Start Solo Workout")
        }
        .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - PR Card (Task 5 — canvas content)

    @ViewBuilder
    private func prCardView(_ pr: PersonalRecord) -> some View {
        let exerciseName = allExercises.first(where: { $0.id == pr.exerciseID })?.name ?? "Exercise"
        GSCard(bordered: false, backgroundColor: theme.accent100) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🔥 New personal record")
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral700)
                Text("\(exerciseName) — \(trimmedDecimal(pr.weight)) lbs × \(pr.reps)")
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text("Beat previous best by \(trimmedDecimal(pr.weight - pr.previousBest)) lbs")
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Today's Routine Card (Task 5 — canvas content)

    @ViewBuilder
    private func todaysRoutineCardView(_ routine: Routine) -> some View {
        Button {
            routinePickerPreselected = routine
            showRoutinePicker = true
        } label: {
            GSCard(bordered: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's routine")
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                    Text(routine.name)
                        .font(GSFont.heading(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    if !todaysRoutineBody.isEmpty {
                        Text(todaysRoutineBody)
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                    }
                    Text("\(todaysRoutineExercises.count) exercises")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var todaysRoutineBody: String {
        let names = todaysRoutineExercises
            .sorted { $0.position < $1.position }
            .compactMap { re in allExercises.first(where: { $0.id == re.exerciseID })?.name }
        guard !names.isEmpty else { return "" }
        if names.count <= 3 {
            return names.joined(separator: " · ")
        }
        let shown = names.prefix(3).joined(separator: " · ")
        return "\(shown) +\(names.count - 3) more"
    }

    // MARK: - Stat Tile Row (Task 5 — canvas content)

    private var statTileRow: some View {
        HStack(spacing: 8) {
            GSStatTile(
                value: "\(StatMath.workoutsThisWeek(sessions: historySessions))",
                label: "Workouts this week"
            )
            GSStatTile(
                value: StatMath.compactNumber(profile?.lifetimeVolumeLifted ?? 0),
                label: "Lifetime lbs"
            )
            GSStatTile(
                value: "\(prsThisMonth)",
                label: "PRs this month",
                valueColor: theme.accent700
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Schedule Button

    private var scheduleButton: some View {
        Button {
            showScheduleSheet = true
        } label: {
            Text("+ Schedule Session")
        }
        .buttonStyle(GSPrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Upcoming Sessions")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if upcomingSessions.isEmpty {
                Text("No upcoming sessions — schedule one above.")
                    .font(GSFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(upcomingSessions) { session in
                    NavigationLink {
                        LobbyView(session: session)
                    } label: {
                        upcomingCard(session)
                    }
                    .buttonStyle(.plain)
                    GSDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingCard(_ session: WorkoutSession) -> some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Kicker: group name or "Session"
                HStack(spacing: 6) {
                    if let groupID = session.groupID,
                       let group = groups.first(where: { $0.id == groupID }) {
                        Text(group.name.uppercased())
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    } else {
                        Text("SESSION")
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    }
                    if session.seriesID != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.accent700)
                    }
                }
                // Title: routine label
                Text(routineLabel(for: session))
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                // Meta: scheduled time or status
                if let scheduledFor = session.scheduledFor {
                    Text(scheduledFor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                } else {
                    Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Join with Code Section

    private var joinWithCodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Join with Code")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            GSCard(bordered: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("6-character code", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(GSFont.bodyMedium(16, relativeTo: .body))
                            .foregroundStyle(theme.text)
                            .onChange(of: joinCode) {
                                let uppercased = joinCode.uppercased()
                                if joinCode != uppercased { joinCode = uppercased }
                                if joinCode.count > 6 { joinCode = String(joinCode.prefix(6)) }
                            }
                        Button("Join") {
                            Task { await joinByCode() }
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(width: 72)
                        .disabled(joinCode.count != 6 || isJoining)
                        .opacity(joinCode.count != 6 || isJoining ? 0.4 : 1)
                    }
                    if isJoining {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(theme.accent)
                            Text("Joining…")
                                .font(GSFont.body(14, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    if let joinError {
                        Text(joinError)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        async let sessionsFetch = SessionRepository.upcoming()
        async let groupsFetch   = GroupRepository.myGroups()
        do {
            let (sessions, fetchedGroups) = try await (sessionsFetch, groupsFetch)
            upcomingSessions = sessions
            groups = fetchedGroups
        } catch {
            // Best-effort: leave existing data; errors are non-blocking for home
        }

        guard let userID = appState.currentProfile?.id else { return }

        // Task 5 additions — same best-effort, swallow-errors-leave-stale-data
        // pattern as above, kicked off in parallel and awaited individually so
        // one failure doesn't discard the others.
        async let historyFetch   = SessionRepository.history(userID: userID, limit: 20)
        async let routinesFetch  = RoutineRepository.fetchAll(ownerID: userID)
        async let exercisesFetch = ExerciseRepository.fetchAll()
        async let prsFetch       = PersonalRecordRepository.recent(userID: userID, limit: 1)
        async let prCountFetch   = PersonalRecordRepository.countSince(userID: userID, date: StatMath.startOfMonth())
        async let profileFetch   = ProfileRepository.refresh(userID: userID)

        if let history = try? await historyFetch { historySessions = history }
        if let routines = try? await routinesFetch { ownedRoutines = routines }
        if let exercises = try? await exercisesFetch { allExercises = exercises }
        if let prs = try? await prsFetch { recentPRs = prs }
        if let prCount = try? await prCountFetch { prsThisMonth = prCount }
        if let refreshedProfile = try? await profileFetch { profile = refreshedProfile }

        await loadTodaysRoutine()
    }

    @MainActor
    private func loadTodaysRoutine() async {
        let targetID = historySessions.first(where: { $0.routineID != nil })?.routineID ?? ownedRoutines.first?.id
        guard let targetID,
              let (routine, exercises) = try? await RoutineRepository.fetch(id: targetID) else {
            todaysRoutine = nil
            todaysRoutineExercises = []
            return
        }
        todaysRoutine = routine
        todaysRoutineExercises = exercises
    }

    @MainActor
    private func joinByCode() async {
        guard joinCode.count == 6 else { return }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let session = try await SessionRepository.joinByCode(joinCode)
            joinCode = ""
            joinedSession = session
            navigateToJoined = true
        } catch let error as GymSyncError {
            joinError = error.errorDescription
        } catch {
            joinError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func routineLabel(for session: WorkoutSession) -> String {
        // Without eager-loading routine names here, use a generic label.
        // If a routineID is present, "Workout" serves as a placeholder;
        // the full name is visible in LobbyView.
        "Workout"
    }

    private func trimmedDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

// MARK: - Routine Picker Sheet
//
// Task 5: the "Start Solo Workout" CTA and the "Today's routine" card both
// route through this sheet. It reuses the EXACT solo-start mechanism already
// used by Library/Workout's `RoutineDetailChoice`
// (`WorkoutSessionView(routine:routineExercises:allExercises:)`) — no new
// session-start path was built. "No routine" starts an untargeted session by
// passing `routine: nil` (see the Task 5 deviation note in
// `WorkoutSessionView.swift`, where `routine` was widened from `Routine` to
// `Routine?` to make that representable).

private struct RoutinePickerSheet: View {
    let routines: [Routine]
    let initialRoutine: Routine?

    @Environment(\.gsTheme) private var theme

    @State private var chosenRoutine: Routine?
    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var startNavigation = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    Task { await start(routine: nil) }
                } label: {
                    Text("No routine")
                        .font(GSFont.bodyMedium(16, relativeTo: .body))
                        .foregroundStyle(theme.text)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .listRowBackground(theme.bg)

                ForEach(routines) { routine in
                    Button {
                        Task { await start(routine: routine) }
                    } label: {
                        Text(routine.name)
                            .font(GSFont.bodyMedium(16, relativeTo: .body))
                            .foregroundStyle(theme.text)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .listRowBackground(theme.bg)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $startNavigation) {
                WorkoutSessionView(routine: chosenRoutine,
                                   routineExercises: routineExercises,
                                   allExercises: allExercises)
            }
            .task {
                if let initialRoutine {
                    await start(routine: initialRoutine)
                }
            }
        }
    }

    @MainActor
    private func start(routine: Routine?) async {
        allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
        if let routine {
            routineExercises = (try? await RoutineRepository.fetch(id: routine.id))?.1 ?? []
        } else {
            routineExercises = []
        }
        chosenRoutine = routine
        startNavigation = true
    }
}
