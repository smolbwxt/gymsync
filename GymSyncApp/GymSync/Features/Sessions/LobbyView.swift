import SwiftUI
import UIKit

// MARK: - LobbyView

struct LobbyView: View {
    let session: WorkoutSession

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Room code banner (canvas: full-width accent fill, large monospaced code)
                roomCodeBanner

                // Check-in status card (canvas: bordered card, accent left border, location icon)
                checkInStatusCard
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // Proposals section
                if !proposals.isEmpty {
                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    proposalsSection
                        .padding(.top, 8)
                }

                GSDivider()
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // Participants "Who's here"
                participantsSection

                GSDivider()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Routine section
                routineSection
                    .padding(.top, 8)

                // Error
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer(minLength: 80)
            }
        }
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Manage Menu (functional items unchanged)

    @ViewBuilder
    private var manageMenu: some View {
        Menu("Manage") {
            if effectiveSeriesID != nil {
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
                    .tint(theme.accent)
                }
                .listRowBackground(theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Change Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showChangeTimeSheet = false }
                        .foregroundStyle(theme.neutral700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await applyReschedule() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(theme.accent700)
                }
            }
        }
    }

    // MARK: - Room code banner
    // Canvas: accent fill, "ROOM CODE" kicker, large monospaced code, bg-fill copy button

    @ViewBuilder
    private var roomCodeBanner: some View {
        if let code = session.roomCode {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROOM CODE")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.bg.opacity(0.85))
                    Text(code)
                        .font(.custom("Archivo-Bold", size: 30).monospacedDigit())
                        .kerning(4)
                        .foregroundStyle(theme.bg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .regular))
                        Text("Share")
                            .font(GSFont.bold(12, relativeTo: .caption))
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.bg)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.accent)
        }
    }

    // MARK: - Check-in status card
    // Canvas: bordered card with 3px accent left border, location icon, name/status, checkmark

    @ViewBuilder
    private var checkInStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: isCheckedIn ? "location.fill" : "location")
                .font(.system(size: 20))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(isCheckedIn ? "You're checked in" : "Not checked in")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text(isCheckedIn ? "Geofence confirmed" : "Tap Check In below")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            if isCheckedIn {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.accent700)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
                Rectangle()
                    .fill(theme.divider)
                    .frame(width: 1)
                    .padding(.leading, 2)
                Spacer()
                Rectangle()
                    .fill(theme.divider)
                    .frame(width: 1)
                Rectangle()
                    .fill(theme.divider)
                    .frame(height: 1)
                    .rotationEffect(.degrees(90))
                    .hidden() // top/bottom via alignment
            }, alignment: .leading
        )
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Proposals Section
    // Canvas: "Proposal · from Jordan" kicker card, progress bar, Veto/Approve buttons

    @ViewBuilder
    private var proposalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Routine Proposals")
                .padding(.horizontal, 16)

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

    // MARK: - Participants Section
    // Canvas: "Who's here" kicker, bordered rows with initials avatar + name/status + check-in tag

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                GSSectionHeader("Who's here")
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                let readyCount = participants.filter { $0.participant.checkInState == "ready" }.count
                let travelCount = participants.filter { $0.participant.checkInState == "traveling_override" }.count
                if readyCount > 0 || travelCount > 0 {
                    Text("\(readyCount) in\(travelCount > 0 ? " · \(travelCount) traveling" : "")")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
            }

            VStack(spacing: 4) {
                ForEach(participants, id: \.participant.userID) { item in
                    participantRow(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // Canvas participant row: initials avatar + name/status + check-in tag or clock
    private func participantRow(
        _ item: (participant: SessionParticipant, profile: Profile)
    ) -> some View {
        HStack(spacing: 10) {
            // Presence dot + initials avatar
            ZStack(alignment: .bottomTrailing) {
                let initials = String(item.profile.username.prefix(2)).uppercased()
                ZStack {
                    Rectangle()
                        .fill(item.participant.checkInState == "ready" ? theme.accent : theme.neutral400)
                        .frame(width: 32, height: 32)
                    Text(initials)
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .foregroundStyle(theme.bg)
                }

                // Presence online dot
                Circle()
                    .fill(presenceSet.contains(item.participant.userID) ? Color.green : theme.neutral400)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(theme.bg, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.profile.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(checkInSubtitle(for: item.participant))
                    .font(GSFont.body(10, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            // Check-in status tag or burpees
            checkInBadge(for: item.participant)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    @ViewBuilder
    private func checkInBadge(for participant: SessionParticipant) -> some View {
        if participant.burpeesOwed > 0 {
            Text("\(participant.burpeesOwed) burpees")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .foregroundStyle(theme.accent700)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accent100)
        } else {
            switch participant.checkInState {
            case "ready":
                // Canvas: accent tag "Checked in"
                GSTag(text: "Checked in", style: .accent)
            case "invited":
                // Canvas: clock icon for not-yet-arrived
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.neutral500)
            default:
                // Traveling / unknown
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    private func checkInSubtitle(for participant: SessionParticipant) -> String {
        switch participant.checkInState {
        case "ready":              return "Checked in"
        case "traveling_override": return "Traveling"
        case "invited":            return "Invited"
        default:                   return participant.checkInState ?? "Invited"
        }
    }

    // MARK: - Routine Section

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Routine")
                .padding(.horizontal, 16)
                .padding(.top, 8)

            routineContent
                .padding(.horizontal, 16)

            Button {
                showProposalComposer = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 14))
                    Text("Edit Routine")
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                }
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var routineContent: some View {
        if let info = routineInfo {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                ForEach(info.exercises) { ex in
                    routineExerciseRow(ex)
                }
            }
        } else {
            Text("No routine — propose one below.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
        }
    }

    private func routineExerciseRow(_ ex: RoutineExercise) -> some View {
        HStack(spacing: 8) {
            if let sets = ex.targetSets {
                Text("\(sets)×")
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
            if let reps = ex.targetReps {
                Text(reps)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    // MARK: - Action bar (pinned bottom)
    // Canvas: "Lock in & Start" primary button; check-in ghost button above if not checked in

    private var actionBar: some View {
        VStack(spacing: 0) {
            GSDivider()

            VStack(spacing: 8) {
                // Check-in button (if not yet checked in)
                if !isCheckedIn {
                    Button {
                        Task { await initiateCheckIn() }
                    } label: {
                        HStack {
                            if isCheckingIn {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(theme.accent)
                                Text("Checking in…")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            } else {
                                Image(systemName: "location.circle.fill")
                                    .font(.system(size: 15))
                                Text("Check In")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            }
                            Spacer()
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(theme.accent100)
                        .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingIn)
                }

                // Start / Waiting row (organizer vs attendee)
                if isOrganizer {
                    Button {
                        if allReady {
                            Task { await startSession() }
                        } else {
                            showStartDialog = true
                        }
                    } label: {
                        HStack {
                            if isStarting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(theme.bg)
                                Text("Starting…")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            } else {
                                Text("Lock in & Start")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            }
                            Spacer()
                        }
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(isStarting ? theme.accent600 : theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                } else if isCheckedIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.neutral500)
                        Text("Waiting for organizer to start…")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral500)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .background(theme.bg)
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
                        showTravelDialog = true
                    }
                } catch {
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
            // Unsubscribe lobby realtime BEFORE navigating to live session
            // so the lobby channel doesn't compete with the live-session channel.
            await realtime.unsubscribe()
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
    @Environment(\.gsTheme) private var theme

    @State private var selectedExercise: Exercise?
    @State private var targetSets: String = "3"
    @State private var targetReps: String = "8-12"
    @State private var targetWeight: String = ""
    @State private var showExercisePicker = false
    @State private var isProposing = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                // Exercise section
                Section {
                    if let ex = selectedExercise {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                                .font(GSFont.bold(14, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            Text(ex.primaryMuscle.capitalized)
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                        .listRowBackground(theme.surface)
                    }
                    Button {
                        showExercisePicker = true
                    } label: {
                        Label(
                            selectedExercise == nil ? "Pick an exercise" : "Change exercise",
                            systemImage: "magnifyingglass"
                        )
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                        .foregroundStyle(theme.accent)
                    }
                    .listRowBackground(theme.surface)
                } header: {
                    GSSectionHeader("Exercise")
                }
                .listRowSeparatorTint(theme.divider)

                // Targets section
                Section {
                    targetRow(label: "Sets", placeholder: "3", text: $targetSets,
                              keyboard: .numberPad)
                    targetRow(label: "Reps", placeholder: "8-12", text: $targetReps,
                              keyboard: .default)
                    targetRow(label: "Weight (optional)", placeholder: "e.g. BW",
                              text: $targetWeight, keyboard: .default)
                } header: {
                    GSSectionHeader("Targets")
                }
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.divider)

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .listRowBackground(theme.bg)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Propose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.neutral700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") { Task { await propose() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(selectedExercise == nil || isProposing
                                         ? theme.neutral500 : theme.accent700)
                        .disabled(selectedExercise == nil || isProposing)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                exercisePickerSheet
            }
        }
    }

    @ViewBuilder
    private func targetRow(label: String, placeholder: String, text: Binding<String>,
                            keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(GSFont.bodyMedium(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .tint(theme.accent)
                .frame(width: 100)
        }
    }

    private var exercisePickerSheet: some View {
        NavigationStack {
            List(allExercises, id: \.id) { ex in
                Button {
                    selectedExercise = ex
                    showExercisePicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text(ex.primaryMuscle.capitalized)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.divider)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showExercisePicker = false }
                        .foregroundStyle(theme.neutral700)
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
