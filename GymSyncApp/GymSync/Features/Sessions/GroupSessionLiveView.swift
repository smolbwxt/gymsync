import SwiftUI
import UIKit

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
    /// Re-rack timers per slug (plate dock, composite v5): slug → when the
    /// plate is throwable again. Entries are cleared by tapSound's expiry
    /// task, which also restores the token's full opacity.
    @State private var soundCooldowns: [String: Date] = [:]
    /// Plates currently landed on the lifter card — capped at 5; each is
    /// removed when its own sound's duration ends (the 5s cap bounds it).
    @State private var landedPlates: [LandedPlate] = []

    /// One plate on the lifter card: which sound, who threw it.
    private struct LandedPlate: Identifiable, Equatable {
        let id = UUID()
        let slug: String
        let sender: String
        let durationMs: Int?
    }

    /// The plate mid-drag / mid-flight (phase-3 throw). Positions live in
    /// the "liveArena" coordinate space, which covers page AND chrome so a
    /// plate picked up from the dock can land on the lifter card.
    private struct PlateDragState: Equatable {
        let grabID = UUID()
        let sound: SoundboardSound
        var location: CGPoint
        var startLocation: CGPoint
        var isFlying = false
    }
    @State private var plateDrag: PlateDragState?
    /// The lifter card's frame in "liveArena" — the throw's landing target,
    /// reported via LifterCardFrameKey.
    @State private var lifterCardFrame: CGRect = .zero

    private struct LifterCardFrameKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    /// Pre-session est-1RM ceilings per (lifter, exercise) — fetched lazily
    /// when BOARD first opens, then cached for the session (the past doesn't
    /// change mid-workout; reopening the board picks up exercises that
    /// appeared since it last loaded).
    @State private var scoreBaselines: [UUID: [UUID: Decimal]] = [:]
    @State private var isLoadingBoard = false
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
    /// Success-haptic trigger for `.sensoryFeedback` — a count (not a Bool)
    /// so every logged set fires, including two in a row.
    @State private var logHapticTick        = 0
    /// REST | BOARD switch on the spectate page (composite v5): false =
    /// my recovery + prep, true = the crew board (crew HR grid until the
    /// phase-4 scoreboard lands).
    @State private var spectateShowsBoard   = false
    /// Session-local HR history behind YOUR RECOVERY — fed by the
    /// `.onChange(of: selfHeartRate?.bpm)` in `body`; pure math lives in
    /// RecoveryBuffer so the HRR numbers are unit-tested.
    @State private var recoveryBuffer       = RecoveryBuffer()
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

    // Redesign 2026-07-30: the local label dictionary is gone —
    // RPESwipeTrack.label is the ONE monotonic table app-wide (this copy and
    // LogSetSheet's previously disagreed with each other AND themselves:
    // 7 and 9 both read "Very hard").

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

    /// The presence trio — the SERVER's definition of "in the rotation"
    /// (advance_turn's next-picker, migration 20260802000001). Every
    /// rotation derivation below filters through this so the phone never
    /// disagrees with the database about who's next. Field bug 2026-07-31:
    /// a no-show read as NEXT here while the server handed the turn
    /// straight back to the lone present lifter, so the solo rest
    /// interlude never fired.
    private static let presentStates: Set<String> = ["online", "ready", "late"]

    /// `rotationOrder` filtered to participants the server would actually
    /// hand the turn to. The full `rotationOrder` remains for surfaces
    /// that deliberately show EVERYONE (crew grid, scoreboard).
    private var presentRotation: [(participant: SessionParticipant, profile: Profile)] {
        rotationOrder.filter {
            Self.presentStates.contains($0.participant.checkInState ?? "")
        }
    }

    private var currentTurnIndex: Int? {
        guard let turnID = liveSession.currentTurnUserID else { return nil }
        return presentRotation.firstIndex(where: { $0.participant.userID == turnID })
    }

    private var nextTurnUserID: UUID? {
        guard let idx = currentTurnIndex else { return nil }
        let n = presentRotation.count
        guard n > 1 else { return nil }
        return presentRotation[(idx + 1) % n].participant.userID
    }

    /// Ordered rotation tiles starting at the current lifter, wrapping circularly.
    private var rotationTiles: [(profile: Profile, userID: UUID, label: String)] {
        guard let idx = currentTurnIndex else { return [] }
        let n = presentRotation.count
        guard n > 0 else { return [] }
        return (0..<n).map { offset in
            let item = presentRotation[(idx + offset) % n]
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
              let myIdx = presentRotation.firstIndex(where: { $0.participant.userID == selfID }) else { return nil }
        let n = presentRotation.count
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
        RPESwipeTrack.label(for: rpe)
    }

    // MARK: - Init

    init(session: WorkoutSession, voicePersistsOnPop: Bool = false) {
        self.session = session
        self.voicePersistsOnPop = voicePersistsOnPop
        _liveSession = State(initialValue: session)
    }

    // MARK: - Redesigned my-turn fixed page (2026-07-30, final-proof.html)
    //
    // The my-turn state is a FIXED, non-scrolling page: fixed control heights,
    // ONE flexible child (the exercise card) absorbing device slack. Four
    // widgets — heart rate, load-the-bar, exercise (SETS|ROUTINE pager),
    // entry — over a compact pinned chrome (56pt sound rail with the compact
    // PTT mic + 64pt CTA). The spectating state keeps the old scroll layout
    // and old dock untouched (sister-page round).
    //
    // Recorded v1 deviations from final-proof (each deliberate, none silent):
    //   - CTA read-back omits "→ <next lifter>" (no verified next-name source
    //     in my-turn state yet).
    //   - Non-barbell exercises: the bar card hides and HR fills the row
    //     (the LAST TIME card is a follow-up).
    //   - ROUTINE page rows show logged-set counts without "/target" (per-
    //     exercise targets aren't wired here yet).
    //   - Stepper long-press auto-repeat deferred.
    //   - Transmit grows the chrome momentarily (PTTDockRow's hero is the
    //     non-compact experience; compact mode shows fill + rings only).

    /// SETS (0) | ROUTINE (1) — the exercise card's footer pager.
    @State private var turnWidgetPage = 0

    /// Vitals polish (user, 2026-07-30): tapping the ♥ card opens the
    /// existing pairing surface — the affordance the old screen lacked.
    @State private var showHRPairing = false
    /// One-shot prime, raised at session start when we have never asked.
    @State private var showHRPrime = false

    /// Solo-in-a-group-session rest (user round 3): when a log-and-pass
    /// hands the turn straight back to you (nobody else checked in), the
    /// my-turn screen "did nothing". Now it enters a REST interlude — the
    /// spectate layout with a START SET CTA — until the rest window ends
    /// or you cut it short. Nil = not resting.
    @State private var selfRotationRestUntil: Date?

    private var isInSelfRotationRest: Bool {
        guard let until = selfRotationRestUntil else { return false }
        return until > .now
    }

    /// TRANSIT flag for the current self-rotation rest window (2026-08):
    /// true when the set just logged completed its exercise, so the next
    /// set is a DIFFERENT station — the window was extended by
    /// `TransitWindow.seconds` and the chrome labels it TRANSIT instead of
    /// RESTING. Set alongside every `selfRotationRestUntil` assignment;
    /// only read while the interlude is active.
    @State private var selfRotationRestIsTransit = false

    /// Recovery-adaptive rest, group mirror of the solo wiring (owner
    /// 2026-08-12): window-open stamp + this session's end-of-rest HR
    /// drops. Applies to the SELF-ROTATION interlude only — crew-rotation
    /// "rest" is spectating others' turns, not a timed window.
    @State private var selfRotationRestStartedAt: Date?
    @State private var selfRotationRestDrops: [Int] = []
    /// Owner item 7: latest logged body weight (canonical lbs), stamped
    /// onto bodyweight-exercise sets. Fetched once in reload's task.
    @State private var turnLatestBodyWeightLbs: Decimal?

    /// Mirror of the solo captureRestDrop — called before every path that
    /// clears `selfRotationRestUntil`; no-op without a window or HR data.
    private func captureSelfRotationRestDrop() {
        guard selfRotationRestUntil != nil, let drop = recoveryBuffer.drop, drop > 0 else { return }
        selfRotationRestDrops.append(drop)
    }

    /// GO EARLY / +30s pill for the self-rotation interlude — same
    /// RestRecoveryMath judgment and house button anatomy as the solo rest
    /// hero. +30s re-arms its own guarded auto-clear (the original task's
    /// `until` guard goes stale on extension by design).
    @ViewBuilder
    private func selfRotationRecoveryPill(now: Date, start: Date, end: Date) -> some View {
        let total = end.timeIntervalSince(start)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(start) / total)) : 0
        let verdict = RestRecoveryMath.verdict(
            currentDrop: recoveryBuffer.drop,
            baseline: RestRecoveryMath.baseline(priorDrops: selfRotationRestDrops),
            progress: progress)
        switch verdict {
        case .ready:
            Button {
                captureSelfRotationRestDrop()
                selfRotationRestUntil = nil
            } label: {
                Text("RECOVERED — GO EARLY")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(0.8)
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 10, lipHeight: 4))
        case .lagging:
            Button {
                let extended = end.addingTimeInterval(30)
                selfRotationRestUntil = extended
                Task {
                    try? await Task.sleep(for: .seconds(max(0, extended.timeIntervalSinceNow)))
                    if selfRotationRestUntil == extended {
                        captureSelfRotationRestDrop()
                        selfRotationRestUntil = nil
                    }
                }
            } label: {
                Text("SLOW RECOVERY — +30s")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(0.8)
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 10, lipHeight: 4))
        case nil:
            EmptyView()
        }
    }

    // MARK: - Warm-up phase (2026-08, 20260803000004)

    /// One-shot re-render tick at the warm-up deadline. `isInWarmUp` reads
    /// live `Date()` per body evaluation (the `isInSelfRotationRest`
    /// idiom), so this only needs to force ONE re-render at the moment the
    /// clock alone would end the phase — vote and force-start end it
    /// through `liveSession` writes instead. Toggled by the
    /// `.task(id: warmupEndsAt)` wake-up below (LobbyView's
    /// `checkInWindowRefreshTick` precedent — never a polling Timer).
    @State private var warmupRefreshTick = false

    /// The effective lifting start the CLOCK enforces: `started_at +
    /// warmup_minutes`. Nil when no warm-up window exists.
    private var warmupEndsAt: Date? {
        guard liveSession.warmupMinutes > 0,
              let startedAt = liveSession.startedAt else { return nil }
        return startedAt.addingTimeInterval(TimeInterval(liveSession.warmupMinutes * 60))
    }

    /// The warm-up page renders INSTEAD of the turn arena while this
    /// holds: live session, a warm-up window configured, lifting not yet
    /// voted/forced open, and the window's clock still running.
    /// `warmup_minutes == 0` — every pre-feature session — can never
    /// enter here.
    private var isInWarmUp: Bool {
        // Read (but don't branch on) `warmupRefreshTick` so SwiftUI's
        // dependency tracking knows this property — and the page/chrome
        // switches on it — depends on the one-shot deadline toggle; the
        // real truth always comes from the fresh `Date()` comparison
        // (LobbyView's `canCheckIn` idiom, verbatim).
        let _ = warmupRefreshTick
        return liveSession.state == "in_progress"
            && liveSession.liftingStartedAt == nil
            && (warmupEndsAt.map { Date() < $0 } ?? false)
    }

    /// Prior-performance state (2026-07-30). ONE fetch feeds two features:
    /// the LAST TIME card (shown where a non-barbell exercise has no bar to
    /// load) and the prefill ladder's rep-goal rung, which needs the same
    /// history. Best-effort — absence just means fewer ladder rungs fire.
    @State private var priorSets: [SetLog] = []
    @State private var activeEnrollment: ProgramEnrollment?

    /// This user's qualifying history for the current exercise, oldest
    /// first: prior sessions plus anything already logged in this one.
    private var turnExerciseHistory: [SetLog] {
        guard let ex = currentExerciseForSheet else { return [] }
        return (priorSets + myTurnSets)
            .filter { $0.exerciseID == ex.id }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    /// The most recent completed set for the current exercise — the LAST
    /// TIME card's content. Excludes this session's own sets: "last time"
    /// means a previous outing, not the set you did four minutes ago.
    private var lastTimeSet: SetLog? {
        guard let ex = currentExerciseForSheet else { return nil }
        return priorSets
            .filter { $0.exerciseID == ex.id && !$0.isFailed && !$0.isPenalty }
            .max { $0.loggedAt < $1.loggedAt }
    }

    private var selfHeartRate: (bpm: Int, zone: HeartRateZone?)? {
        guard let selfID else { return nil }
        return heartRateFor(selfID)
    }

    /// Three-state vitals content (user ruling 2026-07-30):
    ///   .live(bpm)  — a signal is arriving
    ///   .undecided  — we have never asked; show "—", nothing is decided
    ///   .elapsed    — asked and answered (either way): show session time
    /// A dash means UNDECIDED, never "off" — see `HeartRatePrimeStore`.
    private enum TurnVitals { case live(Int), undecided, elapsed }

    private var turnVitalsState: TurnVitals {
        if let mine = selfHeartRate { return .live(mine.bpm) }
        return HeartRatePrimeStore.hasBeenAsked ? .elapsed : .undecided
    }

    private var myTurnActive: Bool {
        isMyTurn && !(participants.isEmpty && rosterLoadFailed) && !isInSelfRotationRest
    }

    /// My non-penalty sets for the current exercise, oldest first.
    /// `allSessionSets` (uncapped, logged_at ASC) — NEVER `feedSets` (30-row
    /// cap) and NEVER `log.setIndex` (derived from the capped array).
    private var myTurnSets: [SetLog] {
        guard let selfID, let ex = currentExerciseForSheet else { return [] }
        return allSessionSets.filter {
            $0.userID == selfID && $0.exerciseID == ex.id && !$0.isPenalty
        }
    }

    private var turnUnit: WeightUnit { ThemeStore.shared.weightUnit }

    /// Weight step in the DISPLAY unit: the smallest loadable pair.
    private var turnWeightStep: Decimal { turnUnit == .kg ? Decimal(2.5) : 5 }

    private func stepTurnWeight(_ direction: Int) {
        let current = Decimal.parseUserInput(logWeight) ?? 0
        let next = max(0, current + turnWeightStep * Decimal(direction))
        var rounded = Decimal()
        var value = next
        NSDecimalRound(&rounded, &value, 1, .plain)
        logWeight = rounded == 0 ? "" : "\(rounded)"
    }

    private func stepTurnReps(_ direction: Int) {
        let current = leadingInt(logReps) ?? 0
        logReps = "\(max(0, current + direction))"
    }

    private var myTurnFixedPage: some View {
        VStack(spacing: 0) {
            turnHeaderRail
            GSDivider()
            Color.clear.frame(height: 10)
            turnVitalsRow
            Color.clear.frame(height: 12)
            if showBarLoader {
                // The full shipped widget takes over the widget region in
                // place — nothing above or below moves, per the approved
                // loader-open frame.
                turnLoaderExpanded
            } else {
                turnExerciseCard
                    .frame(maxHeight: .infinity)
                Color.clear.frame(height: 12)
                turnEntryCard
            }
            Color.clear.frame(height: 8)
        }
        .padding(.horizontal, 0)
        .background(theme.bg)
    }

    // Header rail 44pt: ✕ · session clock · rule · routine name · voice/chat · count
    private var turnHeaderRail: some View {
        HStack(spacing: 0) {
            Button { showEndConfirmation = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave session")

            // One-clock rule: while the ♥ card carries session-elapsed (no
            // HR signal), the rail cedes its copy — the same value must
            // never render twice on one screen.
            if selfHeartRate != nil, let startedAt = liveSession.startedAt {
                Text(startedAt, style: .timer)
                    .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(theme.neutral700)
                    .accessibilityLabel("Session time")
                Rectangle().fill(theme.divider)
                    .frame(width: 2, height: 14)
                    .padding(.horizontal, 8)
            }

            Text((routineName ?? "Session").uppercased())
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.9)
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)

            Spacer(minLength: 8)

            if case .connecting = VoiceRoomService.shared.state {
                GSConnectingVoicePill()
            }
            if isVoiceConnected {
                Button { showVoiceMixerSheet = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { showChatSheet = true } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("\(participants.count)")
                    .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(theme.neutral700)
            .frame(width: 56, height: 44)
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
    }

    // Vitals 116pt: HR card 120w | bar strip. With no HR signal the card
    // shows the SESSION ELAPSED clock instead of a dash (user, 2026-07-30 —
    // "something useful there"), keeps the dim ♥ glyph as the "HR lives
    // here" marker, and taps through to pairing. One-clock rule: the header
    // rail drops its elapsed copy while the card carries it.
    private var turnVitalsRow: some View {
        HStack(spacing: 10) {
            Button { if selfHeartRate == nil { showHRPairing = true } } label: {
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selfHeartRate != nil ? theme.text.opacity(0.78) : theme.neutral700)
                    switch turnVitalsState {
                    case .live(let bpm):
                        Text("\(bpm)")
                            .font(GSFont.boldFixed(52).monospacedDigit())
                            .foregroundStyle(theme.text)
                    case .elapsed:
                        // "24:18" fits at 36pt; past the hour the scale
                        // factor absorbs "1:24:18" rather than clipping.
                        if let startedAt = liveSession.startedAt {
                            Text(startedAt, style: .timer)
                                .font(GSFont.boldFixed(36).monospacedDigit())
                                .foregroundStyle(theme.text.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        } else {
                            Text("—")
                                .font(GSFont.boldFixed(52))
                                .foregroundStyle(theme.neutral700)
                        }
                    case .undecided:
                        // Nothing decided yet — the dash is the honest state
                        // until the prime has been answered.
                        Text("—")
                            .font(GSFont.boldFixed(52))
                            .foregroundStyle(theme.neutral700)
                    }
                }
                .frame(width: isBarbellTurn ? 120 : nil)
                .frame(maxWidth: isBarbellTurn ? 120 : .infinity, maxHeight: .infinity)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selfHeartRate != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel({
                switch turnVitalsState {
                case .live: return "Heart rate"
                case .elapsed: return "Session time. Heart rate unavailable"
                case .undecided: return "Heart rate not set up"
                }
            }())
            .accessibilityValue({
                switch turnVitalsState {
                case .live(let bpm): return "\(bpm) beats per minute"
                case .elapsed, .undecided: return "Tap to set up a heart rate device"
                }
            }())

            // The slot NEVER goes empty: a barbell exercise gets the loader,
            // anything else gets LAST TIME. "Load the bar" answers "what do
            // I put on the bar"; for dumbbell/bodyweight work the same job
            // is answered by "what did I do last time". A collapsing row
            // would shift the whole page when the movement changes.
            if isBarbellTurn {
                turnBarCard
            } else {
                turnLastTimeCard
            }
        }
        .frame(height: 116)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showHRPairing) {
            NavigationStack { HeartRateMonitorView() }
        }
        .sheet(isPresented: $showHRPrime) { turnHRPrimeSheet }
        // Prior performance for the CURRENT exercise. Re-runs when the
        // exercise changes; both consumers (LAST TIME card, prefill ladder)
        // read the same state so they can never disagree.
        .task(id: currentExerciseForSheet?.id) {
            guard let selfID, let ex = currentExerciseForSheet else { return }
            // exerciseHistory already excludes failed/penalty and orders
            // newest-first — the same qualifying filter the rep-goal
            // projection and program baselines use.
            priorSets = (try? await SessionRepository.exerciseHistory(
                userID: selfID, exerciseID: ex.id, limit: 30)) ?? []
            if activeEnrollment == nil {
                activeEnrollment = try? await ProgramRepository.active()
            }
        }
        .task {
            // Ask ONCE, in context — at the moment the feature is about to
            // deliver value, not during onboarding. iOS shows the HealthKit
            // dialog exactly once ever; asking before the user has seen a
            // live session is how that single chance gets spent on a "no"
            // they can only reverse in Settings.
            guard !HeartRatePrimeStore.hasBeenAsked,
                  selfHeartRate == nil,
                  !ThemeStore.shared.shareHeartRate else { return }
            // A beat after the screen settles, so it reads as an offer
            // about THIS session rather than a launch interruption.
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, !HeartRatePrimeStore.hasBeenAsked else { return }
            showHRPrime = true
        }
    }

    /// The one-shot prime. Deliberately NOT a system prompt: this is the
    /// pre-permission explanation, and only "Show my heart rate" goes on to
    /// raise the real HealthKit/Bluetooth dialogs. Either button marks the
    /// question answered — "Not now" is a decision, and the ♥ card remains
    /// the manual route back for anyone who changes their mind.
    private var turnHRPrimeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.accent)
                .padding(.top, 8)

            Text("Show your heart rate?")
                .font(GSFont.bold(24, relativeTo: .title2))
                .foregroundStyle(theme.text)

            Text("Your Apple Watch or a chest strap can show your live heart rate here, and share it with the crew you're training with. You can turn it off any time in the You tab.")
                .font(GSFont.body(15, relativeTo: .body))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Show my heart rate") {
                HeartRatePrimeStore.markAsked()
                showHRPrime = false
                // Turning sharing ON is what makes an already-paired Apple
                // Watch start sampling (ThemeStore.onShareHeartRateChange
                // pushes session state to the Watch). Strap users continue
                // into pairing from the ♥ card.
                Task { await ThemeStore.shared.enableHeartRateSharing() }
            }
            .buttonStyle(GSPrimaryButtonStyle())

            Button("Not now") {
                HeartRatePrimeStore.markAsked()
                showHRPrime = false
            }
            .buttonStyle(GSSecondaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .presentationDetents([.height(400)])
    }

    private var isBarbellTurn: Bool {
        currentExerciseForSheet?.equipment.lowercased() == "barbell"
    }

    /// LAST TIME — the non-barbell twin of the loader card. Same 116pt slot,
    /// same "give me my number before I start" job, different source.
    private var turnLastTimeCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAST TIME")
                .font(GSFont.bold(19, relativeTo: .body))
                .tracking(0.7)
                .foregroundStyle(theme.text.opacity(0.78))
            if let last = lastTimeSet {
                Text("\(last.weight.map { Units.format(pounds: $0, unit: turnUnit, rounded: false, includeUnit: false) } ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
                    .font(GSFont.boldFixed(30).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(turnLastTimeMeta(last))
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
            } else {
                // First outing on this movement — quietly motivating, and
                // honest: there is nothing to report, not a hidden failure.
                Text("FIRST TIME")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(theme.neutral700)
                Spacer(minLength: 2)
                Text("NO PREVIOUS SETS")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral700)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// "RPE 8 · 6 DAYS AGO" — whichever parts are real.
    private func turnLastTimeMeta(_ log: SetLog) -> String {
        var parts: [String] = []
        if let rpe = log.rpe {
            parts.append("RPE \(NSDecimalNumber(decimal: rpe).intValue)")
        }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: log.loggedAt),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: parts.append("TODAY")
        case 1:    parts.append("YESTERDAY")
        default:   parts.append("\(days) DAYS AGO")
        }
        return parts.joined(separator: " · ")
    }

    /// Bar/plate config shared by the strip and the expanded widget —
    /// identical derivation to the (spectating-only) `barLoaderCard`.
    private var turnBarConfig: (unit: WeightUnit, plates: [Decimal], barInUnit: Decimal, prefill: Decimal?, targetInUnit: Decimal) {
        let unit = turnUnit
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
        // Prefill ladder (user, 2026-07-30: "prepopulated with what the
        // estimated weight should be based on rep goal and campaign
        // modifier"): campaign % → routine target → inverse-Epley rep goal
        // → last set → nothing. See WorkingWeight for the full contract;
        // it never invents a number.
        let prefill: Decimal? = {
            guard let ex = currentExerciseForSheet else { return nil }
            let history = turnExerciseHistory
            return WorkingWeight.suggest(
                exerciseID: ex.id,
                targetReps: currentRoutineExercise?.targetReps.flatMap { leadingInt($0) },
                routineTargetPounds: currentRoutineExercise?.targetWeight
                    .flatMap { Decimal(string: $0) },
                history: history,
                lastSetPounds: history.last(where: { !$0.isFailed })?.weight,
                enrollment: activeEnrollment,
                // Getting-started anchor (owner 2026-08-12) — read live off
                // ThemeStore per the shareHeartRate caching-bug precedent.
                seededPounds: LiftAnchorMath.seedPounds(
                    for: ex.slug,
                    anchors: ThemeStore.shared.liftAnchors)
            )?.pounds
        }()
        let targetInUnit = prefill.map { Units.fromPounds($0, to: unit) } ?? barInUnit
        return (unit, plates, barInUnit, prefill, targetInUnit)
    }

    private var turnBarCard: some View {
        let cfg = turnBarConfig
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { showBarLoader.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOAD THE BAR")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(theme.text.opacity(0.78))
                Text(showBarLoader ? "CLOSE" : "TAP HERE")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(showBarLoader ? theme.accent : theme.neutral700)
                Spacer(minLength: 4)
                // The shipped illustration when plates are on. With nothing
                // suggested, an EMPTY BAR renders instead of nothing — the
                // user's 2026-07-27 ruling ("an empty bar should still be
                // displayed"), which the earlier suppression over-applied
                // (caught on device 2026-07-30: "the bar is missing").
                // Card-level drawing only; GSBarLoaderMini stays untouched.
                if cfg.targetInUnit > cfg.barInUnit {
                    // The shaft continues through the card (user: "mimic the
                    // bar in the expanded view") — plates at the left, bar
                    // running the full width, exactly like the full loader.
                    HStack(spacing: 1.5) {
                        GSBarLoaderMini(target: cfg.targetInUnit, barWeight: cfg.barInUnit,
                                        plates: cfg.plates, unit: cfg.unit)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.neutral500.opacity(0.55))
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // Collar + shaft only — right collar gone (user,
                    // 2026-07-30: "eliminate the far right collar").
                    HStack(spacing: 1.5) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.neutral500)
                            .frame(width: 4, height: 16)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.neutral500.opacity(0.55))
                            .frame(height: 4)
                    }
                    .frame(height: 40)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                showBarLoader ? theme.accent : theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Loader open: the full shipped BarLoaderWidget owns the whole widget
    /// region; dialled weight lands in the entry field in the display unit.
    private var turnLoaderExpanded: some View {
        let cfg = turnBarConfig
        return ScrollView {
            BarLoaderWidget(initialPounds: cfg.prefill,
                            onEnteredPoundsChange: { pounds in
                                guard let pounds else { return }
                                logWeight = Units.format(pounds: pounds, unit: cfg.unit,
                                                         rounded: false, includeUnit: false)
                            })
                .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    // Exercise card: title, borderless set columns + SET LEFT, SETS|ROUTINE pager.
    private var turnExerciseCard: some View {
        VStack(spacing: 0) {
            HStack {
                // Owner 2026-08-12: the name is an extruded button — tap
                // opens the exercise page (video + history) as a sheet.
                // (Round-1 wiring landed on the legacy scroll layout's
                // spotlight card, which only renders in the roster-failure
                // state — THIS is the card actually on screen.)
                if let ex = currentExerciseForSheet {
                    Button {
                        exerciseDetailSheet = ex
                    } label: {
                        HStack(spacing: 6) {
                            Text(ex.name)
                                .font(GSFont.bold(20, relativeTo: .title3))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 10, lipHeight: 3))
                } else {
                    Text("Exercise")
                        .font(GSFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.top, 12)

            if turnWidgetPage == 0 { turnSetsPage } else { turnRoutinePage }

            GSDivider().padding(.horizontal, -14)
            HStack(spacing: 0) {
                turnPagerTab("SETS", index: 0)
                turnPagerTab("ROUTINE", index: 1)
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func turnPagerTab(_ label: String, index: Int) -> some View {
        Button { turnWidgetPage = index } label: {
            Text(label)
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(1.0)
                .foregroundStyle(turnWidgetPage == index ? theme.text : theme.neutral700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if turnWidgetPage == index {
                        Capsule().fill(theme.text)
                            .frame(height: 2)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// SETS page: logged columns (horizontal scroll past 4) · rule · N SET LEFT.
    private var turnSetsPage: some View {
        let sets = myTurnSets
        let target = currentRoutineExercise?.targetSets
        let remaining = target.map { max(0, $0 - sets.count - 1) }
        return HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { pair in
                        turnSetColumn(pair.element,
                                      brightness: pair.offset == sets.count - 1 ? 0.78 : nil)
                        Rectangle().fill(theme.divider)
                            .frame(width: 1)
                            .padding(.vertical, 15)
                    }
                    turnCurrentColumn
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(theme.neutral500)
                .frame(width: 1)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)

            VStack(spacing: 8) {
                if remaining == 0 {
                    // Owner 2026-08-13: the last set is a moment, not a
                    // zero — mirrors the solo card.
                    Text("LAST SET")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                    Text("GO TO FAILURE!")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                        .multilineTextAlignment(.center)
                } else {
                    Text(remaining.map { "\($0)" } ?? "\(sets.count)")
                        .font(GSFont.boldFixed(48).monospacedDigit())
                        .foregroundStyle(theme.text)
                    Text(remaining != nil
                         ? (remaining == 1 ? "SET LEFT" : "SETS LEFT")
                         : "LOGGED")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(theme.neutral700)
                }
            }
            .frame(width: 96)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 6)
    }

    private func turnSetColumn(_ log: SetLog, brightness: CGFloat?) -> some View {
        let color: Color = brightness != nil ? theme.text.opacity(0.78) : theme.neutral700
        return VStack(spacing: 8) {
            Text(log.weight.map { Units.format(pounds: $0, unit: turnUnit, rounded: false, includeUnit: false) } ?? "—")
                .font(GSFont.boldFixed(28).monospacedDigit())
                .foregroundStyle(color)
            Text("× \(log.reps.map { "\($0)" } ?? "—")")
                .font(GSFont.boldFixed(16).monospacedDigit())
                .foregroundStyle(color)
            if log.isFailed {
                Text("FAIL")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(theme.text.opacity(0.78), lineWidth: 1))
            } else if let rpe = log.rpe {
                Text("RPE \(NSDecimalNumber(decimal: rpe).intValue)")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .frame(width: 72)
    }

    /// The live column mirrors the entry card and carries the accent underline.
    private var turnCurrentColumn: some View {
        VStack(spacing: 8) {
            Text(logWeight.isEmpty ? "—" : logWeight)
                .font(GSFont.boldFixed(30).monospacedDigit())
                .foregroundStyle(theme.text)
            Text("× \(leadingInt(logReps).map { "\($0)" } ?? "—")")
                .font(GSFont.boldFixed(17).monospacedDigit())
                .foregroundStyle(theme.text)
            Text(logIsFailed ? "FAIL" : "RPE \(Int(logRPE))")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .foregroundStyle(theme.text.opacity(0.78))
        }
        .frame(width: 72)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Capsule().fill(theme.accent)
                .frame(width: 44, height: 3)
                .padding(.bottom, 2)
        }
    }

    /// ROUTINE page: every session exercise, logged count, underline on current.
    private var turnRoutinePage: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(allExercises.enumerated()), id: \.element.id) { index, ex in
                    let isCurrent = ex.id == currentExerciseForSheet?.id
                    let count = allSessionSets.filter {
                        $0.userID == selfID && $0.exerciseID == ex.id && !$0.isPenalty
                    }.count
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(isCurrent ? theme.accent : theme.neutral500)
                            .frame(width: 20, alignment: .leading)
                        Text(ex.name)
                            .font(isCurrent ? GSFont.bold(17, relativeTo: .body)
                                            : GSFont.body(15, relativeTo: .subheadline))
                            .foregroundStyle(isCurrent ? theme.text : theme.neutral700)
                            .lineLimit(1)
                        Spacer()
                        Text("\(count)")
                            .font(GSFont.bold(isCurrent ? 17 : 14, relativeTo: .subheadline).monospacedDigit())
                            .foregroundStyle(isCurrent ? theme.text : theme.neutral700)
                    }
                    .frame(minHeight: isCurrent ? 30 : 22)
                    .overlay(alignment: .bottom) {
                        if isCurrent {
                            Capsule().fill(theme.accent)
                                .frame(height: 3)
                                .padding(.leading, 30)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // Entry card 220pt: SET N OF M + turn clock · labels · steppers · RPE track.
    private var turnEntryCard: some View {
        let setNumber = myTurnSets.count + 1
        let target = currentRoutineExercise?.targetSets
        let targetReps = currentRoutineExercise?.targetReps
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(setNumber)")
                    .font(GSFont.boldFixed(24).monospacedDigit())
                    .foregroundStyle(theme.accent)
                if let target {
                    Text("OF \(target)")
                        .font(GSFont.bold(15, relativeTo: .subheadline))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                        .padding(.leading, 7)
                }
                Spacer()
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral700)
                    .padding(.trailing, 5)
                if let ts = liveSession.currentTurnStartedAt {
                    Text(ts, style: .timer)
                        .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                        .foregroundStyle(theme.text.opacity(0.78))
                } else {
                    Text("—")
                        .font(GSFont.bold(17, relativeTo: .body))
                        .foregroundStyle(theme.neutral700)
                }
            }
            .frame(height: 26)

            Color.clear.frame(height: 10)
            HStack(spacing: 0) {
                Text("WEIGHT · \(turnUnit.label.uppercased())")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .frame(width: 229, alignment: .leading)
                Text(targetReps.map { "REPS · \($0)" } ?? "REPS")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
            }
            .frame(height: 14)

            Color.clear.frame(height: 4)
            // No step labels, no inner hairlines (user, 2026-07-30): the
            // "5" details and four rules were spending the exact pixels a
            // two-digit rep count needs at fixed 36pt — it truncated to "…".
            // Signs and numbers only; one divider between the two fields.
            HStack(spacing: 0) {
                turnStepButton("minus", detail: nil) { stepTurnWeight(-1) }
                    .frame(width: 44)
                Text(logWeight.isEmpty ? "—" : logWeight)
                    .font(GSFont.boldFixed(36).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .frame(width: 96)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                turnStepButton("plus", detail: nil) { stepTurnWeight(1) }
                    .frame(width: 44)

                Rectangle().fill(theme.neutral500)
                    .frame(width: 1, height: 44)
                    .padding(.horizontal, 8)

                turnStepButton("minus", detail: nil) { stepTurnReps(-1) }
                    .frame(width: 44)
                Text(leadingInt(logReps).map { "\($0)" } ?? "—")
                    .font(GSFont.boldFixed(36).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                turnStepButton("plus", detail: nil) { stepTurnReps(1) }
                    .frame(width: 44)
            }
            .frame(height: 56)

            Color.clear.frame(height: 8)
            Text("RPE")
                .font(GSFont.bold(18, relativeTo: .body))
                .tracking(1.2)
                .foregroundStyle(logIsFailed ? theme.text : theme.text.opacity(0.78))
                .frame(height: 20)

            Color.clear.frame(height: 6)
            RPESwipeTrack(value: $logRPE, isFailed: $logIsFailed, theme: theme)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral700.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private var stepperRule: some View {
        Rectangle().fill(theme.neutral700.opacity(0.55)).frame(width: 1, height: 30)
    }

    private func turnStepButton(_ glyph: String, detail: String?, action: @escaping () -> Void) -> some View {
        TurnAutoRepeatButton(glyph: glyph, detail: detail, theme: theme, step: action)
    }

    // Pinned chrome 152pt: sound rail (favourites + ALL + compact mic) + CTA.
    private var turnChrome: some View {
        VStack(spacing: 0) {
            GSDivider()
            Color.clear.frame(height: 6)
            if burpeesRemaining > 0 {
                burpeeDebtStrip
                Color.clear.frame(height: 6)
            }
            turnSoundRail
            Color.clear.frame(height: 6)

            // 3D pass (2026-08): the gs3D style owns the fill (accent face,
            // or the theme's raised face for a failed set) + the 7pt lip;
            // the failed look keeps its outline as a label overlay, landing
            // exactly on the face rect. 57pt face + lip = the prior 64pt
            // footprint.
            Button { commitInlineLog() } label: {
                ZStack {
                    if logIsFailed {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(theme.text, lineWidth: 1.5)
                    }
                    VStack(spacing: 2) {
                        if isLoggingSet {
                            Text("LOGGING…")
                                .font(GSFont.bold(17, relativeTo: .body))
                                .tracking(0.9)
                        } else {
                            Text(logIsFailed ? "LOG FAIL & PASS" : "LOG SET & PASS")
                                .font(GSFont.bold(17, relativeTo: .body))
                                .tracking(0.9)
                            Text(turnCTAReadback)
                                .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                                .opacity(0.8)
                        }
                    }
                    .foregroundStyle(logIsFailed ? theme.text : theme.bg)
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(logIsFailed ? theme.text : theme.bg)
                            .padding(.trailing, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 57)
            }
            .buttonStyle(.gs3D(face: logIsFailed ? theme.raised3DFace : theme.accent,
                               lip: logIsFailed ? theme.raised3DLip : nil,
                               cornerRadius: 16))
            .disabled(isLoggingSet || (leadingInt(logReps) == nil && !logIsFailed))
            .padding(.horizontal, 16)
            Color.clear.frame(height: 10)
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

    private var turnCTAReadback: String {
        if leadingInt(logReps) == nil && !logIsFailed { return "ENTER REPS TO LOG" }
        let weight = logWeight.isEmpty ? "—" : logWeight
        let reps = leadingInt(logReps).map { "\($0)" } ?? "—"
        let rpe = logIsFailed ? "RPE 10 · MISS" : "RPE \(Int(logRPE))"
        return "\(weight) \(turnUnit.label) × \(reps) · \(rpe)"
    }

    /// The plate dock (composite v5), shared verbatim by turnChrome and
    /// spectateChrome: up to four racked plates + ALL + compact mic.
    private var turnSoundRail: some View {
        Group {
            HStack(spacing: 8) {
                ForEach(dockSounds.prefix(4)) { sound in
                    dockPlate(for: sound)
                }
                Button { showSoundLibrary = true } label: {
                    Circle()
                        .strokeBorder(theme.neutral700, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text("ALL")
                                .font(GSFont.bold(9, relativeTo: .caption2))
                                .tracking(0.8)
                                .foregroundStyle(theme.neutral700)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open sound library")

                Spacer(minLength: 4)

                if isVoiceEligible {
                    PTTDockRow(otherParticipantNames: otherParticipantNames, compact: true)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Sister page: spectating (2026-07-30)
    // The my-turn page's fixed geometry with the my-turn organs swapped:
    // the entry card and CTA give way to the CURRENT LIFTER card and the
    // CREW grid — this is where everyone's heart rates live, per the user
    // ruling ("we can view the crew heart rates when it's not our turn").
    // Header rail and vitals row are the my-turn builders, reused verbatim,
    // so paging between states never moves the top of the screen.

    private var spectateActive: Bool {
        (!isMyTurn || isInSelfRotationRest)
            && !(participants.isEmpty && rosterLoadFailed)
            && liveSession.currentTurnUserID != nil
    }

    // Composite v5 (2026-07-30): the lifter card is the platform up top;
    // the middle band is REST (my recovery + prep) or BOARD (the crew
    // grid, until the phase-4 scoreboard); the widget row (rotation +
    // REST|BOARD switch) sits above the chrome. The my-turn vitals row is
    // gone from this page — the recovery card carries my HR three-state
    // and the prep card carries my bar.
    private var spectateFixedPage: some View {
        VStack(spacing: 0) {
            turnHeaderRail
            GSDivider()
            Color.clear.frame(height: 10)
            if showBarLoader {
                turnLoaderExpanded
            } else {
                spectateLifterCard
                Color.clear.frame(height: 12)
                if spectateShowsBoard {
                    spectateBoardCard
                        .frame(maxHeight: .infinity)
                } else {
                    spectateRecoveryCard
                    Color.clear.frame(height: 12)
                    barLoaderCard
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                }
                Color.clear.frame(height: 12)
                spectateWidgetRow
            }
            Color.clear.frame(height: 8)
        }
        .background(theme.bg)
    }

    /// Who has the bar right now — the platform (composite v5). Name at
    /// display size, their live HR big, set number, turn clock, and their
    /// last logged set as the honest "what's on the bar" (a set mid-lift
    /// is unknowable until they log it). Reaction plates land on this card
    /// in the next phase.
    private var spectateLifterCard: some View {
        let lifter = rotationOrder.first { $0.participant.userID == liveSession.currentTurnUserID }
        let lastSet = currentLifterLastSet
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(lifter?.profile.username ?? "—")
                    .font(GSFont.bold(26, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
                Text("SET \(currentTurnSetNumber)")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
            }
            Color.clear.frame(height: 12)
            HStack(alignment: .center) {
                if let id = lifter?.participant.userID, let hr = heartRateFor(id) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.text.opacity(0.78))
                        Text("\(hr.bpm)")
                            .font(GSFont.boldFixed(44).monospacedDigit())
                            .foregroundStyle(theme.text)
                    }
                } else {
                    Text("—")
                        .font(GSFont.boldFixed(44))
                        .foregroundStyle(theme.neutral700)
                }
                Spacer()
                if let s = lastSet, let w = s.weight {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Units.format(pounds: w, unit: turnUnit, rounded: false, includeUnit: false)) × \(s.reps ?? 0)")
                            .font(GSFont.bold(22, relativeTo: .title3).monospacedDigit())
                            .foregroundStyle(theme.text)
                        Text("LAST SET · \(turnUnit.label.uppercased())")
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral700)
                    }
                }
            }
            Color.clear.frame(height: 10)
            HStack {
                // Owner 2026-08-12: spectate's exercise name opens the
                // exercise page too — small extruded chip, same contract as
                // the my-turn card's title button.
                if let ex = currentExerciseForSheet {
                    Button {
                        exerciseDetailSheet = ex
                    } label: {
                        HStack(spacing: 5) {
                            Text(ex.name)
                                .font(GSFont.bold(13, relativeTo: .footnote))
                                .tracking(0.5)
                                .foregroundStyle(theme.neutral700)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 8, lipHeight: 2))
                }
                Spacer()
                if let ts = liveSession.currentTurnStartedAt {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                    Text(ts, style: .timer)
                        .font(GSFont.bold(14, relativeTo: .subheadline).monospacedDigit())
                        .foregroundStyle(theme.text.opacity(0.78))
                }
            }
        }
        .padding(14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            // Thrown weight lands here (composite v5) — deliberately ON
            // TOP of the card's bottom row: plates are transient (≤5s,
            // the sound cap) and the pile IS the point.
            if !landedPlates.isEmpty {
                HStack(spacing: 6) {
                    ForEach(landedPlates) { plate in
                        landedPlateChip(plate)
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Capsule().fill(theme.accent)
                .frame(width: 44, height: 3)
                .padding(.leading, 14)
        }
        .padding(.horizontal, 16)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: LifterCardFrameKey.self,
                                       value: geo.frame(in: .named("liveArena")))
            }
        )
    }

    /// One landed plate: mini class-colored disc + sender tag.
    private func landedPlateChip(_ plate: LandedPlate) -> some View {
        let cls = PlateClass.forDuration(ms: plate.durationMs)
        return HStack(spacing: 4) {
            Circle()
                .strokeBorder(GSBarLoader.plateColor(cls.denomination, unit: .lbs), lineWidth: 3)
                .background(Circle().fill(theme.bg))
                .frame(width: 20, height: 20)
            Text(plate.sender)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.surface))
        .overlay(Capsule().strokeBorder(theme.neutral500.opacity(0.5), lineWidth: 1))
        .transition(.scale(scale: 0.3).combined(with: .opacity))
    }

    /// The current lifter's most recent logged set for the exercise in
    /// play — the honest "what's on the bar". Reads the UNCAPPED session
    /// array, never the 30-row feed (the mySetCount lesson).
    private var currentLifterLastSet: SetLog? {
        guard let lifterID = liveSession.currentTurnUserID,
              let ex = currentExerciseForSheet else { return nil }
        return allSessionSets
            .filter { $0.userID == lifterID && $0.exerciseID == ex.id && !$0.isPenalty }
            .max(by: { $0.loggedAt < $1.loggedAt })
    }

    /// YOUR RECOVERY — live HR falling in real time while you rest, with
    /// the peak-to-now drop and a session-local sparkline. Three-state
    /// like the my-turn vitals card: dash (never asked) / session-elapsed
    /// (asked, no strap) / live. The rest countdown deliberately does NOT
    /// render here — the chrome's START SET CTA already carries it (the
    /// one-clock rule).
    private var spectateRecoveryCard: some View {
        Button { if selfHeartRate == nil { showHRPairing = true } } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YOUR RECOVERY")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                    if selfHeartRate != nil, let drop = recoveryBuffer.drop, drop > 0 {
                        Text("−\(drop)")
                            .font(GSFont.bold(14, relativeTo: .subheadline).monospacedDigit())
                            .foregroundStyle(theme.text.opacity(0.78))
                    }
                }
                Spacer(minLength: 6)
                HStack(alignment: .bottom, spacing: 10) {
                    if let hr = selfHeartRate {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.text.opacity(0.78))
                            Text("\(hr.bpm)")
                                .font(GSFont.boldFixed(36).monospacedDigit())
                                .foregroundStyle(theme.text)
                        }
                        Spacer()
                        recoverySparkline
                    } else if HeartRatePrimeStore.hasBeenAsked, let startedAt = liveSession.startedAt {
                        Text(startedAt, style: .timer)
                            .font(GSFont.boldFixed(30).monospacedDigit())
                            .foregroundStyle(theme.text.opacity(0.78))
                        Spacer()
                    } else {
                        Text("—")
                            .font(GSFont.boldFixed(36))
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selfHeartRate != nil)
        .padding(.horizontal, 16)
    }

    /// 22-bar bpm history — the same bar language as the sound waveforms.
    @ViewBuilder
    private var recoverySparkline: some View {
        let bars = recoveryBuffer.sparkline(barCount: 22)
        if !bars.isEmpty {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { pair in
                    Capsule().fill(theme.text.opacity(0.45))
                        .frame(width: 3, height: max(3, CGFloat(pair.element) * 40))
                }
            }
            .frame(height: 42, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }

    /// ROTATION card + REST|BOARD switch — the widget row above the chrome.
    private var spectateWidgetRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ROTATION")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    ForEach(Array(presentRotation.enumerated()), id: \.element.participant.userID) { index, entry in
                        let isLifting = entry.participant.userID == liveSession.currentTurnUserID
                        let isMe = entry.participant.userID == selfID
                        VStack(spacing: 5) {
                            GSInitialsAvatar(name: entry.profile.username,
                                             avatarURL: entry.profile.avatarURL, size: 30)
                                .overlay {
                                    if isLifting {
                                        Circle().strokeBorder(theme.accent, lineWidth: 2)
                                    } else if isMe {
                                        Circle().strokeBorder(theme.neutral500,
                                            style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                                    }
                                }
                            Text(spectateSlotLabel(index: index))
                                .font(GSFont.bold(9, relativeTo: .caption2))
                                .tracking(0.8)
                                .foregroundStyle(isLifting || isMe ? theme.text.opacity(0.78) : theme.neutral700)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 8) {
                spectateModeSeg("REST", active: !spectateShowsBoard) { spectateShowsBoard = false }
                spectateModeSeg("BOARD", active: spectateShowsBoard) { spectateShowsBoard = true }
            }
            .padding(8)
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .frame(height: 100)
        .padding(.horizontal, 16)
    }

    /// One stacked pill of the REST|BOARD switch — the lbs|kg segmented
    /// idiom turned vertical.
    private func spectateModeSeg(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(label)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(0.9)
                .foregroundStyle(active ? theme.bg : theme.neutral700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(active ? theme.accent : Color.clear)
                .cornerRadius(11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// NOW / NEXT / YOU / ordinals, relative to whoever holds the bar —
    /// over the PRESENT rotation, matching the server's next-picker.
    private func spectateSlotLabel(index: Int) -> String {
        let entry = presentRotation[index]
        let lifterIdx = presentRotation.firstIndex {
            $0.participant.userID == liveSession.currentTurnUserID
        } ?? 0
        let n = presentRotation.count
        let rel = n == 0 ? 0 : (index - lifterIdx + n) % n
        if rel == 0 { return "NOW" }
        if entry.participant.userID == selfID { return "YOU" }
        if rel == 1 { return "NEXT" }
        let ordinals = ["3RD", "4TH", "5TH", "6TH", "7TH", "8TH"]
        return rel - 2 < ordinals.count ? ordinals[rel - 2] : "\(rel + 1)TH"
    }

    /// Everyone in the rotation, with live bpm where it exists. The HR slot
    /// is held (an em-dash, never a collapse) so tiles don't reflow as
    /// signals come and go. The current lifter carries the accent underline
    /// — the same "live" mark as everywhere else.
    private var spectateCrewGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(rotationOrder, id: \.participant.userID) { entry in
                    let isLifting = entry.participant.userID == liveSession.currentTurnUserID
                    let isMe = entry.participant.userID == selfID
                    let hr = heartRateFor(entry.participant.userID)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isMe ? "You" : entry.profile.username)
                            .font(GSFont.bold(15, relativeTo: .subheadline))
                            .foregroundStyle(isLifting ? theme.text : theme.text.opacity(0.78))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(hr != nil ? theme.text.opacity(0.78) : theme.neutral500)
                            Text(hr.map { "\($0.bpm)" } ?? "—")
                                .font(GSFont.boldFixed(22).monospacedDigit())
                                .foregroundStyle(hr != nil ? theme.text : theme.neutral700)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomLeading) {
                        if isLifting {
                            Capsule().fill(theme.accent)
                                .frame(width: 36, height: 3)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    /// Spectating chrome: the shared sound rail over the rotation hint —
    /// no CTA, because there is nothing to commit while you wait.
    private var spectateChrome: some View {
        VStack(spacing: 0) {
            GSDivider()
            Color.clear.frame(height: 6)
            if burpeesRemaining > 0 {
                burpeeDebtStrip
                Color.clear.frame(height: 6)
            }
            turnSoundRail
            Color.clear.frame(height: 6)
            if isInSelfRotationRest {
                // Recovery-adaptive pill (owner 2026-08-12, group mirror):
                // judged against this session's own median end-of-rest
                // drop; silent without HR or a 2-rest baseline.
                if let until = selfRotationRestUntil, let restStart = selfRotationRestStartedAt {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        selfRotationRecoveryPill(now: context.date, start: restStart, end: until)
                    }
                    Color.clear.frame(height: 6)
                }
                // Resting between your own sets — cut it short any time.
                // 3D pass (2026-08): accent gs3D face, 57pt + 7pt lip =
                // the prior 64pt CTA footprint.
                Button {
                    captureSelfRotationRestDrop()
                    selfRotationRestUntil = nil
                } label: {
                    VStack(spacing: 2) {
                        Text("START SET")
                            .font(GSFont.bold(17, relativeTo: .body))
                            .tracking(0.9)
                        if let until = selfRotationRestUntil {
                            HStack(spacing: 4) {
                                // TRANSIT (2026-08): an exercise-change
                                // window announces the station move.
                                Text(selfRotationRestIsTransit
                                     ? "TRANSIT · SET UP YOUR STATION" : "RESTING")
                                    .font(GSFont.bold(11, relativeTo: .caption2))
                                Text(timerInterval: .now...until, countsDown: true)
                                    .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                            }
                            .opacity(0.8)
                        }
                    }
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 57)
                }
                .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 16))
                .padding(.horizontal, 16)
                Color.clear.frame(height: 10)
            } else if let hint = upcomingTurnHint {
                Text(hint)
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .padding(.horizontal, 16)
                Color.clear.frame(height: 10)
            }
        }
        .background(theme.bg)
    }

    // MARK: - Warm-up page (2026-08 warm-up phase)

    /// The fixed-page shell (header rail + divider, the same top chrome as
    /// the my-turn/spectate pages so entering lifting never moves the top
    /// of the screen) around the shared `WarmUpPhaseView`. All session
    /// plumbing stays HERE — the phase view takes plain values + closures
    /// by design (see its own header).
    private var warmUpPage: some View {
        VStack(spacing: 0) {
            turnHeaderRail
            GSDivider()
            WarmUpPhaseView(
                mode: .group,
                countdownEndsAt: warmupEndsAt ?? Date(),
                members: presentRotation.map { entry in
                    WarmUpPhaseView.Member(
                        id: entry.participant.userID,
                        name: entry.profile.username,
                        avatarURL: entry.profile.avatarURL,
                        isReady: entry.participant.warmupReady
                    )
                },
                isOrganizer: isOrganizer,
                myReady: myParticipant?.warmupReady ?? false,
                onReady: { Task { await voteWarmupReady() } },
                // Passed unconditionally — the phase view itself gates the
                // row on `isOrganizer` (and the RPC rejects anyone else).
                onForceStart: { Task { await forceStartLifting() } }
            )
        }
        .background(theme.bg)
    }

    /// "I'm warm" — on TRUE (lifting started: this vote completed
    /// unanimity, or it had already begun) the session row is refreshed
    /// immediately so the arena appears without waiting for the realtime
    /// echo; either way the participants refetch flips my own ready pip.
    @MainActor
    private func voteWarmupReady() async {
        do {
            let started = try await SessionRepository.markWarmupReady(sessionID: session.id)
            if started, let fresh = try? await SessionRepository.session(id: session.id) {
                liveSession = fresh
            }
            await reloadParticipants()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Organizer force-start (the AFK escape hatch). Refreshes the session
    /// row either way — a FALSE return means lifting had already begun,
    /// which the fresh row also reflects.
    @MainActor
    private func forceStartLifting() async {
        do {
            _ = try await SessionRepository.startLifting(sessionID: session.id)
            if let fresh = try? await SessionRepository.session(id: session.id) {
                liveSession = fresh
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

        // MARK: - Body

    /// The pre-redesign scroll layout — reached only in the roster-failure
    /// state now that my-turn and spectate both have fixed pages. Moved
    /// verbatim out of `body` in the 2026-07-31 split.
    private var legacyScrollLayout: some View {
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
    }

    /// PR celebration (full-screen, user-dismissed — p29).
    @ViewBuilder
    private var prOverlayLayer: some View {
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
    }

    /// Floating reaction emoji pill.
    @ViewBuilder
    private var reactionOverlayLayer: some View {
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

    // Body split, round 2 (type-check timeouts: master run 30602065007 at
    // the pre-split body, then branch run 30602390405 at the content-split
    // body — extracting the ZStack content wasn't enough because the COST
    // is the ~25-modifier chain's nested generic depth, not the content):
    // the chain itself is now layered — arenaBase (page + chrome +
    // transient overlay) → arenaWithThrow (throw arena) → body (sheets,
    // dialogs, lifecycle). Each layer is a separately-checked expression.
    /// Exercise whose detail page (video demo + history) is open as a sheet —
    /// set by tapping the exercise name on the spotlight/spectate header
    /// (user 2026-08-11). A sheet, not a push, so dismissing it lands
    /// straight back in the session.
    @State private var exerciseDetailSheet: Exercise?

    var body: some View {
        arenaWithThrow
        // Log Set sheet — penalty (burpee) logging only now; normal sets log inline.
        .sheet(isPresented: $showLogSetSheet) { logSetSheetContent }
        .sheet(item: $exerciseDetailSheet) { ex in
            NavigationStack {
                ExerciseDetailView(exercise: ex)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { exerciseDetailSheet = nil }
                        }
                    }
            }
        }
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
                    onDone: { exitToHome() }
                )
            } else {
                SessionRecapView(
                    session: data.session,
                    sets: data.sets,
                    participants: participants,
                    onDone: { exitToHome() },
                    pumpCheck: data.pumpCheck
                )
            }
        }
        // Leave / end (user 2026-07-31: leaving must never end the session
        // for everyone — the old dialog offered ONLY "end", and for
        // non-organizers the RPC refused, stranding them in the session).
        // Leave = drop out of the rotation; End = the last present lifter
        // (or the organizer) closing it out for the crew's records.
        .confirmationDialog(
            "Leave the session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave session") {
                Task { await leaveSession() }
            }
            if isOrganizer || presentRotation.count <= 1 {
                Button("End for everyone", role: .destructive) {
                    Task { await endSession() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(presentRotation.count <= 1
                 ? "You're the last one lifting — leaving completes the session."
                 : "Leaving removes you from the rotation; the crew keeps lifting.")
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
        // The routine changing under a live session (organizer picked one
        // after some members already entered) re-runs the routine fetch —
        // reload() reads liveSession.routineID (field 2026-07-31: members
        // sat in exercise-less sessions; the root fix is the routines RLS
        // policy in 20260803000003, this covers the mid-session swap).
        .onChange(of: liveSession.routineID) { _, _ in
            Task { await reload() }
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
            // Member-side completion (field 2026-08-01: the organizer's
            // "End for everyone" only ended the session on the organizer's
            // phone — everyone else's screen just sat there). When the
            // completion arrives as a realtime/poll echo, present the same
            // recap the ender sees; isEnding/recapData guard the local-End
            // path from double-presenting.
            if liveSession.state == "completed", !isEnding, recapData == nil {
                Task { await presentCompletion(liveSession) }
            }
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
            // Recovery handle (owner 2026-08-12): survives swipe-down so the
            // SESSION LIVE pill can route back in; cleared only by a
            // deliberate exit (exitToHome) or a terminal state. Title
            // refreshed after reload() once routineName is real.
            appState.liveGroupSession = AppState.LiveGroupSession(
                sessionID: liveSession.id, title: routineName ?? "Crew session")
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

    // MARK: - Body layers (the 2026-07-31 chain split)

    /// Layer 1: the page switch + pinned chrome + transient sound overlay.
    private var arenaBase: some View {
        ZStack(alignment: .bottom) {
            // Redesign 2026-07-30: my-turn is the FIXED page (no scroll);
            // spectating (and the roster-failure state) keep the original
            // scroll layout untouched until the sister-page round.
            // Warm-up (2026-08): while the warm-up window is open the
            // phase page replaces the turn arena entirely — when it ends
            // (vote, force, or clock) the normal switch below resumes and
            // the session's first turn is simply active.
            if isInWarmUp {
                warmUpPage
            } else if myTurnActive {
                myTurnFixedPage
            } else if spectateActive {
                spectateFixedPage
            } else {
                legacyScrollLayout
            }
            prOverlayLayer
            reactionOverlayLayer
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .sensoryFeedback(.success, trigger: logHapticTick)
        .onChange(of: selfHeartRate?.bpm) { _, newValue in
            guard let newValue else { return }
            recoveryBuffer.append(bpm: newValue, at: Date().timeIntervalSinceReferenceDate)
        }
        // Pushed via LobbyView → SessionInProgressView; the soundboard dock +
        // bottom action bar below are bottom-pinned — see GSComponents.swift's
        // GSHidesDock for why the custom app dock can't reach them via
        // safeAreaInset alone.
        .gsHidesDock()
        // Keyboard overlays EVERYTHING, chrome included (user round 3: the
        // CTA was still lifting above the numpad, leaving a stacked buffer).
        // Applied outside the safeAreaInset so neither the page nor the
        // pinned chrome moves while typing; the keyboard simply covers the
        // bottom and everything is exactly where it was on dismiss.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom) { bottomChrome }
        // Incoming-sound transient overlay (inline, above dock area)
        .overlay(alignment: .bottom) { soundOverlayPill }
        .animation(.easeInOut(duration: 0.25), value: soundOverlayText)
    }

    /// Layer 2: the phase-3 throw arena — one coordinate space covering
    /// page + chrome, the lifter-card target frame, and the dragged/flying
    /// plate drawn above everything. The pick-up haptic fires on grab.
    private var arenaWithThrow: some View {
        arenaBase
            .coordinateSpace(name: "liveArena")
            .onPreferenceChange(LifterCardFrameKey.self) { lifterCardFrame = $0 }
            .overlay {
                if let drag = plateDrag { flyingPlateOverlay(drag) }
            }
            .sensoryFeedback(trigger: plateDrag?.grabID) { old, new in
                new != nil && old == nil ? .impact(weight: .medium) : nil
            }
            // BOARD baselines load when the board opens (composite v5 phase 4).
            .onChange(of: spectateShowsBoard) { _, shows in
                guard shows else { return }
                Task { await loadScoreBaselines() }
            }
            // The exercise advancing (RoutineProgression) re-prefills the
            // entry. Field bug 2026-07-31: the squat weight rode into the
            // curls because prefill only fired on turn CHANGES — and a solo
            // rotation's turn never changes (self → self).
            .onChange(of: currentExerciseForSheet?.id) { _, _ in
                if isMyTurn { prefillLogInputs() }
            }
            // Realtime fallback: the turn state POLLS every 10s while live
            // (field 2026-07-31: one phone's dead websocket — "Voice
            // unavailable" — made turn passes invisible to it; push-only
            // signals strand whoever's socket died). Cheap single-row read;
            // only a genuinely newer turn/state is applied, so the realtime
            // echo remains the fast path.
            .task(id: liveSession.state) {
                guard liveSession.state == "in_progress" else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let fresh = try? await SessionRepository.session(id: session.id) else { continue }
                    // Warm-up columns ride this same poll (2026-08): a dead
                    // websocket during warm-up must not strand anyone — a
                    // vote-completed / forced `lifting_started_at` (or the
                    // organizer changing `warmup_minutes`) applies here too.
                    if fresh.turnVersion > liveSession.turnVersion || fresh.state != liveSession.state
                        || fresh.liftingStartedAt != liveSession.liftingStartedAt
                        || fresh.warmupMinutes != liveSession.warmupMinutes {
                        liveSession = fresh
                    }
                    // While warming up, the crew's warmup_ready pips are
                    // participant-row state — refetch on the same cadence
                    // (the realtime participants echo remains the fast path).
                    if isInWarmUp { await reloadParticipants() }
                }
            }
            // Clock-expiry wake-up (2026-08): ONE re-render at `started_at
            // + warmup_minutes` so the arena appears the moment the window
            // lapses with no vote — LobbyView's check-in wake-up idiom,
            // never a polling Timer. `isInWarmUp` itself reads live Date().
            .task(id: warmupEndsAt) {
                guard let endsAt = warmupEndsAt, endsAt > Date() else { return }
                try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow + 0.1))
                guard !Task.isCancelled else { return }
                warmupRefreshTick.toggle()
            }
    }

    /// The pinned bottom chrome (extracted from the safeAreaInset closure).
    /// Redesign 2026-07-30: my-turn gets the compact 152pt chrome; the
    /// legacy dock composition survives for the roster-failure state.
    @ViewBuilder
    private var bottomChrome: some View {
        if isInWarmUp {
            // The warm-up page carries its own CTA — no pinned chrome.
            EmptyView()
        } else if myTurnActive {
            turnChrome
        } else if spectateActive {
            spectateChrome
        } else {
            legacyBottomChrome
        }
    }

    private var legacyBottomChrome: some View {
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

    /// "{username} 🔊 {name}" — floats above the dock while a sound plays.
    @ViewBuilder
    private var soundOverlayPill: some View {
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

                    Button {
                        exerciseDetailSheet = currentExerciseForSheet
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(currentExerciseForSheet?.name ?? "Exercise")
                                .font(GSFont.heading(26, relativeTo: .title))
                                .foregroundStyle(theme.bg)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.bg.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
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
            // Spectate prep face (composite v5): lead with the per-side
            // plate delta from what's on the bar now (the lifter's last
            // logged set) to my next weight. My-turn keeps the original
            // face; so does spectate when either weight is unknown.
            let prepHeadline: String? = {
                guard spectateActive, let mine = prefill, mine > 0,
                      let lifterPounds = currentLifterLastSet?.weight else { return nil }
                let fromInUnit = Units.fromPounds(lifterPounds, to: unit)
                let d = PlateDelta.delta(fromWeight: fromInUnit, toWeight: targetInUnit,
                                         barWeight: barInUnit, plates: plates)
                return d.isNoChange ? PlateDelta.headline(d)
                                    : "\(PlateDelta.headline(d)) · PER SIDE"
            }()

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
                                Text(prepHeadline != nil ? "Your next" : "Load the bar")
                                    .font(GSFont.bold(15, relativeTo: .body))
                                    .foregroundStyle(theme.text)
                                if prepHeadline != nil, let prefill {
                                    Text(Units.format(pounds: prefill, unit: unit, rounded: false))
                                        .font(GSFont.bold(13, relativeTo: .subheadline).monospacedDigit())
                                        .foregroundStyle(theme.neutral500)
                                }
                            }
                            if let prepHeadline {
                                Text(prepHeadline)
                                    .font(GSFont.bold(14, relativeTo: .subheadline).monospacedDigit())
                                    .foregroundStyle(theme.text.opacity(0.78))
                            } else {
                                Text(prefill.map { "\(Units.format(pounds: $0, unit: unit, rounded: false)) · plates & warm-up" }
                                     ?? "Plates & warm-up ramp")
                                    .font(GSFont.body(11.5, relativeTo: .caption))
                                    .foregroundStyle(theme.neutral500)
                            }
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

            // Redesign 2026-07-30: RPESwipeTrack replaces the segment bar AND
            // the separate "Failed set" Toggle — FAIL is the terminal position
            // of the same scale, and arming it snaps the value to 10 (a fail
            // IS an RPE 10; storage writes isFailed = true AND rpe = 10).
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RPE · effort")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Spacer()
                    Text(logIsFailed ? "10 · Miss" : "\(Int(logRPE)) · \(rpeLabel(logRPE))")
                        .font(GSFont.heading(12, relativeTo: .caption))
                        .foregroundStyle(theme.accent700)
                }
                RPESwipeTrack(value: $logRPE, isFailed: $logIsFailed, theme: theme)
            }

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
                Button {
                    exerciseDetailSheet = currentExerciseForSheet
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(currentExerciseForSheet?.name ?? "Exercise")
                            .font(GSFont.heading(22, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.neutral500)
                    }
                }
                .buttonStyle(.plain)
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
                // A failed set stores rpe = 10 (see RPE terminal-position
                // decision), so rendering rpe alone would show a miss as
                // "RPE 10.0" — the signature of a max-effort SUCCESS, to the
                // whole crew. isFailed is the authoritative signal and wins.
                // neutral700 not neutral500: neutral500 measures 2.96:1 on
                // surface, and a label this consequential has to be readable.
                if last.isFailed {
                    Text("FAIL")
                        .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(theme.neutral700)
                } else if let rpe = last.rpe {
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
                // 12.5pt vertical (was 16): content + 25 + the gs3D style's
                // 7pt lip keeps the CTA's exact prior footprint.
                .padding(.vertical, 12.5)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
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

    /// Compact debt strip for the fixed pages (user 2026-07-31: "the
    /// burpee counter doesn't persist" — the redesigned pages dropped the
    /// legacy penalty banner, leaving mid-session debt invisible). Same
    /// destination as the banner: penalty logging via LogSetSheet.
    private var burpeeDebtStrip: some View {
        Button {
            showLogSetSheet = true
        } label: {
            HStack(spacing: 8) {
                Text("YOU OWE \(burpeesRemaining) BURPEES")
                    .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                    .tracking(0.9)
                Spacer()
                Text("LOG THEM")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(theme.bg)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

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
                // theme.bg, NOT theme.accent (UI audit 2026-07-29 measured
                // ~1.78:1). `GSTheme.withAccent` collapses accent600/700/800
                // onto accent.base, so this label and the accent-filled
                // banner behind it resolved to the SAME colour — accent text
                // on accent fill. The kicker and count two lines above
                // already use theme.bg; this now matches them.
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
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
                unit: ThemeStore.shared.weightUnit,
                // Penalty path: FAIL stays a toggle here, never the terminal
                // cap — failed burpees don't clear debt (see logSet's
                // penaltyLogged guard), which "effort 10" must not imply.
                allowsFail: false
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
        // Exercise progression (2026-07-30, closing the in-code-documented
        // gap): the first routine exercise THIS lifter hasn't finished,
        // replacing the hardcoded `.first` that pinned every set of a
        // multi-exercise routine to exercise 1 ("Set 13/3" on device).
        // Counts come from the UNCAPPED session array — the 30-row feed
        // undercounts long sessions. See RoutineProgression's doc.
        if let re = RoutineProgression.currentExercise(
            routine: routineExercises,
            completedSets: { exerciseID in mySetCount(for: exerciseID) }
        ) {
            return allExercises.first(where: { $0.id == re.exerciseID })
        }
        return allExercises.first
    }

    private func mySetCount(for exerciseID: UUID) -> Int {
        // allSessionSets, never feedSets: the feed caps at 30 rows across
        // ALL participants, so it undercounts any real session's history.
        allSessionSets.filter { $0.userID == selfID && $0.exerciseID == exerciseID && !$0.isPenalty }.count
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
            // This session's own work outranks the routine's static target
            // (user 2026-08-01: 355×5 @7 logged, next set prefilled the
            // 225 default). RPE-aware: ≤7 steps up one plate pair, 8+
            // holds — SetProgression, unit-tested.
            if let last = myTurnSets.last(where: { !$0.isFailed && $0.weight != nil }),
               let w = last.weight {
                // Rep-scaled before the RPE step (user 2026-08-02): carrying a
                // heavy low-rep set's load into a higher-rep set suggests a
                // weight nobody can hit for the reps — the 405 × 1 → "set of
                // 5" hazard. Inverse Epley via StatMath, the same helper
                // WorkingWeight's rungs use, so every suggestion in the app
                // agrees on what a rep count is worth.
                let targetReps = leadingInt(target ?? "")
                var base = w
                if let targetReps, let lastReps = last.reps, lastReps != targetReps,
                   let scaled = StatMath.projectedWeight(prWeight: w,
                                                         prReps: lastReps,
                                                         targetReps: targetReps) {
                    base = Decimal(scaled)
                }
                return SetProgression.nextWeight(afterPounds: base, rpe: last.rpe, isFailed: last.isFailed,
                                                 isLowerBody: currentExerciseForSheet?.isLowerBody ?? false,
                                                 unit: turnUnit)
            }
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
        // A set can only ever belong to a LIVE session (field bug
        // 2026-07-31: a set landed in a scheduled future occurrence —
        // whatever surface allowed it, the write itself must refuse).
        // The DB trigger in 20260803000002 is the backstop.
        guard liveSession.state == "in_progress" else { return }
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
        // Pre-log set count for the TRANSIT derivation below — captured
        // BEFORE the async round-trip, because the realtime echo (or the
        // offline optimistic append) may or may not have landed the new
        // set in `allSessionSets` by the time the interlude math runs, and
        // the answer must not depend on that race.
        let preLogSetCount = mySetCount(for: ex.id)
        Task {
            defer { isLoggingSet = false }
            guard await logSetAndAdvance(reps: reps, weight: weight, rpe: rpe,
                                          isFailed: failed, note: note, exerciseID: ex.id) else { return }
            // A logged set visibly leaves this layout (user report 2026-07-30:
            // logging over the open loader looked like nothing happened) —
            // close the loader and keyboard so the my-turn page is reset when
            // the rotation returns, and let the turn advance flip the body to
            // the spectate layout. Failure keeps everything up for a retry —
            // it also must NOT enter the rest interlude below.
            withAnimation(.easeInOut(duration: 0.18)) { showBarLoader = false }
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // Solo-in-a-rotation: the pass came straight back. Enter the
            // rest interlude instead of silently staying on my-turn — the
            // screen visibly changes, the rest is real, and START SET cuts
            // it short (user round 3).
            // PRESENT-rotation gate (field bug 2026-07-31): the old
            // `participants.count <= 1` counted a no-show friend, so the
            // pass-came-straight-back case looked like a real rotation and
            // the interlude never fired. presentRotation mirrors the
            // server's advance_turn exactly.
            if liveSession.currentTurnUserID == selfID, presentRotation.count <= 1 || nextTurnUserID == selfID {
                // TRANSIT (2026-08): when the set just logged completed its
                // exercise, the next set is a DIFFERENT station — extend
                // the window by TransitWindow.seconds and label the WHOLE
                // window TRANSIT. Same-exercise passes are unchanged.
                // Derived through RoutineProgression with the pre-log count
                // + 1 (the just-logged set), never from live
                // `currentExerciseForSheet` — the echo-timing race above.
                let nextRE = RoutineProgression.currentExercise(
                    routine: routineExercises,
                    completedSets: { id in id == ex.id ? preLogSetCount + 1 : mySetCount(for: id) })
                let isTransit = nextRE != nil && nextRE?.exerciseID != ex.id
                let seconds = (currentRoutineExercise?.restSeconds ?? 120)
                    + (isTransit ? TransitWindow.seconds : 0)
                selfRotationRestIsTransit = isTransit
                let until = Date().addingTimeInterval(TimeInterval(seconds))
                selfRotationRestStartedAt = Date()
                selfRotationRestUntil = until
                Task {
                    try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
                    // Only the still-current window clears itself — a rest
                    // the user already cut short must not be re-cleared.
                    if selfRotationRestUntil == until {
                        captureSelfRotationRestDrop()
                        selfRotationRestUntil = nil
                    }
                }
            }
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
        // Recovery-pill title refresh — onAppear registered before reload()
        // populated routineName.
        if appState.liveGroupSession?.sessionID == liveSession.id, let routineName {
            appState.liveGroupSession = AppState.LiveGroupSession(
                sessionID: liveSession.id, title: routineName)
        }
        await ExerciseNameCache.preload()
        // Owner item 7: latest body weight for bodyweight-set stamping.
        if let uid = selfID,
           let latest = try? await BodyWeightLogRepository.recent(userID: uid).first {
            turnLatestBodyWeightLbs = latest.weight
        }
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
                // Incoming remote sound: play locally, land the plate on the
                // lifter card, show the transient overlay.
                // Closures are @MainActor, so @State mutations are safe here.
                landPlate(slug: slug, senderID: userID)
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
        // Plate re-rack (composite v5): a cooling plate can't be thrown.
        if let until = soundCooldowns[slug], until > now { return }
        lastSoundTapAt = now
        let cls = PlateClass.forDuration(
            ms: soundCatalog.first { $0.slug == slug }?.durationMs)
        soundCooldowns[slug] = now.addingTimeInterval(cls.cooldown)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(cls.cooldown))
            // Only clear an unchanged entry — a re-throw after expiry has
            // already written a NEWER date this stale task must not erase.
            if let until = soundCooldowns[slug], until.timeIntervalSinceNow <= 0 {
                soundCooldowns[slug] = nil
            }
        }
        // My own plate lands too — the broadcast self-echo is suppressed,
        // so the tap is the one place it can come from.
        landPlate(slug: slug, senderID: selfID)
        // Local play (immediately) + remote send (fire-and-forget).
        async let playTask: Void = SoundboardPlayer.shared.play(slug: slug)
        async let sendTask: Void = broadcastService.sendSound(
            sessionID: liveSession.id,
            groupID: liveSession.groupID,
            slug: slug
        )
        _ = await (playTask, sendTask)
    }

    /// Drop a plate on the lifter card. Slides off when the sound's own
    /// duration ends — the 5-second cap guarantees it never outlives half
    /// a rest.
    @MainActor
    private func landPlate(slug: String, senderID: UUID?) {
        let sender: String = {
            guard let senderID else { return "?" }
            if senderID == selfID { return "YOU" }
            let username = participants
                .first(where: { $0.participant.userID == senderID })?.profile.username ?? "?"
            return String(username.prefix(2)).uppercased()
        }()
        let sound = soundCatalog.first { $0.slug == slug }
        let plate = LandedPlate(slug: slug, sender: sender, durationMs: sound?.durationMs)
        withAnimation(.spring(duration: 0.35)) {
            landedPlates.append(plate)
            if landedPlates.count > 5 {
                landedPlates.removeFirst(landedPlates.count - 5)
            }
        }
        let lifetime = Double(sound?.durationMs ?? 2000) / 1000
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(lifetime))
            withAnimation(.easeOut(duration: 0.3)) {
                landedPlates.removeAll { $0.id == plate.id }
            }
        }
    }

    /// The bare token + its visual states — kept as its own small
    /// function so each piece stays inside the type-checker budget
    /// (the inline let + Group form was part of the 2026-07-31 timeout).
    private func dockPlateToken(_ sound: SoundboardSound) -> some View {
        GSPlateToken(
            name: sound.plateName,
            envelope: sound.envelope,
            durationMs: sound.durationMs,
            isClipped: sound.isClipped,
            cooldownUntil: soundCooldowns[sound.slug]
        )
        .opacity(plateDrag?.sound.slug == sound.slug ? 0.25 : 1)
        .contentShape(Circle())
    }

    /// One dock plate. Tap = quick send; drag = the throw (spectate only,
    /// never over the open loader). The flick is the fun path, never the
    /// toll.
    @ViewBuilder
    private func dockPlate(for sound: SoundboardSound) -> some View {
        Group {
            if spectateActive && !showBarLoader {
                dockPlateToken(sound).gesture(plateThrowGesture(sound))
            } else {
                dockPlateToken(sound)
            }
        }
        .onTapGesture { Task { await tapSound(slug: sound.slug) } }
        .accessibilityLabel("Send \(sound.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The throw (composite v5 phase 3 — Hearthstone rules)

    private func plateThrowGesture(_ sound: SoundboardSound) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("liveArena"))
            .onChanged { value in
                guard soundCooldowns[sound.slug] == nil else { return }
                if plateDrag == nil {
                    plateDrag = PlateDragState(sound: sound,
                                               location: value.location,
                                               startLocation: value.startLocation)
                } else if plateDrag?.sound.slug == sound.slug,
                          plateDrag?.isFlying == false {
                    plateDrag?.location = value.location
                }
            }
            .onEnded { value in
                guard plateDrag?.sound.slug == sound.slug,
                      plateDrag?.isFlying == false else { return }
                releasePlate(at: value.location, predicted: value.predictedEndLocation)
            }
    }

    /// Release over the platform → the throw completes ballistically and
    /// the sound fires ON LANDING (tapSound IS the landing: pile, play,
    /// broadcast, cooldown). Release anywhere else → the plate springs
    /// home — no sound, no send, a free cancel. Reduce Motion sends
    /// without the flight.
    @MainActor
    private func releasePlate(at location: CGPoint, predicted: CGPoint) {
        guard let drag = plateDrag else { return }
        let target = lifterCardFrame.insetBy(dx: -24, dy: -24)
        let hit = !lifterCardFrame.isEmpty
            && (target.contains(location) || target.contains(predicted))
        let slug = drag.sound.slug
        if hit {
            if UIAccessibility.isReduceMotionEnabled {
                plateDrag = nil
                Task { await tapSound(slug: slug) }
                return
            }
            plateDrag?.isFlying = true
            plateDrag?.location = CGPoint(x: lifterCardFrame.midX,
                                          y: lifterCardFrame.maxY - 30)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                plateDrag = nil
                await tapSound(slug: slug)
            }
        } else {
            let grabID = drag.grabID
            plateDrag?.location = drag.startLocation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                // Only clear THIS grab — a re-grab mid-return owns the state.
                if plateDrag?.grabID == grabID, plateDrag?.isFlying == false {
                    plateDrag = nil
                }
            }
        }
    }

    /// The plate under the finger / in flight, drawn above page + chrome.
    /// Depth is scale + shadow + tilt (how Hearthstone fakes its table);
    /// the carry spring's stiffness is the class's heft — the 45 drags a
    /// beat behind the finger, the 5 snaps to it.
    private func flyingPlateOverlay(_ drag: PlateDragState) -> some View {
        GSPlateToken(
            name: drag.sound.plateName,
            envelope: drag.sound.envelope,
            durationMs: drag.sound.durationMs,
            isClipped: drag.sound.isClipped,
            cooldownUntil: nil
        )
        .scaleEffect(drag.isFlying ? 1.0 : 1.3)
        .shadow(color: .black.opacity(0.45),
                radius: drag.isFlying ? 4 : 14,
                y: drag.isFlying ? 4 : 12)
        .rotationEffect(.degrees(plateTilt(drag)))
        .position(drag.location)
        .allowsHitTesting(false)
        .animation(drag.isFlying ? .easeIn(duration: 0.18) : plateCarrySpring(drag.sound),
                   value: drag.location)
        .animation(.easeOut(duration: 0.15), value: drag.isFlying)
    }

    private func plateCarrySpring(_ sound: SoundboardSound) -> Animation {
        switch PlateClass.forDuration(ms: sound.durationMs) {
        case .five: return .interpolatingSpring(stiffness: 420, damping: 28)
        case .ten: return .interpolatingSpring(stiffness: 300, damping: 24)
        case .twentyFive: return .interpolatingSpring(stiffness: 200, damping: 20)
        case .fortyFive: return .interpolatingSpring(stiffness: 120, damping: 16)
        }
    }

    private func plateTilt(_ drag: PlateDragState) -> Double {
        guard !drag.isFlying else { return 4 }
        let dx = drag.location.x - drag.startLocation.x
        return max(-14, min(14, dx / 9))
    }

    // MARK: - ROUND SCOREBOARD (composite v5 phase 4)

    /// Sets · % SELF · LOAD, self-referenced only. Rows carry a small live
    /// bpm so crew heart rates stay visible here (the 2026-07-27 ruling)
    /// now that the board replaced the crew grid.
    private var spectateBoardCard: some View {
        let rows = SessionScoreboard.rows(
            participants: rotationOrder.map(\.participant.userID),
            sessionSets: allSessionSets,
            baselines: scoreBaselines
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ROUND SCOREBOARD")
                    .font(GSFont.bold(10, relativeTo: .caption2)).tracking(1.3)
                    .foregroundStyle(theme.neutral700)
                Spacer()
                if isLoadingBoard {
                    ProgressView().controlSize(.mini).tint(theme.neutral500)
                } else {
                    Text("VS YOURSELF")
                        .font(GSFont.bold(10, relativeTo: .caption2)).tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                }
            }
            Color.clear.frame(height: 12)
            HStack(spacing: 8) {
                Text("CREW")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("SETS").frame(width: 34, alignment: .trailing)
                Text("% SELF").frame(width: 56, alignment: .trailing)
                Text("LOAD").frame(width: 44, alignment: .trailing)
            }
            .font(GSFont.bold(9, relativeTo: .caption2))
            .foregroundStyle(theme.neutral700)
            Rectangle().fill(theme.divider).frame(height: 1)
                .padding(.top, 8)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(rows) { row in
                        boardRow(row)
                    }
                }
                .padding(.top, 6)
            }
            Text("% SELF = TODAY VS YOUR OWN BEST-EVER EST-1RM · LOAD = Σ REPS × RPE")
                .font(GSFont.bold(8, relativeTo: .caption2)).tracking(0.6)
                .foregroundStyle(theme.neutral500)
                .padding(.top, 8)
        }
        .padding(14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func boardRow(_ row: SessionScoreboard.Row) -> some View {
        let entry = rotationOrder.first { $0.participant.userID == row.userID }
        let isMe = row.userID == selfID
        let hr = heartRateFor(row.userID)
        return HStack(spacing: 8) {
            GSInitialsAvatar(name: entry?.profile.username ?? "?",
                             avatarURL: entry?.profile.avatarURL, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(isMe ? "You" : (entry?.profile.username ?? "—"))
                    .font(GSFont.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(row.ceilingBroken || isMe ? theme.text : theme.text.opacity(0.78))
                    .lineLimit(1)
                if row.ceilingBroken {
                    Text("CEILING BROKEN")
                        .font(GSFont.bold(8, relativeTo: .caption2)).tracking(1.0)
                        .foregroundStyle(theme.accent)
                } else if let hr {
                    Text("♥ \(hr.bpm)")
                        .font(GSFont.bold(9, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(theme.neutral700)
                } else if row.pctSelf == nil {
                    Text("NO BASELINE · SETS ONLY")
                        .font(GSFont.bold(8, relativeTo: .caption2)).tracking(0.8)
                        .foregroundStyle(theme.neutral500)
                }
            }
            Spacer(minLength: 4)
            Text("\(row.sets)")
                .font(GSFont.bold(16, relativeTo: .subheadline).monospacedDigit())
                .foregroundStyle(theme.text.opacity(0.78))
                .frame(width: 34, alignment: .trailing)
            Text(row.pctSelf.map { "\($0)%" } ?? "—")
                .font(GSFont.bold(17, relativeTo: .subheadline).monospacedDigit())
                .foregroundStyle(row.ceilingBroken ? theme.accent
                                 : (row.pctSelf != nil ? theme.text.opacity(0.78) : theme.neutral500))
                .frame(width: 56, alignment: .trailing)
            Text(row.load > 0 ? "\(row.load)" : "—")
                .font(GSFont.bold(15, relativeTo: .subheadline).monospacedDigit())
                .foregroundStyle(row.load > 0 ? theme.text.opacity(0.78) : theme.neutral500)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, row.ceilingBroken ? 8 : 0)
        .background {
            if row.ceilingBroken {
                RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(0.16))
            }
        }
        .overlay {
            if row.ceilingBroken {
                RoundedRectangle(cornerRadius: 12).strokeBorder(theme.accent, lineWidth: 1.5)
            }
        }
    }

    /// Fetch each participant's pre-session ceilings, once per BOARD
    /// opening. Best-effort per (lifter, exercise): a blocked or empty
    /// history just leaves that lifter's honest dash — never a fake
    /// number. Reopening the board picks up newly-lifted exercises.
    @MainActor
    private func loadScoreBaselines() async {
        guard !isLoadingBoard else { return }
        isLoadingBoard = true
        defer { isLoadingBoard = false }
        let exercisesByUser = Dictionary(
            grouping: allSessionSets.filter { !$0.isPenalty }, by: \.userID)
            .mapValues { Set($0.map(\.exerciseID)) }
        for (userID, exercises) in exercisesByUser {
            for exerciseID in exercises where scoreBaselines[userID]?[exerciseID] == nil {
                guard let history = try? await SessionRepository.exerciseHistory(
                    userID: userID, exerciseID: exerciseID, limit: 200) else { continue }
                let base = SessionScoreboard.baseline(history: history,
                                                     excludingSessionID: session.id)
                if let ceiling = base[exerciseID] {
                    scoreBaselines[userID, default: [:]][exerciseID] = ceiling
                }
            }
        }
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
    /// Returns `true` once the set is durably recorded (server insert OR the
    /// offline queue) — `false` only when the attempt failed outright and the
    /// entry UI should stay up for a retry.
    private func logSetAndAdvance(
        reps: Int?, weight: Decimal?, rpe: Decimal?,
        isFailed: Bool, note: String?, exerciseID: UUID
    ) async -> Bool {
        guard let userID = selfID else { return false }
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
            note: note, loggedAt: Date(),
            // Owner item 7: bodyweight sets carry the load they moved.
            bodyWeightLbs: (currentExerciseForSheet?.id == exerciseID
                            && currentExerciseForSheet?.equipment == "bodyweight")
                ? turnLatestBodyWeightLbs : nil
        )
        do {
            // PR check — same logic as solo WorkoutSessionView:
            // after a non-failed set with a positive weight, compare against prior best.
            // prior max MUST be captured before the insert (self-comparison bug)
            var isPR = false
            var priorBest: Decimal = 0
            // Failure doctrine (owner 2026-08-13): failed sets are judged on
            // COMPLETED reps ("7 + FAIL" = 6 at true RIR 0); only the failed
            // single carries nothing. Mirrors solo WorkoutSessionView.log.
            let completedReps = log.completedReps
            if let weight, weight > 0, let completedReps {
                // Phase O Task 3 — see WorkoutSessionView.log's identical catch for
                // the full rationale: without this, an offline attempt throws HERE
                // (before the set-log write below), so a group-session lifter could
                // never queue a set while offline either. Only `.network` is tolerant.
                do {
                    // Rep-aware (owner 2026-08-02): compared against the best
                    // weight already done for AT LEAST these reps, so a heavy
                    // single and a hard set of ten are separate achievements.
                    let prior = try await priorMax(exerciseID: exerciseID,
                                                   reps: completedReps, userID: userID)
                    priorBest = prior
                    isPR = weight > prior
                } catch let error as GymSyncError {
                    guard case .network = error else { throw error }
                    // Offline — PR check skipped (best-effort, never blocks logging).
                }
            }

            // Rep-PR for pure-bodyweight sets (owner item 6) — solo mirror:
            // judged against this exercise's known unloaded sets; stored as
            // weight 0 with previousBest carrying prior REPS.
            var isRepPR = false
            var priorBestReps = 0
            if (weight ?? 0) == 0,
               currentExerciseForSheet?.id == exerciseID,
               currentExerciseForSheet?.equipment == "bodyweight",
               let completedReps {
                priorBestReps = turnExerciseHistory
                    .filter { !$0.isPenalty && ($0.weight ?? 0) == 0 }
                    .compactMap(\.completedReps).max() ?? 0
                isRepPR = completedReps > priorBestReps
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
                // FIXED 2026-07-29 (rotation guard, migration
                // 20260801000001). This used to end here: the turn did not
                // auto-advance while offline and never auto-advanced even
                // after the queued row replayed, because
                // `OfflineSetLogQueue.replay()` only ever resubmits the
                // set_logs INSERT — advanceTurn was not part of replay. One
                // lifter's dead signal froze the rotation for everyone until
                // an organizer unstuck it by hand.
                //
                // The advance is now RECORDED with the `turn_version` we can
                // see right now and replayed on the same triggers as the set
                // queue (RootView's four hooks). Replaying it is safe because
                // `advance_turn(p_session_id, p_expected_version)` no-ops once
                // the rotation has moved on — so if the organizer advances
                // manually in the meantime, or a no-show is marked, the
                // queued advance quietly does nothing instead of shoving the
                // rotation forward a second time.
                PendingTurnAdvanceStore.shared.record(
                    sessionID: session.id,
                    observedVersion: liveSession.turnVersion)
                didQueueSetOffline = true
            }
            // The set is durably recorded either way (server insert or offline
            // queue) — this is the moment the success haptic fires.
            logHapticTick += 1

            if isRepPR, let completedReps {
                let name = await ExerciseNameCache.name(for: exerciseID)
                Task { @MainActor in
                    await showPROverlay(exerciseName: name, weight: 0,
                                         reps: completedReps, priorBest: Decimal(priorBestReps))
                }
                Task { @MainActor in
                    _ = try? await PersonalRecordRepository.record(
                        exerciseID: exerciseID,
                        weight: 0,
                        reps: completedReps,
                        previousBest: Decimal(priorBestReps),
                        sessionID: session.id
                    )
                }
            }

            if isPR, let weight {
                let name = await ExerciseNameCache.name(for: exerciseID)
                let repsForOverlay = completedReps ?? 0
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
            guard !didQueueSetOffline else { return true }
            try await SessionRepository.advanceTurn(sessionID: session.id)
            // A live advance settles any advance this device still owed from
            // an earlier offline set — the queued one would no-op anyway
            // (version guard), but dropping it keeps the store honest rather
            // than accumulating entries that only ever fizzle.
            PendingTurnAdvanceStore.shared.clear(sessionID: session.id)
            return true
        } catch let error as GymSyncError {
            // Upgraded treatment (Canvas Completion Task 4 fix round 1, proof
            // p31-errors) — NOT the shared `errorText` red caption; see
            // `logSetErrorText`'s declaration + the `GSInlineErrorBanner`
            // wiring in `body`.
            logSetErrorText = error.errorDescription
            return false
        } catch {
            logSetErrorText = error.localizedDescription
            return false
        }
    }

    /// Leave ≠ end (user 2026-07-31): flip my check-in to 'left' (outside
    /// the presence trio), hand the turn on first if it's mine, and only
    /// when I'm the last present lifter does leaving complete the session
    /// — "if everyone force quits, end the session."
    @MainActor
    private func leaveSession() async {
        if presentRotation.count <= 1 {
            await endSession()
            return
        }
        do {
            if isMyTurn {
                // While still present and authorized as the current lifter.
                try await SessionRepository.advanceTurn(sessionID: session.id)
            }
            try await SessionRepository.leave(sessionID: session.id)
            exitToHome()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Every exit from a live session lands on HOME, not the lobby
    /// underneath (user 2026-08-01): flag the session for the lobby's
    /// unwind observer, then pop this view.
    @MainActor
    private func exitToHome() {
        appState.sessionExitToHomeID = session.id
        // Deliberate exit — retire the recovery pill (the ONLY in-view clear;
        // onDisappear must not clear it, a swipe-down is recoverable).
        if appState.liveGroupSession?.sessionID == session.id {
            appState.liveGroupSession = nil
        }
        dismiss()
    }

    /// The rep-aware PR baseline: the heaviest weight already done for AT
    /// LEAST `reps` reps (failed sets count at completed reps; penalty sets
    /// excluded). Mirrors the identical
    /// helper in WorkoutSessionView; both defer to `PersonalRecordMath` so the
    /// two live views can never disagree about what a record is.
    ///
    /// Two light columns rather than the 200 full rows this used to download
    /// in front of every write (2026-08-02 latency fix) — this call sits on the
    /// critical path of the turn CTA, and the whole rotation waits on it.
    private func priorMax(exerciseID: UUID, reps: Int?, userID: UUID) async throws -> Decimal {
        let rows = try await SessionRepository.prBasis(userID: userID, exerciseID: exerciseID)
        // Failed rows enter at their COMPLETED reps (doctrine 2026-08-13:
        // n logged − 1; failed singles drop out) — mirrors solo's pairs().
        let basis: [(weight: Decimal, reps: Int)] = rows.compactMap { row in
            guard let w = row.weight, w > 0, let r = row.completedReps else { return nil }
            return (w, r)
        }
        return PersonalRecordMath.bestWeight(atLeastReps: reps ?? 0, in: basis)
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
        // Ronnie for the PR moment (user 2026-08-01) — catalog slug
        // lightweight-baby, imported through the 5s-cap pipeline.
        Task { await SoundboardPlayer.shared.play(slug: "lightweight-baby") }
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

    /// Everything after the session is completed server-side — shared by
    /// the local End action and the member-side path where completion
    /// arrives as a realtime/poll echo (field 2026-08-01: the organizer's
    /// End only ended the session on the organizer's phone; members'
    /// screens just sat there).
    @MainActor
    private func presentCompletion(_ completed: WorkoutSession) async {
        liveSession = completed
        pushWatchSessionState()
        do {
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

    @MainActor
    private func endSession() async {
        isEnding = true
        defer { isEnding = false }
        errorText = nil
        do {
            let completed = try await SessionRepository.complete(sessionID: session.id)
            // presentCompletion carries the Watch-push-before-echo ordering
            // requirement (Phase W Task 3) — it assigns liveSession FIRST,
            // then pushes, then builds the recap.
            await presentCompletion(completed)
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
                guard let r = log.completedReps, let w = log.effectiveWeightPounds else { return acc }
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
                        isPR: (log.completedReps ?? 0) > 0 && log.weight != nil && log.weight == prWeight[id],
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
