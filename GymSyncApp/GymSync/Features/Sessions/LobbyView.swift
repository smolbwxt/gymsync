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
    @State private var proposalVotes: [UUID: [ProposalVote]] = [:]  // proposalID → votes
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

    // Proposal composer
    @State private var showProposalComposer = false
    @State private var allExercises: [Exercise] = []

    // MARK: - Computed helpers

    private var selfID: UUID? { appState.currentProfile?.id }
    private var isOrganizer: Bool { session.organizerID == selfID }

    private var ownParticipant: SessionParticipant? {
        participants.first(where: { $0.participant.userID == selfID })?.participant
    }

    private var allReady: Bool {
        !participants.isEmpty && participants.allSatisfy { $0.participant.checkInState == "ready" }
    }

    private var notReadyCount: Int {
        participants.filter { $0.participant.checkInState != "ready" }.count
    }

    private var isCheckedIn: Bool { ownParticipant?.checkInState == "ready" }

    // MARK: - Body

    var body: some View {
        List {
            // Room-code banner
            if let code = session.roomCode {
                Section {
                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Room Code").font(.caption).foregroundStyle(.secondary)
                                Text(code)
                                    .font(.title2.monospaced()).fontWeight(.bold)
                            }
                            Spacer()
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Routine summary
            Section("Routine") {
                if let info = routineInfo {
                    Text(info.name).fontWeight(.semibold)
                    ForEach(info.exercises) { ex in
                        routineExerciseRow(ex)
                    }
                } else {
                    Text("No routine — propose one below.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showProposalComposer = true
                } label: {
                    Label("Edit Routine", systemImage: "pencil.and.list.clipboard")
                }
            }

            // Participants
            Section("Participants") {
                ForEach(participants, id: \.participant.userID) { item in
                    participantRow(item)
                }
            }

            // Proposals
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

            // Error
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }

            // Actions
            actionSection
        }
        .navigationTitle("Lobby")
        .task { await openAndLoad() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await reload() }
        }
        .onDisappear { Task { await realtime.unsubscribe() } }
        .sheet(isPresented: $showProposalComposer) {
            ProposalComposerView(
                session: session,
                allExercises: allExercises,
                onProposed: { _ in Task { await reload() } }
            )
        }
        .confirmationDialog(
            "Location out of range",
            isPresented: $showTravelDialog,
            titleVisibility: .visible
        ) {
            Button("I'm traveling") {
                Task { await checkIn(method: "traveling_override") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You don't appear to be at your home gym. Check in as traveling?")
        }
        .confirmationDialog(
            notReadyCount == 1
                ? "1 person hasn't checked in"
                : "\(notReadyCount) people haven't checked in",
            isPresented: $showStartDialog,
            titleVisibility: .visible
        ) {
            Button("Start Anyway", role: .destructive) {
                Task { await startSession() }
            }
            Button("Wait", role: .cancel) {}
        } message: {
            Text("They'll be marked late and may owe burpees.")
        }
        .navigationDestination(isPresented: $navigateToInProgress) {
            SessionInProgressView(session: session, participants: participants)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func routineExerciseRow(_ ex: RoutineExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exercise")   // we only have IDs here; names resolved elsewhere
                    .font(.footnote)
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

    @ViewBuilder
    private func participantRow(_ item: (participant: SessionParticipant, profile: Profile)) -> some View {
        HStack(spacing: 10) {
            // Presence dot
            Circle()
                .fill(presenceSet.contains(item.participant.userID) ? Color.green : Color(.systemGray4))
                .frame(width: 8, height: 8)

            Text(item.profile.username)

            Spacer()

            // Check-in state icon
            switch item.participant.checkInState {
            case "ready":
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case "invited":
                Image(systemName: "clock").foregroundStyle(.secondary)
            default:
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            }

            // Burpees badge
            if item.participant.burpeesOwed > 0 {
                Text("\(item.participant.burpeesOwed)🍌")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            // Check In — hidden once ready
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

            // Start (organizer) or waiting label (non-organizer who's ready)
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
                    Text("Waiting for organizer to start…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func openAndLoad() async {
        // Open lobby if still scheduled (idempotent)
        if session.state == "scheduled" {
            do {
                try await SessionRepository.openLobby(sessionID: session.id)
            } catch {
                AppLogger.db.error("openLobby failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        await reload()

        // Subscribe to real-time updates
        guard let selfID, let username = appState.currentProfile?.username else { return }
        await realtime.subscribe(
            sessionID: session.id,
            selfID: selfID,
            username: username,
            onPresence: { [self] set in
                presenceSet = set
            },
            onChange: { [self] in
                Task { await reload() }
            }
        )
    }

    @MainActor
    private func reload() async {
        do {
            async let pFetch = SessionRepository.participants(sessionID: session.id)
            async let propFetch = ProposalRepository.open(sessionID: session.id)

            let (fetchedParticipants, fetchedProposals) = try await (pFetch, propFetch)
            participants = fetchedParticipants

            proposals = fetchedProposals
            if !fetchedProposals.isEmpty {
                let votes = try await ProposalRepository.votes(proposalIDs: fetchedProposals.map(\.id))
                proposalVotes = Dictionary(grouping: votes, by: \.proposalID)

                // Resolve proposer usernames
                let unknownIDs = Set(fetchedProposals.map(\.proposerID))
                    .subtracting(proposerUsernames.keys)
                if !unknownIDs.isEmpty {
                    let profiles = (try? await ProfileRepository.fetchMany(ids: Array(unknownIDs))) ?? []
                    for p in profiles { proposerUsernames[p.id] = p.username }
                }
            }

            // Routine summary
            if let routineID = session.routineID {
                if let (routine, exercises) = try await RoutineRepository.fetch(id: routineID) {
                    routineInfo = (name: routine.name, exercises: exercises)
                }
            }

            // Exercise list for proposal composer
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

    // MARK: - Check-In Flow

    @MainActor
    private func initiateCheckIn() async {
        isCheckingIn = true
        defer { isCheckingIn = false }
        errorText = nil

        do {
            if let gym = try await CheckInService.primaryGym() {
                // Geofence check
                let location = try await CheckInService.requestLocation()
                if CheckInService.distanceCheck(gym: gym, location: location) {
                    await checkIn(method: "geofence")
                } else {
                    // Out of range — offer traveling override via dialog
                    showTravelDialog = true
                }
            } else {
                // No gym configured — offer traveling override
                showTravelDialog = true
            }
        } catch let error as GymSyncError {
            if case .validation = error {
                // Location denied/unavailable — still offer travel
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

    // MARK: - Start Session

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

    // MARK: - Proposal Voting

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
}

// MARK: - ProposalComposerView (add-exercise only)

/// Inline sheet for proposing a new exercise to the session's routine.
/// Reuses the exercise-picker pattern from RoutineBuilderView.
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
                NavigationStack {
                    List(allExercises) { ex in
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
