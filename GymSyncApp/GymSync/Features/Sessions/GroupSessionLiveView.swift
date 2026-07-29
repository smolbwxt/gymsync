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
//   • Soundboard dock — favorites ribbon (Content Curation Task 3): "YOUR SOUNDS"
//     kicker + Edit row, up to 4 favorite tiles (or the first 4 curated catalog
//     sounds until favorites are chosen) + dashed "All" tile, both opening
//     SoundLibrarySheet; tapping a tile plays locally + broadcasts (unchanged
//     send path). Reaction pills (🔥💪😂👏) unchanged, below the ribbon.
//   • Reaction overlay: incoming reactions float up as emoji pills (2s, opacity + offset).
//   • Soundboard overlay: incoming sounds show transient "{username} 🔊 {name}" line.
//   • PR Celebration: full-screen, USER-DISMISSED moment (p29) — replaces the old
//     auto-dismissing toast. Share (ShareLink) + "Keep Lifting" dismiss.
//   • End Session: confirmation (via header X) → complete → HealthKit → SessionRecapView sheet

struct GroupSessionLiveView: View {
    let session: WorkoutSession

    /// True only when this view was reached via LobbyView ->
    /// `SessionInProgressView` (the Lobby<->Live push/pop pair for the SAME
    /// session) — false for every other route, currently `BurpeeLedgerView`'s
    /// direct `NavigationLink` (Phase O Task 5, 3e follow-up queue item 6,
    /// "Lobby<->Live back-nav rejoin blip"). See `onDisappear`'s doc comment
    /// below for what this actually guards.
    let voicePersistsOnPop: Bool

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
    /// Phase W Task 5 (watch-hr design §4) — separate `HeartRateBroadcastService`
    /// instance from `WatchConnectivityBridge`'s own send-only one (see that
    /// type's own doc comment on `heartRateBroadcast`); THIS instance is for
    /// SUBSCRIBING/rendering, mirroring how `broadcastService` above is this
    /// view's own subscribe-side `SessionBroadcastService` instance while
    /// `WatchConnectivityBridge` holds a separate send-only one via
    /// `LiveSoundboardBroadcasting`.
    @State private var heartRateService = HeartRateBroadcastService()
    /// Live HR readings keyed by participant userID — includes the CURRENT
    /// (self) user, since `heartRateService.subscribe`'s self-echo delivers
    /// this phone's own published samples back through the same callback
    /// (see that method's own doc comment). Consumed by `heartRateFor(_:)`
    /// below, which both `rosterCard` (frame 2B) and `spotlightHeaderCard`
    /// (frame 2A, self only) read from.
    @State private var heartRates: [UUID: (bpm: Int, zone: HeartRateZone?, receivedAt: Date)] = [:]
    /// One self-clearing `Task` per userID (task-5-brief.md item 4:
    /// "pills fade/remove when no sample for >15s (sender may stop
    /// anytime)") — same "sleep, then clear if nothing newer arrived"
    /// shape this file's own `showSoundOverlay`/`showReactionOverlay`
    /// already use for their own transient overlay state, just keyed per
    /// user instead of a single shared property. Purely a memory-hygiene +
    /// re-render trigger: `heartRateFor(_:)` is the AUTHORITATIVE
    /// freshness check (`HeartRateFreshness.isFresh`, hermetically tested)
    /// — a delayed or cancelled purge can never cause a stale reading to
    /// render, only a slightly-late removal from this dictionary.
    @State private var heartRateExpiryTasks: [UUID: Task<Void, Never>] = [:]
    private static let heartRateStaleAfter: TimeInterval = 15
    /// Full sound catalog (Task 3 — favorites ribbon + library sheet), populated
    /// async on first appear. Failures degrade to an empty catalog silently —
    /// `dockSounds` below falls back to the curated-first-4 behavior either way.
    @State private var soundCatalog: [SoundboardSound] = []
    /// User's chosen favorite slugs (ordered, max 4), populated async on first
    /// appear from `SoundboardFavoritesRepository.get()`. Empty until chosen.
    @State private var soundFavorites: [String] = []
    /// Presents `SoundLibrarySheet` — both the dock's "Edit" and "All" affordances
    /// open the same sheet.
    @State private var showSoundLibrary = false
    /// 1-second local gate: prevents double-fire and keeps local + remote in sync.
    @State private var lastSoundTapAt: Date = .distantPast
    /// Transient incoming-sound overlay: "{username} 🔊 {name}" — cleared after 2.5s.
    @State private var soundOverlayText: String? = nil
    /// Transient floating reaction pill — cleared after 2s.
    @State private var reactionOverlay: String? = nil
    @State private var reactionOverlayVisible = false
    /// Task 5 (watch-hr design §4) — REMOVED (was: `@State private var
    /// shareHeartRate = false`, populated once from `UserSettingsRepository
    /// .get()` in `openAndSubscribe()`). That one-shot cache was the exact
    /// bug T4's review carried in: a mid-session toggle flip in `YouTabView`
    /// never reached an already-open `GroupSessionLiveView` (this app's
    /// `TabView` keeps a pushed session view alive across tab switches — it
    /// isn't torn down and re-`.task`-ed just by navigating to the You tab
    /// and back). Fixed by DERIVING the value live from `ThemeStore.shared
    /// .shareHeartRate` at every `pushWatchSessionState()` call instead of
    /// caching a local copy once — the same "derive from observed state,
    /// don't cache a snapshot" fix T3's `isActive` finding already
    /// established for this exact function (see `pushWatchSessionState`'s
    /// own doc comment on that precedent). `ThemeStore` is already this
    /// app's one cross-view `@Observable` cache of the live `user_settings`
    /// row (`DesignSystem/ThemeStore.swift`'s own Task 5 extension) and
    /// `YouTabView.setShareHeartRate`'s success path already calls
    /// `ThemeStore.shared.noteExternalSettingsWrite(updated)` — that call
    /// site needed NO changes; only `ThemeStore` itself (new `shareHeartRate`
    /// property) and this view's read site changed.
    ///
    /// Heart-rate roster/pill state (Task 5) lives further down, near
    /// `broadcastService` — see `heartRateService`/`heartRates` below.

    // MARK: - Routine state

    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var routineName: String? = nil

    // MARK: - UI flags

    @State private var showLogSetSheet      = false   // now penalty-only (see logSetSheetContent)
    @State private var showEndConfirmation  = false
    /// Task 3, Phase F — no canvas frame depicts a chat affordance on either
    /// live-session layout (proof-frame-06/07's headers show only LIVE +
    /// routine name + timer + X). System-designed: a bordered icon-button in
    /// `headerBar`, styled after the same header's own X button, opening a
    /// sheet — see docs/design/accepted-deviations.json's "session-chat"
    /// entry.
    @State private var showChatSheet        = false
    /// "Load the bar" expand/collapse for the inline `barLoaderCard` (user
    /// direction 2026-07-28: a widget like the solo session's, not a header
    /// button). The card renders in BOTH the my-turn and spectating branches
    /// — your next weight is yours to plan while someone else lifts.
    @State private var showBarLoader        = false
    @State private var isEnding             = false
    @State private var errorText: String?
    // Phase O Task 5 item 5 — mirrors LobbyView's identical trio (this
    // view's own `voicePersistsOnPop` doc comment already notes it's not
    // the only route in: `BurpeeLedgerView`'s direct push means voice can
    // first connect here without ever having shown Lobby's copies).
    @State private var showVoiceConnectedToast = false
    @State private var showVoiceCoachMark = false
    @State private var showVoiceMixerSheet = false
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
    /// Phase O Task 3 fix wave 1 (reviewer Finding 1): set when the most
    /// recent `logSetAndAdvance` attempt queued its set offline (rather than
    /// hitting a real, retryable failure) — drives the calmer, non-retry
    /// `GSInlineNoticeBanner` in `body` instead of `GSInlineErrorBanner`.
    /// Deliberately separate from `logSetErrorText`: the two states are
    /// mutually exclusive (a queued attempt never throws), but keeping them
    /// as distinct optionals/booleans avoids overloading one property with
    /// two different meanings. Cleared optimistically at the start of every
    /// `logSetAndAdvance` call, same convention as `logSetErrorText`.
    @State private var didQueueSetOffline = false
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
    /// Fix wave 1 (inline-card extension) — "Plates" disclosure toggle for the inline
    /// "LOG THIS SET" card, mirroring `LogSetSheet`'s own `showPlateStack`
    /// (LogSetSheet.swift:36). This view already has an explicit `init(session:)`
    /// (line 346 below) rather than relying on the synthesized memberwise init, so
    /// there's no memberwise-init trap here the way there would be for a plain stored
    /// property — `@State private` with a default is simply this view's own copy of
    /// the toggle, not shared with LogSetSheet's.
    @State private var showPlateStack = false

    // PR full-screen celebration (p29) — user-dismissed, no auto-timeout.
    @State private var isPROverlay          = false
    @State private var prOverlayExerciseName: String = ""
    @State private var prOverlayWeight: Decimal = 0
    @State private var prOverlayReps: Int = 0
    @State private var prOverlayPriorBest: Decimal = 0
    @State private var prOverlayMonthlyCount: Int? = nil

    /// Frame 1: the dock shows the user's 4 favorites; before any are chosen,
    /// the first four curated catalog sounds (matches today's fixed set).
    private var dockSounds: [SoundboardSound] {
        let bySlug = Dictionary(uniqueKeysWithValues: soundCatalog.map { ($0.slug, $0) })
        let chosen = soundFavorites.compactMap { bySlug[$0] }
        if !chosen.isEmpty { return Array(chosen.prefix(4)) }
        return Array(soundCatalog.filter(\.isCurated).prefix(4))
    }
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

    /// Other participants' usernames, for `PTTDockRow`'s transmit hero —
    /// mirrors `LobbyView`'s identical property (same "no shared home for
    /// session-state helpers" reasoning as `voiceEligibleStates` above).
    private var otherParticipantNames: [String] {
        participants
            .filter { $0.participant.userID != selfID }
            .map(\.profile.username)
    }

    /// Mirrors `LobbyView.isVoiceConnected`/`voiceMixerParticipants` —
    /// same reasoning in both places (`VoiceRoomState` isn't `Equatable`;
    /// `VoiceRoomService` only knows identity strings, not usernames).
    private var isVoiceConnected: Bool {
        if case .connected = VoiceRoomService.shared.state { return true }
        return false
    }

    private var voiceMixerParticipants: [(identity: String, name: String)] {
        let byIdentity = Dictionary(
            uniqueKeysWithValues: participants.map { ($0.participant.userID.uuidString.lowercased(), $0.profile.username) }
        )
        return VoiceRoomService.shared.connectedParticipantIDs
            .sorted()
            .map { identity in (identity, byIdentity[identity] ?? "Someone") }
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

    // Units sweep: stored weights (and the routine's free-text target, which
    // carries canonical-lbs digits) render in the user's unit. Exact
    // conversion, no plate snapping — these echo what was/should be lifted.
    private func weightText(_ pounds: Decimal) -> String {
        Units.format(pounds: pounds, unit: ThemeStore.shared.weightUnit,
                     rounded: false, includeUnit: false)
    }

    /// "185" → "84.09" for a kg user; non-numeric target strings pass
    /// through untouched (they were never weights to begin with).
    private func targetWeightText(_ target: String?) -> String {
        guard let target else { return "—" }
        guard let parsed = Decimal(string: target) else { return target }
        return weightText(parsed)
    }

    private var currentExerciseTargetText: String? {
        guard let re = currentRoutineExercise, re.targetReps != nil || re.targetWeight != nil else { return nil }
        return "target \(targetWeightText(re.targetWeight)) × \(re.targetReps ?? "—")"
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

    init(session: WorkoutSession, voicePersistsOnPop: Bool = false) {
        self.session = session
        self.voicePersistsOnPop = voicePersistsOnPop
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
                            barLoaderCard
                            logThisSetCard
                            if let logSetErrorText {
                                GSInlineErrorBanner(
                                    title: "Set didn't save.",
                                    message: "Check your connection, then try again — your reps are still filled in above.",
                                    retry: { commitInlineLog() }
                                )
                            } else if didQueueSetOffline {
                                // Phase O Task 3 fix wave 1 (reviewer Finding 1) — see
                                // `logSetAndAdvance`'s offline-queue branch for the full
                                // rationale. No retry CTA: the set already saved locally,
                                // so a retry here would only mint a duplicate queue entry.
                                GSInlineNoticeBanner(
                                    title: "Saved on this phone.",
                                    message: "Your turn will pass once you're back online."
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
                            barLoaderCard
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
                PRCelebrationOverlay(
                    exerciseName: prOverlayExerciseName,
                    weight: prOverlayWeight,
                    reps: prOverlayReps,
                    priorBest: prOverlayPriorBest,
                    monthlyCount: prOverlayMonthlyCount,
                    unit: ThemeStore.shared.weightUnit,
                    onDismiss: {
                        withAnimation(.easeIn(duration: 0.2)) { isPROverlay = false }
                    }
                )
                .transition(.opacity)
            }

            // ── REACTION OVERLAY (floating emoji pill) ───────────────────
            if let emoji = reactionOverlay {
                Text(emoji)
                    .font(.system(size: 40))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
                // First-run coach mark (Phase O Task 5 item 5) — mirrors
                // LobbyView's identical placement directly above the dock.
                if showVoiceCoachMark {
                    GSVoiceCoachMark(onDismiss: { showVoiceCoachMark = false })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                // ── PUSH-TO-TALK DOCK ────────────────────────────────────
                // Dossier §A.2 confirms the exact insertion point: between
                // the HYPE strip and the bottom action bar.
                if isVoiceEligible {
                    PTTDockRow(otherParticipantNames: otherParticipantNames)
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
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                .padding(.bottom, 130)  // float above dock
                .transition(.opacity)
                .id(txt)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: soundOverlayText)
        // Log Set sheet — penalty (burpee) logging only now; normal sets log inline.
        .sheet(isPresented: $showLogSetSheet) { logSetSheetContent }
        // Session chat sheet (Task 3)
        .sheet(isPresented: $showChatSheet) { chatSheet }
        // Voice mixer sheet (Phase O Task 5 item 5)
        .sheet(isPresented: $showVoiceMixerSheet) { voiceMixerSheet }
        .onChange(of: isVoiceConnected) { wasConnected, nowConnected in
            guard nowConnected, !wasConnected else { return }
            // Mirrors LobbyView's identical trigger — see that view's
            // `.onChange(of: isVoiceConnected)` doc comment for the full
            // "toast every time, coach mark only the first time ever"
            // reasoning.
            withAnimation { showVoiceConnectedToast = true }
            if !VoiceCoachMarkStore.hasBeenShown {
                showVoiceCoachMark = true
                VoiceCoachMarkStore.markShown()
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { showVoiceConnectedToast = false }
            }
        }
        .overlay(alignment: .top) {
            // "Voice connected" toast (Phase O Task 5 item 5) — mirrors
            // LobbyView's identical overlay.
            if showVoiceConnectedToast {
                // Unlike LobbyView, this view has no fetched group-name
                // state to hand the toast's subtitle — `nil` renders just
                // the "Voice connected" headline (GSVoiceConnectedToast's
                // `groupName` param is optional exactly for this reason).
                GSVoiceConnectedToast(groupName: nil)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Recap sheet — Phase F Task 4: the frame-8 group celebration
        // (GroupRecapView) replaces this sheet's content for genuine
        // group-backed sessions (data.groupPayload != nil); solo/ad-hoc
        // completions through this same live view are UNCHANGED — still
        // SessionRecapView. See `buildGroupRecapPayload`'s doc comment for
        // the exact before/after and why.
        .sheet(item: $recapData) { data in
            if let payload = data.groupPayload {
                GroupRecapView(
                    kicker: payload.kicker,
                    durationText: payload.durationText,
                    subline: payload.subline,
                    totalLbsText: payload.totalLbsText,
                    setCount: payload.setCount,
                    prCount: payload.prCount,
                    leaderboard: payload.leaderboard,
                    heaviestPR: payload.heaviestPR,
                    shareSummary: payload.shareSummary,
                    sessionID: data.session.id,
                    recipientIDs: payload.recipientIDs,
                    unit: ThemeStore.shared.weightUnit,
                    pumpCheck: data.pumpCheck,
                    onDone: { dismiss() }
                )
            } else {
                SessionRecapView(
                    session: data.session,
                    sets: data.sets,
                    participants: participants,
                    onDone: { dismiss() },
                    pumpCheck: data.pumpCheck
                )
            }
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
            // Phase W Task 2 — the turn passing is exactly the moment the
            // Watch's "whose turn" state goes stale; re-push immediately
            // rather than waiting for the next scenePhase/reload cycle.
            pushWatchSessionState()
        }
        .onChange(of: liveSession.state) { _, _ in
            // Phase W Task 3 fix wave 1 (reviewer finding, CRITICAL) —
            // mirrors the `.onChange(of: liveSession.currentTurnUserID)`
            // block immediately above, for the SAME reason: `liveSession`
            // changing out from under this view is exactly the moment a
            // Watch's state goes stale, and for a PARTICIPANT (everyone but
            // the organizer), the ONLY way `liveSession.state` ever flips to
            // `"completed"`/`"abandoned"` is the realtime sessions-UPDATE
            // echo (`onSessionChange` below, `liveSession = updated`) — the
            // organizer's own `endSession()` call is a route this
            // participant never takes. Before this handler existed, nothing
            // pushed to a participant's watch when that echo landed; their
            // watch kept showing the session as live until the next
            // incidental turn-change push or scenePhase reload (up to the
            // full 90s idle-ladder staleness window). `pushWatchSessionState()`
            // itself now derives `isActive` from `liveSession.state` (see
            // that function's own doc comment) — this handler only needs to
            // trigger the re-push, no argument to pass.
            pushWatchSessionState()
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
                // Phase O Task 4 (Sentry, master spec §6.8.5) — piggybacks
                // this existing foreground hook rather than adding a new
                // one; refreshed AFTER reload() so the participant count is
                // current. No-op when Sentry isn't started.
                SentryContext.refreshLiveSession(rawState: liveSession.state, participantCount: participants.count)
            }
        }
        .onAppear {
            // Suppresses the push banner for this same session while it's
            // open live (AppDelegate.willPresent, AppState.activeSessionID).
            appState.activeSessionID = liveSession.id
            // Phase O Task 4 (Sentry) — "session join" refresh; see
            // SentryContext.refreshLiveSession's doc comment.
            SentryContext.refreshLiveSession(rawState: liveSession.state, participantCount: participants.count)
            // Phase W Task 2 (watch-hr design §3) — lazy WCSession
            // activation, triggered by the SAME "session went live" signal
            // as the `activeSessionID` assignment right above (see
            // `WatchConnectivityBridge.activateIfNeeded`'s doc comment for
            // why this exact call site was chosen over launch-time
            // activation). Push an initial state snapshot immediately after
            // so a Watch that's already reachable doesn't wait for the
            // first turn change to see anything.
            WatchConnectivityBridge.shared.activateIfNeeded()
            // Fix wave 1 (reviewer finding, CRITICAL) — `pushWatchSessionState()`
            // already reads `ThemeStore.shared.shareHeartRate` LIVE on every
            // call (see that function's own doc comment), but nothing ever
            // FIRED a call when the value changed mid-session: this app's
            // tabs stay mounted across switches (no re-`.task`), so a
            // toggle flip in `YouTabView` while this view is on screen sat
            // unseen by the Watch until an unrelated turn-change/session-end
            // push happened to carry it along — an opt-out could keep
            // broadcasting HR for the rest of the session. `ThemeStore
            // .onShareHeartRateChange` (`DesignSystem/ThemeStore.swift`) is
            // the trigger this was missing: set here so a flip anywhere in
            // the app re-pushes state to the Watch immediately in EITHER
            // direction (opt-out stops the sampler on the very next push,
            // opt-in starts it) — cleared back to `nil` in `.onDisappear`
            // below.
            ThemeStore.shared.onShareHeartRateChange = { pushWatchSessionState() }
            pushWatchSessionState()
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
                // Phase O Task 4 (Sentry) — "session leave" refresh, only
                // when THIS view was genuinely the active one (mirrors the
                // guard above) so a stale disappear from a covered view
                // doesn't overwrite a still-live session's context.
                SentryContext.refreshAppWide()
            }
            // Phase W Task 5 — HR channel teardown is its OWN path,
            // independent of the Watch-side sampler stop condition (design
            // brief: "trace both teardown paths"). This is the PHONE
            // unsubscribing from `session:{id}:hr` because THIS VIEW is
            // going away; the Watch's own sampler stop is driven purely by
            // `isActive`/`shareHeartRate` signals in `WatchSessionStore
            // .syncHeartRateSampler()` (`GymSyncWatch/WatchSessionStore.swift`)
            // and does NOT depend on whether the phone happens to be
            // looking at this screen — the session may still be live for
            // other participants. Cancelling the pending expiry `Task`s too
            // (not just `unsubscribe()`) so none of them fires a late,
            // harmless-but-pointless mutation against a dictionary this
            // view is about to stop observing.
            heartRateExpiryTasks.values.forEach { $0.cancel() }
            heartRateExpiryTasks = [:]
            // Fix wave 1 (reviewer finding, CRITICAL) — clears the trigger
            // set in `.onAppear` above. Unconditional (no "still points at
            // THIS session" guard the way `appState.activeSessionID`'s
            // clear above needs): only one `GroupSessionLiveView` is ever
            // genuinely live-on-screen at a time in this app's navigation
            // model, so there's no sibling instance whose hook this could
            // wrongly clear — leaving it set would let a departed view's
            // stale `pushWatchSessionState()` closure keep firing (harmless
            // today since it reads live state, but a dangling reference to
            // a view that's gone is still the wrong thing to leave live).
            ThemeStore.shared.onShareHeartRateChange = nil
            // BLE relay teardown — the strap stays connected (it's a device
            // pairing, not a session resource) but stops feeding a session
            // that no longer exists.
            BLEHeartRateService.shared.onSample = nil
            Task {
                await liveService.unsubscribe()
                await broadcastService.unsubscribe()
                await heartRateService.unsubscribe()
                // Phase O Task 5 (3e follow-up queue item 6, "Lobby<->Live
                // back-nav rejoin blip"): this used to be unconditional
                // (every disappearance treated as a genuine "stop talking"
                // moment). That's still right for a child pushed on top
                // (re-subscribes everything, voice included, on return via
                // this same `.task`) and for `BurpeeLedgerView`'s direct
                // route into a DIFFERENT session (`voicePersistsOnPop` false
                // there — no Lobby is about to reclaim the room). Fix wave 1
                // (Finding F4): that direct route can no longer target the
                // SAME session this view is already showing — `Burpee
                // LedgerView`'s CTA now pops back to THIS instance instead
                // of pushing a duplicate one in that case, so this view's
                // own `onDisappear` never fires for that push/pop pair at
                // all. But backing OUT to LobbyView
                // for the SAME still-live session (`voicePersistsOnPop`
                // true — `SessionInProgressView` is the only route that
                // sets it, per its own "LobbyView navigates here" doc
                // comment) is exactly LobbyView's own guarded-leave case,
                // mirrored: LobbyView's `.task` re-fires `joinVoiceIfEligible
                // ()` on reappearance and `VoiceRoomService.join()`'s
                // idempotent guard no-ops against an already-`.connected`
                // room — so tearing the room down here just to have Lobby
                // immediately reconnect it produced an audible disconnect/
                // reconnect blip for no reason. Only leave() when EITHER
                // this isn't that persisting route OR the session has left
                // the voice-eligible window (ended/cancelled/abandoned) —
                // a genuine "stop talking" moment either way.
                if !voicePersistsOnPop || !isVoiceEligible {
                    await VoiceRoomService.shared.leave()
                }
            }
        }
    }

    // MARK: - Soundboard Dock
    // Frame 1 (favorites ribbon): "YOUR SOUNDS" kicker + Edit row, 4 favorite
    // tiles + dashed "All" expand button — sits above the reaction-pill strip
    // (unchanged) and the PTT dock. Both Edit and All open SoundLibrarySheet.

    private var soundboardDock: some View {
        VStack(alignment: .leading, spacing: 10) {
            GSDivider()

            VStack(alignment: .leading, spacing: 10) {
                // "YOUR SOUNDS" kicker + Edit
                HStack {
                    Text("YOUR SOUNDS")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.9)
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Button {
                        showSoundLibrary = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Edit")
                                .font(GSFont.bold(11, relativeTo: .caption))
                            Image(systemName: "viewfinder")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.accent700)
                    }
                    .buttonStyle(.plain)
                }

                // Favorite tiles + "All" expand button
                HStack(spacing: 6) {
                    ForEach(dockSounds) { sound in
                        Button {
                            Task { await tapSound(slug: sound.slug) }
                        } label: {
                            VStack(spacing: 4) {
                                Text(sound.icon ?? "🔊")
                                    .font(.system(size: 22))
                                Text(sound.label)
                                    .font(GSFont.bold(10, relativeTo: .caption2))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showSoundLibrary = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 16, weight: .semibold))
                            Text("All")
                                .font(GSFont.bold(9, relativeTo: .caption2))
                        }
                        .foregroundStyle(theme.accent)
                        .frame(width: 52)
                        .frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open sound library")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)

            // Reaction pills (unchanged — out of Task 3's scope).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(reactionEmojis, id: \.self) { emoji in
                        Button {
                            Task { await tapReaction(emoji: emoji) }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 13))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 9)
        }
        .background(theme.bg)
        .sheet(isPresented: $showSoundLibrary) {
            SoundLibrarySheet(
                catalog: soundCatalog,
                favorites: soundFavorites,
                onFavoritesChanged: { updated in
                    soundFavorites = updated
                    Task { try? await SoundboardFavoritesRepository.set(updated) }
                },
                onSend: { slug in Task { await tapSound(slug: slug) } }
            )
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

            // Voice mixer entry point (Phase O Task 5 item 5) — same
            // bordered-square idiom as the chat/X buttons beside it; no
            // canvas frame shows WHERE the mixer opens from (only its own
            // content), see docs/design/accepted-deviations.json's
            // "voice-mixer-entry-point" entry.
            if isVoiceConnected {
                Button {
                    showVoiceMixerSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // ("Load the bar" was a bordered-square header button here until
            // 2026-07-28 — it is now the inline `barLoaderCard` widget in the
            // content column, matching the solo session. See that property.)

            // Session chat (Task 3) — same bordered-square idiom as the X
            // button beside it (30×30 glyph in a 44×44 tap target); no
            // canvas frame shows this affordance, see `showChatSheet`'s doc
            // comment.
            Button {
                showChatSheet = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
    // target W × R" subtitle. BPM waveform decoration from the proof is skipped (no
    // continuous waveform data source exists — the pill's bpm NUMBER is now real,
    // Phase W Task 5, but the small sparkline under it in frame 2A stays chrome-only:
    // this app's HR feed is discrete ~5s samples, not a continuous trace to plot).

    private var spotlightHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR TURN")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(theme.bg.opacity(0.85))

                    Text(currentExerciseForSheet?.name ?? "Exercise")
                        .font(GSFont.heading(26, relativeTo: .title))
                        .foregroundStyle(theme.bg)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                // Phase W Task 5 (watch-hr design §4) — canvas frame 2A's
                // own HR pill: this is the SPOTLIGHT hero, "your turn" —
                // always the current (self) user, so `selfID` is the only
                // key this slot ever reads. See `GSHeartRatePill`'s header
                // comment for the frame citation.
                //
                // Fix wave 1 (CI compile error, `selfID` is `UUID?` —
                // `appState.currentProfile?.id`, line 234 — but
                // `heartRateFor(_:)` takes a non-optional `UUID`): unwrapped
                // here rather than force-unwrapped or defaulted. A nil
                // `selfID` (no signed-in profile resolved yet) means no
                // pill — the honest choice, matching every OTHER optional
                // guard on `selfID` elsewhere in this file (e.g. line 407's
                // `guard let selfID, ... else { return nil }`).
                if let selfID, let mine = heartRateFor(selfID) {
                    GSHeartRatePill(
                        bpm: mine.bpm,
                        zone: mine.zone,
                        showsLiveSuffix: true,
                        captionColor: theme.bg.opacity(0.85)
                    )
                }
            }

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
        .cornerRadius(GSMetrics.radiusMd)   // redesign: rounded accent surface
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
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Load the bar (inline widget — parity with the solo session)
    //
    // User direction 2026-07-28: "Group session load the bar should be the
    // same as the solo workout. Not a small button, but a widget." This is
    // `WorkoutSessionView.barLoaderCard`'s design verbatim — collapsed card
    // with a `GSBarLoaderMini` preview, expanding to the full
    // `BarLoaderWidget` — and it renders in BOTH the my-turn and spectating
    // branches, preserving the original "reachable whether or not it's your
    // turn" property (plan your bar while someone else lifts).
    //
    // Bar/plate settings come from `ThemeStore`'s already-cached
    // `user_settings` row rather than a fetch of this view's own, matching
    // how this file already reads `weightUnit`.
    @ViewBuilder
    private var barLoaderCard: some View {
        if let ex = currentExerciseForSheet, ex.equipment.lowercased() == "barbell" {
            let unit = ThemeStore.shared.weightUnit
            let plates: [Decimal] = {
                if let custom = ThemeStore.shared.plateInventory, !custom.isEmpty {
                    return custom.sorted(by: >)
                }
                return unit.standardPlates
            }()
            let barInUnit: Decimal = {
                var value = Units.fromPounds(ThemeStore.shared.barWeightLbs, to: unit)
                var rounded = Decimal()
                NSDecimalRound(&rounded, &value, 2, .plain)
                return rounded
            }()
            // Prefill priority mirrors solo: the programmed target, else the
            // last set I logged for THIS exercise.
            let prefill: Decimal? = {
                if let target = currentRoutineExercise?.targetWeight,
                   let parsed = Decimal(string: target), parsed > 0 { return parsed }
                return feedSets.first { $0.userID == selfID && $0.exerciseID == ex.id && !$0.isFailed }?.weight
            }()
            let targetInUnit = prefill.map { Units.fromPounds($0, to: unit) } ?? barInUnit

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showBarLoader.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Image(systemName: "scalemass")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                                Text("Load the bar")
                                    .font(GSFont.bold(15, relativeTo: .body))
                                    .foregroundStyle(theme.text)
                            }
                            Text(prefill.map { "\(Units.format(pounds: $0, unit: unit, rounded: false)) · plates & warm-up" }
                                 ?? "Plates & warm-up ramp")
                                .font(GSFont.body(11.5, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                        Spacer(minLength: 8)
                        GSBarLoaderMini(target: targetInUnit, barWeight: barInUnit,
                                        plates: plates, unit: unit)
                        Image(systemName: showBarLoader ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showBarLoader {
                    // Whatever gets dialled in lands in the inline LOG THIS
                    // SET card's weight field, in the display unit.
                    BarLoaderWidget(initialPounds: prefill,
                                    onEnteredPoundsChange: { pounds in
                                        guard let pounds else { return }
                                        logWeight = Units.format(pounds: pounds, unit: unit,
                                                                 rounded: false, includeUnit: false)
                                    })
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusMd)
        }
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
                    // Units sweep: the USER'S unit, not the exercise's
                    // default — commitInlineLog parses in this.
                    label: "Weight (\(ThemeStore.shared.weightUnit.label))",
                    value: $logWeight,
                    borderColor: theme.accent,
                    valueColor: theme.accent700,
                    keyboard: .decimalPad,
                    onDecrement: { decrementDecimal(&logWeight) },
                    onIncrement: { incrementDecimal(&logWeight) }
                )
            }

            // Fix wave 1 (inline-card extension) — reuses `PlateStackDisclosure`
            // (LogSetSheet.swift:397), the same free-standing view LogSetSheet's own
            // "Plates" row renders (LogSetSheet.swift:124), instead of copy-pasting its
            // body per the reviewer's explicit ruling against that approach. Same
            // hidden/inert-for-empty/invalid/non-positive-weight gate as LogSetSheet
            // and the same `Decimal.parseUserInput(_:)` locale-safe parse idiom
            // `commitInlineLog()` (below) already uses for this exact field (Phase O
            // Task 2 — was the bare `Decimal(string:)` initializer) — this card just
            // holds its weight in `logWeight` rather than LogSetSheet's `weight`
            // (LogSetSheet.swift:22).
            if let targetWeight = Decimal.parseUserInput(logWeight), targetWeight > 0 {
                // Units sweep: `target` is what the user TYPED, i.e. already
                // in their unit — the disclosure now runs its plate math
                // natively in that unit (see PlateStackDisclosure).
                PlateStackDisclosure(target: targetWeight, theme: theme,
                                     unit: ThemeStore.shared.weightUnit,
                                     isExpanded: $showPlateStack)
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
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(
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
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
        // reused here for the live-session roster grid).
        let identity = item.participant.userID.uuidString.lowercased()
        let voice = VoiceRoomService.shared
        let isSpeaking = voice.speakingParticipantIDs.contains(identity)
        // Phase O Task 5 item 4 ("muted-others roster rows") — mirrors
        // LobbyView.participantRow's identical derivation now that
        // VoiceRoomService exposes a roster + both mute-state sets; see
        // that view's doc comment for the full "muted" definition (own-mic
        // mute OR muted-by-you via the mixer, one shared caption for both).
        let isInVoiceRoom = voice.connectedParticipantIDs.contains(identity)
        let isMuted = isInVoiceRoom && !isSpeaking &&
            (voice.remoteMutedParticipantIDs.contains(identity) || voice.locallyMutedParticipantIDs.contains(identity))

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
                } else if isMuted {
                    Text("muted")
                        .font(GSFont.body(9, relativeTo: .caption2))
                        .foregroundStyle(isLifting ? theme.bg.opacity(0.7) : theme.neutral500)
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

            // Phase W Task 5 (watch-hr design §4) — zone-colored HR pill,
            // canvas frame 2B's exact heart+number+"BPM" shape (see
            // `GSHeartRatePill`'s own header comment for the frame
            // citation + the "any status, not just LIFTING NOW" generalization).
            if let hr = heartRateFor(item.participant.userID) {
                GSHeartRatePill(
                    bpm: hr.bpm,
                    zone: hr.zone,
                    captionColor: isLifting ? theme.bg.opacity(0.85) : theme.neutral500
                )
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(isLifting ? theme.accent : theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(
            isSpeaking ? theme.accent700 : (isLifting ? Color.clear : theme.divider),
            lineWidth: isSpeaking ? 2 : 1))
        .opacity(isMuted ? 0.7 : 1)
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
                Text("Set \(setCount(userID: userID, exerciseID: currentExerciseForSheet?.id ?? UUID()) + 1) · target \(targetWeightText(re.targetWeight)) × \(re.targetReps ?? "—")")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
        case .upNext:
            if let last = lastSetAnyExercise(userID) {
                Text("Last set")
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                Text("\(last.weight.map(weightText) ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
                    .font(GSFont.bodyMedium(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
            } else {
                Text("Get ready")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
        case .done:
            if let last = lastSetForCurrentExercise(userID) {
                Text("\(last.weight.map(weightText) ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
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
                Text("Target \(targetWeightText(re.targetWeight)) × \(re.targetReps ?? "—")")
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
                .cornerRadius(GSMetrics.radiusSm)   // redesign: rounded accent surface
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // `leadingInt` — a rep range must not dead-end the CTA (see the
            // helper in LogSetSheet.swift).
            .disabled(isLoggingSet || (leadingInt(logReps) == nil && !logIsFailed))
            .background(theme.bg)
        } else if let hint = upcomingTurnHint {
            Text(hint)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.bg.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Secondary entry into the group-wide Burpee Ledger (Canvas
            // Completion Task 3, proof p25) — only for group sessions;
            // ad-hoc/solo sessions have no group-scoped ledger to show.
            if let ledgerGroup {
                NavigationLink {
                    // Fix wave 1 (reviewer Finding F4): threads this view's
                    // own session id through so BurpeeLedgerView's "Log
                    // burpees now" CTA can tell whether ITS target session
                    // is the SAME one already live further down the nav
                    // stack — see that property's doc comment for why.
                    BurpeeLedgerView(group: ledgerGroup, pushedFromLiveSessionID: session.id)
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
                // Units sweep: stored-lbs → display unit (renamed from
                // `weightText` so it can't shadow the helper it calls).
                let weightStr = log.weight.map { weightText($0) } ?? "—"
                HStack(spacing: 4) {
                    Text("\(repsText) × \(weightStr)")
                        .font(GSFont.bodyMedium(13, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    if log.isPenalty {
                        GSTag(text: "penalty", style: .accent)
                    }
                    if log.isFailed {
                        GSTag(text: "failed", style: .neutral)
                    }
                    // Phase O Task 3 — syncing indicator (system-designed, no canvas
                    // frame; docs/design/accepted-deviations.json's
                    // "offline-syncing-indicator" entry). Same GSTag(.outline) chip
                    // idiom this row's own penalty/failed tags already use.
                    if OfflineSetLogQueue.shared.pendingSetLogIDs.contains(log.id) {
                        GSTag(text: "syncing", style: .outline)
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
                defaultWeight: nil,
                unit: ThemeStore.shared.weightUnit
            ) { reps, weight, rpe, isFailed, note in
                Task { await logSet(reps: reps, weight: weight, rpe: rpe,
                                    isFailed: isFailed, note: note,
                                    exerciseID: ex.id, isPenalty: true) }
            }
        }
    }

    // MARK: - Chat sheet (Task 3, Phase F)
    //
    // `liveSession.groupID` is passed straight through as the sub-thread's
    // group_id — ChatView.init(sessionID:groupID:)'s doc comment explains
    // why this MUST be the session's own group_id (nil for a solo/ad-hoc
    // session): the sub-thread INSERT RLS binds it via `IS NOT DISTINCT
    // FROM sessions.group_id`
    // (20260719000011_chat_subthread_lock_hardening.sql #5).

    private var chatSheet: some View {
        NavigationStack {
            ChatView(sessionID: liveSession.id, groupID: liveSession.groupID)
                .navigationTitle("Session Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showChatSheet = false }
                            .font(GSFont.bold(14, relativeTo: .body))
                            .foregroundStyle(theme.accent700)
                    }
                }
        }
    }

    // MARK: - Voice mixer (Phase O Task 5 item 5) — mirrors LobbyView's
    // identical sheet, same toolbar-button + sheet idiom as chatSheet above.

    private var voiceMixerSheet: some View {
        NavigationStack {
            GSVoiceMixerSheet(
                participants: voiceMixerParticipants,
                mutedIdentities: VoiceRoomService.shared.remoteMutedParticipantIDs
                    .union(VoiceRoomService.shared.locallyMutedParticipantIDs),
                onToggleMute: { identity in
                    let isMuted = VoiceRoomService.shared.locallyMutedParticipantIDs.contains(identity)
                    Task { await VoiceRoomService.shared.setLocalMute(!isMuted, forParticipantIdentity: identity) }
                }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showVoiceMixerSheet = false }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(theme.accent700)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
        // Reps: resolve a rep RANGE to its low end so the field holds a
        // number the steppers and Save can actually use ("8-12" → "8").
        let target = defaultReps(for: ex.id)
        logReps = target.flatMap(leadingInt).map(String.init) ?? target ?? ""
        // Weight was cleared unconditionally here, so it was blank on EVERY
        // turn — the one field that most wants a prefill. Same priority the
        // solo sheet uses: the programmed target, else my last non-failed
        // set for this exercise, rendered in my display unit.
        let unit = ThemeStore.shared.weightUnit
        let prefillPounds: Decimal? = {
            if let t = currentRoutineExercise?.targetWeight,
               let parsed = Decimal(string: t), parsed > 0 { return parsed }
            return feedSets.first {
                $0.userID == selfID && $0.exerciseID == ex.id && !$0.isFailed
            }?.weight
        }()
        logWeight = prefillPounds.map {
            Units.format(pounds: $0, unit: unit, rounded: false, includeUnit: false)
        } ?? ""
        logRPE = 7.0
        logIsFailed = false
        logNote = ""
        // Fix wave 1 (inline-card extension) — collapse the "Plates" disclosure on every
        // fresh turn, matching LogSetSheet's behavior (a new sheet instance always starts
        // with `showPlateStack == false`; this persistent view needs the explicit reset).
        showPlateStack = false
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
        let reps = leadingInt(logReps)
        // Phase O Task 2: `Decimal.parseUserInput(_:)` — see the "Plates"
        // disclosure gate above for why the bare `Decimal(string:)`
        // initializer was locale-unsafe.
        // Units sweep: the field is typed in the USER'S unit — convert to
        // canonical pounds before storage (a kg user typing 100 must store
        // 220.46, not a silent 100 lb set corrupting volume and PRs).
        let weight = Decimal.parseUserInput(logWeight)
            .map { Units.toPounds($0, from: ThemeStore.shared.weightUnit) }
        let rpe = Decimal(logRPE)
        let note = logNote.isEmpty ? nil : logNote
        let failed = logIsFailed
        Task {
            defer { isLoggingSet = false }
            await logSetAndAdvance(reps: reps, weight: weight, rpe: rpe,
                                    isFailed: failed, note: note, exerciseID: ex.id)
        }
    }

    // MARK: - Watch bridge (Phase W Task 2, watch-hr design §3)

    /// Builds a `WatchSessionStatePayload` from this view's OWN already-
    /// fetched models — `liveSession` (`WorkoutSession`), `rotationOrder`
    /// (`[(SessionParticipant, Profile)]`, this file's line 257),
    /// `currentExerciseForSheet` (`Exercise`, this file's own property
    /// above) — the exact same
    /// derivations `spotlightHeaderCard`/`spectatingHeaderCard` already
    /// render, not a second computation. See `WatchConnectivityBridge`'s
    /// header doc comment for why the bridge itself accepts this
    /// already-built payload instead of re-deriving it. Called from
    /// `.onAppear` (initial snapshot), `.onChange(of: liveSession.currentTurnUserID)`
    /// (turn passes — the state most likely to matter to someone glancing
    /// at their Watch), `.onChange(of: liveSession.state)` (Task 3 fix wave
    /// 1 addition, immediately above both `.onChange` blocks in `body` —
    /// see that handler's own comment), `openAndSubscribe()` twice (once
    /// right after `reload()`, once more — Task 3 addition — after
    /// `soundFavorites` finishes loading, since that fetch runs LATER in the
    /// same function and this payload's `soundboardFavorites` field would
    /// otherwise stay empty until the next turn change), and `endSession()`.
    /// Best-effort: `WatchConnectivityBridge.updateSessionState` itself
    /// never throws into this call site.
    ///
    /// `isActive` (Task 3 fix wave 1 — reviewer finding, CRITICAL; replaces
    /// the original `isActive: Bool = true` PARAMETER this function used to
    /// take): now derived HERE, from `liveSession.state`, instead of being
    /// handed in by each call site. The original shape let every
    /// pre-existing call site default to `true` unconditionally and trusted
    /// `endSession()` as the ONE call site allowed to pass `false` — which
    /// had two bugs in practice: (a) a PARTICIPANT's watch (everyone except
    /// the organizer) never learned a session ended AT ALL, because
    /// `endSession()` is the organizer's own local success path and
    /// participants only ever observe completion via the realtime
    /// sessions-UPDATE echo (`onSessionChange` below, `liveSession =
    /// updated`) — which had no push attached to it; and (b) `.onAppear`
    /// pushed a hardcoded `true` with no state check at all, so reopening
    /// this view for an already-completed session (however that's reached)
    /// would push the WRONG state. Deriving `isActive` from `liveSession.state`
    /// on every call fixes both at once: the realtime echo's `liveSession =
    /// updated` assignment (now paired with the `.onChange(of: liveSession.state)`
    /// handler above) feeds a genuinely live-or-not read straight into the
    /// very next push, and `.onAppear`'s push is correct BY CONSTRUCTION —
    /// whatever `liveSession.state` this view was constructed/updated with
    /// is exactly what gets reported, no separate bookkeeping required to
    /// keep the two in sync. `"in_progress"` is the one state string this
    /// view's own `voiceEligibleStates`-adjacent reasoning and every other
    /// state-string call site in this codebase (`SentryContext.swift`'s
    /// `SessionPhase(rawState:)`, `GroupView.swift`'s `pastStates`,
    /// `BurpeeLedgerMath.swift:143`) treat as "actually live" as opposed to
    /// `completed`/`abandoned` (or a pre-live Lobby state) — matches here
    /// for the identical reason.
    ///
    /// `endSession()` no longer needs a special-cased `isActive: false`
    /// ARGUMENT to lead the realtime echo: it now assigns `liveSession =
    /// completed` itself, right after `SessionRepository.complete(sessionID:)`
    /// succeeds and BEFORE calling this function (see that call site's own
    /// comment) — so by the time this function reads `liveSession.state`
    /// below, it already reads `"completed"`, immediately, without waiting
    /// for the realtime UPDATE to round-trip back in.
    private func pushWatchSessionState() {
        let currentLifter = rotationOrder.first(where: { $0.participant.userID == liveSession.currentTurnUserID })?.profile
        let payload = WatchSessionStatePayload(
            sessionID: liveSession.id,
            groupID: liveSession.groupID,
            sessionName: routineName ?? "Session",
            currentExerciseName: currentExerciseForSheet?.name,
            currentExerciseID: currentExerciseForSheet?.id,
            currentLifterName: currentLifter?.username,
            isMyTurn: isMyTurn,
            burpeesOwed: burpeesRemaining,
            burpeesPaid: penaltyLogged,
            // Task 3 fix wave 1 (reviewer finding, IMPORTANT 1 + 2) —
            // `dockSounds` (line 166 above) already encodes the EXACT same
            // "favorites, or the first 4 curated sounds until any are
            // chosen" fallback the phone's own soundboard dock ribbon
            // renders. Sending raw `soundFavorites` here (the old shape)
            // diverged from that: an empty-favorites watch showed "No
            // favorites yet" while the phone's own dock, right next to it,
            // was showing 4 curated tiles. `.label` (`displayName ?? slug`,
            // `Models/Soundboard.swift:16`) is ADDITIVE alongside the
            // slugs, same order — the watch's TAP path
            // (`SoundboardView.soundTile` -> `WatchSessionStore.
            // tapSoundboard(slug:)` -> `WatchConnectivityBridge.
            // handleSoundboardTap`) still sends the SLUG back for playback,
            // unchanged; labels are display-only, resolved here so
            // `SoundboardSound`/`SoundboardRepository` (`GymSync`-only,
            // Supabase-shaped) never need to compile into the watch target.
            soundboardFavorites: dockSounds.map(\.slug),
            soundboardFavoriteLabels: dockSounds.map(\.label),
            isActive: WatchDisplayFormatting.isSessionActive(state: liveSession.state),
            // Task 5 (watch-hr design §4) — tells the Watch whether to start
            // its HR sampler for this session. DERIVED live from
            // `ThemeStore.shared.shareHeartRate` on every call, the same
            // "derive from observed state" fix `isActive` immediately above
            // already established (see that field's own doc comment for
            // the T3 precedent this mirrors) — NOT a locally cached
            // `@State` snapshot fetched once, which was T4's carried-in bug
            // (a mid-session toggle flip in `YouTabView` never reaching an
            // already-open live session). `ThemeStore` is the live,
            // cross-view cache of `user_settings` this app already
            // maintains for exactly this purpose.
            shareHeartRate: ThemeStore.shared.shareHeartRate
        )
        WatchConnectivityBridge.shared.updateSessionState(payload)
    }

    // MARK: - Data loading

    @MainActor
    private func openAndSubscribe() async {
        await reload()
        // Phase W Task 2 — `.onAppear`'s push (right after this `.task`
        // fires) runs before `reload()` has populated `routineExercises`/
        // `allExercises`/`routineName`, so its payload's exercise/session
        // name fields are still nil/placeholder at that point. Re-push now
        // that the real models are in, so a Watch that's already reachable
        // sees the actual current exercise shortly after entering, not
        // only after the first turn change.
        pushWatchSessionState()
        await ExerciseNameCache.preload()
        if let groupID = liveSession.groupID {
            // Fast-follow wave, Fix 3: this used to be a bare `try?` — a
            // fetch failure here was completely silent. `ledgerGroup` stays
            // nil either way (unchanged fallback behavior: the burpee-ledger
            // link stays hidden, and — per `buildGroupRecapPayload`'s guard
            // at the bottom of this file — completion falls back to
            // `SessionRecapView` instead of the frame-8 `GroupRecapView`,
            // even though this genuinely IS a group session, not a solo one.
            // That's the "silent frame-8 downgrade": no UI signal distinguishes
            // it from an intentional solo completion. One warn line surfaces
            // it for diagnosis without changing behavior.
            do {
                ledgerGroup = try await GroupRepository.fetch(id: groupID)
            } catch {
                AppLogger.sessions.warning(
                    "GroupSessionLiveView openAndSubscribe: GroupRepository.fetch failed for group \(groupID, privacy: .public) on a real group session — completion will downgrade to SessionRecapView instead of frame-8 GroupRecapView: \(error, privacy: .public)")
            }
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
                // Phase O Task 3 — dedupe guard: an optimistically-appended offline
                // set (queued via OfflineSetLogQueue, see logSetAndAdvance/logSet
                // above) shares its `id` with the eventual realtime echo of its own
                // successful replay. Without this guard, that echo would double
                // -append the row (and double-count penaltyLogged) once reconnected.
                // No-op for the ordinary online path — a fresh id is never already
                // in feedSets.
                guard !feedSets.contains(where: { $0.id == log.id }) else { return }
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
        // Favorites ribbon (Task 3): catalog + chosen favorites. Failures degrade
        // to the curated-first-4 fallback in `dockSounds` — never blocks the session.
        soundCatalog = (try? await SoundboardRepository.fetchCatalog()) ?? []
        soundFavorites = (try? await SoundboardFavoritesRepository.get()) ?? []
        // Task 5 — the `shareHeartRate` fetch that used to live here was
        // removed: `pushWatchSessionState()` now reads `ThemeStore.shared
        // .shareHeartRate` live on every call instead (see that call site's
        // own doc comment) — `ThemeStore.shared.load()` is bootstrapped
        // once at `MainTabView`'s own `.task` (`App/RootView.swift:215-221`,
        // "runs on every launch that reaches signed-in + profile-loaded
        // state"), well before a user can navigate deep enough to reach a
        // live session, so no separate fetch is needed here.
        // Phase W Task 3 — `soundFavorites` finishes loading AFTER the
        // `pushWatchSessionState()` call above (which itself already re-runs
        // post-`reload()`), so a Watch that's already reachable would
        // otherwise never see the soundboard favorites until the next turn
        // change. Re-push once more now that they're actually in.
        pushWatchSessionState()
        await subscribeBroadcast()
        if isMyTurn { prefillLogInputs() }
        // Initial heartbeat — the scenePhase→active heartbeat above only
        // fires on a later transition, so this covers "already foreground,
        // just opened the session" (push-dossier.md §A.4).
        try? await SessionRepository.touchActivity(sessionID: liveSession.id)
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
        // Phase W Task 5 (watch-hr design §4) — subscribes alongside the
        // soundboard/reaction broadcast subscribe immediately above, per
        // the task brief's explicit instruction to add this "alongside its
        // existing broadcast subscriptions." `onHeartRate` is already
        // `@MainActor`-typed (`HeartRateBroadcastService.subscribe`'s own
        // signature), so `receiveHeartRate` is called directly here, same
        // as `onSoundboard`'s guard-then-mutate shape — no extra `Task {
        // @MainActor in ... }` wrapper needed the way `onReaction` above
        // uses one (that wrapper exists only because `showReactionOverlay`
        // is itself `async`; `receiveHeartRate` is synchronous).
        await heartRateService.subscribe(
            sessionID: liveSession.id,
            onHeartRate: { userID, bpm, zone in
                receiveHeartRate(userID: userID, bpm: bpm, zone: zone)
            }
        )

        // BLE monitor relay (2026-07-27: "everyone has the option to have
        // live HR"): a paired chest strap / broadcasting watch feeds the
        // EXACT gate + publish path the Apple Watch uses — same share
        // toggle, same zone derivation, same throttle inside publish, and
        // the self-echo lights your own pill identically. Publishes through
        // this view's HELD channel (the debt-sprint channel rule).
        BLEHeartRateService.shared.connectRememberedIfAny()
        BLEHeartRateService.shared.onSample = { bpm in
            guard ThemeStore.shared.shareHeartRate, let selfID else { return }
            let zone = HeartRateZone.zone(bpm: bpm)
            Task {
                await heartRateService.publish(
                    sessionID: liveSession.id, userID: selfID,
                    bpm: bpm, zone: zone.rawValue
                )
            }
        }
    }

    // MARK: - Heart rate roster state (Phase W Task 5, watch-hr design §4)

    /// Records a live HR reading and (re)schedules its 15s auto-expiry.
    /// Cancels any PRIOR pending expiry `Task` for the same user first — a
    /// fresh sample resets the clock, matching the design's own "one
    /// broadcast per 5s" cadence (a healthy stream re-arms this every ~5s,
    /// well under the 15s staleness window; three consecutive missed
    /// broadcasts is what actually lets a pill go stale).
    @MainActor
    private func receiveHeartRate(userID: UUID, bpm: Int, zone: String?) {
        let now = Date()
        heartRates[userID] = (bpm, HeartRateZone(rawValue: zone ?? ""), now)
        heartRateExpiryTasks[userID]?.cancel()
        heartRateExpiryTasks[userID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.heartRateStaleAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Only purge if THIS task's own sample is still the latest one
            // recorded — a cancel-race where a newer sample's replacement
            // task already started is handled by the `cancel()` above, but
            // this timestamp check is the second, authoritative guard
            // (same "check right before mutating" discipline `ThemeStore
            // .select(_:)`'s own cancellation-race doc comment describes).
            if heartRates[userID]?.receivedAt == now {
                withAnimation(.easeOut(duration: 0.3)) {
                    heartRates[userID] = nil
                }
            }
            heartRateExpiryTasks[userID] = nil
        }
    }

    /// Freshness-gated read — `HeartRateFreshness.isFresh` (`Services/
    /// HeartRateZone.swift`) is the AUTHORITATIVE staleness check (see that
    /// type's own doc comment); the auto-purge `Task` above is memory
    /// hygiene + a re-render trigger, not the source of truth. `rosterCard`
    /// and `spotlightHeaderCard` both call this rather than reading
    /// `heartRates` directly.
    private func heartRateFor(_ userID: UUID) -> (bpm: Int, zone: HeartRateZone?)? {
        guard let entry = heartRates[userID],
              HeartRateFreshness.isFresh(receivedAt: entry.receivedAt, now: Date(), staleAfter: Self.heartRateStaleAfter)
        else { return nil }
        return (entry.bpm, entry.zone)
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
        // Phase O Task 3 fix wave 1 (reviewer Finding 1) — same "clear
        // optimistically at the start of every attempt" convention as
        // `logSetErrorText` above, so a fresh attempt never shows a stale
        // notice left over from a previous set.
        didQueueSetOffline = false
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
                // Phase O Task 3 — see WorkoutSessionView.log's identical catch for
                // the full rationale: without this, an offline attempt throws HERE
                // (before the set-log write below), so a group-session lifter could
                // never queue a set while offline either. Only `.network` is tolerant.
                do {
                    let prior = try await priorMax(exerciseID: exerciseID,
                                                   weight: weight, userID: userID)
                    priorBest = prior
                    isPR = weight > prior
                } catch let error as GymSyncError {
                    guard case .network = error else { throw error }
                    // Offline — PR check skipped (best-effort, never blocks logging).
                }
            }

            do {
                try await SessionRepository.logSet(log)
                Task { await OfflineSetLogQueue.shared.replay() }   // cheap drain
            } catch let error as GymSyncError {
                guard case .network = error else { throw error }
                // Offline — queue for replay + optimistic local append. `feedSets`/
                // `allSessionSets` normally only ever get a set from the realtime
                // echo (`onSetLogged` below — "single source" per its own comment);
                // that echo can't arrive while offline, so this is now this path's
                // ONLY way the set becomes visible / counts toward mySetCount()
                // until reconnect. `onSetLogged` gained a dedupe-by-id guard (below)
                // so the eventual echo of this same id, once replay succeeds, does
                // not double-append the row.
                OfflineSetLogQueue.shared.enqueue(log)
                feedSets.insert(log, at: 0)
                if feedSets.count > 30 { feedSets = Array(feedSets.prefix(30)) }
                allSessionSets.append(log)
                // Phase O Task 3 fix wave 1 (reviewer Finding 1) — advanceTurn
                // below is now deliberately SKIPPED (via `didQueueSetOffline`)
                // rather than "attempted below (unchanged)" as this comment used
                // to claim. That claim was wrong in practice: the set-log write
                // above already succeeded LOCALLY (queued + optimistically
                // applied), so calling advanceTurn unconditionally next would
                // just throw its own `.network` and land in the outer catch,
                // which showed "Set didn't save" — false, the set DID save — with
                // a "Try again" retry that mints a BRAND NEW `SetLog(id: UUID(),
                // ...)` at an advanced `setIndex` (mySetCount() already counts
                // this optimistic append, commitInlineLog() ~1505-1522). Every
                // offline retry tap therefore queued one more DISTINCT duplicate
                // row — different UUIDs, so the 23505 dedupe in
                // OfflineSetLogQueue.replay() can't catch them.
                //
                // Accepted consequence (reviewer + spec scope both accept this):
                // this lifter's turn does NOT auto-advance while offline, and it
                // never auto-advances for this specific set even once the queued
                // row replays successfully — `OfflineSetLogQueue.replay()` only
                // ever resubmits the set_logs INSERT itself (Services/
                // OfflineSetLogQueue.swift:120-182 → `SupabaseSetLogSubmitter.
                // submit` → `SessionRepository.logSet`), advanceTurn is not part
                // of replay. The closest existing session-level fallback is the
                // idle-ladder's "Still Going"/"Wrap Up" push actions
                // (PushReceiver.stillGoing/wrapUpSession, App/AppDelegate.swift
                // ~91-92) — but that's a session-idle heartbeat, not a per-turn
                // advance, so it won't unstick this turn either. Honestly: the
                // organizer (or this lifter, once back online, by logging their
                // next set — `isMyTurn` stays true) advances manually.
                didQueueSetOffline = true
            }

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

            // Phase O Task 3 fix wave 1 (reviewer Finding 1) — skip advanceTurn
            // entirely when this attempt queued offline; see the queuing
            // branch's comment above for the full rationale. The normal
            // ONLINE path is unaffected: `didQueueSetOffline` stays false, so
            // advanceTurn still runs, and a genuine failure here (e.g. a real
            // permanent error, or connectivity dropping between logSet and
            // advanceTurn) still falls into the catch below and shows the
            // existing retry banner exactly as before.
            guard !didQueueSetOffline else { return }
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
            Task { await OfflineSetLogQueue.shared.replay() }   // cheap drain
            // penaltyLogged updates via the realtime echo (single source; reload() re-seeds)
        } catch let error as GymSyncError {
            guard case .network = error else {
                errorText = error.errorDescription
                return
            }
            // Phase O Task 3 — offline: queue for replay + optimistic local append.
            // This function's "single source: realtime echo" comment above no longer
            // holds while offline (there is no realtime channel to echo from) — the
            // local append here is this path's ONLY way the set becomes visible /
            // counts toward penaltyLogged until reconnect. Mirrors what the realtime
            // echo (onSetLogged, below) does for the exact same fields.
            OfflineSetLogQueue.shared.enqueue(log)
            feedSets.insert(log, at: 0)
            if feedSets.count > 30 { feedSets = Array(feedSets.prefix(30)) }
            allSessionSets.append(log)
            if isPenalty && !isFailed { penaltyLogged += reps ?? 0 }
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
            // Phase W Task 3 — CARRIED-IN REQUIREMENT from T2's review: push
            // the "session ended" state to the Watch immediately, right here
            // at the one moment the session has unambiguously ended
            // server-side (see `pushWatchSessionState`'s doc comment for why
            // THIS call site, not `.onDisappear`). Fired before the
            // HealthKit export / recap-payload work below since none of
            // that affects what the Watch needs to know, and this view
            // stays mounted (presenting the recap sheet) for a while after
            // this point — no reason to delay it.
            //
            // Fix wave 1 (reviewer finding, CRITICAL): `pushWatchSessionState()`
            // no longer takes an `isActive` override argument — it derives
            // `isActive` from `liveSession.state` itself (see that
            // function's own doc comment). This assignment is what makes
            // THIS call site still lead the realtime echo the way the old
            // `isActive: false` argument used to: without it, `liveSession.state`
            // would still read its stale pre-completion value (this `@State`
            // var is otherwise only ever updated by `reload()` or the
            // realtime `onSessionChange` echo, neither of which has run yet
            // at this exact point) and the push below would incorrectly
            // report the session as still live.
            liveSession = completed
            pushWatchSessionState()
            let allSets = try await SessionRepository.sessionSets(sessionID: session.id)
            try? await HealthKitBridge.requestPermission()
            try? await HealthKitBridge.exportWorkout(session: completed, setLogs: allSets)
            await liveService.unsubscribe()
            let groupPayload = await buildGroupRecapPayload(session: completed, sets: allSets)
            let pumpCheck = await buildPumpCheckContext(session: completed, sets: allSets)
            recapData = RecapData(session: completed, sets: allSets,
                                  groupPayload: groupPayload, pumpCheck: pumpCheck)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Group recap payload (Phase F Task 4 — frame 8)
    //
    // BEFORE this task: every completion through this view — solo, ad-hoc,
    // or group-backed — presented the identical `SessionRecapView` sheet
    // (leaderboard-by-volume + YOUR PR card + Share/Done, no kudos, no live
    // updates). AFTER: a genuine group session (`liveSession.groupID !=
    // nil`, equivalently `ledgerGroup != nil` — fetched once in
    // `openAndSubscribe()`) instead gets `GroupRecapView` (frame 8): same
    // leaderboard/PR-card shape plus per-recipient kudos counts (live via
    // realtime) and the crew-wide kudos send row. Solo/ad-hoc completions
    // through this same live view are UNCHANGED — `ledgerGroup` is nil for
    // them, so this returns nil and the `.sheet` falls back to
    // `SessionRecapView`, exactly as before this task.
    //
    // `ledgerGroup` can ALSO be nil for a genuine group session if
    // `GroupRepository.fetch` failed in `openAndSubscribe()` — that failure
    // is logged there now (Fast-follow wave, Fix 3) since this guard has no
    // way to tell that case apart from an intentional solo completion.
    //
    // The PR-celebration overlay (`isPROverlay`, a ZStack sibling — see
    // `body`) is untouched by any of this: it lives outside the `.sheet`
    // entirely, so presenting either recap sheet on top of it doesn't
    // structurally remount it (the U-Task 4 "hoisted to outer ZStack
    // sibling" fix, progress.md:394, is what makes that safe — the overlay
    // is never inside an if/else branch that this change alters). Tapping
    // "Done" on either recap calls `dismiss()`, which pops this whole view
    // off the navigation stack — that's what actually clears `isPROverlay`
    // (view teardown), not anything this function does.
    @MainActor
    private func buildGroupRecapPayload(session: WorkoutSession, sets: [SetLog]) async -> GroupRecapPayload? {
        guard let ledgerGroup else { return nil }

        // Fix round 1 (task-4-report.md Finding 1) — CRITICAL: this used to
        // be the ONLY PR fetch here, and `sessionPRs` was (mis)used both for
        // the caller's own heaviestPR detail below AND for every
        // participant's PR count (prCount below, GroupRecapPayload.prCount).
        // `PersonalRecordRepository.bySession` is gated by personal_records'
        // SELF-ONLY SELECT RLS (20260715000002_personal_records.sql:23-25),
        // so despite querying by session_id with no user filter it only ever
        // returned the CALLER's own rows — a real group session rendered 0
        // PRs for every teammate (hero "PRS" stat + every "N PR" badge),
        // and only the catalog fixture (which bypasses the network fetch
        // entirely) looked right.
        //
        // `sessionPRs` below is kept ONLY for the caller's own heaviestPR
        // card (exercise name/weight/reps/previousBest) — that data is
        // genuinely self-scoped by the product (frame-8 only ever shows
        // YOUR heaviest PR), so RLS narrowing it to "my own rows" is
        // correct there, not a bug.
        //
        // `prCounts`/`prCountByUser` below replace the old crew-wide use of
        // `sessionPRs` for counting: calls the `session_pr_counts` SECURITY
        // DEFINER RPC (20260720000002_session_pr_counts_and_kudos_guard.sql),
        // gated on session participation, aggregating every participant's
        // rows server-side (see `session_pr_counts_test.sql`).
        let sessionPRs = (try? await PersonalRecordRepository.bySession(sessionID: session.id)) ?? []
        let prCounts = (try? await PersonalRecordRepository.countsBySession(sessionID: session.id)) ?? []
        let prCountByUser: [UUID: Int] = prCounts.reduce(into: [:]) { acc, row in acc[row.userID] = row.prCount }

        var prExerciseNames: [UUID: String] = [:]
        for exerciseID in Set(sessionPRs.map(\.exerciseID)) {
            if let exercise = try? await ExerciseRepository.fetch(id: exerciseID) {
                prExerciseNames[exerciseID] = exercise.name
            }
        }

        struct Stat {
            let profile: Profile
            let userID: UUID
            let volume: Double
            let prCount: Int
        }
        // Volume math (Σ reps×weight, excluding failed/penalty sets) mirrors
        // SessionRecapView.stats / CompletedSessionView.stats verbatim —
        // parallel structure, not a shared extraction (see GroupRecapView's
        // type doc comment for why).
        let stats: [Stat] = participants.map { item in
            let mySets = sets.filter { $0.userID == item.participant.userID && !$0.isPenalty }
            let volume = mySets.reduce(0.0) { acc, log in
                guard !log.isFailed, let r = log.reps, let w = log.weight else { return acc }
                return acc + Double(r) * NSDecimalNumber(decimal: w).doubleValue
            }
            let prCount = prCountByUser[item.participant.userID] ?? 0
            return Stat(profile: item.profile, userID: item.participant.userID, volume: volume, prCount: prCount)
        }
        .sorted { $0.volume > $1.volume }   // descending volume = leaderboard order

        // Units sweep: volumes accumulate in stored-lbs — convert once here,
        // then every formatted figure below is already in the user's unit.
        let unit = ThemeStore.shared.weightUnit
        let leaderboard = stats.map { stat in
            GroupRecapView.LeaderboardRow(
                id: stat.userID,
                initials: String(stat.profile.username.prefix(2)).uppercased(),
                name: stat.userID == selfID ? "You" : stat.profile.username,
                volumeText: "\(formatVolumeFull(Units.fromPounds(stat.volume, to: unit))) \(unit.label)",
                prCount: stat.prCount,
                isYou: stat.userID == selfID
            )
        }

        let totalVolume = stats.reduce(0.0) { $0 + $1.volume }
        let totalSets = sets.filter { !$0.isPenalty }.count

        let durationSeconds: TimeInterval = {
            guard let start = session.startedAt, let end = session.completedAt else { return 0 }
            return max(0, end.timeIntervalSince(start))
        }()

        // "Thursday, July 10" — weekday + month + day, no year (matches
        // proof-frame-08.png's subline exactly). DateFormatter has no canned
        // style for this combination (.long/.full both include the year),
        // hence the explicit format string rather than reusing
        // SessionRecapView.dateString's `.dateStyle = .long`.
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEEE, MMMM d"
        let dateString = (session.completedAt ?? session.startedAt).map { dateFmt.string(from: $0) } ?? ""
        let subline = "\(dateString) · \(participants.count) lifter\(participants.count == 1 ? "" : "s")"

        let kicker: String = {
            guard let routineName else { return ledgerGroup.name.uppercased() }
            return "\(ledgerGroup.name.uppercased()) · \(routineName.uppercased())"
        }()

        let heaviestPR: GroupRecapView.HeaviestPR? = {
            guard let selfID, let myPR = sessionPRs.first(where: { $0.userID == selfID }) else { return nil }
            return GroupRecapView.HeaviestPR(
                exerciseName: prExerciseNames[myPR.exerciseID] ?? "Exercise",
                weight: myPR.weight,
                reps: myPR.reps,
                previousBest: myPR.previousBest
            )
        }()

        let shareSummary = "\(kicker) — \(formatDuration(durationSeconds)), \(formatVolume(Units.fromPounds(totalVolume, to: unit))) \(unit.label), \(totalSets) sets."

        // Crew-wide kudos send model (documented in
        // 20260720000001_session_kudos.sql and SessionKudosRepository.send):
        // one row per OTHER participant per tap — never a self-kudos row.
        let recipientIDs = participants
            .map(\.participant.userID)
            .filter { $0 != selfID }

        return GroupRecapPayload(
            kicker: kicker,
            durationText: formatDuration(durationSeconds),
            subline: subline,
            totalLbsText: formatVolume(Units.fromPounds(totalVolume, to: unit)),
            setCount: totalSets,
            prCount: prCountByUser.values.reduce(0, +),
            leaderboard: leaderboard,
            heaviestPR: heaviestPR,
            shareSummary: shareSummary,
            recipientIDs: recipientIDs
        )
    }

    // MARK: - Pump Check context (spec 2026-07-27, P4)

    /// The composer's post-ready payload for THIS lifter: my non-penalty
    /// sets only (a pump check is personal — never the crew's data), frozen
    /// in first-logged order with per-set PR flags from my session PRs.
    /// HR comes from the same HealthKit backfill the solo recap uses — any
    /// watch brand whose companion app synced. Window anchor = now (this
    /// runs at the moment the recap sheet is presented).
    private func buildPumpCheckContext(session: WorkoutSession,
                                       sets: [SetLog]) async -> PumpCheckContext? {
        guard let selfID else { return nil }
        let mySets = sets.filter { $0.userID == selfID && !$0.isPenalty }
        guard !mySets.isEmpty else { return nil }

        var order: [UUID] = []
        var byExercise: [UUID: [SetLog]] = [:]
        for log in mySets {
            if byExercise[log.exerciseID] == nil { order.append(log.exerciseID) }
            byExercise[log.exerciseID, default: []].append(log)
        }
        // `bySession` is SELF-ONLY by personal_records' RLS (see
        // buildGroupRecapPayload's PR-fetch doc) — exactly right here: a
        // pump check flags MY PRs. Fetched locally; there is no stored
        // sessionPRs property on this view.
        let myPRs = (try? await PersonalRecordRepository.bySession(sessionID: session.id)) ?? []
        let prWeight: [UUID: Decimal] = Dictionary(
            myPRs.filter { $0.userID == selfID }.map { ($0.exerciseID, $0.weight) },
            uniquingKeysWith: max)
        let exercises = order.map { id -> PostSummary.ExerciseEntry in
            let ex = allExercises.first { $0.id == id }
            let setEntries = (byExercise[id] ?? [])
                .sorted { $0.setIndex < $1.setIndex }
                .map { log in
                    PostSummary.ExerciseEntry.SetEntry(
                        weightLbs: log.weight,
                        reps: log.reps,
                        isPR: !log.isFailed && log.weight != nil && log.weight == prWeight[id],
                        isFailed: log.isFailed)
                }
            return PostSummary.ExerciseEntry(
                name: ex?.name ?? "Exercise",
                equipment: ex?.equipment ?? "",
                sets: setEntries)
        }

        let duration: Int = {
            guard let start = session.startedAt, let end = session.completedAt else { return 0 }
            return Int(max(0, end.timeIntervalSince(start)))
        }()
        let myVolume = HealthKitBridge.totalVolume(from: mySets)

        var hrStats: (avg: Int, max: Int)?
        if let start = session.startedAt, let end = session.completedAt {
            hrStats = await HealthKitBridge.heartRateStats(start: start, end: end)
        }

        return PumpCheckContext(
            sessionID: session.id,
            summary: PostSummary(
                durationSeconds: duration,
                totalVolumeLbs: Decimal(myVolume),
                exercises: exercises),
            avgBpm: hrStats?.avg,
            maxBpm: hrStats?.max,
            includeHRDefault: ThemeStore.shared.shareHeartRate && hrStats != nil,
            windowStart: Date())
    }

    /// Hero total only — abbreviated ("24.6k"), matches SessionRecapView/
    /// CompletedSessionView's existing `formatVolume` verbatim.
    private func formatVolume(_ v: Double) -> String {
        v >= 1_000 ? String(format: "%.1fk", v / 1_000) : String(format: "%.0f", v)
    }

    /// Leaderboard rows only — full, comma-grouped number (proof-frame-08.png:
    /// "7,420 lbs", not an abbreviated "7.4k"). Verified against the same
    /// frame's hero "24.6k" TOTAL LBS figure: the split between abbreviated
    /// (hero) and full (rows) formatting is a deliberate reading of the
    /// proof, not an inconsistency.
    private func formatVolumeFull(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    /// Mirrors SessionRecapView.durationString verbatim (h>0 -> H:MM:SS, else MM:SS).
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - RecapData (Identifiable for sheet presentation)

private struct RecapData: Identifiable {
    let id = UUID()
    let session: WorkoutSession
    let sets: [SetLog]
    /// Non-nil for a genuine group session — routes the sheet to
    /// `GroupRecapView` (frame 8) instead of `SessionRecapView`. See
    /// `buildGroupRecapPayload`'s doc comment.
    let groupPayload: GroupRecapPayload?
    /// Pump Check (spec 2026-07-27, P4): built ONCE here so the composer's
    /// 1:00 window anchor survives sheet-content re-evaluation. Personal:
    /// the snapshot is MY sets only, never the crew's.
    let pumpCheck: PumpCheckContext?
}

/// Display-ready values for `GroupRecapView` — computed once in
/// `buildGroupRecapPayload` at the moment a group session completes.
private struct GroupRecapPayload {
    let kicker: String
    let durationText: String
    let subline: String
    let totalLbsText: String
    let setCount: Int
    let prCount: Int
    let leaderboard: [GroupRecapView.LeaderboardRow]
    let heaviestPR: GroupRecapView.HeaviestPR?
    let shareSummary: String
    let recipientIDs: [UUID]
}
