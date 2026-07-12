import SwiftUI
import UIKit

// MARK: - LobbyView

struct LobbyView: View {
    let session: WorkoutSession

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var participants: [(participant: SessionParticipant, profile: Profile)] = []
    @State private var proposals: [RoutineProposal] = []
    @State private var proposalVotes: [UUID: [ProposalVote]] = [:]
    @State private var proposerUsernames: [UUID: String] = [:]
    @State private var routineInfo: (name: String, exercises: [RoutineExercise])? = nil
    @State private var presenceSet: Set<UUID> = []
    @State private var realtime = LobbyRealtimeService()

    @State private var errorText: String?
    @State private var isCheckingIn = false
    @State private var showTravelDialog = false
    @State private var isStarting = false
    @State private var showStartDialog = false
    @State private var navigateToInProgress = false
    @State private var showProposalComposer = false
    @State private var allExercises: [Exercise] = []
    @State private var currentSession: WorkoutSession?

    // MARK: - Manage menu state

    @State private var showChangeTimeSheet = false
    @State private var changeTimeDate: Date = Date()

    @State private var showCancelOccurrenceDialog = false
    @State private var showCancelSeriesDialog = false
    @State private var upcomingOccurrenceCount: Int = 0

    @State private var showSeriesEditor = false

    // MARK: - Computed helpers

    private var selfID: UUID? { appState.currentProfile?.id }
    private var isOrganizer: Bool { (currentSession ?? session).organizerID == selfID }

    private var effectiveSession: WorkoutSession { currentSession ?? session }
    private var effectiveSeriesID: UUID? { effectiveSession.seriesID }

    private var isManageVisible: Bool {
        let state = effectiveSession.state
        return isOrganizer && (state == "scheduled" || state == "lobby_open")
    }

    private var ownParticipant: SessionParticipant? {
        participants.first(where: { $0.participant.userID == selfID })?.participant
    }

    private var allReady: Bool {
        !participants.isEmpty
            && participants.allSatisfy { $0.participant.checkInState == "ready" }
    }

    private var notReadyCount: Int {
        participants.filter { $0.participant.checkInState != "ready" }.count
    }

    private var isCheckedIn: Bool { ownParticipant?.checkInState == "ready" }

    private var notReadyDialogTitle: String {
        notReadyCount == 1
            ? "1 person hasn't checked in"
            : "\(notReadyCount) people haven't checked in"
    }

    // MARK: - Body

    var body: some View {
        List {
            roomCodeSection
            routineSection
            participantsSection
            proposalsSection
            errorSection
            actionSection
        }
        .navigationTitle("Lobby")
        .toolbar {
            if isManageVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    manageMenu
                }
            }
        }
        .task { await openAndLoad() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await reload() }
        }
        .onDisappear { Task { await realtime.unsubscribe() } }
        // Proposal composer sheet
        .sheet(isPresented: $showProposalComposer) {
            proposalComposerSheet
        }
        // Change time sheet
        .sheet(isPresented: $showChangeTimeSheet) {
            changeTimeSheet
        }
        // Series editor sheet
        .sheet(isPresented: $showSeriesEditor) {
            if let sid = effectiveSeriesID {
                SeriesEditorView(seriesID: sid) {
                    Task { await reload() }
                }
            }
        }
        // Check-in dialog
        .confirmationDialog(
            "Check In Anyway?",
            isPresented: $showTravelDialog,
            titleVisibility: .visible
        ) {
            Button("I'm traveling") { Task { await checkIn(method: "traveling_override") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Couldn't verify you're at your gym. Check in as traveling?")
        }
        // Start-anyway dialog
        .confirmationDialog(
            notReadyDialogTitle,
            isPresented: $showStartDialog,
            titleVisibility: .visible
        ) {
            Button("Start Anyway", role: .destructive) { Task { await startSession() } }
            Button("Wait", role: .cancel) {}
        } message: {
            Text("They'll be marked late and may owe burpees.")
        }
        // Cancel single occurrence dialog
        .confirmationDialog(
            "Cancel this session?",
            isPresented: $showCancelOccurrenceDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel session", role: .destructive) {
                Task { await cancelOccurrence() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This session will be deleted. Other sessions in the series are unaffected.")
        }
        // Cancel series forward dialog
        .confirmationDialog(
            "Cancel rest of series?",
            isPresented: $showCancelSeriesDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel \(upcomingOccurrenceCount) remaining sessions", role: .destructive) {
                Task { await cancelSeriesForward() }
            }
            Button("Keep series", role: .cancel) {}
        } message: {
            Text("All \(upcomingOccurrenceCount) upcoming sessions in this series will be deleted.")
        }
        .navigationDestination(isPresented: $navigateToInProgress) {
            SessionInProgressView(session: session, participants: participants)
        }
    }

    // MARK: - Manage Menu

    @ViewBuilder
    private var manageMenu: some View {
        Menu("Manage") {
            if effectiveSeriesID != nil {
                // Series session menu items
                Button {
                    changeTimeDate = effectiveSession.scheduledFor ?? Date()
                    showChangeTimeSheet = true
                } label: {
                    Label("Change time", systemImage: "clock")
                }

                Button {
                    showSeriesEditor = true
                } label: {
                    Label("Edit series…", systemImage: "repeat")
                }

                Divider()

                Button(role: .destructive) {
                    showCancelOccurrenceDialog = true
                } label: {
                    Label("Cancel this session", systemImage: "xmark.circle")
                }

                Button(role: .destructive) {
                    Task { await loadUpcomingCount() }
                    showCancelSeriesDialog = true
                } label: {
                    Label("Cancel rest of series", systemImage: "xmark.circle.fill")
                }
            } else {
                // Non-series session menu items
                Button {
                    changeTimeDate = effectiveSession.scheduledFor ?? Date()
                    showChangeTimeSheet = true
                } label: {
                    Label("Change time", systemImage: "clock")
                }

                Button(role: .destructive) {
                    showCancelOccurrenceDialog = true
                } label: {
                    Label("Cancel session", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Change Time Sheet

    private var changeTimeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "New time",
                        selection: $changeTimeDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Change Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showChangeTimeSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await applyReschedule() } }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var roomCodeSection: some View {
        if let code = session.roomCode {
            Section {
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Room Code").font(.caption).foregroundStyle(.secondary)
                            Text(code)
                                .font(.title2.monospaced())
                                .fontWeight(.bold)
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var routineSection: some View {
        Section("Routine") {
            routineContent
            Button {
                showProposalComposer = true
            } label: {
                Label("Edit Routine", systemImage: "pencil.and.list.clipboard")
            }
        }
    }

    @ViewBuilder
    private var routineContent: some View {
        if let info = routineInfo {
            Text(info.name).fontWeight(.semibold)
            ForEach(info.exercises) { ex in
                routineExerciseRow(ex)
            }
        } else {
            Text("No routine — propose one below.")
                .foregroundStyle(.secondary)
        }
    }

    private var participantsSection: some View {
        Section("Participants") {
            ForEach(participants, id: \.participant.userID) { item in
                participantRow(item)
            }
        }
    }

    @ViewBuilder
    private var proposalsSection: some View {
        if !proposals.isEmpty {
            Section("Routine Proposals") {
                ForEach(proposals) { proposal in
                    ProposalCardView(
                        proposal: proposal,
                        votes: proposalVotes[proposal.id] ?? [],
                        usernames: proposerUsernames,
                        myID: selfID,
                        onApprove: { await castVote(proposalID: proposal.id, approve: true) },
                        onVeto:    { await castVote(proposalID: proposal.id, approve: false) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorText {
            Section {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
        }
    }

    private var actionSection: some View {
        Section {
            checkInRow
            startRow
        }
    }

    @ViewBuilder
    private var checkInRow: some View {
        if !isCheckedIn {
            Button {
                Task { await initiateCheckIn() }
            } label: {
                if isCheckingIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking in…")
                    }
                } else {
                    Label("Check In", systemImage: "location.circle.fill")
                }
            }
            .disabled(isCheckingIn)
        }
    }

    @ViewBuilder
    private var startRow: some View {
        if isOrganizer {
            Button {
                if allReady {
                    Task { await startSession() }
                } else {
                    showStartDialog = true
                }
            } label: {
                if isStarting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Starting…")
                    }
                } else {
                    Label("Start Session", systemImage: "play.circle.fill")
                }
            }
            .disabled(isStarting)
        } else if isCheckedIn {
            HStack {
                ProgressView().controlSize(.small)
                Text("Waiting for organizer to start…").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Row helpers

    private func routineExerciseRow(_ ex: RoutineExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exercise").font(.footnote)
                HStack(spacing: 8) {
                    if let sets = ex.targetSets {
                        Text("\(sets)×").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let reps = ex.targetReps {
                        Text(reps).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    private func participantRow(
        _ item: (participant: SessionParticipant, profile: Profile)
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    presenceSet.contains(item.participant.userID)
                        ? Color.green
                        : Color(.systemGray4)
                )
                .frame(width: 8, height: 8)

            Text(item.profile.username)
            Spacer()

            checkInIcon(for: item.participant.checkInState)

            if item.participant.burpeesOwed > 0 {
                Text("\(item.participant.burpeesOwed) burpees")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func checkInIcon(for state: String?) -> some View {
        switch state {
        case "ready":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "invited":
            Image(systemName: "clock").foregroundStyle(.secondary)
        default:
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
        }
    }

    // MARK: - Proposal Composer Sheet

    private var proposalComposerSheet: some View {
        ProposalComposerView(
            session: session,
            allExercises: allExercises,
            onProposed: { _ in Task { await reload() } }
        )
    }

    // MARK: - Data Loading

    @MainActor
    private func openAndLoad() async {
        if session.state == "scheduled" {
            do {
                try await SessionRepository.openLobby(sessionID: session.id)
            } catch {
                AppLogger.db.error(
                    "openLobby failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        await reload()

        guard let selfID, let username = appState.currentProfile?.username else { return }
        await realtime.subscribe(
            sessionID: session.id,
            selfID: selfID,
            username: username,
            onPresence: { [self] set in presenceSet = set },
            onChange:   { [self] in Task { await reload() } }
        )
    }

    @MainActor
    private func reload() async {
        do {
            currentSession = try? await SessionRepository.session(id: session.id)

            async let pFetch    = SessionRepository.participants(sessionID: session.id)
            async let propFetch = ProposalRepository.open(sessionID: session.id)
            let (fetchedParticipants, fetchedProposals) = try await (pFetch, propFetch)
            participants = fetchedParticipants
            proposals    = fetchedProposals

            if !fetchedProposals.isEmpty {
                let votes = try await ProposalRepository.votes(
                    proposalIDs: fetchedProposals.map(\.id))
                proposalVotes = Dictionary(grouping: votes, by: \.proposalID)

                let unknownIDs = Set(fetchedProposals.map(\.proposerID))
                    .subtracting(proposerUsernames.keys)
                if !unknownIDs.isEmpty {
                    let profiles = (try? await ProfileRepository.fetchMany(
                        ids: Array(unknownIDs))) ?? []
                    for p in profiles { proposerUsernames[p.id] = p.username }
                }
            }

            let effectiveRoutineID = (currentSession ?? session).routineID
            if let routineID = effectiveRoutineID {
                if let (routine, exercises) = try await RoutineRepository.fetch(id: routineID) {
                    routineInfo = (name: routine.name, exercises: exercises)
                }
            }

            if allExercises.isEmpty {
                allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
            }

            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Check-In

    @MainActor
    private func initiateCheckIn() async {
        isCheckingIn = true
        defer { isCheckingIn = false }
        errorText = nil
        do {
            if let gym = try await CheckInService.primaryGym() {
                do {
                    let location = try await CheckInService.requestLocation()
                    if CheckInService.distanceCheck(gym: gym, location: location) {
                        await checkIn(method: "geofence")
                    } else {
                        // Out of range — offer traveling override
                        showTravelDialog = true
                    }
                } catch {
                    // Location unavailable / denied — always offer override so check-in is reachable
                    showTravelDialog = true
                }
            } else {
                showTravelDialog = true
            }
        } catch let error as GymSyncError {
            if case .validation = error {
                showTravelDialog = true
            } else {
                errorText = error.errorDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func checkIn(method: String) async {
        isCheckingIn = true
        defer { isCheckingIn = false }
        do {
            try await SessionRepository.checkIn(sessionID: session.id, method: method)
            await reload()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Start

    @MainActor
    private func startSession() async {
        isStarting = true
        defer { isStarting = false }
        errorText = nil
        do {
            try await SessionRepository.start(sessionID: session.id)
            navigateToInProgress = true
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Proposals

    @MainActor
    private func castVote(proposalID: UUID, approve: Bool) async {
        do {
            try await ProposalRepository.vote(proposalID: proposalID, approve: approve)
            await reload()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Manage actions

    @MainActor
    private func applyReschedule() async {
        showChangeTimeSheet = false
        do {
            try await SessionRepository.reschedule(sessionID: session.id, to: changeTimeDate)
            await reload()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func cancelOccurrence() async {
        do {
            try await SeriesRepository.cancelOccurrence(sessionID: session.id)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadUpcomingCount() async {
        guard let sid = effectiveSeriesID else { return }
        let all = (try? await SeriesRepository.occurrences(seriesID: sid)) ?? []
        let now = Date()
        upcomingOccurrenceCount = all.filter { session in
            session.state == "scheduled" && (session.scheduledFor ?? .distantPast) > now
        }.count
    }

    @MainActor
    private func cancelSeriesForward() async {
        guard let sid = effectiveSeriesID else { return }
        do {
            try await SeriesRepository.cancelSeriesForward(seriesID: sid)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - ProposalComposerView

/// Inline sheet for proposing a new exercise to the session's routine.
private struct ProposalComposerView: View {
    let session: WorkoutSession
    let allExercises: [Exercise]
    let onProposed: (RoutineProposal) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: Exercise?
    @State private var targetSets: String = "3"
    @State private var targetReps: String = "8-12"
    @State private var targetWeight: String = ""
    @State private var showExercisePicker = false
    @State private var isProposing = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                exercisePickSection
                targetsSection
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Propose Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") { Task { await propose() } }
                        .disabled(selectedExercise == nil || isProposing)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                exercisePickerSheet
            }
        }
    }

    private var exercisePickSection: some View {
        Section("Exercise") {
            if let ex = selectedExercise {
                VStack(alignment: .leading) {
                    Text(ex.name).fontWeight(.semibold)
                    Text(ex.primaryMuscle.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                showExercisePicker = true
            } label: {
                Label(
                    selectedExercise == nil ? "Pick an exercise" : "Change exercise",
                    systemImage: "magnifyingglass"
                )
            }
        }
    }

    private var targetsSection: some View {
        Section("Targets") {
            HStack {
                Text("Sets")
                Spacer()
                TextField("3", text: $targetSets)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Reps")
                Spacer()
                TextField("8-12", text: $targetReps)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Weight (optional)")
                Spacer()
                TextField("e.g. BW", text: $targetWeight)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var exercisePickerSheet: some View {
        NavigationStack {
            List(allExercises, id: \.id) { ex in
                Button {
                    selectedExercise = ex
                    showExercisePicker = false
                } label: {
                    VStack(alignment: .leading) {
                        Text(ex.name)
                        Text(ex.primaryMuscle.capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showExercisePicker = false }
                }
            }
        }
    }

    @MainActor
    private func propose() async {
        guard let exercise = selectedExercise else { return }
        isProposing = true
        defer { isProposing = false }
        errorText = nil

        let payload = RoutineProposal.addExercisePayload(
            exerciseID: exercise.id,
            targetSets: Int(targetSets),
            targetReps: targetReps.isEmpty ? nil : targetReps,
            targetWeight: targetWeight.isEmpty ? nil : targetWeight
        )

        do {
            let proposal = try await ProposalRepository.propose(
                sessionID: session.id,
                type: .addExercise,
                payload: payload,
                affectsExerciseID: exercise.id
            )
            onProposed(proposal)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
