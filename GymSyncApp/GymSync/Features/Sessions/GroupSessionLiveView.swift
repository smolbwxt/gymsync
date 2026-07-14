import SwiftUI

// MARK: - GroupSessionLiveView
//
// Proof-matched design (p06 Live Spotlight / p07 Live Roster / p29 PR Celebration):
//   • Top bar: LIVE pulse + session name + elapsed timer + X (→ End Session confirmation)
//   • My-turn state ("Spotlight"): exercise-headline turn card (accent fill) + SET TIMER /
//     REST AFTER stat tiles + inline "LOG THIS SET" card (reps/weight steppers + RPE bar,
//     no sheet) + ROTATION strip (NOW/NEXT/3RD/4TH) — primary "Log Set & Pass" pinned to
//     the bottom action bar, NOT inside the card.
//   • Spectating state ("Roster"): "CURRENT LIFT" headline + round/set progress bar +
//     2-col roster grid (LIFTING NOW / UP NEXT / DONE / WAITING per participant) — bottom
//     bar shows a dashed "you're up next" style hint instead of a CTA.
//   • Chess clock: Text(_, style: .timer), state-driven from currentTurnStartedAt — never
//     a Swift Timer. Advance-turn flow (priorMax-before-logSet ordering, fire-and-forget
//     PR record, advanceTurn call) is UNCHANGED — only the caller moved from a sheet's
//     onLog closure to the inline card's commit action.
//   • Penalty banner (accent fill, unchanged): "YOU OWE N burpees" + Log burpees button
//     (still opens LogSetSheet — burpee logging is out of the proof's scope for this view).
//   • Set feed: reverse-chron rows, cap 30, penalty rows tagged (unchanged).
//   • Soundboard dock (unchanged, Task 3c): horizontally scrolling sound tiles (4 slugs)
//     + reaction pills (🔥💪😂👏), tapping plays locally + broadcasts.
//   • Reaction overlay: incoming reactions float up as emoji pills (2s, opacity + offset).
//   • Soundboard overlay: incoming sounds show transient "{username} 🔊 {name}" line.
//   • PR Celebration: full-screen, USER-DISMISSED moment (p29) — replaces the old
//     auto-dismissing toast. Share (ShareLink) + "Keep Lifting" dismiss.
//   • End Session: confirmation (via header X) → complete → HealthKit → SessionRecapView sheet

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
    /// Full (uncapped) session sets — powers rotation/roster derivations (last-set data,
    /// per-exercise set counts, round/progress math). `feedSets` stays capped at 30 for
    /// the feed UI; this mirrors the same fetch so no extra network calls are introduced.
    @State private var allSessionSets: [SetLog] = []
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

    @State private var showLogSetSheet      = false   // now penalty-only (see logSetSheetContent)
    @State private var showEndConfirmation  = false
    @State private var isEnding             = false
    @State private var errorText: String?
    /// Canvas Completion Task 4 fix round 1 (proof p31-errors, "Couldn't load
    /// the roster"): `reload()` previously swallowed participants/session
    /// fetch failures with only an `AppLogger` line — no UI signal at all.
    /// Set in `reload()`'s catch, cleared on success. Gates the `GSErrorCard`
    /// replacement for the roster/spotlight block below (see `body`).
    @State private var rosterLoadFailed     = false
    /// Canvas Completion Task 4 fix round 1 (proof p31-errors, "Set didn't
    /// save"): dedicated to `logSetAndAdvance`'s failure only — deliberately
    /// separate from the generic `errorText` above (which stays the small
    /// red caption for skipTurn/endSession/penalty-log failures, unchanged).
    /// Cleared optimistically at the start of every `logSetAndAdvance` call.
    @State private var logSetErrorText: String?
    @State private var recapData: RecapData?          // non-nil → sheet
    @State private var penaltyLogged        = 0       // reps logged this session as penalty by me
    /// Fetched lazily when this is a group session — backs the penalty
    /// banner's secondary "Crew ledger" link into BurpeeLedgerView (Canvas
    /// Completion Task 3). `nil` for ad-hoc/solo sessions (no groupID) and
    /// until the fetch completes.
    @State private var ledgerGroup: GymGroup?

    // MARK: - Inline "LOG THIS SET" card state (my-turn spotlight — replaces the old sheet)

    @State private var logReps: String = ""
    @State private var logWeight: String = ""
    @State private var logRPE: Double = 7.0
    @State private var logIsFailed = false
    @State private var logNote: String = ""
    /// In-flight guard for "Log Set & Pass" — prevents a double-tap from double-inserting
    /// the set and double-advancing the turn during the async commitInlineLog() round-trip.
    @State private var isLoggingSet = false

    // PR full-screen celebration (p29) — user-dismissed, no auto-timeout.
    @State private var isPROverlay          = false
    @State private var prOverlayExerciseName: String = ""
    @State private var prOverlayWeight: Decimal = 0
    @State private var prOverlayReps: Int = 0
    @State private var prOverlayPriorBest: Decimal = 0
    @State private var prOverlayMonthlyCount: Int? = nil

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

    // Canvas RPE labels — "Very easy" .. "Max effort" (mirrors LogSetSheet's scale so the
    // inline card and the (still-used, penalty-only) sheet read identically).
    private static let rpeLabels: [Double: String] = [
        1: "Very easy", 2: "Easy", 3: "Moderate", 4: "Somewhat hard",
        5: "Hard", 6: "Hard+", 7: "Very hard", 8: "Very hard+",
        9: "Very hard", 10: "Max effort"
    ]

    // MARK: - Helpers

    private var selfID: UUID? { appState.currentProfile?.id }
    private var isMyTurn: Bool { liveSession.currentTurnUserID == selfID }
    private var isOrganizer: Bool { liveSession.organizerID == selfID }

    // MARK: - Voice (Task 4 — PTT dock, Dossier §A.1's locked session-state scope)

    /// Mirrors `LobbyView`'s identical set — kept as a second literal copy
    /// rather than a shared constant since neither view currently has a
    /// common home for session-state helpers, and this codebase has no
    /// existing precedent of factoring session-state string sets out of
    /// individual views.
    private static let voiceEligibleStates: Set<String> = [
        "lobby_open", "editing", "voting", "locked", "in_progress"
    ]

    private var isVoiceEligible: Bool {
        Self.voiceEligibleStates.contains(liveSession.state)
    }

    @MainActor
    private func joinVoiceIfEligible() async {
        guard isVoiceEligible else { return }
        await VoiceRoomService.shared.join(sessionID: liveSession.id)
    }

    private var myParticipant: SessionParticipant? {
        participants.first(where: { $0.participant.userID == selfID })?.participant
    }

    /// Burpees remaining = owed - penalty reps already logged this session by me
    private var burpeesRemaining: Int {
        max(0, (myParticipant?.burpeesOwed ?? 0) - penaltyLogged)
    }

    // MARK: - Rotation / roster derivations
    //
    // "Current exercise" concept: this view has no per-lifter exercise-progression tracker
    // (a pre-existing gap — `currentExerciseForSheet` already just returned the first
    // routine exercise before this wave). We keep that exact behavior and reuse it as the
    // single "current exercise" for the spotlight headline, the rotation math, and the
    // roster grid, so the displayed exercise always matches what "Log Set & Pass" will
    // actually log. Multi-exercise progression during a live session remains out of scope.

    private enum RosterStatus { case lifting, upNext, done, waiting }

    /// Participants ordered by `turn_order` (nil last), stable by username.
    private var rotationOrder: [(participant: SessionParticipant, profile: Profile)] {
        participants.sorted { lhs, rhs in
            let l = lhs.participant.turnOrder ?? Int.max
            let r = rhs.participant.turnOrder ?? Int.max
            if l != r { return l < r }
            return lhs.profile.username < rhs.profile.username
        }
    }

    private var currentTurnIndex: Int? {
        guard let turnID = liveSession.currentTurnUserID else { return nil }
        return rotationOrder.firstIndex(where: { $0.participant.userID == turnID })
    }

    private var nextTurnUserID: UUID? {
        guard let idx = currentTurnIndex else { return nil }
        let n = rotationOrder.count
        guard n > 1 else { return nil }
        return rotationOrder[(idx + 1) % n].participant.userID
    }

    /// Ordered rotation tiles starting at the current lifter, wrapping circularly.
    private var rotationTiles: [(profile: Profile, userID: UUID, label: String)] {
        guard let idx = currentTurnIndex else { return [] }
        let n = rotationOrder.count
        guard n > 0 else { return [] }
        return (0..<n).map { offset in
            let item = rotationOrder[(idx + offset) % n]
            return (profile: item.profile, userID: item.participant.userID, label: rotationLabel(offset))
        }
    }

    private func rotationLabel(_ offset: Int) -> String {
        switch offset {
        case 0:  return "NOW"
        case 1:  return "NEXT"
        default: return ordinal(offset + 1).uppercased()
        }
    }

    private func setCount(userID: UUID, exerciseID: UUID) -> Int {
        allSessionSets.filter { $0.userID == userID && $0.exerciseID == exerciseID && !$0.isPenalty }.count
    }

    private var currentRoutineExercise: RoutineExercise? {
        guard let ex = currentExerciseForSheet else { return nil }
        return routineExercises.first(where: { $0.exerciseID == ex.id })
    }

    private var targetSetsPerLifter: Int { currentRoutineExercise?.targetSets ?? 1 }

    /// The set number about to be logged by whoever currently holds the turn — doubles as
    /// the "Round N" figure on the roster header (one set per lifter per round).
    private var currentTurnSetNumber: Int {
        guard let turnID = liveSession.currentTurnUserID, let ex = currentExerciseForSheet else { return 1 }
        return setCount(userID: turnID, exerciseID: ex.id) + 1
    }

    private var totalLoggedForCurrentExercise: Int {
        guard let ex = currentExerciseForSheet else { return 0 }
        return allSessionSets.filter { $0.exerciseID == ex.id && !$0.isPenalty }.count
    }

    private var totalExpectedForCurrentExercise: Int {
        max(1, targetSetsPerLifter * max(participants.count, 1))
    }

    private var currentExerciseTargetText: String? {
        guard let re = currentRoutineExercise, re.targetReps != nil || re.targetWeight != nil else { return nil }
        return "target \(re.targetWeight ?? "—") × \(re.targetReps ?? "—")"
    }

    private func rosterStatus(for userID: UUID) -> RosterStatus {
        if userID == liveSession.currentTurnUserID { return .lifting }
        if userID == nextTurnUserID { return .upNext }
        if hasLoggedCurrentExercise(userID) { return .done }
        return .waiting
    }

    private func hasLoggedCurrentExercise(_ userID: UUID) -> Bool {
        guard let ex = currentExerciseForSheet else { return false }
        return allSessionSets.contains { $0.userID == userID && $0.exerciseID == ex.id && !$0.isPenalty }
    }

    private func lastSetForCurrentExercise(_ userID: UUID) -> SetLog? {
        guard let ex = currentExerciseForSheet else { return nil }
        return allSessionSets
            .filter { $0.userID == userID && $0.exerciseID == ex.id && !$0.isPenalty }
            .max(by: { $0.loggedAt < $1.loggedAt })
    }

    private func lastSetAnyExercise(_ userID: UUID) -> SetLog? {
        allSessionSets
            .filter { $0.userID == userID && !$0.isPenalty }
            .max(by: { $0.loggedAt < $1.loggedAt })
    }

    /// Bottom-bar hint for spectators — "you're up next" or how many lifters are ahead.
    /// Deliberately does NOT fabricate an ETA (the proof's "~2 min" isn't backed by any
    /// duration data we track) — see visual-sweep-B p06/p07 findings.
    private var upcomingTurnHint: String? {
        guard let selfID, liveSession.currentTurnUserID != nil else { return nil }
        if nextTurnUserID == selfID { return "You're up next" }
        guard let idx = currentTurnIndex,
              let myIdx = rotationOrder.firstIndex(where: { $0.participant.userID == selfID }) else { return nil }
        let n = rotationOrder.count
        guard n > 0 else { return nil }
        let aheadCount = ((myIdx - idx) + n) % n
        guard aheadCount > 0 else { return nil }
        return "Waiting your turn — \(aheadCount) lifter\(aheadCount == 1 ? "" : "s") ahead"
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11...13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func decimalString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    private func rpeLabel(_ rpe: Double) -> String {
        Self.rpeLabels[rpe] ?? ""
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

                    // ── SPOTLIGHT (my turn) / ROSTER (spectating) ───────────
                    // Canvas Completion Task 4 fix round 1 (proof p31-errors,
                    // "Couldn't load the roster"): when the participants fetch
                    // has actually failed AND left the list blank, show the
                    // error card in place of both the spotlight and spectating
                    // blocks — both derive rotation/roster state from
                    // `participants`, so a blank list means neither block has
                    // anything real to show anyway (stale/placeholder text at
                    // best). A transient refresh failure that leaves an
                    // already-populated `participants` list intact never
                    // triggers this (matches the same best-effort contract as
                    // `GSErrorCard`'s other call sites).
                    if participants.isEmpty && rosterLoadFailed {
                        GSErrorCard(
                            title: "Couldn't load the roster",
                            message: "Check your connection. Your workout keeps logging locally.",
                            retry: { Task { await reload() } }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    } else if isMyTurn {
                        VStack(alignment: .leading, spacing: 12) {
                            spotlightHeaderCard
                            statTimerRow
                            logThisSetCard
                            if let logSetErrorText {
                                GSInlineErrorBanner(
                                    title: "Set didn't save.",
                                    message: "Check your connection, then try again — your reps are still filled in above.",
                                    retry: { commitInlineLog() }
                                )
                            }
                            if !rotationTiles.isEmpty {
                                rotationStrip
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            spectatingHeaderCard
                            if !rotationOrder.isEmpty {
                                rosterGrid
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }

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

            // ── PR CELEBRATION (full-screen, user-dismissed — p29) ─────────
            if isPROverlay {
                prCelebrationOverlay
                    .transition(.opacity)
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
        // Pushed via LobbyView → SessionInProgressView; the soundboard dock +
        // bottom action bar below are bottom-pinned — see GSComponents.swift's
        // GSHidesDock for why the custom app dock can't reach them via
        // safeAreaInset alone.
        .gsHidesDock()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // ── VOICE DEGRADED BANNER ────────────────────────────────
                // "Inserted above the dock" per Dossier §A.2's live-session
                // unavailable frame — above the whole sticky composition
                // (soundboard + PTT + action bar), matching that frame's
                // literal ordering.
                if isVoiceEligible, case .unavailable = VoiceRoomService.shared.state {
                    GSVoiceUnavailableBanner(retry: {
                        Task { await VoiceRoomService.shared.retry() }
                    })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.bg)
                }
                // ── SOUNDBOARD DOCK ──────────────────────────────────────
                soundboardDock
                // ── PUSH-TO-TALK DOCK ────────────────────────────────────
                // Dossier §A.2 confirms the exact insertion point: between
                // the HYPE strip and the bottom action bar.
                if isVoiceEligible {
                    PTTDockRow()
                }
                // ── BOTTOM ACTION BAR ────────────────────────────────────
                // My turn → pinned "Log Set & Pass" CTA (per proof, lives OUTSIDE the
                // spotlight card). Spectating → dashed rotation hint, no CTA.
                // (End Session moved off this bar — the header X already triggers the
                // same confirmation; the proof's live screens never show a second
                // "End Session" affordance alongside the primary action.)
                bottomActionBar
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
        // Log Set sheet — penalty (burpee) logging only now; normal sets log inline.
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
        .onChange(of: liveSession.currentTurnUserID) { _, newValue in
            if newValue == selfID { prefillLogInputs() }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await reload()
                await subscribeBroadcast()
                // Idle-ladder activity heartbeat (push-dossier.md §A.4) —
                // one call per foreground transition, no timer. Best-effort:
                // a failed heartbeat must never disrupt the live session UI.
                try? await SessionRepository.touchActivity(sessionID: liveSession.id)
            }
        }
        .onAppear {
            // Suppresses the push banner for this same session while it's
            // open live (AppDelegate.willPresent, AppState.activeSessionID).
            appState.activeSessionID = liveSession.id
        }
        .onDisappear {
            // Only clear the suppression flag if it's still pointing at THIS
            // session — a second GroupSessionLiveView push (or a fast
            // navigate-away-and-back) could have already overwritten it with
            // a different session's id by the time this onDisappear fires,
            // and clearing unconditionally would un-suppress banners for
            // whichever session is now actually live.
            if appState.activeSessionID == session.id {
                appState.activeSessionID = nil
            }
            Task {
                await liveService.unsubscribe()
                await broadcastService.unsubscribe()
                // Unconditional, mirroring the two unsubscribes above — this
                // is the top of the voice-eligible flow (no further "more
                // live" view to hand the room off to, unlike LobbyView's
                // guarded leave() for its Lobby -> live-session transition),
                // so every disappearance here is a genuine "stop talking"
                // moment (session ended, backed out, or a child pushed on
                // top — the latter already re-subscribes everything else on
                // return via this same `.task`, so voice re-joining too is
                // consistent, not a new blip class introduced here).
                await VoiceRoomService.shared.leave()
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
    // (X → end-session confirmation; this is the proof's only end-session affordance
    // on the live screens, so the old separately-pinned "End Session" bar was removed).

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

            // "Connecting voice…" pill — Dossier §A.2: "header shows the
            // same connecting pill as the lobby frame."
            if case .connecting = VoiceRoomService.shared.state {
                GSConnectingVoicePill()
            }

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

    // MARK: - Spotlight header card (my turn) — p06
    // Exercise-name headline (not the lifter's name — per finding p06 #1), "Set N of M ·
    // target W × R" subtitle. BPM/waveform decorations from the proof are skipped: no
    // heart-rate data source exists anywhere in the app (canvas chrome, not real data).

    private var spotlightHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR TURN")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(currentExerciseForSheet?.name ?? "Exercise")
                .font(GSFont.heading(26, relativeTo: .title))
                .foregroundStyle(theme.bg)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text("Set \(currentTurnSetNumber) of \(targetSetsPerLifter)")
                if let targetText = currentExerciseTargetText {
                    Text("· \(targetText)")
                }
            }
            .font(GSFont.body(13, relativeTo: .subheadline))
            .foregroundStyle(theme.bg.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    // MARK: - Stat timer row (SET TIMER / REST AFTER) — p06
    // SET TIMER is the live chess clock (state-driven from currentTurnStartedAt).
    // REST AFTER shows the routine's configured rest duration for this exercise — a
    // static value, not a running countdown (no rest-phase-active state exists in the
    // data model; adding one is a behavior change out of scope for this layout wave).

    private var statTimerRow: some View {
        HStack(spacing: 10) {
            statTile(kicker: "SET TIMER") {
                if let ts = liveSession.currentTurnStartedAt {
                    Text(ts, style: .timer)
                        .font(.custom("Archivo-Bold", size: 26).monospacedDigit())
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.custom("Archivo-Bold", size: 26))
                        .foregroundStyle(theme.neutral500)
                }
            }
            statTile(kicker: "REST AFTER") {
                Text(restAfterText)
                    .font(.custom("Archivo-Bold", size: 26).monospacedDigit())
                    .foregroundStyle(theme.text)
            }
        }
    }

    private var restAfterText: String {
        let seconds = currentRoutineExercise?.restSeconds ?? 120
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func statTile<Content: View>(kicker: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral500)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Inline "LOG THIS SET" card — p06
    // Replaces the modal LogSetSheet for normal (non-penalty) set logging so logging
    // happens without leaving the screen, per finding p06 #3. The proof only shows
    // reps/weight steppers + an RPE scale; a compact "Failed set" toggle + optional note
    // field are kept (smaller, secondary) so the fail/note capability the old sheet
    // offered isn't silently dropped.

    private var logThisSetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOG THIS SET")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)

            HStack(spacing: 10) {
                stepperCell(
                    theme: theme,
                    label: "Reps",
                    value: $logReps,
                    borderColor: theme.divider,
                    valueColor: theme.text,
                    keyboard: .numberPad,
                    onDecrement: { decrementInt(&logReps) },
                    onIncrement: { incrementInt(&logReps) }
                )
                stepperCell(
                    theme: theme,
                    label: "Weight (\(currentExerciseForSheet?.defaultUnit ?? "lbs"))",
                    value: $logWeight,
                    borderColor: theme.accent,
                    valueColor: theme.accent700,
                    keyboard: .decimalPad,
                    onDecrement: { decrementDecimal(&logWeight) },
                    onIncrement: { incrementDecimal(&logWeight) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RPE · effort")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Text("\(Int(logRPE)) · \(rpeLabel(logRPE))")
                        .font(GSFont.heading(12, relativeTo: .caption))
                        .foregroundStyle(theme.accent700)
                }
                RPESegmentBar(value: $logRPE, theme: theme)
            }

            HStack {
                Toggle(isOn: $logIsFailed) {
                    Text("Failed set")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                .toggleStyle(.switch)
                .tint(theme.accent)
            }
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("NOTE")
                    .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(theme.neutral500)
                TextField("Anything to remember?", text: $logNote, axis: .vertical)
                    .lineLimit(1...2)
                    .font(GSFont.body(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // Reps/weight stepper cell and its arithmetic helpers now live in LogSetSheet.swift
    // (shared, internal — see `stepperCell`, `decrementInt`/`incrementInt`/
    // `decrementDecimal`/`incrementDecimal`) so this view no longer duplicates them.

    // MARK: - Rotation strip (my turn) — p06 "NOW / NEXT / 3RD / 4TH" tiles

    private var rotationStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROTATION")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)

            HStack(spacing: 6) {
                ForEach(rotationTiles, id: \.userID) { tile in
                    let isNow = tile.label == "NOW"
                    // Speaking ring (Task 4) — see `rosterCard`'s comment on
                    // why only the "talking" sub-state is derivable here.
                    let isSpeaking = VoiceRoomService.shared.speakingParticipantIDs
                        .contains(tile.userID.uuidString.lowercased())
                    VStack(spacing: 4) {
                        Text(tile.label)
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(isNow ? theme.bg.opacity(0.85) : theme.neutral500)
                        Text(tile.userID == selfID ? "You" : tile.profile.username)
                            .font(GSFont.bold(13, relativeTo: .body))
                            .foregroundStyle(isNow ? theme.bg : theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isNow ? theme.accent : theme.surface)
                    .overlay(Rectangle().strokeBorder(
                        isSpeaking ? theme.accent700 : (isNow ? Color.clear : theme.divider),
                        lineWidth: isSpeaking ? 2 : 1))
                }
            }
        }
    }

    // MARK: - Spectating header card ("CURRENT LIFT") — p07

    private var spectatingHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT LIFT")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)

            HStack(alignment: .firstTextBaseline) {
                Text(currentExerciseForSheet?.name ?? "Exercise")
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Round \(currentTurnSetNumber)")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Text("Set \(totalLoggedForCurrentExercise) / \(totalExpectedForCurrentExercise)")
                        .font(GSFont.bodyMedium(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
            }

            progressSegments

            if isOrganizer && liveSession.currentTurnUserID != nil {
                Button {
                    Task { await skipTurn() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "forward.end")
                            .font(.system(size: 11))
                        Text("Skip turn")
                            .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    }
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private var progressSegments: some View {
        let total = max(totalExpectedForCurrentExercise, 1)
        let filled = min(totalLoggedForCurrentExercise, total)
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? theme.accent : theme.neutral400)
                    .frame(height: 5)
            }
        }
    }

    // MARK: - Roster grid (spectating) — p07 2×2 status cards
    // "JORDAN IS LOGGING" live-typing preview from the proof is skipped: it would require
    // broadcasting in-progress form input, which doesn't exist anywhere in the realtime
    // model (documented per instructions to skip anything requiring absent data).

    private var rosterGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(rotationOrder, id: \.participant.userID) { item in
                rosterCard(item)
            }
        }
    }

    @ViewBuilder
    private func rosterCard(_ item: (participant: SessionParticipant, profile: Profile)) -> some View {
        let status = rosterStatus(for: item.participant.userID)
        let isLifting = status == .lifting
        // Speaking ring (Task 4, Dossier §A.2's lobby-strip "talking" state,
        // reused here for the live-session roster grid). `VoiceRoomService`
        // exposes only WHO is currently speaking, not a full roster of who
        // else has joined the room — so "listening"/"muted" for other
        // participants isn't derivable here either (same honest limitation
        // as `LobbyView.participantRow`); only the "talking" ring is real.
        let isSpeaking = VoiceRoomService.shared.speakingParticipantIDs
            .contains(item.participant.userID.uuidString.lowercased())

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(rosterStatusLabel(status))
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(isLifting ? theme.bg.opacity(0.85) : theme.neutral500)
                if status == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accent700)
                }
                if isSpeaking {
                    GSTalkingBars(color: isLifting ? theme.bg : theme.accent700, barWidth: 2, maxHeight: 9)
                    Text("talking")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .foregroundStyle(isLifting ? theme.bg.opacity(0.85) : theme.accent700)
                }
            }

            HStack(spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(isLifting ? theme.bg.opacity(0.25) : theme.neutral400)
                        .frame(width: 26, height: 26)
                    Text(String(item.profile.username.prefix(2)).uppercased())
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(isLifting ? theme.bg : theme.text)
                }
                // Avatar glow while talking — blessed frames' solid 3px
                // accent-30% spread (live-voice frame 2's audible-now rows);
                // bg-tinted on the accent-filled lifting card so it stays
                // visible against the accent fill.
                .background {
                    if isSpeaking {
                        Rectangle()
                            .fill((isLifting ? theme.bg : theme.accent).opacity(0.3))
                            .frame(width: 32, height: 32)
                    }
                }
                Text(item.participant.userID == selfID ? "You" : item.profile.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(isLifting ? theme.bg : theme.text)
                    .lineLimit(1)
            }

            rosterCardDetail(item.participant.userID, status: status)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(isLifting ? theme.accent : theme.surface)
        .overlay(Rectangle().strokeBorder(
            isSpeaking ? theme.accent700 : (isLifting ? Color.clear : theme.divider),
            lineWidth: isSpeaking ? 2 : 1))
    }

    private func rosterStatusLabel(_ status: RosterStatus) -> String {
        switch status {
        case .lifting: return "LIFTING NOW"
        case .upNext:  return "UP NEXT"
        case .done:    return "DONE"
        case .waiting: return "WAITING"
        }
    }

    @ViewBuilder
    private func rosterCardDetail(_ userID: UUID, status: RosterStatus) -> some View {
        switch status {
        case .lifting:
            if let re = currentRoutineExercise {
                Text("Set \(setCount(userID: userID, exerciseID: currentExerciseForSheet?.id ?? UUID()) + 1) · target \(re.targetWeight ?? "—") × \(re.targetReps ?? "—")")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
        case .upNext:
            if let last = lastSetAnyExercise(userID) {
                Text("Last set")
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                Text("\(last.weight.map(decimalString) ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
                    .font(GSFont.bodyMedium(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
            } else {
                Text("Get ready")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
        case .done:
            if let last = lastSetForCurrentExercise(userID) {
                Text("\(last.weight.map(decimalString) ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
                    .font(GSFont.bodyMedium(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                if let rpe = last.rpe {
                    Text("RPE \(decimalString(rpe))")
                        .font(GSFont.body(10, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                }
            }
        case .waiting:
            if let re = currentRoutineExercise, re.targetWeight != nil || re.targetReps != nil {
                Text("Target \(re.targetWeight ?? "—") × \(re.targetReps ?? "—")")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                Text("Waiting")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    // MARK: - Bottom action bar
    // My turn → pinned primary CTA (commits the inline card's state via logSetAndAdvance,
    // UNCHANGED order of operations). Spectating → dashed rotation hint, no CTA (matches
    // p07's "You're up next — ~2 min" treatment, minus the fabricated ETA — see
    // `upcomingTurnHint`).

    @ViewBuilder
    private var bottomActionBar: some View {
        if isMyTurn {
            Button {
                commitInlineLog()
            } label: {
                HStack {
                    if isLoggingSet {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.bg)
                        Text("Logging…")
                            .font(GSFont.bold(16, relativeTo: .body))
                        Spacer()
                    } else {
                        Text("Log Set & Pass")
                            .font(GSFont.bold(16, relativeTo: .body))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoggingSet || (Int(logReps) == nil && !logIsFailed))
            .background(theme.bg)
        } else if let hint = upcomingTurnHint {
            Text(hint)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(Rectangle().strokeBorder(theme.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.bg)
        }
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

            // Secondary entry into the group-wide Burpee Ledger (Canvas
            // Completion Task 3, proof p25) — only for group sessions;
            // ad-hoc/solo sessions have no group-scoped ledger to show.
            if let ledgerGroup {
                NavigationLink {
                    BurpeeLedgerView(group: ledgerGroup)
                } label: {
                    HStack(spacing: 4) {
                        Text("Crew ledger")
                            .font(GSFont.bodyMedium(12, relativeTo: .caption))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.bg.opacity(0.85))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
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

    // MARK: - PR celebration overlay (full-screen, user-dismissed) — p29

    private var prCelebrationOverlay: some View {
        ZStack {
            theme.accent.ignoresSafeArea()

            // Concentric target-ring background (canvas chrome, approximated with two
            // static strokes — no animation/particle system exists in this app).
            ZStack {
                Circle().stroke(theme.bg.opacity(0.22), lineWidth: 1).frame(width: 340, height: 340)
                Circle().stroke(theme.bg.opacity(0.32), lineWidth: 1).frame(width: 230, height: 230)
            }

            VStack(spacing: 16) {
                Spacer()

                Text("🔥")
                    .font(.system(size: 44))

                Text("NEW PERSONAL RECORD")
                    .font(GSFont.bold(13, relativeTo: .caption))
                    .tracking(3.0)
                    .foregroundStyle(theme.bg.opacity(0.9))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(decimalString(prOverlayWeight))
                        .font(.custom("Archivo-Bold", size: 56))
                        .foregroundStyle(theme.bg)
                    Text("lbs")
                        .font(GSFont.bold(18, relativeTo: .title3))
                        .foregroundStyle(theme.bg.opacity(0.85))
                }

                Text("\(prOverlayExerciseName) × \(prOverlayReps)")
                    .font(GSFont.heading(20, relativeTo: .title3))
                    .foregroundStyle(theme.bg)
                    .multilineTextAlignment(.center)

                Text("▲ Beat your best by \(decimalString(prOverlayWeight - prOverlayPriorBest)) lbs")
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.bg.opacity(0.9))

                if let count = prOverlayMonthlyCount, count > 0 {
                    Text("🏆 \(ordinal(count)) PR this month")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.bg.opacity(0.18))
                }

                Spacer()

                HStack(spacing: 10) {
                    ShareLink(item: prShareText) {
                        Text("Share")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .overlay(Rectangle().strokeBorder(theme.bg.opacity(0.6), lineWidth: 1))

                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { isPROverlay = false }
                    } label: {
                        Text("Keep Lifting")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .background(theme.bg)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
    }

    private var prShareText: String {
        "New PR! \(prOverlayExerciseName) — \(decimalString(prOverlayWeight)) lbs × \(prOverlayReps) on GymSync."
    }

    // MARK: - LogSetSheet content (penalty / burpee logging only — normal sets log inline)

    @ViewBuilder
    private var logSetSheetContent: some View {
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

    /// Reset the inline log card to fresh defaults — called whenever it becomes my turn.
    @MainActor
    private func prefillLogInputs() {
        guard let ex = currentExerciseForSheet else { return }
        logReps = defaultReps(for: ex.id) ?? ""
        logWeight = ""
        logRPE = 7.0
        logIsFailed = false
        logNote = ""
    }

    /// Commit the inline "LOG THIS SET" card — delegates to `logSetAndAdvance` UNCHANGED
    /// (same priorMax-before-insert ordering, same PR pipeline, same advanceTurn call).
    /// Only the caller changed (was a sheet's onLog closure).
    ///
    /// `isLoggingSet` guards against re-entrancy: the CTA stays tappable for the whole
    /// async round-trip otherwise, and a double-tap would double-insert the set and
    /// double-advance the turn. Set true here (before any await), cleared via `defer`
    /// once `logSetAndAdvance` returns — on every path, since that function already
    /// catches its own errors internally and never rethrows.
    private func commitInlineLog() {
        guard !isLoggingSet else { return }
        guard let ex = currentExerciseForSheet else { return }
        isLoggingSet = true
        let reps = Int(logReps)
        let weight = Decimal(string: logWeight)
        let rpe = Decimal(logRPE)
        let note = logNote.isEmpty ? nil : logNote
        let failed = logIsFailed
        Task {
            defer { isLoggingSet = false }
            await logSetAndAdvance(reps: reps, weight: weight, rpe: rpe,
                                    isFailed: failed, note: note, exerciseID: ex.id)
        }
    }

    // MARK: - Data loading

    @MainActor
    private func openAndSubscribe() async {
        await reload()
        await ExerciseNameCache.preload()
        if let groupID = liveSession.groupID {
            ledgerGroup = try? await GroupRepository.fetch(id: groupID)
        }
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
                // Mirror into the uncapped set list that powers rotation/roster derivations.
                allSessionSets.append(log)
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
        if isMyTurn { prefillLogInputs() }
        // Initial heartbeat — the scenePhase→active heartbeat above only
        // fires on a later transition, so this covers "already foreground,
        // just opened the session" (push-dossier.md §A.4).
        try? await SessionRepository.touchActivity(sessionID: liveSession.id)
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
            rosterLoadFailed = false
            participants = fetchedParts
            if let s = fetchedSession { liveSession = s }

            // Build feed: newest first, cap 30
            feedSets = Array(fetchedSets.reversed().prefix(30))
            // Uncapped mirror — powers rotation/roster derivations.
            allSessionSets = fetchedSets

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
            rosterLoadFailed = true
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

        // Auto-join voice once `liveSession` reflects the latest state
        // (Task 4) — no-ops once already connecting/connected, so it's safe
        // to call from every reload(), not just the first (`openAndSubscribe`
        // calls this at its very start, and the scenePhase→active handler
        // calls it again on every foreground transition).
        await joinVoiceIfEligible()
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
        // Canvas Completion Task 4 fix round 1: clear optimistically at the
        // start of every attempt (mirrors `endSession()`'s `errorText = nil`
        // convention) so a retry that succeeds drops the banner immediately,
        // and a retry that fails re-sets it fresh below.
        logSetErrorText = nil
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
                let repsForOverlay = reps ?? 0
                Task { @MainActor in
                    await showPROverlay(exerciseName: name, weight: weight,
                                         reps: repsForOverlay, priorBest: priorBest)
                }
                // Ordered PR pipeline: record insert → monthly count → badge update, as ONE
                // detached task so `countSince` can never race the insert it depends on
                // (previously two unordered tasks — the badge could undercount by 1). Still
                // off the turn-critical path: advanceTurn below does not await this task.
                Task { @MainActor in
                    _ = try? await PersonalRecordRepository.record(
                        exerciseID: exerciseID,
                        weight: weight,
                        reps: repsForOverlay,
                        previousBest: priorBest,
                        sessionID: session.id
                    )
                    let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
                    prOverlayMonthlyCount = try? await PersonalRecordRepository.countSince(
                        userID: userID, date: startOfMonth)
                }
            }

            try await SessionRepository.advanceTurn(sessionID: session.id)
        } catch let error as GymSyncError {
            // Upgraded treatment (Canvas Completion Task 4 fix round 1, proof
            // p31-errors) — NOT the shared `errorText` red caption; see
            // `logSetErrorText`'s declaration + the `GSInlineErrorBanner`
            // wiring in `body`.
            logSetErrorText = error.errorDescription
        } catch {
            logSetErrorText = error.localizedDescription
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

    /// Show the full-screen, USER-DISMISSED PR celebration (p29) — no auto-timeout.
    /// The overlay presents immediately with no monthly badge; the ordered PR pipeline in
    /// `logSetAndAdvance` populates `prOverlayMonthlyCount` once its record insert →
    /// countSince chain resolves, so the badge appears when the count is actually correct.
    @MainActor
    private func showPROverlay(exerciseName: String, weight: Decimal, reps: Int, priorBest: Decimal) async {
        prOverlayExerciseName = exerciseName
        prOverlayWeight = weight
        prOverlayReps = reps
        prOverlayPriorBest = priorBest
        prOverlayMonthlyCount = nil
        withAnimation(.easeOut(duration: 0.25)) { isPROverlay = true }
        Task { await SoundboardPlayer.shared.play(slug: "ding") }
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
