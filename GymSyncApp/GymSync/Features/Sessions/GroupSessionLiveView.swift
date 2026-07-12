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
//   • Soundboard dock (canvas gs-dock-scroll strip): horizontally scrolling sound tiles
//     (4 slugs) + reaction pills (🔥💪😂👏), tapping plays locally + broadcasts.
//   • Reaction overlay: incoming reactions float up as emoji pills (2s, opacity + offset).
//   • Soundboard overlay: incoming sounds show transient "{username} 🔊 {name}" line.
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

    // MARK: - Soundboard & broadcast state

    @State private var broadcastService = SessionBroadcastService()
    /// Catalog of (slug, displayName) pairs, populated async on first appear.
    @State private var soundCatalog: [(slug: String, name: String)] = []
    /// 1-second local gate: prevents double-fire and keeps local + remote in sync.
    @State private var lastSoundTapAt: Date = .distantPast
    /// Transient incoming-sound overlay: "{username} 🔊 {name}" — cleared after 2.5s.
    @State private var soundOverlayText: String? = nil
    /// Transient floating reaction pill — cleared after 2s.
    @State private var reactionOverlay: String? = nil
    @State private var reactionOverlayVisible = false

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

    // PR in-session overlay: shown for ~2.5s after MY set hits a new weight PR
    @State private var isPROverlay          = false
    @State private var prOverlayExerciseName: String = ""

    /// Fixed slug list — display names fetched async from the catalog.
    private let soundSlugs = ["airhorn", "lets-go", "ding", "boo"]
    /// Per-slug icon so soundboard tiles are visually differentiated (per proof) —
    /// client-side mapping only; does not touch the `soundboard_sounds` catalog content.
    private let soundIcons: [String: String] = [
        "airhorn": "megaphone.fill",
        "lets-go": "bolt.fill",
        "ding":    "bell.fill",
        "boo":     "hand.thumbsdown.fill"
    ]
    /// Reaction emojis per canvas reaction strip.
    private let reactionEmojis = ["🔥", "💪", "😂", "👏"]

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
        ZStack(alignment: .bottom) {
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

            // ── PR OVERLAY (full-width accent flash, ~2.5s, auto-dismiss) ──
            // Centred via a full-screen VStack with Spacers so it sits mid-screen
            // regardless of the ZStack's .bottom alignment.
            if isPROverlay {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🔥")
                            .font(.system(size: 36))
                        Text("NEW PR")
                            .font(.custom("Archivo-Bold", size: 13))
                            .tracking(2.0)
                            .foregroundStyle(theme.bg.opacity(0.9))
                        Text(prOverlayExerciseName)
                            .font(.custom("Archivo-Bold", size: 22))
                            .foregroundStyle(theme.bg)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(theme.accent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.accent.opacity(0.55))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .allowsHitTesting(false)
            }

            // ── REACTION OVERLAY (floating emoji pill) ───────────────────
            if let emoji = reactionOverlay {
                Text(emoji)
                    .font(.system(size: 40))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                    .opacity(reactionOverlayVisible ? 1 : 0)
                    .offset(y: reactionOverlayVisible ? -120 : -80)
                    .animation(.easeOut(duration: 0.3), value: reactionOverlayVisible)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // ── SOUNDBOARD DOCK ──────────────────────────────────────
                soundboardDock
                // ── END SESSION BAR ──────────────────────────────────────
                endSessionBar
            }
        }
        // Incoming-sound transient overlay (inline, above dock area)
        .overlay(alignment: .bottom) {
            if let txt = soundOverlayText {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 11, weight: .semibold))
                    Text(txt)
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.neutral700)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(theme.surface)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                .padding(.bottom, 130)  // float above dock
                .transition(.opacity)
                .id(txt)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: soundOverlayText)
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
        // Realtime lifecycle — SessionLiveService + SessionBroadcastService
        .task { await openAndSubscribe() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await reload()
                await subscribeBroadcast()
            }
        }
        .onDisappear {
            Task {
                await liveService.unsubscribe()
                await broadcastService.unsubscribe()
            }
        }
    }

    // MARK: - Soundboard Dock
    // Canvas gs-dock-scroll strip: HYPE kicker + sound tiles + divider + reaction pills.

    private var soundboardDock: some View {
        VStack(spacing: 0) {
            GSDivider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    // Section kicker
                    Text("HYPE")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(theme.neutral500)
                        .fixedSize()

                    // Sound tiles
                    ForEach(soundSlugs, id: \.self) { slug in
                        let name = soundCatalog.first(where: { $0.slug == slug })?.name
                            ?? slug.uppercased()
                        Button {
                            Task { await tapSound(slug: slug) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: soundIcons[slug] ?? "speaker.wave.1")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(name.uppercased())
                                    .font(GSFont.bold(10, relativeTo: .caption2))
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(theme.accent100)
                            .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }

                    // Vertical separator
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1, height: 20)
                        .fixedSize()

                    // Reaction pills
                    ForEach(reactionEmojis, id: \.self) { emoji in
                        Button {
                            Task { await tapReaction(emoji: emoji) }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 13))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(theme.surface)
                                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(theme.bg)
        }
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
                    .contentShape(Rectangle())
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
    // Note: GSDivider omitted here — soundboardDock above already provides the top border.

    private var endSessionBar: some View {
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
                                        isFailed: isFailed, note: note,
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
                // Track penalty reps logged by me (failed burpees don't clear debt)
                if log.userID == selfID && log.isPenalty && !log.isFailed {
                    penaltyLogged += log.reps ?? 0
                }
                // Populate exercise name cache entry
                if exerciseNames[log.exerciseID] == nil {
                    let id = log.exerciseID
                    Task { exerciseNames[id] = await ExerciseNameCache.name(for: id) }
                }
            }
        )
        // Pre-fetch sound catalog display names and subscribe to broadcast.
        await loadSoundCatalog()
        await subscribeBroadcast()
    }

    /// Fetch display names for the 4 known slugs so tiles render correctly before any tap.
    @MainActor
    private func loadSoundCatalog() async {
        var entries: [(slug: String, name: String)] = []
        for slug in soundSlugs {
            let name = await SoundboardPlayer.shared.displayName(for: slug)
            entries.append((slug: slug, name: name))
        }
        soundCatalog = entries
    }

    /// Subscribe to broadcast events (soundboard + reaction). Mirrors the SessionLiveService
    /// lifecycle — call from .task and re-call on scenePhase → active reload path.
    @MainActor
    private func subscribeBroadcast() async {
        await broadcastService.subscribe(
            sessionID: liveSession.id,
            onSoundboard: { userID, slug in
                // Skip own soundboard echo — sender already played locally on tap.
                guard userID != selfID else { return }
                // Incoming remote sound: play locally + show transient overlay.
                // Closures are @MainActor, so @State mutations are safe here.
                Task { @MainActor in
                    await SoundboardPlayer.shared.play(slug: slug)
                    let name = await SoundboardPlayer.shared.displayName(for: slug)
                    let username = participants
                        .first(where: { $0.participant.userID == userID })?.profile.username
                        ?? "Someone"
                    await showSoundOverlay("\(username) 🔊 \(name)")
                }
            },
            onReaction: { _, emoji in
                Task { @MainActor in
                    await showReactionOverlay(emoji)
                }
            }
        )
    }

    /// Show the incoming-sound transient overlay for 2.5 seconds.
    @MainActor
    private func showSoundOverlay(_ text: String) async {
        soundOverlayText = text
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if soundOverlayText == text { soundOverlayText = nil }
    }

    /// Show a floating reaction pill for 2 seconds (opacity + offset animation per canvas).
    @MainActor
    private func showReactionOverlay(_ emoji: String) async {
        reactionOverlay = emoji
        reactionOverlayVisible = false
        // Small yield so the view re-renders the initial hidden state first.
        try? await Task.sleep(nanoseconds: 30_000_000)
        reactionOverlayVisible = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        reactionOverlayVisible = false
        try? await Task.sleep(nanoseconds: 350_000_000)
        if reactionOverlay == emoji { reactionOverlay = nil }
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

            // Precount my penalty reps already logged (failed burpees don't clear debt)
            penaltyLogged = fetchedSets
                .filter { $0.userID == selfID && $0.isPenalty && !$0.isFailed }
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

    // MARK: - Soundboard & Reaction Actions

    /// Local 1-second gate covers both the local play AND the remote send so they stay
    /// perfectly in sync — if the gate blocks, we skip both without queuing.
    @MainActor
    private func tapSound(slug: String) async {
        let now = Date()
        guard now.timeIntervalSince(lastSoundTapAt) >= 1.0 else { return }
        lastSoundTapAt = now
        // Local play (immediately) + remote send (fire-and-forget).
        async let playTask: Void = SoundboardPlayer.shared.play(slug: slug)
        async let sendTask: Void = broadcastService.sendSound(
            sessionID: liveSession.id,
            groupID: liveSession.groupID,
            slug: slug
        )
        _ = await (playTask, sendTask)
    }

    /// Tap a reaction emoji — sends broadcast; own pill shows via onReaction callback.
    @MainActor
    private func tapReaction(emoji: String) async {
        // Show own pill immediately (don't wait for round-trip).
        Task { @MainActor in await showReactionOverlay(emoji) }
        await broadcastService.sendReaction(sessionID: liveSession.id, emoji: emoji)
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
            // PR check — same logic as solo WorkoutSessionView:
            // after a non-failed set with a positive weight, compare against prior best.
            // prior max MUST be captured before the insert (self-comparison bug)
            var isPR = false
            var priorBest: Decimal = 0
            if !isFailed, let weight, weight > 0 {
                let prior = try await priorMax(exerciseID: exerciseID,
                                               weight: weight, userID: userID)
                priorBest = prior
                isPR = weight > prior
            }

            try await SessionRepository.logSet(log)

            if isPR, let weight {
                let name = await ExerciseNameCache.name(for: exerciseID)
                Task { @MainActor in await showPROverlay(exerciseName: name) }
                // Best-effort PR record — a failed insert must never block turn advancement.
                Task { _ = try? await PersonalRecordRepository.record(
                    exerciseID: exerciseID,
                    weight: weight,
                    reps: reps ?? 0,
                    previousBest: priorBest,
                    sessionID: session.id
                ) }
            }

            try await SessionRepository.advanceTurn(sessionID: session.id)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Fetch the prior weight maximum for a given exercise (excluding failed/penalty sets).
    /// Mirrors the identical helper in WorkoutSessionView.
    private func priorMax(exerciseID: UUID, weight: Decimal, userID: UUID) async throws -> Decimal {
        let history = try await SessionRepository.exerciseHistory(userID: userID,
                                                                   exerciseID: exerciseID,
                                                                   limit: 200)
        return history
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { $0.weight }
            .max() ?? 0
    }

    /// Show the in-session PR overlay for 2.5 seconds, play ding locally (no broadcast).
    /// Uses Task.sleep — zero Timers.
    @MainActor
    private func showPROverlay(exerciseName: String) async {
        prOverlayExerciseName = exerciseName
        withAnimation(.easeOut(duration: 0.25)) { isPROverlay = true }
        Task { await SoundboardPlayer.shared.play(slug: "ding") }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation(.easeIn(duration: 0.25)) { isPROverlay = false }
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
            // penaltyLogged updates via the realtime echo (single source; reload() re-seeds)
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
