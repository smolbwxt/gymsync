import SwiftUI

// MARK: - GroupSessionLiveView
//
// Canvas design:
//   • Top bar: LIVE pulse + session name + elapsed timer + X dismiss
//   • Turn card: accent-fill when my turn / surface when spectating
//     - current lifter initials avatar + name + chess clock (Text(_:style:.timer))
//     - MY TURN → Log Set primary button
//     - NOT MY TURN + organizer → ghost Skip turn button
//   • Penalty banner (accent fill, per canvas): "YOU OWE N burpees" + Log burpees button
//   • Set feed: reverse-chron rows, cap 30, penalty rows tagged
//   • End Session: confirmation → complete → HealthKit → SessionRecapView sheet

struct GroupSessionLiveView: View {
    let session: WorkoutSession

    @Environment(AppState.self)       private var appState
    @Environment(\.dismiss)          private var dismiss
    @Environment(\.scenePhase)       private var scenePhase
    @Environment(\.gsTheme)          private var theme

    // MARK: - Realtime state

    @State private var liveSession: WorkoutSession
    @State private var participants: [(participant: SessionParticipant, profile: Profile)] = []
    @State private var feedSets: [SetLog] = []       // cap 30, prepend on INSERT
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var liveService = SessionLiveService()

    // MARK: - Routine state

    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var routineName: String? = nil

    // MARK: - UI flags

    @State private var showLogSetSheet      = false
    @State private var isPenaltySheet       = false   // true when LogSetSheet is for burpees
    @State private var showEndConfirmation  = false
    @State private var isEnding             = false
    @State private var errorText: String?
    @State private var recapData: RecapData?          // non-nil → sheet
    @State private var penaltyLogged        = 0       // reps logged this session as penalty by me

    // MARK: - Helpers

    private var selfID: UUID? { appState.currentProfile?.id }
    private var isMyTurn: Bool { liveSession.currentTurnUserID == selfID }
    private var isOrganizer: Bool { liveSession.organizerID == selfID }

    private var currentLifterName: String {
        guard let turnID = liveSession.currentTurnUserID else { return "—" }
        return participants.first(where: { $0.participant.userID == turnID })?.profile.username ?? "—"
    }

    private var currentLifterInitials: String {
        guard let turnID = liveSession.currentTurnUserID else { return "—" }
        let name = participants.first(where: { $0.participant.userID == turnID })?.profile.username ?? "?"
        return String(name.prefix(2)).uppercased()
    }

    private var myParticipant: SessionParticipant? {
        participants.first(where: { $0.participant.userID == selfID })?.participant
    }

    /// Burpees remaining = owed - penalty reps already logged this session by me
    private var burpeesRemaining: Int {
        max(0, (myParticipant?.burpeesOwed ?? 0) - penaltyLogged)
    }

    // MARK: - Init

    init(session: WorkoutSession) {
        self.session = session
        _liveSession = State(initialValue: session)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── HEADER ──────────────────────────────────────────────
                headerBar

                GSDivider()

                // ── TURN CARD ────────────────────────────────────────────
                turnCard
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // ── PENALTY BANNER ───────────────────────────────────────
                if burpeesRemaining > 0 {
                    penaltyBanner
                        .padding(.top, 12)
                }

                // ── SET FEED ─────────────────────────────────────────────
                if !feedSets.isEmpty {
                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    feedSection
                }

                // ── ERROR ────────────────────────────────────────────────
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                Spacer(minLength: 88)
            }
        }
        .background(theme.bg)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .safeAreaInset(edge: .bottom) { endSessionBar }
        // Log Set sheet (reuse LogSetSheet — must pick an exercise first)
        .sheet(isPresented: $showLogSetSheet) { logSetSheetContent }
        // Recap sheet
        .sheet(item: $recapData) { data in
            SessionRecapView(
                session: data.session,
                sets: data.sets,
                participants: participants,
                onDone: { dismiss() }
            )
        }
        // End confirmation
        .confirmationDialog(
            "End session for everyone?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                Task { await endSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will complete the session for all participants.")
        }
        // Realtime lifecycle
        .task { await openAndSubscribe() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await reload() }
        }
        .onDisappear { Task { await liveService.unsubscribe() } }
    }

    // MARK: - Header bar
    // Canvas: LIVE pulse + session name (routine) + elapsed since startedAt + X button

    private var headerBar: some View {
        HStack(spacing: 10) {
            // LIVE indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 9, height: 9)
                Text("LIVE")
                    .font(GSFont.bold(12, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
            }

            Text(routineName ?? "Session")
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer()

            // Session elapsed — Text timer, never a Swift Timer
            if let startedAt = liveSession.startedAt {
                Text(startedAt, style: .timer)
                    .font(.custom("Archivo-Bold", size: 14).monospacedDigit())
                    .foregroundStyle(theme.neutral700)
                    .monospacedDigit()
            }

            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Turn card
    // Canvas 2A (my turn): accent fill, "YOUR TURN" kicker, name, chess clock, Log Set button
    // Canvas 2B (spectating): surface card, "LIFTING NOW" kicker, name, clock, ghost Skip

    @ViewBuilder
    private var turnCard: some View {
        let turnStart = liveSession.currentTurnStartedAt

        VStack(alignment: .leading, spacing: 12) {
            // Kicker + name row
            HStack(alignment: .center, spacing: 8) {
                // Initials avatar
                ZStack {
                    Rectangle()
                        .fill(isMyTurn ? theme.bg.opacity(0.25) : theme.neutral400)
                        .frame(width: 36, height: 36)
                    Text(currentLifterInitials)
                        .font(GSFont.bold(12, relativeTo: .caption2))
                        .foregroundStyle(isMyTurn ? theme.bg : theme.text)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isMyTurn ? "YOUR TURN" : "LIFTING NOW")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(isMyTurn ? theme.bg.opacity(0.85) : theme.accent700)

                    Text(isMyTurn ? "You" : currentLifterName)
                        .font(GSFont.heading(20, relativeTo: .title2))
                        .foregroundStyle(isMyTurn ? theme.bg : theme.text)
                }

                Spacer()

                // Chess clock — state-driven from currentTurnStartedAt, never a Timer
                VStack(alignment: .trailing, spacing: 1) {
                    Text("SET TIMER")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(isMyTurn ? theme.bg.opacity(0.7) : theme.neutral500)

                    if let ts = turnStart {
                        Text(ts, style: .timer)
                            .font(.custom("Archivo-Bold", size: 26).monospacedDigit())
                            .foregroundStyle(isMyTurn ? theme.bg : theme.text)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.custom("Archivo-Bold", size: 26))
                            .foregroundStyle(isMyTurn ? theme.bg : theme.neutral500)
                    }
                }
            }

            // Action buttons
            if isMyTurn {
                Button {
                    isPenaltySheet = false
                    showLogSetSheet = true
                } label: {
                    HStack {
                        Text("Log Set & Pass")
                            .font(GSFont.bold(15, relativeTo: .body))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(theme.bg.opacity(0.2))
                    .overlay(Rectangle().strokeBorder(theme.bg.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else if isOrganizer && liveSession.currentTurnUserID != nil {
                // Organizer can skip a stuck turn
                Button {
                    Task { await skipTurn() }
                } label: {
                    HStack {
                        Image(systemName: "forward.end")
                            .font(.system(size: 13))
                        Text("Skip turn")
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                        Spacer()
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(theme.accent100)
                    .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMyTurn ? theme.accent : theme.surface)
        .overlay(Rectangle().strokeBorder(
            isMyTurn ? Color.clear : theme.divider, lineWidth: 1))
    }

    // MARK: - Penalty banner
    // Canvas: accent fill "YOU OWE N BURPEES" kicker, large count, Log burpees button

    private var penaltyBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOU OWE")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(burpeesRemaining)")
                    .font(GSFont.bold(48, relativeTo: .largeTitle))
                    .foregroundStyle(theme.bg)
                    .lineLimit(1)
                Text("burpees")
                    .font(GSFont.bold(18, relativeTo: .title2))
                    .foregroundStyle(theme.bg)
            }

            Button {
                isPenaltySheet = true
                showLogSetSheet = true
            } label: {
                HStack {
                    Text("Log burpees")
                        .font(GSFont.bold(14, relativeTo: .body))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.bg.opacity(0.15))
                .overlay(Rectangle().strokeBorder(theme.bg.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent700.opacity(0.85))
        .padding(.horizontal, 16)
    }

    // MARK: - Set feed
    // Reverse-chron, cap 30 rows; penalty rows tagged; username · exercise · reps×weight

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Live Feed")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            // feedSets is already newest-first (prepended on INSERT)
            ForEach(feedSets.prefix(30)) { log in
                feedRow(log)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                if log.id != feedSets.prefix(30).last?.id {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func feedRow(_ log: SetLog) -> some View {
        HStack(spacing: 8) {
            // Avatar initial for the logger
            let loggerInitials: String = {
                let name = participants.first(where: { $0.participant.userID == log.userID })?.profile.username ?? "?"
                return String(name.prefix(2)).uppercased()
            }()
            ZStack {
                Rectangle()
                    .fill(log.userID == selfID ? theme.accent : theme.neutral400)
                    .frame(width: 28, height: 28)
                Text(loggerInitials)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 1) {
                let username = participants.first(where: { $0.participant.userID == log.userID })?.profile.username ?? "?"
                let exerciseName = exerciseNames[log.exerciseID] ?? "Exercise"

                HStack(spacing: 4) {
                    Text(username)
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                    Text("· \(exerciseName)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                }

                let repsText = log.reps.map { "\($0)" } ?? "—"
                let weightText = log.weight.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—"
                HStack(spacing: 4) {
                    Text("\(repsText) × \(weightText)")
                        .font(GSFont.bodyMedium(13, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    if log.isPenalty {
                        GSTag(text: "penalty", style: .accent)
                    }
                    if log.isFailed {
                        GSTag(text: "failed", style: .neutral)
                    }
                }
            }

            Spacer()

            // Elapsed time since logged
            Text(log.loggedAt, style: .relative)
                .font(GSFont.body(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    // MARK: - End session bar

    private var endSessionBar: some View {
        VStack(spacing: 0) {
            GSDivider()
            Button(role: .destructive) {
                showEndConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "stop.circle")
                    Text("End Session")
                    Spacer()
                }
                .font(GSFont.bold(15, relativeTo: .body))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(isEnding ? Color.red.opacity(0.6) : Color.red)
            }
            .buttonStyle(.plain)
            .disabled(isEnding)
        }
        .background(theme.bg)
    }

    // MARK: - LogSetSheet content

    @ViewBuilder
    private var logSetSheetContent: some View {
        if isPenaltySheet {
            // Penalty burpees: use a burpee exercise if present, else first exercise
            let burpeeExercise = allExercises.first(where: {
                $0.name.localizedCaseInsensitiveContains("burpee")
            }) ?? allExercises.first
            if let ex = burpeeExercise {
                LogSetSheet(
                    exercise: ex,
                    setIndex: 1,
                    defaultReps: "\(burpeesRemaining)",
                    defaultWeight: nil
                ) { reps, weight, rpe, isFailed, note in
                    Task { await logSet(reps: reps, weight: weight, rpe: rpe,
                                        isFailed: false, note: note,
                                        exerciseID: ex.id, isPenalty: true) }
                }
            }
        } else {
            // Normal set: pick from routine exercises or first available
            let exerciseForSheet = currentExerciseForSheet
            if let ex = exerciseForSheet {
                LogSetSheet(
                    exercise: ex,
                    setIndex: mySetCount(for: ex.id) + 1,
                    defaultReps: defaultReps(for: ex.id),
                    defaultWeight: nil
                ) { reps, weight, rpe, isFailed, note in
                    Task { await logSetAndAdvance(reps: reps, weight: weight, rpe: rpe,
                                                   isFailed: isFailed, note: note,
                                                   exerciseID: ex.id) }
                }
            }
        }
    }

    /// Best-guess current exercise for the turn (first routine exercise, or first from allExercises).
    private var currentExerciseForSheet: Exercise? {
        if let firstRE = routineExercises.first {
            return allExercises.first(where: { $0.id == firstRE.exerciseID })
        }
        return allExercises.first
    }

    private func mySetCount(for exerciseID: UUID) -> Int {
        feedSets.filter { $0.userID == selfID && $0.exerciseID == exerciseID && !$0.isPenalty }.count
    }

    private func defaultReps(for exerciseID: UUID) -> String? {
        routineExercises.first(where: { $0.exerciseID == exerciseID })?.targetReps
    }

    // MARK: - Data loading

    @MainActor
    private func openAndSubscribe() async {
        await reload()
        await ExerciseNameCache.preload()
        await liveService.subscribe(
            sessionID: liveSession.id,
            onSessionChange: { updated in
                liveSession = updated
            },
            onParticipantsChange: {
                Task { await reloadParticipants() }
            },
            onSetLogged: { log in
                // Prepend to feed (newest-first), cap 30
                feedSets.insert(log, at: 0)
                if feedSets.count > 30 { feedSets = Array(feedSets.prefix(30)) }
                // Track penalty reps logged by me
                if log.userID == selfID && log.isPenalty {
                    penaltyLogged += log.reps ?? 0
                }
                // Populate exercise name cache entry
                if exerciseNames[log.exerciseID] == nil {
                    let id = log.exerciseID
                    Task { exerciseNames[id] = await ExerciseNameCache.name(for: id) }
                }
            }
        )
    }

    @MainActor
    private func reload() async {
        async let pFetch     = SessionRepository.participants(sessionID: session.id)
        async let setsFetch  = SessionRepository.sessionSets(sessionID: session.id)
        async let sessionRef = SessionRepository.session(id: session.id)

        do {
            let (fetchedParts, fetchedSets, fetchedSession) =
                try await (pFetch, setsFetch, sessionRef)
            participants = fetchedParts
            if let s = fetchedSession { liveSession = s }

            // Build feed: newest first, cap 30
            feedSets = Array(fetchedSets.reversed().prefix(30))

            // Precount my penalty reps already logged
            penaltyLogged = fetchedSets
                .filter { $0.userID == selfID && $0.isPenalty }
                .compactMap(\.reps)
                .reduce(0, +)

            // Populate exercise names
            let exerciseIDs = Set(fetchedSets.map(\.exerciseID))
            for id in exerciseIDs where exerciseNames[id] == nil {
                let name = await ExerciseNameCache.name(for: id)
                exerciseNames[id] = name
            }
        } catch {
            AppLogger.sessions.error("GroupSessionLiveView reload: \(error, privacy: .public)")
        }

        // Routine
        if let routineID = liveSession.routineID {
            if let (routine, exercises) = try? await RoutineRepository.fetch(id: routineID) {
                routineName = routine.name
                routineExercises = exercises
                let exIDs = exercises.map(\.exerciseID)
                if allExercises.isEmpty || !exIDs.allSatisfy({ id in allExercises.contains(where: { $0.id == id }) }) {
                    allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
                }
            }
        } else if allExercises.isEmpty {
            allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
        }
    }

    @MainActor
    private func reloadParticipants() async {
        if let fetched = try? await SessionRepository.participants(sessionID: session.id) {
            participants = fetched
        }
    }

    // MARK: - Actions

    @MainActor
    private func logSetAndAdvance(
        reps: Int?, weight: Decimal?, rpe: Decimal?,
        isFailed: Bool, note: String?, exerciseID: UUID
    ) async {
        guard let userID = selfID else { return }
        let log = SetLog(
            id: UUID(), userID: userID, sessionID: session.id,
            exerciseID: exerciseID,
            setIndex: mySetCount(for: exerciseID) + 1,
            reps: reps, weight: weight, rpe: rpe,
            isFailed: isFailed, isPenalty: false,
            note: note, loggedAt: Date()
        )
        do {
            try await SessionRepository.logSet(log)
            try await SessionRepository.advanceTurn(sessionID: session.id)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func logSet(
        reps: Int?, weight: Decimal?, rpe: Decimal?,
        isFailed: Bool, note: String?, exerciseID: UUID, isPenalty: Bool
    ) async {
        guard let userID = selfID else { return }
        let log = SetLog(
            id: UUID(), userID: userID, sessionID: session.id,
            exerciseID: exerciseID,
            setIndex: 1,
            reps: reps, weight: weight, rpe: rpe,
            isFailed: isFailed, isPenalty: isPenalty,
            note: note, loggedAt: Date()
        )
        do {
            try await SessionRepository.logSet(log)
            if isPenalty {
                penaltyLogged += reps ?? 0
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func skipTurn() async {
        do {
            try await SessionRepository.advanceTurn(sessionID: session.id)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func endSession() async {
        isEnding = true
        defer { isEnding = false }
        errorText = nil
        do {
            let completed = try await SessionRepository.complete(sessionID: session.id)
            let allSets = try await SessionRepository.sessionSets(sessionID: session.id)
            try? await HealthKitBridge.requestPermission()
            try? await HealthKitBridge.exportWorkout(session: completed, setLogs: allSets)
            await liveService.unsubscribe()
            recapData = RecapData(session: completed, sets: allSets)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - RecapData (Identifiable for sheet presentation)

private struct RecapData: Identifiable {
    let id = UUID()
    let session: WorkoutSession
    let sets: [SetLog]
}
