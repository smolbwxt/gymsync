import SwiftUI
import UIKit

// MARK: - SessionLiveView
//
// THE ONE SESSION BODY (plan task S5). Was `GroupSessionLiveView`, in
// `Features/Sessions/`; the spectate sister page, the roster-failure layout,
// the soundboard dock, the throw and the BOARD left in plan task S4, and what
// remains is moved here under the name it earned — one body, three styles.
//
// `style` is handed in by `SessionInProgressView`, the style router, and it
// has NO DEFAULT: an explicit argument at the one call site is what makes the
// router readable. Rounds is a rotation, so the log control belongs to
// whoever holds the turn (`logControlIsMine` below); Freestyle and Together
// have no turn at all, so it is everyone's at once (spec §3.3).
//
// Proof-matched design (p06 Live Spotlight / p29 PR Celebration), AS IT
// STANDS AFTER PLAN TASK S13's DEAD-MEMBER SWEEP (this list drifted twice
// before — F4 fixed the Roster bullet, this pass fixes the other four
// review finding 5 named):
//   • Top bar: `turnHeaderRail` — session-elapsed timer (one-clock rule with the
//     vitals card below it) + routine name + voice/chat entry points + X
//     (→ End Session confirmation) + participant count.
//   • My-turn page (`myTurnFixedPage`): `turnVitalsRow` (HR pill or session-elapsed,
//     one-clock rule) + `turnExerciseCard` + `turnEntryCard` (reps/weight readout +
//     RPE swipe track, no sheet) — or `turnLoaderExpanded` while the bar
//     loader is open. `turnChrome`, pinned below via `bottomChrome`, carries
//     the actual CTA: `LogControlButton` ("Log Set & Pass" — Freestyle and
//     Together mount the SAME button in their own feet, ruling R-B17), the
//     voice notices, the mic rail (`PTTDockRow`, compact) and, when burpees
//     are owed, `burpeeDebtStrip` above it. The ROTATION strip
//     (NOW/NEXT/3RD/4TH) moved to `RoundPieces.TurnStrip` (plan task S8);
//     `SpotterView` mounts it now, not this page. `turnEntryCard` ITSELF is
//     no longer this page's alone (fix round 4 / finding 1, ruling R-B21):
//     Together and Freestyle mount the IDENTICAL view, directly above their
//     own copy of the LOG foot — `togetherScreen`/`freestyleScreen` hand it
//     in as `entryCard` — because the button those two styles already had
//     could never enable with nowhere on screen to enter reps into.
//     `logControlIsMine`, not `isMyTurn`, is what every prefill call site
//     gates on now, so the same fix reaches all three styles at once.
//   • Chess clock: Text(_, style: .timer), state-driven from currentTurnStartedAt — never
//     a Swift Timer. The log flow keeps its priorMax-before-logSet ordering
//     and its fire-and-forget PR record; what follows the insert is now the
//     STYLE'S answer, not one fixed call (`LogFollowUp.calls(for:)`, ruling
//     R-B22): Rounds advances the turn and then offers to close the round,
//     Together and Freestyle run neither, and a follow-up that fails never
//     takes the saved set's entry card back down.
//   • Burpee debt: `burpeeDebtStrip`, a compact accent-fill strip above
//     `turnChrome`'s CTA — "YOU OWE N BURPEES" + LOG THEM, opens
//     `LogSetSheet` for penalty-only logging. The full-page penalty banner
//     this bullet used to describe was retired with the spectate page (plan
//     task S4) and swept as dead code (plan task S13).
//   • Set feed: retired with the spectate page (plan task S4) and swept as
//     dead code (plan task S13) — no reverse-chron feed exists on this page
//     anymore.
//   • Reaction pills (🔥💪😂👏): moved to `RoundPieces.ReactionStrip` (plan task S6) —
//     mounted on every page that shows a dock, which is all five (fix round 5,
//     final review finding 6): the round wait's and spotter's own feet,
//     `turnChrome` for Rounds-my-turn and Freestyle, and Together's foot. Tap
//     to broadcast, incoming reactions float up as emoji pills (2s, opacity +
//     offset) via `reactionOverlayLayer`.
//   • PR Celebration: full-screen, USER-DISMISSED moment (p29) — replaces the old
//     auto-dismissing toast. Share (ShareLink) + "Keep Lifting" dismiss. Its
//     sound left with the soundboard (ruling R-B8, plan task S11); the haptic stays.
//   • End Session: confirmation (via header X) → complete → HealthKit → SessionRecapView sheet

struct SessionLiveView: View {
    let session: WorkoutSession

    /// How this crew moves (plan task S5). NO DEFAULT — `SessionInProgressView`
    /// names it at the one call site, and the three styles mount different
    /// bodies underneath (the round wait and spotter mode for `.rounds`, plan
    /// tasks S6 and S8; Together's clock, S9; Freestyle's rail, S10).
    ///
    /// Read from `sessions.style` rather than `liveSession.style` so the whole
    /// body agrees with the router that pushed it: the column is frozen the
    /// moment `lifting_started_at` is stamped (`private.session_round_guard`,
    /// plan task D3), so a live session's style cannot change under this view.
    let style: SessionStyle

    /// True only when this view was reached via LobbyView ->
    /// `SessionInProgressView` (the Lobby<->Live push/pop pair for the SAME
    /// session) — false for every other route, currently `BurpeeLedgerView`'s
    /// direct `NavigationLink` (Phase O Task 5, 3e follow-up queue item 6,
    /// "Lobby<->Live back-nav rejoin blip"). See `onDisappear`'s doc comment
    /// below for what this actually guards.
    let voicePersistsOnPop: Bool

    /// TODAY'S ACCEPTED SET REDUCTION (plan task S8, decision 5). A value the
    /// warm-up hands down through `SessionInProgressView`, session-local and in
    /// memory — nil for every other route in, and nil until the athlete taps
    /// Accept. `effectiveRoutineExercises` is the one place it is applied.
    let todaysScale: TodaysScale?

    #if DEBUG
    /// THE CATALOG'S WORLD (plan task S4, global constraint 11).
    ///
    /// Spec §7 asks for a "your turn" production frame, and nothing could
    /// photograph the live body: every page it draws sits behind a realtime
    /// subscription, a voice room, a Watch bridge and a 10 s poll. This is
    /// `LobbyView`'s shape (`LobbyView.swift:26-31`), which is constraint
    /// 11's sanctioned form — with one set, every load path below returns
    /// immediately and every presentation value that cannot be derived from
    /// a fixture reads the world instead.
    ///
    /// THE LOG PATH IS NOT TOUCHED (R-B2-7, rulings R-B21/R-B22).
    /// `commitInlineLog`, `logSetAndAdvance`, `LogFollowUp.calls(for:)` and
    /// `turnEntryCard`'s own composition are byte-unchanged: the frame is
    /// reached by seeding state, never by rerouting the act.
    private let catalog: LiveWorld?
    #endif

    /// True only for a catalog capture. EVERY load path in this file guards
    /// on it — the nine `.task`/`.onAppear`/`.onChange` entry points, the
    /// `.onDisappear` teardown, and the two helpers (`pushWatchSessionState`,
    /// `restoreTimersFromStore`) that several of them share, so a guard
    /// cannot be missed by adding a call site. Constraint 10 is what it is
    /// for: no catalog path may reach `WatchConnectivityBridge`,
    /// `HeartRateBroadcastService`, `HealthKitBridge`, `CheckInService` or
    /// the voice room.
    private var catalogSkipLoad: Bool {
        #if DEBUG
        return catalog != nil
        #else
        return false
        #endif
    }

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

    // MARK: - Broadcast & heart-rate state

    @State private var broadcastService = SessionBroadcastService()
    /// Phase W Task 5 (watch-hr design §4) — separate `HeartRateBroadcastService`
    /// instance from `WatchConnectivityBridge`'s own send-only one (see that
    /// type's own doc comment on `heartRateBroadcast`); THIS instance is for
    /// SUBSCRIBING/rendering, mirroring how `broadcastService` above is this
    /// view's own subscribe-side `SessionBroadcastService` instance while
    /// `WatchConnectivityBridge` holds a separate send-only
    /// `HeartRateBroadcastService` of its own.
    @State private var heartRateService = HeartRateBroadcastService()
    /// Live HR readings keyed by participant userID — includes the CURRENT
    /// (self) user, since `heartRateService.subscribe`'s self-echo delivers
    /// this phone's own published samples back through the same callback
    /// (see that method's own doc comment). Consumed by `heartRateFor(_:)`
    /// below — `rosterCard` and `spotlightHeaderCard` (frame 2A, self only)
    /// were both readers until plan tasks S4 and S13's dead-member sweep
    /// retired them in turn; spotter mode's crew rows (plan task S8) are
    /// the live reader now.
    @State private var heartRates: [UUID: (bpm: Int, zone: HeartRateZone?, receivedAt: Date)] = [:]
    /// One self-clearing `Task` per userID (task-5-brief.md item 4:
    /// "pills fade/remove when no sample for >15s (sender may stop
    /// anytime)") — same "sleep, then clear if nothing newer arrived"
    /// shape this file's own `showReactionOverlay` already uses for its own
    /// transient overlay state, just keyed per
    /// user instead of a single shared property. Purely a memory-hygiene +
    /// re-render trigger: `heartRateFor(_:)` is the AUTHORITATIVE
    /// freshness check (`HeartRateFreshness.isFresh`, hermetically tested)
    /// — a delayed or cancelled purge can never cause a stale reading to
    /// render, only a slightly-late removal from this dictionary.
    @State private var heartRateExpiryTasks: [UUID: Task<Void, Never>] = [:]
    private static let heartRateStaleAfter: TimeInterval = 15
    /// Transient floating reaction pill — cleared after 2s.
    @State private var reactionOverlay: String? = nil
    @State private var reactionOverlayVisible = false
    /// Task 5 (watch-hr design §4) — REMOVED (was: `@State private var
    /// shareHeartRate = false`, populated once from `UserSettingsRepository
    /// .get()` in `openAndSubscribe()`). That one-shot cache was the exact
    /// bug T4's review carried in: a mid-session toggle flip in `YouTabView`
    /// never reached an already-open `SessionLiveView` (this app's
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
    /// routine name + timer + X). System-designed: a bordered icon-button
    /// in `turnHeaderRail` (`headerBar`'s replacement, since plan task S13's
    /// dead-member sweep retired `headerBar` itself), styled after the same
    /// header's own X button, opening a sheet — see
    /// docs/design/accepted-deviations.json's "session-chat" entry.
    @State private var showChatSheet        = false
    /// "Load the bar" expand/collapse for the my-turn page's `turnBarCard` /
    /// `turnLoaderExpanded` pair (user direction 2026-07-28: a widget like the
    /// solo session's, not a header button). It used to drive `barLoaderCard`
    /// on the spectate page too — "plan your bar while someone else lifts" —
    /// but that page left in plan task S4, `barLoaderCard` went callerless
    /// with it, and plan task S13's dead-member sweep retired it in turn.
    @State private var showBarLoader        = false
    /// Success-haptic trigger for `.sensoryFeedback` — a count (not a Bool)
    /// so every logged set fires, including two in a row.
    @State private var logHapticTick        = 0
    /// Session-local HR history behind YOUR RECOVERY — fed by the
    /// `.onChange(of: selfHeartRate?.bpm)` in `body`; pure math lives in
    /// RecoveryBuffer so the HRR numbers are unit-tested.
    @State private var recoveryBuffer       = RecoveryBuffer()
    @State private var isEnding             = false
    /// THE VERB YOU PRESSED THAT DID NOT HAPPEN — ending the session,
    /// leaving it, the crew's skip, the penalty log, Coach's door.
    ///
    /// Twelve writers and, until plan task S3, no reader at all: plan task S4
    /// deleted `legacyBottomChrome`, where its banner used to render, and the
    /// state outlived the surface. `errorBannerOverlay` is that one reader
    /// now — mounted once on the body root, so all five pages are covered.
    /// Cleared on tap, and by `endSession()`'s own `errorText = nil` at the
    /// start of the next attempt.
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
    /// red caption for the crew skip / endSession / penalty-log failures —
    /// `skipTurn()`, the organizer's old one-lifter skip, was swept in fix
    /// round 5 with the rest of finding 4's orphans).
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
    /// A FOLLOW-UP THAT FAILED ON AN ALREADY-SAVED SET (ruling R-B22) —
    /// `advance_turn` / `advance_round` after the insert landed. Deliberately
    /// NOT `logSetErrorText`: that one means "nothing was saved, try again"
    /// and holds the entry card up for the retry, which is the one thing a
    /// persisted set must never invite. This is a one-line note, it never
    /// blocks anything, and it clears itself (`noteLogFollowUpFailure`) — the
    /// set is safe, the rotation or the round will be nudged on by the next
    /// lifter's own call, and there is nothing for this lifter to do.
    @State private var logFollowUpNote: String?
    /// THE CREW'S READINGS PER INTERVAL (plan task S9). Session-local,
    /// bounded and it dies with this view -- `RecoveryBuffer`'s own category,
    /// which is what spec §6's "no new store" blesses. Filled by
    /// `receiveHeartRate` from the samples the broadcast already carries;
    /// nothing else in the app remembers them, and without it Together's
    /// timeline could only ever draw one column.
    @State private var togetherTrace = TogetherTrace()
    /// "I NEED A MINUTE", ONCE PER EXERCISE (plan task S7, owner decision
    /// 11). The exercise ids the held lifter has already spent their minute
    /// on -- a set rather than a flag, because the routine moves on and the
    /// next exercise is a fresh minute.
    @State private var minuteTakenForExercise: Set<UUID> = []
    /// Extensions this client has SEEN this round, its own included. Any
    /// count above one buys nothing (`RoundHold.threshold(_:extensionsTaken:)`
    /// refuses to stack), which is exactly why a double-counted self-echo is
    /// harmless -- and why this needs no de-duplication.
    @State private var minuteExtensionsThisRound = 0
    /// Freestyle's two suggestions, once acknowledged either way (plan task
    /// S10, owner decision 4). NEITHER APPLIES A CHANGE — there is no rest
    /// enforcement and no accessory-adding mechanism in this schema — so
    /// "acknowledged" is the whole of what Accept and Not today do: the card
    /// stops showing. The stretch is one suggestion for the whole session;
    /// the accessory is keyed by exercise, because a lifter who accepts (or
    /// declines) today's accessory should still see tomorrow's.
    @State private var freestyleStretchAcknowledged = false
    @State private var freestyleAcknowledgedAccessoryIDs: Set<UUID> = []
    /// COACH'S DOOR (plan task S6, spec §3.6). The lobby's pair, mirrored —
    /// see `openCoachThread()` below for why the thread is resolved on tap
    /// and never on load.
    @State private var openedCoachThread: OpenedCoachThread?
    @State private var showCoachPaywall = false
    @State private var recapData: RecapData?          // non-nil → sheet
    // Coach debrief for MY sets (AI after-action, group mirror
    // 2026-08-22): assembled once at completion, same builder and same
    // conversation the solo recap uses.
    @State private var groupDebrief: WorkoutDebrief? = nil
    @State private var groupCoachProfile = TrainingProfile()
    @State private var groupTrendHistory: [String: [SetLog]] = [:]
    @State private var showGroupCoachRecap = false
    @State private var penaltyLogged        = 0       // reps logged this session as penalty by me

    // MARK: - Hot-swap state (owner rulings 2026-08-21)
    //
    // Self-scale: QUIET - the member's own remaining sets use the
    // replacement, shown on their set when their turn comes, never
    // announced (no overlay, no feed event). Squad swap: ANYONE proposes,
    // UNANIMOUS consent (every present member votes yes) applies it to
    // everyone. Session-local like the solo overrides - dies with the
    // session; set_logs carry the replacement exercise as real data.
    struct SwapTarget: Equatable { let id: UUID; let name: String }
    struct SwapProposal: Equatable {
        let id: UUID
        let proposerID: UUID
        let exerciseID: UUID
        let target: SwapTarget
        var votes: [UUID: Bool]
    }
    /// Per-member quiet scales: userID -> (original exerciseID -> replacement).
    @State private var selfScales: [UUID: [UUID: SwapTarget]] = [:]
    /// Squad-approved swaps: original exerciseID -> replacement.
    @State private var squadSwaps: [UUID: SwapTarget] = [:]
    @State private var swapProposal: SwapProposal? = nil
    @State private var swapProposalExpiry: Task<Void, Never>? = nil
    @State private var showGroupSwapSheet = false
    @State private var groupSwapOptions: [GroupSwapOption] = []
    @State private var swapForSquad = false
    struct GroupSwapOption: Identifiable {
        let id: UUID
        let name: String
        let detail: String
    }
    /// Fetched lazily when this is a group session — backs the penalty
    /// banner's secondary "Crew ledger" link into BurpeeLedgerView (Canvas
    /// Completion Task 3). `nil` for ad-hoc/solo sessions (no groupID) and
    /// until the fetch completes.
    @State private var ledgerGroup: GymGroup?

    // MARK: - Inline "LOG THIS SET" card state (my-turn spotlight — replaces the old sheet)

    @State private var logReps: String = ""
    // Group coach note (docket: the deferred note UX from the partial
    // turnCoachDecision hookup) - compact line, expandable reason,
    // per-exercise dismissal. Quiet: visible to ME only.
    @State private var turnCoachNoteExpanded = false
    @State private var turnCoachNoteDismissedFor: UUID? = nil
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
    /// Records HELD until their exercise finishes (ruling R-OD-1), keyed by
    /// exercise. A record on set 1 of 4 does not take the screen over and is
    /// not thrown away either: `PRFiring.step` parks it here and hands it
    /// back at completion, or `flushPendingPRs(except:)` fires it when the
    /// lifter moves on. SESSION-LOCAL BY DESIGN — a party resurrected three
    /// days later is worse than a quiet one, and the recap's `PR` tag is the
    /// record of anything this dictionary loses.
    @State private var pendingPRs: [UUID: PRFiring.Pending] = [:]

    /// THE VENUE'S RACK COUNTS, class → count (plan task S6, decision 1).
    /// Empty is the ordinary answer — no venue, or a building nobody has
    /// counted — and an ABSENT class is unknown, never zero.
    @State private var venueRackCounts: [String: Int] = [:]
    /// What `set_venue_rack_count` said, shown inside the station card's own
    /// popover. Never `errorText`: a refused rack count is not a session
    /// error and must not sit where a failed End would.
    @State private var rackErrorText: String?

    /// Reaction emojis per canvas reaction strip.
    private let reactionEmojis = ["🔥", "💪", "😂", "👏"]

    // Redesign 2026-07-30: the local label dictionary is gone —
    // RPESwipeTrack.label is the ONE monotonic table app-wide (this copy and
    // LogSetSheet's previously disagreed with each other AND themselves:
    // 7 and 9 both read "Very hard").

    // MARK: - Helpers

    /// A capture has no signed-in profile, so `appState.currentProfile` is
    /// nil and every "is this me" derivation below — `isMyTurn`,
    /// `logControlIsMine`, `myTurnSets` — would answer for nobody. The world
    /// names its own self (`LobbyView.isOrganizer`'s identical `#if DEBUG`
    /// argument), and the catalog branch returns BEFORE `appState` is read.
    private var selfID: UUID? {
        #if DEBUG
        if let catalog { return catalog.selfID }
        #endif
        return appState.currentProfile?.id
    }
    private var isMyTurn: Bool { liveSession.currentTurnUserID == selfID }

    /// The header rail's participant count. `participants` is
    /// `[(SessionParticipant, Profile)]` and BOTH of those replace their
    /// synthesized memberwise init with `init(from:)` — they are decode-only
    /// types, so no fixture can build one (`LobbyFixtures`' own header
    /// records the same fact, which is why `LobbyWorld` carries `ArrivalRow`s
    /// instead). A catalog world therefore leaves the roster EMPTY and names
    /// the count it stands for; every other roster derivation the my-turn
    /// page reaches answers correctly on an empty roster (no burpee debt, no
    /// held lifter, no crew page), which is why this is the only one that
    /// needs saying.
    private var rosterCount: Int {
        #if DEBUG
        if let catalog { return catalog.participantCount }
        #endif
        return participants.count
    }
    private var isOrganizer: Bool { liveSession.organizerID == selfID }

    /// WHOSE ACT THE LOG CONTROL IS — plan task S5's one behavioural change.
    ///
    /// Rounds is a rotation: the inline LOG THIS SET card belongs to whoever
    /// holds the turn, which is the gate the spectate sister page used to
    /// enforce by simply not drawing the card (plan task S4 deleted that page;
    /// the round wait and spotter mode replace it in S6 and S8). Freestyle and
    /// Together have NO TURN — spec §3.3 — so the control is everyone's at
    /// once and `currentTurnUserID` is not consulted at all.
    ///
    /// `LogControlGate.isMine(style:isMyTurn:)` (`RoundPieces.swift`, fix
    /// round 4 / finding 1) is the pure law behind this; every prefill call
    /// site below reads THIS property rather than re-deriving the rule, so
    /// the entry that fills the card and the button that logs it can never
    /// disagree about whose turn it is.
    private var logControlIsMine: Bool {
        LogControlGate.isMine(style: style, isMyTurn: isMyTurn)
    }

    // MARK: - Voice (Task 4 — PTT dock, Dossier §A.1's locked session-state scope)

    /// Mirrors `LobbyView`'s identical set — kept as a second literal copy
    /// rather than a shared constant since neither view currently has a
    /// common home for session-state helpers, and this codebase has no
    /// existing precedent of factoring session-state string sets out of
    /// individual views. `editing`/`voting`/`locked` narrowed out (D7's
    /// five-state CHECK, mechanical cleanup decision 6, plan task S13): the
    /// states no longer exist.
    private static let voiceEligibleStates: Set<String> = [
        "lobby_open", "in_progress"
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

    /// The shared routine with hot-swaps applied: squad swaps first
    /// (everyone), then MY quiet self-scales on top (my own choice for my
    /// body beats the squad's), then TODAY'S ACCEPTED SET REDUCTION last
    /// (plan task S8, decision 5 — the warm-up's own Accept, which is mine
    /// alone and about the dose rather than the lift). Progression, logging,
    /// and display all read THIS, so a swapped lift is what actually gets
    /// logged and a scaled row is what actually gets counted.
    ///
    /// THE ORDER ITSELF LIVES IN `RoutineLayering` (plan task S7) — it was
    /// hand-copied here, into `SessionRunnerView.planRows` and into a test,
    /// which is three chances for two screens to print two prescriptions for
    /// one lift. The doc above is kept because it is still the best statement
    /// of WHY the order is that order; the body is now a delegation.
    ///
    /// `SwapTarget` carries a NAME for the consent card's wording, and the
    /// layering needs only the replacement's id — so the two dictionaries are
    /// mapped down here rather than dragging a view's nested type into a
    /// model.
    private var effectiveRoutineExercises: [RoutineExercise] {
        RoutineLayering.apply(
            routineExercises,
            squadSwaps: squadSwaps.mapValues(\.id),
            selfScale: selfID.flatMap { selfScales[$0] }?.mapValues(\.id) ?? [:],
            todaysScale: todaysScale)
    }

    private var currentRoutineExercise: RoutineExercise? {
        guard let ex = currentExerciseForSheet else { return nil }
        return effectiveRoutineExercises.first(where: { $0.exerciseID == ex.id })
    }

    /// The CURRENT exercise's venue equipment class, or `nil` when there is no
    /// venue to count racks at or the catalog's equipment word has no venue
    /// class (plan task S6, decision 1). `nil` is also the gate on the
    /// station card's correction affordance: no class, no question.
    private var currentEquipmentClass: String? {
        guard liveSession.venueID != nil else { return nil }
        return Venue.equipmentClass(for: currentExerciseForSheet?.equipment)
    }

    /// The rack count that caps the split — the venue's number for the class
    /// above. `nil` means UNKNOWN, which means no cap at all, which is
    /// `ceil(crew / 3)`: the shipped behaviour, never a guess and never zero.
    private var currentEquipmentCap: Int? {
        guard let equipmentClass = currentEquipmentClass else { return nil }
        return venueRackCounts[equipmentClass]
    }

    // Units sweep: stored weights render in the user's unit. Exact
    // conversion, no plate snapping — these echo what was/should be lifted.
    // (`targetWeightText`, the free-text-target sibling this block used to
    // carry, went with `currentExerciseTargetText` in the fix-round-5 sweep
    // below — it had no other caller.)
    private func weightText(_ pounds: Decimal) -> String {
        Units.format(pounds: pounds, unit: ThemeStore.shared.weightUnit,
                     rounded: false, includeUnit: false)
    }

    private func hasLoggedCurrentExercise(_ userID: UUID) -> Bool {
        guard let ex = currentExerciseForSheet else { return false }
        return allSessionSets.contains { $0.userID == userID && $0.exerciseID == ex.id && !$0.isPenalty }
    }

    // Retired by the fix-round-5 sweep (final review, finding 4): the pages
    // that read them left with plan task S4's spectate/roster strip, and plan
    // task S13's own sweep inherited an incomplete list. All had exactly one
    // occurrence left in the app — their own declaration — and Swift does not
    // warn on an unused private member, so nothing but a grep would have said
    // so. `targetSetsPerLifter`, `currentTurnSetNumber` (the old roster
    // header's "Round N"), `currentExerciseTargetText` + `targetWeightText`,
    // `lastSetForCurrentExercise`, `turnTunerStep` and `skipTurn()` — the
    // organizer's old skip, superseded by `skipHeldLifter()` and the crew's
    // own line (R-B13). The round's figure now comes from `liveSession.round`,
    // the server's own count.

    private func lastSetAnyExercise(_ userID: UUID) -> SetLog? {
        allSessionSets
            .filter { $0.userID == userID && !$0.isPenalty }
            .max(by: { $0.loggedAt < $1.loggedAt })
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

    init(session: WorkoutSession, style: SessionStyle, voicePersistsOnPop: Bool = false,
         todaysScale: TodaysScale? = nil) {
        self.session = session
        self.style = style
        self.voicePersistsOnPop = voicePersistsOnPop
        self.todaysScale = todaysScale
        #if DEBUG
        self.catalog = nil
        #endif
        _liveSession = State(initialValue: session)
    }

    #if DEBUG
    /// The catalog's entry point (plan task S4). It takes NO `session:` and
    /// NO `style:` — the world carries both, so a frame cannot be built half
    /// from a fixture and half from a row somebody fetched (`LobbyView`'s
    /// `init(catalog:)` makes the same argument).
    ///
    /// Everything seeded here is state the page READS. Nothing seeded here
    /// starts anything: the subscriptions, the poll, the Watch push and the
    /// timer store all sit behind `catalogSkipLoad`.
    init(catalog: LiveWorld) {
        self.session = catalog.session
        self.style = catalog.session.style
        // A capture is never the Lobby→Live push/pop pair, and the flag's
        // only reader is the `.onDisappear` teardown this init guards off.
        self.voicePersistsOnPop = false
        // A frame is a value: the world's routine rows are already what they
        // are, and a scale the capture never tapped for would be a second
        // source for the same numbers.
        self.todaysScale = nil
        self.catalog = catalog
        _liveSession = State(initialValue: catalog.session)
        _routineName = State(initialValue: catalog.routineName)
        _routineExercises = State(initialValue: catalog.routineExercises)
        _allExercises = State(initialValue: catalog.allExercises)
        _allSessionSets = State(initialValue: catalog.sets)
        // The feed is newest-first and capped at 30, exactly as `reload()`
        // builds it — the one derivation a seeded world must not get wrong,
        // because `prefillLogInputs` reads it.
        _feedSets = State(initialValue: Array(catalog.sets.reversed().prefix(30)))
        _logReps = State(initialValue: catalog.logReps)
        _logWeight = State(initialValue: catalog.logWeight)
        _logRPE = State(initialValue: catalog.logRPE)
    }
    #endif

    // MARK: - Redesigned my-turn fixed page (2026-07-30, final-proof.html)
    //
    // The my-turn state is a FIXED, non-scrolling page: fixed control heights,
    // ONE flexible child (the exercise card) absorbing device slack. Four
    // widgets — heart rate, load-the-bar, exercise (SETS|ROUTINE pager),
    // entry — over a compact pinned chrome (the mic rail with the compact PTT
    // mic + 57pt CTA; the rail was 56pt of soundboard plates until plan task
    // S4 took them). This is now the ONLY page this body has: the spectate
    // sister page and the roster-failure scroll layout left with S4, and the
    // round wait (S6) and spotter mode (S8) are what render in their place.
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
    /// my-turn screen "did nothing". It entered a REST interlude — the
    /// spectate layout with a START SET CTA — until the window ended or you
    /// cut it short. THE INTERLUDE'S LAYOUT LEFT WITH THE SPECTATE PAGE (plan
    /// task S4): the window, its notifier and its store still run — the
    /// recovery pill that used to render on top of it, and the boolean that
    /// gated it, both went callerless with the page and plan task S13's
    /// dead-member sweep retired them in turn. Nil = not resting.
    @State private var selfRotationRestUntil: Date?

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
    /// "rest" is the round wait (plan task S6), which measures its own
    /// elapsed clock from the crew's logs and opens no window.
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

    /// BlockProgression at the START of this exercise (nothing of mine
    /// logged for it yet this session) — group parity with the solo coach
    /// note (owner 2026-08-20). The load advance joins the prefill ladder;
    /// the compact note line below the entry header carries deloads,
    /// stalls, and fatigue warnings (docket close 2026-08-22) — quiet,
    /// mine only, per-exercise dismissable.
    private var turnCoachDecision: BlockProgression.Decision? {
        // Owner ruling (field #38): only Coach-authored routines get
        // live tweaks; user-curated group routines are never altered.
        guard routineName?.hasPrefix("Coach · ") == true else { return nil }
        guard let ex = currentExerciseForSheet,
              let re = currentRoutineExercise,
              let low = re.targetRepsLow, let high = re.targetRepsHigh,
              !myTurnSets.contains(where: { $0.exerciseID == ex.id })
        else { return nil }
        return BlockProgression.decide(
            history: priorSets.filter { $0.exerciseID == ex.id },
            repsLow: low, repsHigh: high,
            isLowerBody: ex.isLowerBody,
            isIsolation: false,
            lastSetToFailure: re.targetFailure,
            unit: turnUnit)
    }

    private func turnCoachNote(for decision: BlockProgression.Decision) -> BlockProgression.CoachNote? {
        switch decision {
        case .advanceLoad(_, let note), .advanceReps(_, let note),
             .proposeDeload(_, let note), .flagStall(let note),
             .warnFatigue(let note):
            return note
        case .hold(let note):
            return note
        }
    }

    private var turnCoachDeloadPounds: Decimal? {
        if case .proposeDeload(let pounds, _) = turnCoachDecision { return pounds }
        return nil
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
        #if DEBUG
        // `heartRateFor(_:)` is a FRESHNESS gate measured against `Date()`
        // (15 s), so a seeded reading with a fixture timestamp would always
        // read stale and the vitals card would print an em dash. The world
        // states the reading it stands for, and no clock is read.
        if let reading = catalog?.heartRate { return (bpm: reading.bpm, zone: reading.zone) }
        if catalog != nil { return nil }
        #endif
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
                Text("\(rosterCount)")
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
            // LOAD PATH 1 of 9 (plan task S4): `SessionRepository
            // .exerciseHistory` + `ProgramRepository.active()`.
            guard !catalogSkipLoad else { return }
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
            //
            // LOAD PATH 2 of 9 (plan task S4). CONSTRAINT 10 IS THIS ONE'S
            // POINT: the sheet it raises is the pre-permission prime whose
            // "Show my heart rate" goes on to raise the real HealthKit /
            // Bluetooth dialogs, and a raised sheet hung `build-test` for 45
            // minutes once. A capture must never reach it.
            guard !catalogSkipLoad else { return }
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
            parts.append("RPE \((rpe).displayInt)")
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

    /// Bar/plate config shared by `turnBarCard` and `turnLoaderExpanded`. It
    /// was written as the twin of `barLoaderCard`'s own derivation — plan
    /// task S4 deleted `barLoaderCard`'s only mount, and plan task S13's
    /// dead-member sweep retired the callerless view itself.
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
            // Block engine outranks the ladder when the rep range was
            // topped last session — it IS that history's conclusion.
            if case .advanceLoad(let pounds, _)? = turnCoachDecision {
                return pounds
            }
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
                // Hot-swap (owner 2026-08-21): scale for yourself quietly,
                // or put a swap to the squad - unanimous applies.
                Button {
                    swapForSquad = false
                    showGroupSwapSheet = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap exercise")
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
                Text("RPE \((rpe).displayInt)")
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
                Text(Units.weightKicker(unit: turnUnit,
                                        equipment: currentExerciseForSheet?.equipment,
                                        unilateral: currentExerciseForSheet?.unilateral))
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 229, alignment: .leading)
                Text(targetReps.map { "REPS · \($0)" } ?? "REPS")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
            }
            .frame(height: 14)

            // Group coach note (docket close 2026-08-22): the block
            // engine's non-advance decisions finally get their line -
            // compact, expandable, mine only, dismissable per exercise.
            if let decision = turnCoachDecision,
               let note = turnCoachNote(for: decision),
               turnCoachNoteDismissedFor != currentExerciseForSheet?.id {
                Color.clear.frame(height: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Button { turnCoachNoteExpanded.toggle() } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text("COACH · \(note.summary.uppercased())")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .tracking(0.6)
                                .foregroundStyle(theme.text.opacity(0.82))
                                .lineLimit(turnCoachNoteExpanded ? 3 : 1)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: turnCoachNoteExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .buttonStyle(.plain)
                    if turnCoachNoteExpanded {
                        Text(note.reason)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let deloadPounds = turnCoachDeloadPounds {
                        HStack(spacing: 10) {
                            Button {
                                logWeight = Units.format(pounds: deloadPounds, unit: turnUnit,
                                                         rounded: false, includeUnit: false)
                                if let low = currentRoutineExercise?.targetRepsLow {
                                    logReps = String(low)
                                }
                                turnCoachNoteDismissedFor = currentExerciseForSheet?.id
                            } label: {
                                Text("TAKE THE DELOAD")
                                    .font(GSFont.bold(11, relativeTo: .caption2))
                                    .tracking(0.6)
                                    .foregroundStyle(theme.bg)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.accent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                turnCoachNoteDismissedFor = currentExerciseForSheet?.id
                            } label: {
                                Text("NOT TODAY")
                                    .font(GSFont.bold(11, relativeTo: .caption2))
                                    .tracking(0.6)
                                    .foregroundStyle(theme.neutral700)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

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
            // The track and the log path's line share one child: this VStack
            // already sits at ViewBuilder's ten-child ceiling.
            VStack(alignment: .leading, spacing: 0) {
                RPESwipeTrack(value: $logRPE, isFailed: $logIsFailed, theme: theme)

                // THE LOG PATH'S ONE LINE (ruling R-B22). Two states, one
                // line, because they are mutually exclusive by construction: a
                // failed INSERT sets `logSetErrorText` and holds this card up
                // for the retry; a failed FOLLOW-UP on an already-saved set
                // sets `logFollowUpNote`, which clears itself and blocks
                // nothing. Both were write-only until now — plan task S4
                // deleted `legacyBottomChrome`, which was where the banner
                // used to render, so a lifter whose set genuinely failed to
                // save was told nothing at all. This card is the one surface
                // every style's log path mounts (`myTurnFixedPage`, and
                // Together/Freestyle through `entryCard:`), so it is where
                // the line belongs.
                if let line = logSetErrorText ?? logFollowUpNote {
                    Color.clear.frame(height: 6)
                    Text(line.uppercased())
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(logSetErrorText == nil
                                         ? theme.neutral700 : theme.text.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral700.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func turnStepButton(_ glyph: String, detail: String?, action: @escaping () -> Void) -> some View {
        TurnAutoRepeatButton(glyph: glyph, detail: detail, theme: theme, step: action)
    }

    // Pinned chrome: the mic rail + the CTA. (Was 152 pt with the plate
    // rail; the plates left with the soundboard — plan task S4.)
    private var turnChrome: some View {
        VStack(spacing: 0) {
            GSDivider()
            Color.clear.frame(height: 6)
            if burpeesRemaining > 0 {
                burpeeDebtStrip
                Color.clear.frame(height: 6)
            }
            needAMinuteRow
            voiceNotices
            // THE STRIP RIDES WITH THE DOCK (final review, finding 6). On
            // master the reaction pills lived INSIDE `soundboardDock`, so
            // every page that showed a dock could send one; plan task S4
            // deleted that dock and S6/S8 re-hosted the strip on the round
            // wait and spotter pages only, which left a lifter in Together or
            // Freestyle — and a Rounds lifter on their own turn — with no way
            // to react at all, though `tapReaction` and the broadcast path
            // stayed wired the whole time. `turnChrome` is the foot Rounds'
            // my-turn page and Freestyle share, so this mount is two of the
            // three missing pages; Together's own foot carries the third.
            // Same order as the round wait's foot: notices, strip, dock.
            if !reactionEmojis.isEmpty {
                ReactionStrip(emojis: reactionEmojis,
                              onTap: { emoji in Task { await tapReaction(emoji: emoji) } })
                Color.clear.frame(height: 6)
            }
            turnMicRail
            Color.clear.frame(height: 6)

            // `LogControlButton` (RoundPieces.swift, fix round 3 / F6):
            // Together mounts the identical button in its own foot, both
            // built from `logControlFoot` below, so the two mounts cannot
            // draw two different buttons.
            LogControlButton(
                title: logControlFoot.title,
                readback: logControlFoot.readback,
                isFailed: logControlFoot.isFailed,
                isDisabled: logControlFoot.isDisabled,
                onTap: logControlFoot.onTap)
            .padding(.horizontal, 16)
            Color.clear.frame(height: 10)
        }
        .background(theme.bg)
    }

    /// The live log control's current state — shared by `turnChrome`
    /// (Rounds/Freestyle) and `togetherScreen` (Together, fix round 3 /
    /// F6, ruling R-B17). `logControlIsMine` (plan task S5) is what makes
    /// mounting it unconditionally in Together safe: in Rounds the CTA is
    /// the turn-holder's; in Freestyle and Together there is no turn to
    /// hold, so it reads true for everyone. The readback says which, so a
    /// dead button is never a silent one.
    private var logControlFoot: LogControlFoot {
        LogControlFoot(
            title: isLoggingSet ? "LOGGING…" : (logIsFailed ? "LOG FAIL & PASS" : "LOG SET & PASS"),
            readback: isLoggingSet ? nil : turnCTAReadback,
            isFailed: logIsFailed,
            isDisabled: isLoggingSet || !logControlIsMine
                || (leadingInt(logReps) == nil && !logIsFailed),
            onTap: { commitInlineLog() })
    }

    private var turnCTAReadback: String {
        if !logControlIsMine { return "WAITING FOR YOUR TURN" }
        if leadingInt(logReps) == nil && !logIsFailed { return "ENTER REPS TO LOG" }
        let weight = logWeight.isEmpty ? "—" : logWeight
        let reps = leadingInt(logReps).map { "\($0)" } ?? "—"
        let rpe = logIsFailed ? "RPE 10 · MISS" : "RPE \(Int(logRPE))"
        return "\(weight) \(turnUnit.label) × \(reps) · \(rpe)"
    }

    /// THE TWO VOICE NOTICES, above whichever dock is on screen — the
    /// degraded banner and the first-run coach mark (fix round 1 / F2, ruling
    /// R-B12).
    ///
    /// Both lived in `legacyBottomChrome`, which plan task S4 deleted with the
    /// page it served. That left `showVoiceCoachMark` and
    /// `VoiceCoachMarkStore.markShown()` WRITE-ONLY: the one-shot flag was
    /// consumed by a live session with nothing rendered, so a lifter who first
    /// connected voice here (`BurpeeLedgerView`'s direct route does exactly
    /// that) spent their single teaching moment on a blank screen. Neither
    /// object is spectate furniture — the mark teaches the dock, and the
    /// banner is how a degraded room is retried — so both come back above the
    /// dock, same gates and same paddings as before the strip.
    ///
    /// `voicePersistsOnPop`'s doc comment is the reason this cannot be left to
    /// `LobbyView`'s copy: the lobby is not always the route in.
    /// ONE SPELLING FOR TWO FEET (plan task S6): the pinned `turnChrome` here
    /// and the round wait's own pinned foot both render `VoiceNotices` from
    /// this same value, so the mark cannot teach the dock on one page and not
    /// the other.
    private var voiceFoot: VoiceFoot {
        VoiceFoot(isUnavailable: isVoiceEligible && isVoiceUnavailable,
                  showsCoachMark: showVoiceCoachMark,
                  onRetry: { Task { await VoiceRoomService.shared.retry() } },
                  onDismissCoachMark: { showVoiceCoachMark = false })
    }

    /// Mirrors `isVoiceConnected` above — `VoiceRoomState` is not `Equatable`,
    /// so the case test is spelled out.
    private var isVoiceUnavailable: Bool {
        if case .unavailable = VoiceRoomService.shared.state { return true }
        return false
    }

    private var voiceNotices: some View {
        VoiceNotices(foot: voiceFoot)
    }

    /// The mic rail: what is left of the plate dock (plan task S4) once the
    /// plates and the ALL door left with the soundboard. Push-to-talk is NOT
    /// collateral (plan constraint 21), and it sits exactly where it sat.
    private var turnMicRail: some View {
        Group {
            HStack(spacing: 8) {
                Spacer(minLength: 4)

                if isVoiceEligible {
                    PTTDockRow(otherParticipantNames: otherParticipantNames, compact: true)
                }
            }
            .padding(.horizontal, 16)
        }
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
    // the chain itself is layered — arenaBase (page + chrome) →
    // arenaWithLifecycle (prefill + turn poll) → body (sheets, dialogs,
    // lifecycle). Each layer is a separately-checked expression.
    /// Exercise whose detail page (video demo + history) is open as a sheet —
    /// set by tapping the exercise name on `turnExerciseCard` (user
    /// 2026-08-11; the spotlight/spectate headers that also raised it left in
    /// plan task S4 and plan task S13's dead-member sweep in turn). A sheet,
    /// not a push, so dismissing it lands straight back in the session.
    @State private var exerciseDetailSheet: Exercise?

    var body: some View {
        arenaWithLifecycle
        .overlay(alignment: .top) { topNotices }
        // Log Set sheet — penalty (burpee) logging only now; normal sets log inline.
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showLogSetSheet) { logSetSheetContent }
        .sheet(isPresented: $showGroupSwapSheet) { groupSwapSheet }
        .sheet(isPresented: $showGroupCoachRecap) {
            if let debrief = groupDebrief {
                CoachRecapView(
                    debrief: debrief,
                    persona: CoachPersona.bySlug(groupCoachProfile.persona),
                    profile: groupCoachProfile,
                    trendLookup: { [history = groupTrendHistory] name in
                        if let logs = history[name.lowercased()], logs.count > 1 {
                            return DebriefBuilder.trendSentence(name: name, logs: logs)
                        }
                        return "\(name): not enough logged history for a trend yet — today's numbers are in the report."
                    },
                    volumeLookup: {
                        "Per-muscle weekly volume lands in an upcoming update — ask about any lift's trend instead."
                    })
            }
        }
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
            // Review finding carried from S1-S4 (R-B2-11's leg), closed by
            // plan task S10: this was the one load-path hook left unguarded
            // when frame 145 (`session-your-turn`) landed — a catalog capture
            // never joins voice (constraint 10), so `isVoiceConnected` cannot
            // flip true under one, but the guard is added here for the same
            // reason every other hook in this file carries it: a property of
            // the code, not of a list somebody keeps up to date.
            guard !catalogSkipLoad else { return }
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
            recapSheetContent(data)
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
        //
        // LOAD PATH 3 of 9 (plan task S4), and the widest: `reload()`'s three
        // repository fetches, `ExerciseNameCache.preload()`, the realtime
        // channel, `subscribeBroadcast()`'s reaction + `HeartRateBroadcastService`
        // subscriptions, `BLEHeartRateService`, `joinVoiceIfEligible()` and
        // `touchActivity`. Constraint 10's other half lives behind this guard.
        .task {
            guard !catalogSkipLoad else { return }
            await openAndSubscribe()
        }
        .onChange(of: liveSession.currentTurnUserID) { _, _ in
            // `logControlIsMine`, not `newValue == selfID` (fix round 4 /
            // finding 1, ruling R-B21): Together and Freestyle never carry
            // a turn to compare against, so gating this on the turn holder
            // left their entry blank forever. Rounds is unaffected — the
            // predicate reduces to the same `isMyTurn` check it always was.
            if logControlIsMine { prefillLogInputs() }
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
            // `routineID` is a `let` on a seeded `liveSession` that nothing
            // in a capture reassigns, so this cannot fire — guarded because
            // `reload()` is three repository fetches (plan task S4).
            guard !catalogSkipLoad else { return }
            Task { await reload() }
        }
        // A new round is a new wait (plan task S7). The minute a lifter took
        // in round 3 must not still be holding the crew off in round 4; the
        // once-per-exercise gate is deliberately NOT reset here, because a
        // minute is once per exercise and an exercise outlives a round.
        // `liveSession.round` is the SERVER's round, arriving on the
        // `sessions` UPDATE the realtime channel carries (or led by the log
        // path's own `advance_round` return — ruling R-B22, which is what
        // finally gives this handler something to fire on outside a crew
        // skip). Ruling R-B23: the round wait reads that live value and
        // nothing cached.
        .onChange(of: liveSession.round) { _, _ in
            minuteExtensionsThisRound = 0
        }
        // Rest buzz (owner 2026-08-14) — one observation point for the
        // self-rotation interlude, same shape as solo's restEndAt wire.
        // The same point PERSISTS the window to LiveSessionTimerStore so a
        // sheet swipe-down/rejoin can't erase a running rest.
        .onChange(of: selfRotationRestUntil) { _, _ in
            // A capture never enters the rest interlude (nothing logs), so
            // this cannot fire — the guard is here so that stays true if
            // something later seeds the window (`RestNotifier` schedules a
            // local notification, and `LiveSessionTimerStore` writes to disk).
            guard !catalogSkipLoad else { return }
            if let end = selfRotationRestUntil {
                RestNotifier.schedule(at: end)
            } else {
                RestNotifier.cancel()
            }
            LiveSessionTimerStore.shared.updateRest(
                sessionID: session.id,
                until: selfRotationRestUntil,
                startedAt: selfRotationRestStartedAt,
                isTransit: selfRotationRestIsTransit)
        }
        .onChange(of: selfRotationRestDrops) { _, _ in
            guard !catalogSkipLoad else { return }
            LiveSessionTimerStore.shared.updateDrops(
                sessionID: session.id, drops: selfRotationRestDrops)
        }
        // LOAD PATH 4 of 9 (plan task S4): `LiveSessionTimerStore.shared
        // .snapshot(for:)` — guarded here AND inside `restoreTimersFromStore`
        // itself, so a future second call site cannot miss it.
        .onAppear {
            guard !catalogSkipLoad else { return }
            restoreTimersFromStore()
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
            // LOAD PATH 5 of 9 (plan task S4): `reload()`, `subscribeBroadcast()`
            // and `touchActivity` all over again on every foreground.
            guard !catalogSkipLoad else { return }
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
            // LOAD PATH 6 of 9 (plan task S4), and CONSTRAINT 10's other
            // named site: `WatchConnectivityBridge.activateIfNeeded()`. A
            // capture must also not claim `appState.activeSessionID` /
            // `liveGroupSession` — that would suppress push banners and raise
            // the SESSION LIVE pill for a session that does not exist — and
            // must not register `ThemeStore.shared.onShareHeartRateChange`,
            // a global hook this view's `.onDisappear` is the only clearer of.
            guard !catalogSkipLoad else { return }
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
            // THE TEARDOWN'S OWN GUARD (plan task S4). Nothing was opened, so
            // nothing is closed — and `VoiceRoomService.shared.leave()` at the
            // bottom of this block would otherwise hang up a room some OTHER
            // screen in the catalog host is holding.
            guard !catalogSkipLoad else { return }
            // Only clear the suppression flag if it's still pointing at THIS
            // session — a second SessionLiveView push (or a fast
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
            // clear above needs): only one `SessionLiveView` is ever
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

    /// Layer 1: the page + the pinned chrome.
    private var arenaBase: some View {
        ZStack(alignment: .bottom) {
            // THE PAGE, CHOSEN BY STYLE AND WHOSE TURN IT IS (plan tasks S4,
            // S6, S10). The spectate sister page and the roster-failure
            // scroll layout are gone; in Rounds, a crewmate who is not
            // lifting gets the ROUND WAIT in their place, and everyone else —
            // every lifter on their turn — gets the my-turn page. Freestyle
            // and Together have no turn at all (S5), so every lifter in
            // either gets that style's own page instead; Freestyle's still
            // composes above `bottomChrome`'s pinned `turnChrome` for the
            // actual log control (`freestylePage`'s own doc comment).
            if style == .together {
                togetherPage
            } else if style == .freestyle {
                freestylePage
            } else if showsSpotter {
                spotterPage
            } else if showsRoundWait {
                roundWaitPage
            } else {
                myTurnFixedPage
            }
            prOverlayLayer
            reactionOverlayLayer
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .sensoryFeedback(.success, trigger: logHapticTick)
        .onChange(of: selfHeartRate?.bpm) { _, newValue in
            // A seeded reading never changes, so this cannot fire in a
            // capture — and it reads `Date()` (plan task S4, constraint 11).
            guard !catalogSkipLoad else { return }
            guard let newValue else { return }
            recoveryBuffer.append(bpm: newValue, at: Date().timeIntervalSinceReferenceDate)
        }
        // Pushed via LobbyView → SessionInProgressView; the bottom action bar
        // below is bottom-pinned — see GSComponents.swift's GSHidesDock for
        // why the custom app dock can't reach it via safeAreaInset alone.
        .gsHidesDock()
        // Keyboard overlays EVERYTHING, chrome included (user round 3: the
        // CTA was still lifting above the numpad, leaving a stacked buffer).
        // Applied outside the safeAreaInset so neither the page nor the
        // pinned chrome moves while typing; the keyboard simply covers the
        // bottom and everything is exactly where it was on dismiss.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom) { bottomChrome }
    }

    /// Layer 2: the lifecycle chain. Was `arenaWithThrow` — the throw arena's
    /// coordinate space, its drag overlay and its grab haptic left with the
    /// throw itself, and the BOARD's baseline load left with the BOARD (plan
    /// task S4). The LAYER stays: the split exists for the type-checker, not
    /// for the throw (see the note above `body`).
    private var arenaWithLifecycle: some View {
        arenaBase
            // The exercise advancing (RoutineProgression) re-prefills the
            // entry. Field bug 2026-07-31: the squat weight rode into the
            // curls because prefill only fired on turn CHANGES — and a solo
            // rotation's turn never changes (self → self).
            .onChange(of: currentExerciseForSheet?.id) { _, _ in
                // `logControlIsMine`, not `isMyTurn` (fix round 4 / finding
                // 1, ruling R-B21) — Freestyle progresses through exercises
                // per lifter same as Rounds, but `isMyTurn` never becomes
                // true there, so the old gate never re-prefilled it.
                if logControlIsMine { prefillLogInputs() }
            }
            // Realtime fallback: the turn state POLLS every 10s while live
            // (field 2026-07-31: one phone's dead websocket — "Voice
            // unavailable" — made turn passes invisible to it; push-only
            // signals strand whoever's socket died). Cheap single-row read;
            // only a genuinely newer turn/state is applied, so the realtime
            // echo remains the fast path.
            .task(id: liveSession.state) {
                // LOAD PATH 7 of 9 (plan task S4): the 10 s turn poll, a
                // `SessionRepository.session(id:)` read that never ends.
                guard !catalogSkipLoad else { return }
                guard liveSession.state == "in_progress" else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let fresh = try? await SessionRepository.session(id: session.id) else { continue }
                    // `liftingStartedAt` STAYS in the freshness check: this
                    // view still needs to notice the flip, because a client
                    // that mounted the arena on a stale row would be lifting
                    // against a session the server says has not started.
                    // `warmupMinutes` leaves with the phase (plan task S9) —
                    // `SessionRunnerView` owns the pre-lifting poll now.
                    if fresh.turnVersion > liveSession.turnVersion || fresh.state != liveSession.state
                        || fresh.liftingStartedAt != liveSession.liftingStartedAt {
                        liveSession = fresh
                    }
                }
            }
            // THE STATION SPLIT (plan task S3). `.task(id:)` rather than
            // `.onChange` so the crew's FIRST exercise is assigned too, and
            // `set_session_stations`' idempotency on the exercise position is
            // what makes every repeat free.
            .task(id: currentRoutineExercise?.position) {
                // LOAD PATH 8 of 9 (plan task S4): `remixStations` calls
                // `set_session_stations`, a WRITE — the one load path that
                // would change a real row.
                guard !catalogSkipLoad else { return }
                // THE EXERCISE CHANGED, so anything still held for the one we
                // just left celebrates now (ruling R-OD-2). This `.task(id:)`
                // rather than a new `.onChange`: the exercise's position is
                // already this chain's identity, and `body`'s modifier chain
                // has blown the type-checker's budget twice.
                await flushPendingPRs(except: currentExerciseForSheet?.id)
                // The celebration's sound, built and decoded ahead of the
                // moment rather than inside the overlay's animation turn
                // (ruling R-OD-4). Idempotent — the second call onwards is a
                // no-op — and silent when the resource is missing.
                await MainActor.run { CelebrationSound.prepare() }
                // THE VENUE'S RACK COUNTS, before the split that spends them
                // (plan task S6). Its own `isEmpty` guard makes every repeat
                // free; a failure leaves the cap unknown, which is today's
                // `ceil(crew / 3)`.
                await loadVenueRackCounts()
                guard let position = currentRoutineExercise?.position else { return }
                await remixStations(exercisePosition: position)
            }
            // COACH'S ROOM (plan task S6). On THIS layer rather than on
            // `body`: the split above exists because `body`'s ~25-modifier
            // chain twice blew the type-checker's budget (two CI timeouts),
            // and a `navigationDestination` plus a `sheet` are two more links
            // in whichever chain they join.
            .navigationDestination(item: $openedCoachThread) { opened in
                CoachThreadView(thread: CoachChatThread(
                    id: opened.thread.threadID,
                    title: SessionCopy.talkToCoach,
                    summary: "",
                    summarizedThrough: nil,
                    updatedAt: liveSession.scheduledFor ?? liveSession.createdAt))
                    .background(theme.bg)
                    .navigationTitle(SessionCopy.talkToCoach)
                    .navigationBarTitleDisplayMode(.inline)
            }
            // The door's paywall, for the branch `open()` takes when the crew
            // cannot reach the room. No `highlight`: none of
            // `Monetization.Feature`'s cases names a session Coach room, and
            // inventing one is a product decision this task is not making.
            .sheet(isPresented: $showCoachPaywall) {
                PaywallView()
            }
    }

    /// The pinned bottom chrome (extracted from the safeAreaInset closure).
    ///
    /// EMPTY WHILE A CREW PAGE IS UP (plan tasks S6 and S8): `RoundPage` pins
    /// its own foot inside the page, so a chrome here would put a second dock
    /// under the first one. The my-turn page has no foot of its own, which is
    /// why it still needs this.
    @ViewBuilder
    private var bottomChrome: some View {
        if style != .together, !showsCrewPage { turnChrome }
    }

    /// THE CREW'S ROUTINE CHANGE (plan task S1, spec §3.4 mode 1, decision 3).
    ///
    /// Was `swapVoteBanner`: one line, a bare count and two capsule pills,
    /// with the old exercise named only inside a sentence. You cannot consent
    /// to a swap you cannot look up, so the card `SwapConsentCard` draws in
    /// its place makes both exercises doors onto the real exercise page.
    ///
    /// THE FIVE SOURCES ARE THE BANNER'S OWN — `swapProposal`, `participants`,
    /// `presentRotation`, `exerciseNames` and `allExercises`. Nothing about
    /// the wire moved (constraint 21): `receiveSwap`, `evaluateUnanimity`,
    /// `armProposalExpiry` and the broadcast payloads are untouched, and the
    /// two answers are `castVote(true)` / `castVote(false)` exactly as before.
    private var swapConsentModel: SwapConsentCard.Model? {
        guard let proposal = swapProposal else { return nil }
        let proposer = participants.first { $0.participant.userID == proposal.proposerID }?
            .profile.username ?? "Someone"
        let fromName = exerciseNames[proposal.exerciseID]
            ?? allExercises.first(where: { $0.id == proposal.exerciseID })?.name
            ?? "this exercise"
        let agreedIDs = Set(proposal.votes.filter { $0.value }.map(\.key))
        // The pips count the PRESENT crew, because that is exactly the set
        // `evaluateUnanimity` requires to have said yes. `max` guards the one
        // case where a vote can outrun the roster this client has fetched —
        // a meter showing 3 of 2 would be worse than a wide one.
        let crewSize = max(presentRotation.count, agreedIDs.count)
        let details = swapDoorDetails(for: proposal.exerciseID,
                                      target: proposal.target.id)
        return SwapConsentCard.Model(
            proposerName: SessionCopy.firstName(proposer),
            from: SwapConsentCard.Door(
                exerciseID: proposal.exerciseID,
                name: fromName,
                detail: details.now,
                // A door this client cannot open is drawn as a line, not as
                // a button that does nothing (`ExerciseDoorRow`'s own rule).
                opens: allExercises.contains(where: { $0.id == proposal.exerciseID })),
            to: SwapConsentCard.Door(
                exerciseID: proposal.target.id,
                name: proposal.target.name,
                detail: details.proposed,
                opens: allExercises.contains(where: { $0.id == proposal.target.id })),
            crewSize: crewSize,
            agreed: agreedIDs.count,
            agreedNames: presentRotation
                .filter { agreedIDs.contains($0.participant.userID) }
                .map { SessionCopy.firstName($0.profile.username) },
            iHaveAnswered: selfID.map { proposal.votes[$0] != nil } ?? true)
    }

    /// Both doors' load lines, from the ONE routine row the swap would
    /// replace. A row the routine does not carry prints the honest dash
    /// `SessionPlanRow.prescription(for:)` already returns.
    ///
    /// THE PROPOSED DOOR IS THE SWAP'S OWN ROW (R-B2-15). It used to be a hand
    /// copy — `var swapped = re; swapped.targetWeight = nil` — which agreed
    /// with the real rebuild on most rows and disagreed on a to-failure one:
    /// the door printed `3 × AMRAP` while `effectiveRoutineExercises` produced
    /// `3 × —`, because the rebuild dropped `targetFailure` and the copy kept
    /// it. Both now go through `RoutineLayering.swapped(_:to:)`, so a door cannot promise
    /// a prescription the swap does not produce, whatever field is added next.
    private func swapDoorDetails(for exerciseID: UUID,
                                 target: UUID) -> (now: String, proposed: String) {
        guard let re = routineExercises.first(where: { $0.exerciseID == exerciseID }) else {
            return ("—", "—")
        }
        return (SessionPlanRow.prescription(for: re),
                SessionPlanRow.prescription(for: RoutineLayering.swapped(re, to: target)))
    }

    /// THE BODY'S ONE TOP SLOT (plan tasks S1 and S3).
    ///
    /// Both notices want the same place — under the 44 pt header rail, over
    /// whichever of the five pages is up — and both are rare, so they share
    /// one slot rather than stacking on each other or adding a second
    /// `.overlay` link to `body`'s chain (the split above `body` exists
    /// because that chain blew the type-checker's budget twice).
    ///
    /// AN OPEN PROPOSAL WINS. It is a question addressed to this lifter with
    /// a deadline on it (`armProposalExpiry`, 120 s); the error is a
    /// statement about something already over. Nothing is lost either way —
    /// `errorText` holds until it is tapped or the next attempt succeeds.
    @ViewBuilder
    private var topNotices: some View {
        if swapConsentModel != nil {
            swapConsentOverlay
        } else {
            errorBannerOverlay
        }
    }

    /// THE LIVE BODY'S ERROR LINE, SHOWN (plan task S3).
    ///
    /// `errorText` had twelve writers and no reader at all: plan task S4
    /// deleted `legacyBottomChrome`, which was where its banner used to
    /// render, so a failed "End for everyone", a failed Leave, a failed crew
    /// skip and a failed penalty log all told the lifter nothing whatsoever.
    /// Mounted ONCE here on the body root rather than per page, so all five
    /// pages are covered by one mount.
    ///
    /// RED IS THE TEXT, NOT THE SURFACE (rule 2). This is deliberately not
    /// `GSInlineErrorBanner`, whose whole face is the accent: the accent on
    /// every one of these pages is already spent on the LOG control, and a
    /// solid-accent banner would be the page's second shout. No retry button
    /// either — each of these verbs has its own control still on screen, and
    /// a second "Try again" would be a second way to press the same thing.
    @ViewBuilder
    private var errorBannerOverlay: some View {
        if let text = errorText {
            Button { errorText = nil } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 5) {
                        (
                            Text(SessionCopy.verbFailed)
                                .font(GSFont.bold(13, relativeTo: .footnote))
                            + Text(" \(text)")
                                .font(GSFont.body(13, relativeTo: .footnote))
                        )
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(SessionCopy.verbFailedDismiss)
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(0.9)
                            .foregroundStyle(theme.neutral500)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusMd)
                    .strokeBorder(theme.divider, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusMd))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 52)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// The card, mounted where the banner was mounted, with the same
    /// transition.
    @ViewBuilder
    private var swapConsentOverlay: some View {
        if let model = swapConsentModel {
            SwapConsentCard(
                model: model,
                // The sheet the body already presents (`:exerciseDetailSheet`),
                // so a door opens the real exercise page with its own PR and
                // trend reads rather than a second, thinner copy of it.
                onOpen: { exerciseID in
                    exerciseDetailSheet = allExercises.first(where: { $0.id == exerciseID })
                },
                onAgree: { castVote(true) },
                onKeep: { castVote(false) })
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Swap sheet: candidates from the substitution graph (coached edges
    /// first), same-muscle/pattern neighbors as fallback - the solo swap
    /// sheet's exact sourcing, plus the just-me / squad-vote mode switch.
    private var groupSwapSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Who is this for?", selection: $swapForSquad) {
                        Text("Just me").tag(false)
                        Text("Squad vote").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(swapForSquad
                         ? "Everyone votes. It only applies if the whole squad is in."
                         : "Your remaining sets use the swap - shown on your turn, never announced.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                if groupSwapOptions.isEmpty {
                    Text("Looking for swaps…")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                }
                ForEach(groupSwapOptions) { option in
                    Button { chooseSwap(option) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.name)
                                .font(GSFont.bold(15, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Text(option.detail)
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Swap \(currentExerciseForSheet?.name ?? "exercise")")
            .navigationBarTitleDisplayMode(.inline)
            // LOAD PATH 9 of 9 (plan task S4): `ExerciseSubstitutionRepository`.
            // The sheet is never presented in a capture — `showGroupSwapSheet`
            // starts false and nothing taps — but a guard on the presentation
            // is not a guard on the fetch, and this is the fetch.
            .task {
                guard !catalogSkipLoad else { return }
                await loadGroupSwapOptions()
            }
        }
    }

    // MARK: - Reaction strip
    //
    // MOVED TO `Live/RoundPieces.swift` as the value-in `ReactionStrip` (plan
    // task S6, fix round 1 / F3). It sat here with no call site from S4 until
    // then, which meant the crew could not react from the live view at all.
    // Fix round 5 (final review, finding 6) finished the job: on master the
    // pills lived INSIDE the dock, so the strip belongs on every page that
    // shows one — the round wait's and spotter's feet, `turnChrome`
    // (Rounds-my-turn and Freestyle) and Together's foot, five of five.
    // `reactionEmojis` above is still the one list. Nothing about the pills'
    // drawing changed.

    // Reps/weight stepper cell and its arithmetic helpers now live in LogSetSheet.swift
    // (shared, internal — see `stepperCell`, `decrementInt`/`incrementInt`/
    // `decrementDecimal`/`incrementDecimal`) so this view no longer duplicates them.

    // MARK: - Rotation strip (my turn) — p06 "NOW / NEXT / 3RD / 4TH" tiles
    //
    // MOVED TO `Live/RoundPieces.swift` as the value-in `TurnStrip` (plan
    // task S8). It had had no call site since the strip took the page that
    // mounted it; spotter mode is the caller, and `turnStripTiles` below
    // builds its tiles from `rotationTiles`, which is unchanged. Nothing
    // about the drawing changed — only who owns it and whether the current
    // tile is filled with accent, which is now the caller's to say.

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
            routine: effectiveRoutineExercises,
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
        effectiveRoutineExercises.first(where: { $0.exerciseID == exerciseID })?.targetReps
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

    /// Commit the inline "LOG THIS SET" card — delegates to `logSetAndAdvance`
    /// (same priorMax-before-insert ordering, same PR pipeline). Only the
    /// caller changed (was a sheet's onLog closure).
    ///
    /// THE INSERT IS THE TRANSACTION (ruling R-B22): `logSetAndAdvance`
    /// answers `true` the moment the set is durably recorded, so everything
    /// below — closing the loader, dismissing the keyboard, re-prefilling —
    /// runs on every saved set in every style, whatever the follow-up RPCs
    /// went on to return. `false` now means one thing only: nothing was
    /// saved. That is what makes the retry this card offers honest, and it is
    /// what closes the duplicate hazard the final review found (finding 1),
    /// where a P0001 from `advance_turn` — raised at every Together and
    /// Freestyle lifter who was not the turn holder — kept the card up over a
    /// set that was already in the database.
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
            // the round wait (plan task S6). A set that never saved keeps
            // everything up for a retry — it also must NOT enter the rest
            // interlude below.
            withAnimation(.easeInOut(duration: 0.18)) { showBarLoader = false }
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // Together and Freestyle have no turn to hand the card back
            // through (fix round 4 / finding 1, ruling R-B21) — Rounds gets
            // its reset from the turn/exercise-change handlers above once
            // the rotation returns to this lifter; these two styles never
            // see that handler fire, so they get the reset explicitly here,
            // on every successful log.
            if style != .rounds { prefillLogInputs() }
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
                    routine: effectiveRoutineExercises,
                    completedSets: { id in id == ex.id ? preLogSetCount + 1 : mySetCount(for: id) })
                let exerciseChanged = nextRE != nil && nextRE?.exerciseID != ex.id
                // Superset handoff (phase B group mirror): A→B is the same
                // station cluster with NO rest — skip the interlude
                // entirely and stay on my-turn for the partner's set.
                let currentRE = effectiveRoutineExercises.first(where: { $0.exerciseID == ex.id })
                if exerciseChanged,
                   RoutineProgression.arePaired(currentRE, nextRE, in: effectiveRoutineExercises) {
                    // No interlude — the pair's whole point.
                } else {
                    let isTransit = exerciseChanged
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
    }

    /// Re-seed the self-rotation rest window + recovery-drop history from
    /// the store after a sheet swipe-down/rejoin (owner bug 2026-08-14).
    /// The window only restores while still in the future, and its
    /// auto-clear task is RE-ARMED here — the original died with the view.
    private func restoreTimersFromStore() {
        // Guarded here as well as at its one `.onAppear` call site (plan task
        // S4): a store read is a disk read, and a re-armed clear `Task` is a
        // clock.
        guard !catalogSkipLoad else { return }
        guard let snap = LiveSessionTimerStore.shared.snapshot(for: session.id) else { return }
        if selfRotationRestDrops.isEmpty, !snap.restDrops.isEmpty {
            selfRotationRestDrops = snap.restDrops
        }
        guard selfRotationRestUntil == nil,
              let until = snap.restUntil, until > .now else { return }
        selfRotationRestUntil = until
        selfRotationRestStartedAt = snap.restStartedAt
        selfRotationRestIsTransit = snap.restIsTransit
        Task {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            if selfRotationRestUntil == until {
                captureSelfRotationRestDrop()
                selfRotationRestUntil = nil
            }
        }
    }

    // MARK: - Watch bridge (Phase W Task 2, watch-hr design §3)

    /// Builds a `WatchSessionStatePayload` from this view's OWN already-
    /// fetched models — `liveSession` (`WorkoutSession`), `rotationOrder`
    /// (`[(SessionParticipant, Profile)]`, this file's line 257),
    /// `currentExerciseForSheet` (`Exercise`, this file's own property
    /// above) — the exact same derivations the my-turn page already
    /// renders, not a second computation. See `WatchConnectivityBridge`'s
    /// header doc comment for why the bridge itself accepts this
    /// already-built payload instead of re-deriving it. Called from
    /// `.onAppear` (initial snapshot), `.onChange(of: liveSession.currentTurnUserID)`
    /// (turn passes — the state most likely to matter to someone glancing
    /// at their Watch), `.onChange(of: liveSession.state)` (Task 3 fix wave
    /// 1 addition, immediately above both `.onChange` blocks in `body` —
    /// right after `reload()`, once more once the live subscription is up),
    /// and `endSession()`.
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
        // CONSTRAINT 10, AT THE FUNCTION RATHER THAN AT ITS SIX CALL SITES
        // (plan task S4). `.onAppear`, three `.onChange` handlers,
        // `openAndSubscribe()` and `presentCompletion()` all reach
        // `WatchConnectivityBridge` through here; guarding the function is
        // what makes "no catalog path reaches the Watch bridge" a property of
        // the code rather than of a list somebody keeps up to date.
        guard !catalogSkipLoad else { return }
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
            shareHeartRate: ThemeStore.shared.shareHeartRate,
            // Always sample: it is the athlete's own number on their own
            // screen. Whether it is BROADCAST is still shareHeartRate's
            // decision, made phone-side.
            sampleHeartRate: true
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
                    "SessionLiveView openAndSubscribe: GroupRepository.fetch failed for group \(groupID, privacy: .public) on a real group session — completion will downgrade to SessionRecapView instead of frame-8 GroupRecapView: \(error, privacy: .public)")
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
        // Task 5 — the `shareHeartRate` fetch that used to live here was
        // removed: `pushWatchSessionState()` now reads `ThemeStore.shared
        // .shareHeartRate` live on every call instead (see that call site's
        // own doc comment) — `ThemeStore.shared.load()` is bootstrapped
        // once at `MainTabView`'s own `.task` (`App/RootView.swift:215-221`,
        // "runs on every launch that reaches signed-in + profile-loaded
        // state"), well before a user can navigate deep enough to reach a
        // live session, so no separate fetch is needed here.
        // Re-push now that the live subscription is up, so a Watch that was
        // already reachable sees this session's current state.
        pushWatchSessionState()
        await subscribeBroadcast()
        // `logControlIsMine`, not `isMyTurn` (fix round 4 / finding 1,
        // ruling R-B21) — this is the PAGE-APPEAR prefill, and Together and
        // Freestyle open with no turn at all, so `isMyTurn` never fired it:
        // the entry sat blank, forever, for every lifter in either style.
        if logControlIsMine { prefillLogInputs() }
        // Initial heartbeat — the scenePhase→active heartbeat above only
        // fires on a later transition, so this covers "already foreground,
        // just opened the session" (push-dossier.md §A.4).
        try? await SessionRepository.touchActivity(sessionID: liveSession.id)
    }

    /// Subscribe to broadcast events (reactions + swaps). Mirrors the SessionLiveService
    /// lifecycle — call from .task and re-call on scenePhase → active reload path.
    @MainActor
    private func subscribeBroadcast() async {
        await broadcastService.subscribe(
            sessionID: liveSession.id,
            // The soundboard PARAMETER left with the service's soundboard
            // half in plan task S11; the reaction stream beside it stays
            // (plan constraint 21).
            onReaction: { _, emoji in
                Task { @MainActor in
                    // "I need a minute" rides this channel (plan task S7):
                    // the marker extends THIS client's threshold as well as
                    // floating its glyph, so the whole crew's skip offer
                    // moves out together. Any count above one buys nothing,
                    // so a self-echo double-count is harmless.
                    if emoji == RoundCopy.minuteMarker {
                        minuteExtensionsThisRound += 1
                    }
                    await showReactionOverlay(emoji)
                }
            },
            onSwap: { event in
                receiveSwap(event)
            }
        )
        // Phase W Task 5 (watch-hr design §4) — subscribes alongside the
        // reaction broadcast subscribe immediately above, per the task
        // brief's explicit instruction to add this "alongside its existing
        // broadcast subscriptions." `onHeartRate` is already
        // `@MainActor`-typed (`HeartRateBroadcastService.subscribe`'s own
        // signature), so `receiveHeartRate` is called directly here — no
        // extra `Task { @MainActor in ... }` wrapper needed the way
        // `onReaction` above uses one (that wrapper exists only because
        // `showReactionOverlay` is itself `async`; `receiveHeartRate` is
        // synchronous).
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

    // MARK: - Hot-swap wire handling

    /// All swap events land here. Idempotent by design - the sender's own
    /// local state was already set at send time, so a self-echo re-applies
    /// the same values. UNANIMITY is evaluated by the PROPOSER's client
    /// only (one decision point beats racy per-client tallies); everyone
    /// else applies on the proposer's "apply".
    @MainActor
    private func receiveSwap(_ event: SessionBroadcastService.SwapEvent) {
        switch event.kind {
        case "self":
            // Quiet: store and show on their set. Never an overlay.
            selfScales[event.userID, default: [:]][event.exerciseID] =
                SwapTarget(id: event.replacementID, name: event.replacementName)
            exerciseNames[event.replacementID] = event.replacementName
        case "propose":
            guard let pid = event.proposalID else { return }
            // A newer proposal replaces an older one (last write wins -
            // one vote at a time keeps the banner comprehensible).
            var proposal = SwapProposal(
                id: pid, proposerID: event.userID,
                exerciseID: event.exerciseID,
                target: SwapTarget(id: event.replacementID, name: event.replacementName),
                votes: [event.userID: true])
            if let existing = swapProposal, existing.id == pid {
                proposal.votes.merge(existing.votes) { new, _ in new }
            }
            swapProposal = proposal
            armProposalExpiry(pid)
        case "vote":
            guard var proposal = swapProposal, proposal.id == event.proposalID else { return }
            proposal.votes[event.userID] = event.vote ?? false
            if event.vote == false {
                // Unanimous means unanimous: one pass ends it, quietly.
                clearProposal()
                return
            }
            swapProposal = proposal
            // Proposer's client is the single decision point.
            if proposal.proposerID == selfID { evaluateUnanimity(proposal) }
        case "apply":
            squadSwaps[event.exerciseID] =
                SwapTarget(id: event.replacementID, name: event.replacementName)
            exerciseNames[event.replacementID] = event.replacementName
            clearProposal()
        default:
            break
        }
    }

    @MainActor
    private func evaluateUnanimity(_ proposal: SwapProposal) {
        // Everyone the server would hand a turn to must have said yes.
        let present = Set(presentRotation.map(\.participant.userID))
        let yes = Set(proposal.votes.filter { $0.value }.map(\.key))
        guard !present.isEmpty, present.subtracting(yes).isEmpty else { return }
        squadSwaps[proposal.exerciseID] = proposal.target
        exerciseNames[proposal.target.id] = proposal.target.name
        clearProposal()
        Task {
            await broadcastService.sendSwap(
                sessionID: liveSession.id, kind: "apply", proposalID: proposal.id,
                exerciseID: proposal.exerciseID,
                replacementID: proposal.target.id,
                replacementName: proposal.target.name)
        }
    }

    @MainActor
    private func clearProposal() {
        swapProposalExpiry?.cancel()
        swapProposalExpiry = nil
        swapProposal = nil
    }

    /// A proposal nobody resolves dies quietly after two minutes.
    @MainActor
    private func armProposalExpiry(_ pid: UUID) {
        swapProposalExpiry?.cancel()
        swapProposalExpiry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, swapProposal?.id == pid else { return }
            clearProposal()
        }
    }

    // MARK: - Hot-swap actions

    private func loadGroupSwapOptions() async {
        guard let current = currentExerciseForSheet else { return }
        var options: [GroupSwapOption] = []
        var seen: Set<UUID> = [current.id]
        if let edges = try? await ExerciseSubstitutionRepository.forExercise(slug: current.slug) {
            for edge in edges {
                guard let match = allExercises.first(where: { $0.slug == edge.toSlug }),
                      match.aliasOf == nil, !seen.contains(match.id) else { continue }
                seen.insert(match.id)
                options.append(GroupSwapOption(id: match.id, name: match.name,
                                               detail: edge.reason))
            }
        }
        for ex in allExercises where ex.aliasOf == nil
            && ex.primaryMuscle == current.primaryMuscle
            && ex.movementPattern == current.movementPattern
            && !seen.contains(ex.id) {
            seen.insert(ex.id)
            options.append(GroupSwapOption(id: ex.id, name: ex.name,
                                           detail: "Same muscle, same pattern"))
            if options.count >= 10 { break }
        }
        groupSwapOptions = options
    }

    @MainActor
    private func chooseSwap(_ option: GroupSwapOption) {
        guard let ex = currentExerciseForSheet, let selfID else { return }
        showGroupSwapSheet = false
        let target = SwapTarget(id: option.id, name: option.name)
        if swapForSquad {
            let pid = UUID()
            swapProposal = SwapProposal(id: pid, proposerID: selfID,
                                        exerciseID: ex.id, target: target,
                                        votes: [selfID: true])
            armProposalExpiry(pid)
            Task {
                await broadcastService.sendSwap(
                    sessionID: liveSession.id, kind: "propose", proposalID: pid,
                    exerciseID: ex.id, replacementID: target.id,
                    replacementName: target.name)
            }
        } else {
            selfScales[selfID, default: [:]][ex.id] = target
            exerciseNames[target.id] = target.name
            Task {
                await broadcastService.sendSwap(
                    sessionID: liveSession.id, kind: "self", proposalID: nil,
                    exerciseID: ex.id, replacementID: target.id,
                    replacementName: target.name)
            }
        }
    }

    @MainActor
    private func castVote(_ yes: Bool) {
        guard var proposal = swapProposal, let selfID else { return }
        proposal.votes[selfID] = yes
        if yes {
            swapProposal = proposal
        } else {
            clearProposal()
        }
        Task {
            await broadcastService.sendSwap(
                sessionID: liveSession.id, kind: "vote", proposalID: proposal.id,
                exerciseID: proposal.exerciseID,
                replacementID: proposal.target.id,
                replacementName: proposal.target.name, vote: yes)
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
        let parsedZone = HeartRateZone(rawValue: zone ?? "")
        heartRates[userID] = (bpm, parsedZone, now)
        // Together's timeline (plan task S9): the last reading of each
        // interval, per lifter. A no-op for the other two styles, which draw
        // no timeline -- and free, because the sample is already here.
        // The BROADCAST zone rides along (fix round 3 / F7) -- the same
        // `parsedZone` the live pill above reads, never recomputed a
        // second time from `bpm`.
        if style == .together, let position = togetherPosition {
            togetherTrace.record(userID: userID, bpm: bpm, zone: parsedZone, interval: position.index)
        }
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
    /// hygiene + a re-render trigger, not the source of truth.
    /// `selfHeartRate`, `crewHeartRateRows` (plan task S8) and
    /// `togetherLanes` (plan task S9) all call this rather than reading
    /// `heartRates` directly.
    private func heartRateFor(_ userID: UUID) -> (bpm: Int, zone: HeartRateZone?)? {
        guard let entry = heartRates[userID],
              HeartRateFreshness.isFresh(receivedAt: entry.receivedAt, now: Date(), staleAfter: Self.heartRateStaleAfter)
        else { return nil }
        return (entry.bpm, entry.zone)
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
            AppLogger.sessions.error("SessionLiveView reload: \(error, privacy: .public)")
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

    // MARK: - The round wait (spec §2 and §3.3, plan task S6)
    //
    // What a crewmate who is not lifting sees. It replaces the spectate sister
    // page plan task S4 deleted, and the difference is spec §5's whole point:
    // that page was a scoreboard, this one is the crew.
    //
    // Every model below is built from state this view ALREADY HOLDS --
    // `participants`, `allSessionSets`, `liveSession`, `recoveryBuffer`,
    // `effectiveRoutineExercises`. No fetch is added, and no store: spec §6's
    // "no new store" is what makes the recovery curve `RecoveryBuffer`'s
    // sparkline rather than a second history.

    /// ROUNDS ONLY, and only when somebody else holds the turn — the state in
    /// which this body shows THE CREW rather than my own entry card.
    ///
    /// `currentTurnUserID != nil` and a non-empty roster are both required
    /// because `isMyTurn` is an equality on two optionals: with no signed-in
    /// profile and no current turn it answers `true`, and with a roster that
    /// failed to load it would answer `false` and strand the reader on a page
    /// with no stations. Either way the my-turn page -- which is what renders
    /// today -- is the honest fallback.
    private var showsCrewPage: Bool {
        style == .rounds
            && liveSession.currentTurnUserID != nil
            && !isMyTurn
            && !participants.isEmpty
    }

    /// SPOTTER MODE takes the crew page when my prescription has no set left
    /// in this round (plan task S8, owner decision 7); the round wait takes it
    /// otherwise. Two pages, one gate, so they can never both be up.
    private var showsSpotter: Bool { showsCrewPage && hasNoSetThisRound }
    private var showsRoundWait: Bool { showsCrewPage && !hasNoSetThisRound }

    /// Have I finished my prescription for the exercise the crew is on?
    ///
    /// Answered from the ROUTINE'S OWN target and my own logged count, which
    /// is what `turnSetsPage` already counts with. A routine with no target
    /// sets prescribes no end, so it never answers yes — an unbounded
    /// prescription is not a finished one.

    /// The page, on a one-second tick.
    ///
    /// `TimelineView(.periodic(by: 1))` rather than a `Timer`, and rather than
    /// a `@State` date the 10 s turn poll refreshes: the elapsed rest is the
    /// biggest numeral on the screen and a clock that jumped ten seconds at a
    /// time would read as broken. The house already drives three surfaces this
    /// way (`WarmUpPhaseView`, `WorkoutSessionView`, `HomeView`). The VIEW
    /// still owns no clock -- `RoundWaitView` takes an already-formatted
    /// string -- so the catalog's frame stays deterministic (constraint 11).
    private var roundWaitPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            RoundWaitView(
                kicker: RoundCopy.kicker(crew: ledgerGroup?.name ?? "",
                                         round: liveSession.round),
                title: "The round",
                stations: roundStationModels,
                rest: restModel(now: context.date),
                planKicker: "THE SESSION · WHERE WE ARE",
                rungLine: routineName ?? "",
                plan: roundPlanRows,
                coach: CoachDoorRow.Model(title: SessionCopy.talkToCoach,
                                          detail: SessionCopy.talkToCoachDetail),
                waitingOn: waitingOnNames,
                dockNames: otherParticipantNames,
                reactionEmojis: reactionEmojis,
                voice: voiceFoot,
                skip: skipOffer(now: context.date),
                rackCount: currentEquipmentCap,
                rackErrorText: rackErrorText,
                onSetRackCount: currentEquipmentClass == nil ? nil : { count in
                    Task { await saveRackCount(count) }
                },
                onCoachTap: { Task { await openCoachThread() } },
                onReaction: { emoji in Task { await tapReaction(emoji: emoji) } },
                onSkip: { Task { await skipHeldLifter() } })
        }
    }

    /// THE ROUND'S OWN PREDICATE, mirroring `public.advance_round` (plan task
    /// D3): a non-penalty `set_logs` row at or after `round_started_at`.
    ///
    /// Spelled the same way here as there so the tick on a station card and
    /// the server's decision to close the round cannot disagree. THE WINDOW
    /// IS `RoundWindow.openedAt(...)` (ruling R-B23), the same
    /// `COALESCE(round_started_at, lifting_started_at, ...)` the RPC itself
    /// evaluates: `round_started_at` is NULL until the first round closes, and
    /// round 1 opens when the crew started LIFTING — fix-forward
    /// `20260913000105` was written precisely so a warm-up set does not count
    /// toward it. Both values ride the `sessions` UPDATE the realtime channel
    /// already delivers, so this reads the live server round.
    ///
    /// The old round-1 stand-in, "has logged this exercise at all", survives
    /// as the LAST resort only — the server's own `'-infinity'` arm, reachable
    /// only in a session with no lifting stamp, which is a session with no
    /// round wait on screen. Until this fix it was the round-1 answer itself,
    /// and it counted a warm-up set the server does not (final review,
    /// finding 3).
    private func hasLoggedThisRound(_ userID: UUID) -> Bool {
        guard let since = RoundWindow.openedAt(roundStartedAt: liveSession.roundStartedAt,
                                               liftingStartedAt: liveSession.liftingStartedAt) else {
            return hasLoggedCurrentExercise(userID)
        }
        return allSessionSets.contains {
            $0.userID == userID && !$0.isPenalty && $0.loggedAt >= since
        }
    }

    /// One card per rack, from `sessions.stations` -- plan task S3's own
    /// write, read back.
    ///
    /// A crew of three or fewer never has a stored assignment (`remixStations`
    /// leaves the column alone: there is nothing to split), so the whole
    /// present rotation becomes one rack. `StationSplit.name(0)` gives it the
    /// same word a written assignment would.
    private var roundStationModels: [StationCard.Model] {
        let racks: [(name: String, ids: [UUID])]
        if let stored = liveSession.stations, !stored.stations.isEmpty {
            racks = stored.stations.map { ($0.name, $0.turnOrder) }
        } else {
            racks = [(StationSplit.name(0), presentRotation.map(\.participant.userID))]
        }
        return racks.map { rack in
            StationCard.Model(
                name: rack.name,
                lifters: rack.ids.compactMap { stationLifter($0) },
                liftingID: rack.ids.first(where: { $0 == liveSession.currentTurnUserID }))
        }
    }

    /// A lifter nobody in the roster can name is left OUT of the rack rather
    /// than drawn as a blank column: a station is people, and a column with no
    /// name is not one of them.
    private func stationLifter(_ userID: UUID) -> StationCard.Lifter? {
        guard let profile = participants.first(where: { $0.participant.userID == userID })?.profile
        else { return nil }
        return StationCard.Lifter(
            id: userID,
            name: profile.username,
            isYou: userID == selfID,
            hasLogged: hasLoggedThisRound(userID),
            // Spec §3.4 mode 2 -- quiet, and only where the crew already looks.
            scaleDown: currentExerciseForSheet.flatMap { selfScales[userID]?[$0.id]?.name })
    }

    /// Who the round is still waiting on, first names, me excluded -- if I had
    /// not logged, it would be my turn and this page would not be up.
    private var waitingOnNames: [String] {
        presentRotation
            .filter { $0.participant.userID != selfID && !hasLoggedThisRound($0.participant.userID) }
            .map { SessionCopy.firstName($0.profile.username) }
    }

    /// THE SESSION · WHERE WE ARE -- the whole routine with MY progress on it.
    ///
    /// Mine and not the crew's, because `mySetCount(for:)` is what the rest of
    /// this view counts with and a row that mixed the two would answer a
    /// question nobody asked. Spec §2's "is the plan still achievable" is
    /// about the exercises that are LEFT, which is what these rows show.
    private var roundPlanRows: [SessionPlanRow] {
        effectiveRoutineExercises.map { re in
            SessionPlanRow(
                id: re.id,
                name: allExercises.first(where: { $0.id == re.exerciseID })?.name
                    ?? exerciseNames[re.exerciseID] ?? "Exercise",
                prescription: SessionPlanRow.prescription(for: re),
                isCurrent: re.exerciseID == currentExerciseForSheet?.id,
                setsDone: mySetCount(for: re.exerciseID),
                sets: re.targetSets ?? 0)
        }
    }

    /// The rest card's world. `now` comes from the page's `TimelineView`, so
    /// this function reads no clock of its own.
    private func restModel(now: Date) -> RestModel {
        let mine = selfHeartRate
        return RestModel(
            elapsed: RoundCopy.elapsed(since: myLastLoggedAt, now: now),
            // NO NEW STORE (spec §6): the same buffer the my-turn page's
            // `.onChange(of: selfHeartRate?.bpm)` already fills.
            curve: recoveryBuffer.sparkline(barCount: 10),
            // A stale reading is NO reading -- `heartRateFor(_:)`'s 15 s gate
            // returns nil and the card prints an em dash, never a last-known
            // number.
            bpm: mine?.bpm,
            zone: mine?.zone,
            nextPrescription: RoundCopy.nextPrescription(
                setNumber: myTurnSets.count + 1,
                targetSets: currentRoutineExercise?.targetSets,
                exercise: currentExerciseForSheet?.name,
                prescription: currentTargetLine),
            achievability: RoundCopy.achievability(
                lastMoved: lastMovedText,
                target: targetWeightLine,
                isUnderTarget: isLastSetUnderTarget))
    }

    /// When my rest started: my own last non-penalty log, anywhere in this
    /// session. Nil before I have logged at all, which reads `0:00`.
    private var myLastLoggedAt: Date? {
        guard let selfID else { return nil }
        return lastSetAnyExercise(selfID)?.loggedAt
    }

    /// `225 × 5` -- the routine's own prescription for the current exercise,
    /// in my unit. Nil when the routine prescribes neither.
    private var currentTargetLine: String? {
        guard let re = currentRoutineExercise else { return nil }
        let weight = targetPounds.map { weightText($0) }
        switch (weight, re.targetReps) {
        case let (weight?, reps?): return "\(weight) × \(reps)"
        case let (weight?, nil):   return weight
        case let (nil, reps?):     return "× \(reps)"
        default:                   return nil
        }
    }

    private var targetPounds: Decimal? {
        currentRoutineExercise?.targetWeight.flatMap { Decimal(string: $0) }
    }

    private var targetWeightLine: String? {
        targetPounds.map { weightText($0) }
    }

    /// What I last actually moved on this exercise -- failed sets excluded,
    /// because a miss is not a load the plan can be judged against.
    private var lastMovedPounds: Decimal? {
        myTurnSets.last(where: { !$0.isFailed && $0.weight != nil })?.weight
    }

    private var lastMovedText: String? {
        lastMovedPounds.map { weightText($0) }
    }

    private var isLastSetUnderTarget: Bool {
        guard let last = lastMovedPounds, let target = targetPounds else { return false }
        return last < target
    }

    // MARK: - Coach's door (spec §3.6, plan task S6)

    /// `navigationDestination(item:)` needs an `Identifiable`;
    /// `SessionCoachThread` is a plain value. `LobbyView`'s identical wrapper.
    private struct OpenedCoachThread: Identifiable, Hashable {
        let thread: SessionCoachThread
        var id: UUID { thread.threadID }

        static func == (lhs: OpenedCoachThread, rhs: OpenedCoachThread) -> Bool {
            lhs.thread == rhs.thread
        }
        func hash(into hasher: inout Hasher) { hasher.combine(thread.threadID) }
    }

    /// Find-or-create this session's Coach room, then open it.
    ///
    /// `LobbyView.openCoachThread()`, mirrored rather than shared: the two
    /// views hold different session values and neither has a common home for
    /// session-side helpers, which is the same reasoning `voiceEligibleStates`
    /// and `otherParticipantNames` above already carry.
    ///
    /// ON TAP, NEVER ON LOAD. A screen that opened a Coach room every time it
    /// appeared would create a thread for a session nobody asked Coach about
    /// -- and the round wait appears on every turn that is not yours.
    @MainActor
    private func openCoachThread() async {
        do {
            let thread = try await SessionCoachThreadRepository.open(sessionID: liveSession.id)
            // Branch on reachability rather than navigating unconditionally.
            // Inert today (`Monetization.paywallEnabled` is false, so
            // `isReachable` is always true) -- this is what makes the branch
            // correct once it flips live.
            if SessionCoachThreadRepository.isReachable(thread) {
                openedCoachThread = OpenedCoachThread(thread: thread)
            } else {
                showCoachPaywall = true
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var hasNoSetThisRound: Bool {
        guard let exercise = currentExerciseForSheet,
              let target = currentRoutineExercise?.targetSets, target > 0 else { return false }
        return mySetCount(for: exercise.id) >= target
    }

    // MARK: - Spotter mode (spec §1, owner decision 7, plan task S8)

    private var spotterPage: some View {
        SpotterView(
            kicker: RoundCopy.kicker(crew: ledgerGroup?.name ?? "", round: liveSession.round),
            title: "You're spotting",
            turn: turnStripTiles,
            stillToGo: stillToGoLine,
            crew: crewHeartRateRows,
            coach: CoachDoorRow.Model(title: SessionCopy.talkToCoach,
                                      detail: SessionCopy.talkToCoachDetail),
            dockNames: otherParticipantNames,
            reactionEmojis: reactionEmojis,
            voice: voiceFoot,
            onCoachTap: { Task { await openCoachThread() } },
            onReaction: { emoji in Task { await tapReaction(emoji: emoji) } },
            onCheer: { Task { await tapReaction(emoji: RoundCopy.cheerEmoji) } })
    }

    /// `rotationTiles`, worded for the strip. The speaking ring is resolved
    /// here because only this view holds the identity map
    /// (`VoiceRoomService` knows LiveKit identity strings, never usernames).
    ///
    /// `doing` is spec §3.4 mode 2 reaching the second place the crew already
    /// looks (plan task S2). The lookup is `stationLifter`'s own — the SAME
    /// `selfScales[userID]?[currentExerciseID]` the station card reads, for
    /// EVERY lifter including the viewer, so who's up next and who's at the
    /// rack cannot disagree about what somebody is lifting. Nothing new is
    /// broadcast: `selfScales` is filled by `chooseSwap`'s "Just me" path and
    /// by the inbound `self` event, and `evaluateUnanimity` is not on this
    /// path at all.
    private var turnStripTiles: [TurnStrip.Tile] {
        let currentExerciseID = currentExerciseForSheet?.id
        return rotationTiles.map { tile in
            TurnStrip.Tile(
                id: tile.userID,
                label: tile.label,
                name: tile.userID == selfID ? "You" : tile.profile.username,
                isNow: tile.label == "NOW",
                isSpeaking: VoiceRoomService.shared.speakingParticipantIDs
                    .contains(tile.userID.uuidString.lowercased()),
                doing: currentExerciseID.flatMap { selfScales[tile.userID]?[$0]?.name })
        }
    }

    /// `2 STILL TO GO` — how much of this round is left. Empty when nobody
    /// is outstanding, so no count is drawn rather than a zero.
    private var stillToGoLine: String {
        let outstanding = presentRotation.filter { !hasLoggedThisRound($0.participant.userID) }.count
        return outstanding > 0 ? RoundCopy.stillToGo(outstanding) : ""
    }

    /// The crew's readings, in rotation order so the card and the strip above
    /// it agree about who is who.
    ///
    /// EVERY ROW READS `heartRateFor(_:)`, the 15 s freshness gate, so a
    /// reading that stopped arriving becomes `nil` here and an em dash on the
    /// card — never a last-known number.
    private var crewHeartRateRows: [CrewHeartRatesCard.Row] {
        presentRotation.map { row in
            let reading = heartRateFor(row.participant.userID)
            return CrewHeartRatesCard.Row(
                id: row.participant.userID,
                name: row.participant.userID == selfID ? "You" : row.profile.username,
                isLifting: row.participant.userID == liveSession.currentTurnUserID,
                bpm: reading?.bpm,
                zone: reading?.zone)
        }
    }

    // MARK: - Together (spec §3.3, owner decisions 1 and 13, plan task S9)

    /// The routine's cardio rows as intervals. A routine with none is ONE
    /// OPEN interval, which `TogetherIntervals.plan(from:)` decides -- not
    /// this view, and not a literal.
    private var togetherIntervals: [TogetherIntervals.Interval] {
        TogetherIntervals.plan(from: effectiveRoutineExercises.map { re in
            (id: re.id,
             name: allExercises.first(where: { $0.id == re.exerciseID })?.name
                 ?? exerciseNames[re.exerciseID] ?? TogetherIntervals.openIntervalName,
             cardioZone: re.cardioZone,
             cardioMinutes: re.cardioMinutes)
        })
    }

    /// Where the crew is, measured from LIFTING START -- not `startedAt`,
    /// which is when the session opened and includes the warm-up phase
    /// (`20260803000004_session_warmup_phase.sql`; the same distinction
    /// `advance_round` was fixed for in 20260913000105).
    ///
    /// Nil before lifting begins, which is the honest answer: no interval has
    /// started.
    private var togetherPosition: TogetherIntervals.Position? {
        guard let start = liveSession.liftingStartedAt else { return nil }
        return TogetherIntervals.position(in: togetherIntervals,
                                          elapsed: Date().timeIntervalSince(start))
    }

    /// The page, on a one-second tick -- the countdown is the screen's
    /// largest numeral, and the same reasoning as the round wait's clock.
    private var togetherPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            togetherScreen(now: context.date)
        }
    }

    private func togetherScreen(now: Date) -> TogetherClockView {
        let intervals = togetherIntervals
        let elapsed = liveSession.liftingStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let position = TogetherIntervals.position(in: intervals, elapsed: elapsed)
        let index = position?.index ?? 0
        let current = intervals.indices.contains(index) ? intervals[index] : nil
        let next = intervals.indices.contains(index + 1) ? intervals[index + 1] : nil
        return TogetherClockView(
            kicker: togetherKicker,
            title: routineName ?? "Together",
            intervalKicker: RoundCopy.intervalKicker(index: index, count: max(intervals.count, 1)),
            phase: (current?.name ?? TogetherIntervals.openIntervalName).uppercased(),
            phaseDetail: current?.detail ?? "",
            // An OPEN interval counts UP: there is no end to count down to,
            // and a zero would claim one.
            readout: RoundCopy.clock(position?.remaining ?? position?.elapsedInInterval ?? 0),
            progress: position?.progress ?? 0,
            nextLine: RoundCopy.nextInterval(next.map { $0.detail.isEmpty ? $0.name : $0.detail }),
            lanes: togetherLanes(intervalCount: intervals.count),
            axisStart: RoundCopy.intervalKicker(index: 0, count: intervals.count),
            axisEnd: RoundCopy.intervalKicker(index: max(intervals.count - 1, 0),
                                              count: intervals.count),
            dockNames: otherParticipantNames,
            reactionEmojis: reactionEmojis,
            voice: voiceFoot,
            // The IDENTICAL entry card the my-turn page mounts (fix round 4
            // / finding 1, ruling R-B21) — Together has no turn to render
            // `myTurnFixedPage` at all, so without this the LOG button
            // above had nothing to enable it. One view, injected, rather
            // than a second copy: logging a set is one code path
            // regardless of which of the three styles is on screen.
            entryCard: AnyView(turnEntryCard),
            logControl: logControlFoot,
            onReaction: { emoji in Task { await tapReaction(emoji: emoji) } },
            onEnd: { showEndConfirmation = true })
    }

    private var togetherKicker: String {
        let crew = (ledgerGroup?.name ?? "").uppercased()
        return crew.isEmpty ? "TOGETHER" : "\(crew) · TOGETHER"
    }

    /// One lane per present lifter, on the shared interval axis.
    private func togetherLanes(intervalCount: Int) -> [TogetherLane] {
        presentRotation.map { row in
            let reading = heartRateFor(row.participant.userID)
            return TogetherLane(
                id: row.participant.userID,
                name: row.participant.userID == selfID
                    ? "You" : SessionCopy.firstName(row.profile.username),
                bpm: reading?.bpm,
                zone: reading?.zone,
                trace: togetherTrace.trace(for: row.participant.userID,
                                           count: max(intervalCount, 1)))
        }
    }

    // MARK: - Freestyle (spec §3.3, owner decision 4, plan task S10)

    /// The routine's own total prescribed sets — own pace has no round to
    /// count within, so the rail's denominator is the whole plan.
    private var freestyleTotalSets: Int {
        effectiveRoutineExercises.reduce(0) { $0 + ($1.targetSets ?? 0) }
    }

    /// Every non-penalty set this lifter has logged, across the whole
    /// routine — `setCount(userID:exerciseID:)`'s own count, summed.
    private func freestyleSetsDone(_ userID: UUID) -> Int {
        effectiveRoutineExercises.reduce(0) { $0 + setCount(userID: userID, exerciseID: $1.exerciseID) }
    }

    private var freestyleRailModel: FreestyleRailModel {
        FreestyleRailModel(
            lifters: presentRotation.map { row in
                FreestyleRailModel.Lifter(
                    id: row.participant.userID,
                    name: SessionCopy.firstName(row.profile.username),
                    isYou: row.participant.userID == selfID,
                    setsDone: freestyleSetsDone(row.participant.userID))
            },
            totalSets: freestyleTotalSets)
    }

    /// `nil` with no signed-in profile answers `.level` (`FreestylePace`'s own
    /// default) — the honest fallback, the same one `isMyTurn` takes.
    private var freestyleStanding: FreestylePace.Standing {
        guard let selfID else { return .level }
        let sets = presentRotation.map {
            FreestylePace.Lifter(userID: $0.participant.userID,
                                 setsDone: freestyleSetsDone($0.participant.userID))
        }
        return FreestylePace.standing(sets: sets, for: selfID)
    }

    /// THE PLAN'S OWN ISOLATION ROWS, never an invented recommendation —
    /// `exercises.category` (`20260709000002:5`) is the only "what kind of
    /// exercise is this" signal the schema carries.
    private var freestyleAccessoryCandidates: [FreestylePace.AccessoryCandidate] {
        effectiveRoutineExercises.compactMap { re in
            guard let exercise = allExercises.first(where: { $0.id == re.exerciseID }) else { return nil }
            return FreestylePace.AccessoryCandidate(
                id: re.id, name: exercise.name, category: exercise.category,
                prescription: SessionPlanRow.prescription(for: re))
        }
    }

    private var freestyleStartedExerciseIDs: Set<UUID> {
        guard let selfID else { return [] }
        return Set(effectiveRoutineExercises
            .filter { setCount(userID: selfID, exerciseID: $0.exerciseID) > 0 }
            .map(\.id))
    }

    private var freestyleAccessorySuggestion: FreestylePace.AccessoryCandidate? {
        FreestylePace.accessorySuggestion(from: freestyleAccessoryCandidates,
                                          startedIDs: freestyleStartedExerciseIDs)
    }

    /// `PUSH CREW · FREESTYLE` — `togetherKicker`'s own pattern.
    private var freestyleKicker: String {
        let crew = (ledgerGroup?.name ?? "").uppercased()
        return crew.isEmpty ? "FREESTYLE" : "\(crew) · FREESTYLE"
    }

    /// The page, on a one-second tick — the rest clock is the biggest numeral
    /// on it, `roundWaitPage`'s own reasoning.
    private var freestylePage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            freestyleScreen(now: context.date)
        }
    }

    /// Exactly one of three things follows the rest card: nothing (level),
    /// two suggestions (ahead), or a stated wait with nothing to accept
    /// (behind) — never more than one shape at once.
    private func freestyleScreen(now: Date) -> FreestyleRailView {
        let standing = freestyleStanding
        var stretch: FreestyleSuggestion?
        var accessory: FreestyleSuggestion?
        var behind: String?

        if case .ahead(let by) = standing {
            if !freestyleStretchAcknowledged {
                stretch = FreestyleSuggestion(
                    kicker: RoundCopy.freestyleStretchKicker,
                    sentence: RoundCopy.freestyleStretchSentence(setsAhead: by))
            }
            if let candidate = freestyleAccessorySuggestion,
               !freestyleAcknowledgedAccessoryIDs.contains(candidate.id) {
                accessory = FreestyleSuggestion(
                    kicker: RoundCopy.freestyleAccessoryKicker,
                    sentence: RoundCopy.freestyleAccessorySentence(
                        name: candidate.name, prescription: candidate.prescription))
            }
        } else if case .behind = standing {
            behind = RoundCopy.freestyleBehindLine
        }

        return FreestyleRailView(
            kicker: freestyleKicker,
            title: RoundCopy.freestyleTitle,
            rail: freestyleRailModel,
            restElapsed: RoundCopy.elapsed(since: myLastLoggedAt, now: now),
            standing: standing,
            stretchSuggestion: stretch,
            accessorySuggestion: accessory,
            behindLine: behind,
            // The IDENTICAL entry card the my-turn page mounts (fix round 4
            // / finding 1, ruling R-B21) — Freestyle still owns no LOG foot
            // of its own (the header comment's reasoning is unchanged), but
            // it had nothing on screen to fill the reps `turnChrome`'s
            // button needed, so the button below it could never enable.
            entryCard: AnyView(turnEntryCard),
            // NEITHER APPLIES A CHANGE (owner decision 4) — acknowledging
            // either way just stops the card from showing again.
            onAcceptStretch: { freestyleStretchAcknowledged = true },
            onDeclineStretch: { freestyleStretchAcknowledged = true },
            onAcceptAccessory: { freestyleAcknowledgeAccessory() },
            onDeclineAccessory: { freestyleAcknowledgeAccessory() })
    }

    private func freestyleAcknowledgeAccessory() {
        guard let id = freestyleAccessorySuggestion?.id else { return }
        freestyleAcknowledgedAccessoryIDs.insert(id)
    }

    // MARK: - The hold, the skip and the minute (spec §9a, plan task S7)

    /// The present crew's own measured rests, this session.
    ///
    /// The WHOLE session and not the round: the threshold wants each lifter's
    /// typical pace, and one round is one data point. `allSessionSets` is the
    /// uncapped `logged_at ASC` array -- never `feedSets`, which caps at 30
    /// rows across all participants.
    private var sessionRestMedians: [UUID: TimeInterval] {
        RestMeasure.medians(from: allSessionSets,
                            since: liveSession.startedAt ?? .distantPast)
    }

    /// The single lifter this round is still waiting on, if there is exactly
    /// one. More than one and nobody is being held; none and the round closes
    /// on its own.
    private var heldLifter: (participant: SessionParticipant, profile: Profile)? {
        let outstanding = presentRotation.filter { !hasLoggedThisRound($0.participant.userID) }
        return outstanding.count == 1 ? outstanding.first : nil
    }

    /// When the crew began waiting: the SECOND-TO-LAST log of the round, from
    /// `allSessionSets` and never from a view timer (`RoundHold`'s own law).
    ///
    /// The round's window is `RoundWindow.openedAt(...)` — the same live
    /// server values `hasLoggedThisRound` reads (ruling R-B23), so the lifter
    /// the crew is held on and the clock they are held by are measured over
    /// one window, not two.
    private var holdStartedAt: Date? {
        let since = RoundWindow.openedAt(roundStartedAt: liveSession.roundStartedAt,
                                         liftingStartedAt: liveSession.liftingStartedAt)
        let times = presentRotation.compactMap { row -> Date? in
            allSessionSets
                .filter { log in
                    log.userID == row.participant.userID && !log.isPenalty
                        && (since.map { start in log.loggedAt >= start } ?? true)
                }
                .map(\.loggedAt)
                .max()
        }
        return RoundHold.holdStartedAt(roundLogTimes: times,
                                       presentCount: presentRotation.count)
    }

    /// The held lifter's own median, or the CREW'S when nobody has measured
    /// them yet -- a lifter with one log has no median (`RestMeasure`'s law),
    /// and falling back to zero would put the bare 90 s floor on the person
    /// the crew is waiting for. With no crew median either, zero floors it,
    /// which is the honest answer for a session nobody has rested in yet.
    private var heldMedianRest: TimeInterval {
        let medians = sessionRestMedians
        if let held = heldLifter, let mine = medians[held.participant.userID] { return mine }
        guard !medians.isEmpty else { return 0 }
        return medians.values.reduce(0, +) / Double(medians.count)
    }

    /// The three lines, once the crew is past the threshold. Nil the rest of
    /// the time, which is nearly always.
    ///
    /// ANY CREWMATE MAY TAP IT (ruling R-B13, fix-forward `20260913000107`,
    /// applied live). The organizer-only button and the note-for-others it
    /// used to fall back to are gone: `SessionRepository.advanceRound`'s
    /// `force` parameter bypasses the server's close predicate once the
    /// round is genuinely old enough (the server's own 90 s floor, checked
    /// server-side — never a client-side gate), so the tap now does what
    /// spec §9a always asked for regardless of who is present.
    private func skipOffer(now: Date) -> SkipOffer? {
        guard let held = heldLifter, let since = holdStartedAt else { return nil }
        let median = heldMedianRest
        guard RoundHold.isHeld(since: since, now: now,
                               medianRestSeconds: median,
                               extensionsTaken: minuteExtensionsThisRound) else { return nil }
        return SkipOffer(
            name: SessionCopy.firstName(held.profile.username),
            waited: now.timeIntervalSince(since),
            threshold: RoundHold.threshold(medianRestSeconds: median,
                                           extensionsTaken: minuteExtensionsThisRound))
    }

    /// The crew's tap. NOTHING HAPPENS ON ITS OWN (spec §9a) and nothing is
    /// recorded against the skipped lifter: their set stays in their plan,
    /// no `skipped` flag is written, no penalty row is inserted, and they
    /// rejoin at the top of the next round. The task's job here is to not add
    /// anything that would make that untrue, and it adds nothing.
    ///
    /// `advanceRound(force: true)` is what actually moves the crew on now
    /// (ruling R-B13) -- the server's close predicate is bypassed once the
    /// round has genuinely run long enough, checked server-side against
    /// `holdStartedAt`'s own clock, not this client's. `advanceTurn` still
    /// runs first when the tapper is the organizer -- it authorises only the
    /// current lifter and the organizer
    /// (`20260801000001_advance_turn_version_guard.sql:84-86`) -- as a
    /// bonus nudge to the rotation's own turn pointer; it is no longer what
    /// makes the round close, so a non-organizer's tap skips it and goes
    /// straight to the call that does. Both calls are safe to repeat and
    /// safe to lose.
    @MainActor
    private func skipHeldLifter() async {
        do {
            if isOrganizer {
                try await SessionRepository.advanceTurn(sessionID: liveSession.id)
            }
            _ = try await SessionRepository.advanceRound(sessionID: liveSession.id,
                                                         expectedRound: liveSession.round,
                                                         force: true)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Is "I need a minute" mine to tap right now?
    ///
    /// Only in Rounds, only when the crew is genuinely waiting on ME, and only
    /// once for this exercise. It appears BEFORE the threshold on purpose --
    /// the point is to head the offer off, not to answer it after the fact.
    private var canTakeAMinute: Bool {
        guard style == .rounds, let selfID, let exercise = currentExerciseForSheet else { return false }
        guard heldLifter?.participant.userID == selfID else { return false }
        return !minuteTakenForExercise.contains(exercise.id)
    }

    /// Spend it: remember the exercise, extend this client's own threshold,
    /// and tell the crew.
    ///
    /// The message rides the EXISTING reaction channel (plan task S7 -- no new
    /// channel, no new broadcast kind), carrying `RoundCopy.minuteMarker`.
    /// Every client, this one included through the self-echo, reads that
    /// marker in `subscribeBroadcast` and extends its own threshold, so the
    /// whole crew's offer moves out together. Double-counting is harmless:
    /// `RoundHold.threshold(_:extensionsTaken:)` refuses to stack.
    @MainActor
    private func takeAMinute() async {
        guard let exercise = currentExerciseForSheet else { return }
        minuteTakenForExercise.insert(exercise.id)
        minuteExtensionsThisRound += 1
        await broadcastService.sendReaction(sessionID: liveSession.id,
                                            emoji: RoundCopy.minuteMarker)
    }

    /// The held lifter's own control, on their own screen -- the my-turn
    /// page's chrome, because in Rounds the last outstanding lifter is the one
    /// holding the turn.
    ///
    /// A FLAT, QUIET row above the mic rail. It is not a second accent (rule
    /// 2): the my-turn page already spends its accent on LOG SET & PASS, and
    /// asking for a minute is not the act the screen is for.
    @ViewBuilder
    private var needAMinuteRow: some View {
        if canTakeAMinute {
            Button {
                Task { await takeAMinute() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RoundCopy.needAMinute)
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                        Text(RoundCopy.needAMinuteDetail)
                            .font(GSFont.body(11, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.neutral700)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - The station split (spec §3.3, owner decisions 2 and 6)

    /// Write the crew's station assignment for one exercise (plan task S3).
    ///
    /// A crew of three or fewer IS one station: there is nothing to split and
    /// nothing to re-mix, so the column is left alone rather than written with
    /// an answer nobody reads.
    ///
    /// The roster sent is `presentRotation` — `check_in_state` in
    /// online/ready/late, `advance_turn`'s own next-picker
    /// (`20260802000001_rotation_presence.sql:77,87`) — which is exactly the
    /// set `set_session_stations` validates against (plan ruling R-B7). An
    /// invited lifter who never arrived is not standing at a rack.
    ///
    /// The medians are measured over the WHOLE SESSION, not the round: the
    /// re-mix wants each lifter's typical pace, and one round is one data
    /// point. `allSessionSets` is the uncapped, `logged_at ASC` array — never
    /// `feedSets`, which caps at 30 rows across all participants.
    ///
    /// FAILURE IS NOT FATAL. A re-mix that cannot be written leaves the
    /// previous assignment standing and logs: a station split must never block
    /// a round.
    /// The venue's rack counts, read once per live session (plan task S6,
    /// decision 1).
    ///
    /// Best-effort, like `remixStations` below: a failure leaves the counts
    /// empty, which leaves the cap `nil`, which is the shipped split. Never
    /// surfaced — a station split must never block a round, and neither must
    /// the number that caps it.
    @MainActor
    private func loadVenueRackCounts() async {
        guard venueRackCounts.isEmpty, let venueID = liveSession.venueID else { return }
        do {
            venueRackCounts = try await VenueRackRepository.counts(venueID: venueID)
        } catch {
            AppLogger.sessions.error(
                "rack counts failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// THE CORRECTION, from the station card's header: whoever is standing in
    /// the room can see that there are three racks and not two (decision 1).
    ///
    /// ON A REFUSAL — `P0001`, the RPC saying this caller holds no
    /// `venue_checkins` row at this venue inside 12 hours — the message lands
    /// inside the popover it was asked in, the count stays as it was, the cap
    /// stays whatever it already was, and the round is not touched. The split
    /// itself is NOT re-mixed here: a re-mix moves people between racks
    /// mid-round, and it is the next exercise's `.task(id:)` that spends the
    /// corrected number.
    @MainActor
    private func saveRackCount(_ count: Int) async {
        guard let venueID = liveSession.venueID,
              let equipmentClass = currentEquipmentClass else { return }
        rackErrorText = nil
        do {
            try await VenueRackRepository.set(venueID: venueID,
                                              equipmentClass: equipmentClass,
                                              count: count)
            venueRackCounts[equipmentClass] = count
        } catch let error as GymSyncError {
            rackErrorText = error.errorDescription
        } catch {
            rackErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func remixStations(exercisePosition: Int) async {
        let lifters = presentRotation.map(\.participant.userID)
        guard lifters.count > 3 else { return }

        let medians = RestMeasure.medians(
            from: allSessionSets,
            since: liveSession.startedAt ?? .distantPast)
        let split = StationSplit.assign(
            lifters: lifters,
            // THE OWNER'S `min(ceil(n/3), racks at the venue)`, finally whole
            // (plan task S6, decision 1). B1 passed `nil` because neither
            // half of the second term existed; S5 gave the session its venue
            // and D1 gave the venue its counts, so the cap is the count for
            // THIS exercise's equipment class — and still `nil` when the
            // venue, the class or the count is unknown, which is today's
            // `ceil(crew / 3)`. Re-read on every exercise change, so a
            // barbell block and a dumbbell block may split differently.
            count: StationSplit.count(crew: lifters.count,
                                      equipmentCap: currentEquipmentCap),
            restMedians: medians,
            previous: liveSession.stations)

        do {
            // `StationSplit.rows` is the ONE place `lifterIDs` and `turnOrder`
            // are paired: `set_session_stations` validates the shape and the
            // roster but not `turn_order`'s contents (D4), so that invariant
            // is the client's to keep and it is kept in one function.
            liveSession.stations = try await SessionRepository.setStations(
                sessionID: liveSession.id,
                exercisePosition: exercisePosition,
                stations: StationSplit.rows(from: split))
        } catch {
            AppLogger.sessions.error(
                "station re-mix failed at exercise \(exercisePosition, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reaction actions

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
        // Same convention for the follow-up note (ruling R-B22): a fresh
        // attempt never shows the previous set's leftover.
        logFollowUpNote = nil
        // Field report #20 instrumentation: failed-set sends reportedly
        // hang for seconds with no obvious synchronous culprit. Every
        // await on the critical path gets a millisecond stamp, tagged by
        // failed-vs-normal, so one Console filter ("logSet timing")
        // names the offender. Remove once the hang is caught.
        let tTotal = Date()
        func stamp(_ label: String, _ since: Date) {
            let ms = Int(Date().timeIntervalSince(since) * 1000)
            AppLogger.workout.info("logSet timing [\(isFailed ? "FAILED" : "normal", privacy: .public)] \(label, privacy: .public): \(ms, privacy: .public)ms")
        }
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
            // Docket row 7's rule (a): nothing to beat is not a record to
            // celebrate. Stays `true` on the offline path below, where the PR
            // check is skipped entirely and `isPR` stays false anyway.
            var prBasisIsEmpty = true
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
                    let tPrior = Date()
                    let prior = try await priorMax(exerciseID: exerciseID,
                                                   reps: completedReps, userID: userID)
                    stamp("priorMax", tPrior)
                    priorBest = prior.best
                    prBasisIsEmpty = prior.basisIsEmpty
                    isPR = weight > prior.best
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
            // The rep-PR twin of `prBasisIsEmpty` — a first bodyweight set
            // beats `max() ?? 0` and was a rep PR for exactly the same reason.
            var repBasisIsEmpty = true
            if (weight ?? 0) == 0,
               currentExerciseForSheet?.id == exerciseID,
               currentExerciseForSheet?.equipment == "bodyweight",
               let completedReps {
                let priorReps = turnExerciseHistory
                    .filter { !$0.isPenalty && ($0.weight ?? 0) == 0 }
                    .compactMap(\.completedReps)
                repBasisIsEmpty = priorReps.isEmpty
                priorBestReps = priorReps.max() ?? 0
                isRepPR = completedReps > priorBestReps
            }

            do {
                let tInsert = Date()
                try await SessionRepository.logSet(log)
                stamp("logSet insert", tInsert)
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
                //
                // ONLY IN A STYLE THAT HAS TURNS (ruling R-B22): a recorded
                // advance is an `advance_turn` deferred, not a different call,
                // so it answers to the same law as the online path below. A
                // Together or Freestyle lifter who logged offline would
                // otherwise have that replay fire on reconnect and raise
                // P0001 against a rotation their style does not run.
                if LogFollowUp.calls(for: style).contains(.advanceTurn) {
                    PendingTurnAdvanceStore.shared.record(
                        sessionID: session.id,
                        observedVersion: liveSession.turnVersion)
                }
                didQueueSetOffline = true
            }
            // The set is durably recorded either way (server insert or offline
            // queue) — this is the moment the success haptic fires.
            logHapticTick += 1

            // Docket row 7, in one place for both bodies (`PRFiring`): the
            // first log of a lift is a baseline, and the record DEFERS to the
            // last set — it is never lost (ruling R-OD-1). THE RECORD ITSELF
            // IS NOT GATED — both `PersonalRecordRepository.record` inserts
            // below run exactly as they did; only the celebration waits.
            //
            // `targetSets` from the EFFECTIVE routine, never `routineExercises`:
            // an accepted scale-down of 4 × 5 → 3 × 5 makes the third set the
            // last one, and the celebration must agree with the number the
            // screen printed. `nil` = unprescribed, which celebrates on the
            // record itself.
            let firingTargetSets = effectiveRoutineExercises
                .first(where: { $0.exerciseID == exerciseID })?.targetSets
            // THE RECORD PAYLOAD, built whenever the set IS one — held or
            // fired, `PRFiring.step` decides which. The two forms are
            // mutually exclusive by construction (`isRepPR` needs
            // `weight == 0`, `isPR` needs `weight > 0`), so one context and
            // one payload cover both; the rep form is `weight: 0` with
            // `priorBest` carrying the prior REP count.
            var firingRecord: PRFiring.Pending?
            if isRepPR, let completedReps {
                let tName = Date()
                let name = await ExerciseNameCache.name(for: exerciseID)
                stamp("nameCache repPR", tName)
                firingRecord = PRFiring.Pending(exerciseName: name, weight: 0,
                                                reps: completedReps,
                                                priorBest: Decimal(priorBestReps))
            } else if isPR, let weight {
                let tName = Date()
                let name = await ExerciseNameCache.name(for: exerciseID)
                stamp("nameCache PR", tName)
                firingRecord = PRFiring.Pending(exerciseName: name, weight: weight,
                                                reps: completedReps ?? 0,
                                                priorBest: priorBest)
            }
            // `log.setIndex` is `mySetCount(for:) + 1` — sets of this exercise
            // logged by me in this session, counting the one just written,
            // which is the one meaning `setsLogged` has (ruling R-OD-3).
            let firingStep = PRFiring.step(
                record: firingRecord,
                context: PRFiring.Context(basisIsEmpty: isRepPR ? repBasisIsEmpty : prBasisIsEmpty,
                                          setsLogged: log.setIndex,
                                          targetSets: firingTargetSets),
                held: pendingPRs[exerciseID])
            pendingPRs[exerciseID] = firingStep.held
            if let celebration = firingStep.celebrate {
                // The monthly badge is re-read only when THIS set wrote no
                // record — the ordered pipeline below already re-reads it
                // after its own insert, and a second read racing that insert
                // is the undercount its comment warns about.
                let needsCount = firingRecord == nil
                Task { @MainActor in
                    await firePendingPR(celebration, userID: userID,
                                        refreshMonthlyCount: needsCount)
                }
            }

            if isRepPR, let completedReps {
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
                let repsForOverlay = completedReps ?? 0
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

            // Phase O Task 3 fix wave 1 (reviewer Finding 1) — skip the
            // follow-ups entirely when this attempt queued offline; see the
            // queuing branch's comment above for the full rationale. The
            // normal ONLINE path is unaffected: `didQueueSetOffline` stays
            // false, so the follow-ups below still run.
            guard !didQueueSetOffline else { stamp("TOTAL (offline)", tTotal); return true }
            // THE INSERT WAS THE TRANSACTION (ruling R-B22). Everything past
            // this line is a follow-up on a set that is ALREADY IN THE
            // DATABASE, so it gets its own `do` and can never reach the outer
            // `catch` — which returns `false`, which `commitInlineLog` reads
            // as "nothing was saved, keep the card up for a retry". That read
            // was true when the only follow-up was `advance_turn` on a turn
            // this lifter necessarily held; it became a duplicate-set factory
            // the moment Together and Freestyle started logging (final review,
            // finding 1), because `advance_turn` raises P0001 for every lifter
            // who is neither the current turn holder nor the organizer.
            // WHICH calls run is `LogFollowUp.calls(for:)`'s answer, not a
            // condition spelled here (RoundPieces.swift, unit-tested).
            do {
                for call in LogFollowUp.calls(for: style) {
                    switch call {
                    case .advanceTurn:
                        let tAdvance = Date()
                        try await SessionRepository.advanceTurn(sessionID: session.id)
                        stamp("advanceTurn", tAdvance)
                        // A live advance settles any advance this device still
                        // owed from an earlier offline set — the queued one
                        // would no-op anyway (version guard), but dropping it
                        // keeps the store honest rather than accumulating
                        // entries that only ever fizzle.
                        PendingTurnAdvanceStore.shared.clear(sessionID: session.id)
                    case .advanceRound:
                        // NEVER FORCED: `p_force` is the crew's skip line's own
                        // escape (R-B13) and nothing else. Unforced, the server
                        // returns the round unchanged unless every present
                        // lifter has logged since the round opened — so this
                        // call is a cheap OFFER to close, safe to repeat and
                        // safe to lose, made by whoever happens to log last.
                        let tRound = Date()
                        let round = try await SessionRepository.advanceRound(
                            sessionID: session.id, expectedRound: liveSession.round)
                        stamp("advanceRound", tRound)
                        // Lead the realtime echo with the round the server just
                        // told us (`endSession`'s own idiom — see
                        // `pushWatchSessionState`'s doc comment). ONLY the
                        // round: `round_started_at` belongs to the same UPDATE
                        // and arrives with it, and stamping a client `Date()`
                        // in its place would hand every round-wait derivation a
                        // window this device invented — exactly what
                        // `RoundHold`'s "never from a view timer" law forbids.
                        if round != liveSession.round { liveSession.round = round }
                    }
                }
            } catch let error as GymSyncError {
                noteLogFollowUpFailure(error.errorDescription)
            } catch {
                noteLogFollowUpFailure(error.localizedDescription)
            }
            stamp("TOTAL", tTotal)
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

    /// Say once, quietly, that a follow-up on an already-saved set did not go
    /// through (ruling R-B22), then take it back down.
    ///
    /// Auto-clearing because there is no action attached: the set is in the
    /// database, and the turn or the round is moved on by the next lifter's
    /// own call — a note that outlived its moment would just be a stuck
    /// warning about something already fixed. The `==` re-check before
    /// clearing is `selfRotationRestUntil`'s own idiom in this file: only the
    /// note still on screen clears itself, so a newer one is never wiped by an
    /// older one's timer.
    @MainActor
    private func noteLogFollowUpFailure(_ text: String?) {
        guard let text else { return }
        AppLogger.workout.warning(
            "logSet follow-up failed on a persisted set (style \(style.rawValue, privacy: .public)): \(text, privacy: .public)")
        logFollowUpNote = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if logFollowUpNote == text { logFollowUpNote = nil }
        }
    }

    /// The recap sheet's content, extracted so the 20-argument init is
    /// its own type-checked expression (the inline form blew the
    /// compiler's budget) and the debrief args sit in declaration order.
    @ViewBuilder
    private func recapSheetContent(_ data: RecapData) -> some View {
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
                coachDebrief: groupDebrief,
                coachName: CoachPersona.bySlug(groupCoachProfile.persona)?.name ?? "Coach",
                onTalkToCoach: { showGroupCoachRecap = true },
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

    /// The AI after-action for a GROUP session: built from MY sets only
    /// (the report is personal even when the session wasn't), against
    /// the effective routine (hot-swaps included), with per-lift history
    /// prefetched so the trend tool narrates real numbers. Best effort -
    /// a failure just means no coach card on the recap.
    @MainActor
    private func assembleGroupDebrief(session completed: WorkoutSession,
                                      allSets: [SetLog]) async {
        guard let selfID else { return }
        if let profile = try? await TrainingProfileRepository.load() {
            groupCoachProfile = profile
        }
        let mySets = allSets.filter { $0.userID == selfID && !$0.isPenalty }
        guard !mySets.isEmpty else { return }
        let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        let logsByExercise = Dictionary(grouping: mySets, by: \.exerciseID)
        let reports = effectiveRoutineExercises
            .filter { $0.cardioZone == nil }
            .map { re in
                DebriefBuilder.ExerciseReport(
                    name: nameByID[re.exerciseID] ?? exerciseNames[re.exerciseID] ?? "Exercise",
                    prescribedSets: re.targetSets ?? 3,
                    repsLow: re.targetRepsLow,
                    repsHigh: re.targetRepsHigh,
                    sets: (logsByExercise[re.exerciseID] ?? [])
                        .sorted { $0.setIndex < $1.setIndex },
                    decision: nil)
            }
        guard reports.contains(where: { !$0.sets.isEmpty }) else { return }
        var context = DebriefBuilder.Context()
        context.profile = groupCoachProfile
        if let end = completed.completedAt, let start = completed.startedAt {
            context.sessionMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        }
        groupDebrief = DebriefBuilder.build(reports: reports, context: context)
        // Trend fuel for the conversation's tool - my lifts only, capped.
        for re in effectiveRoutineExercises.prefix(10) where re.cardioZone == nil {
            guard let name = nameByID[re.exerciseID] else { continue }
            if let history = try? await SessionRepository.exerciseHistory(
                userID: selfID, exerciseID: re.exerciseID, limit: 60) {
                groupTrendHistory[name.lowercased()] = history
            }
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
    ///
    /// Returns the emptiness of the basis alongside the number, because the
    /// number alone cannot express it: `bestWeight` answers `0` both for "you
    /// have never logged this" and for a basis it cannot beat. Docket row 7
    /// needs the first of those two told apart from the second, and this is
    /// the only place that still has the rows to tell it with (one fetch, not
    /// two — this call is on the turn CTA's critical path).
    private func priorMax(exerciseID: UUID, reps: Int?, userID: UUID) async throws
        -> (best: Decimal, basisIsEmpty: Bool) {
        let rows = try await SessionRepository.prBasis(userID: userID, exerciseID: exerciseID)
        // Failed rows enter at their COMPLETED reps (doctrine 2026-08-13:
        // n logged − 1; failed singles drop out) — mirrors solo's pairs().
        let basis: [(weight: Decimal, reps: Int)] = rows.compactMap { row in
            guard let w = row.weight, w > 0, let r = row.completedReps else { return nil }
            return (w, r)
        }
        return (PersonalRecordMath.bestWeight(atLeastReps: reps ?? 0, in: basis),
                PersonalRecordMath.qualifyingBasisIsEmpty(atLeastReps: reps ?? 0, in: basis))
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
        // The sound is back (owner 2026-09-18: "keep the sound effect") as
        // the bundled `lightweight-baby.mp3` — not the soundboard, which
        // stays gone (ruling R-B8, B1 plan task S11). Beside the flag, never
        // before it: `CelebrationSound.playPR()` cannot throw and returns on
        // every failure, so the celebration appears whether or not a sound
        // does. The haptic (`logHapticTick`) is unchanged.
        CelebrationSound.playPR()
    }

    /// Celebrate one payload `PRFiring` handed back — the set that completed
    /// the exercise, or the flush when the lifter moved on (rulings R-OD-1,
    /// R-OD-2). Exactly one moment per call.
    ///
    /// `refreshMonthlyCount` re-reads the badge for a DEFERRED celebration,
    /// whose own record was inserted sets ago: `showPROverlay` clears
    /// `prOverlayMonthlyCount` to `nil` for freshness, and without this the
    /// deferred overlay would show no count at all. Never passed `true` on a
    /// set that wrote a record — the ordered pipeline in `logSetAndAdvance`
    /// re-reads it after its own insert, and a second read racing that insert
    /// is the undercount its comment warns about.
    @MainActor
    private func firePendingPR(_ pending: PRFiring.Pending, userID: UUID,
                               refreshMonthlyCount: Bool) async {
        await showPROverlay(exerciseName: pending.exerciseName,
                            weight: pending.weight,
                            reps: pending.reps,
                            priorBest: pending.priorBest)
        guard refreshMonthlyCount else { return }
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        prOverlayMonthlyCount = try? await PersonalRecordRepository.countSince(
            userID: userID, date: startOfMonth)
    }

    /// LEAVING THE EXERCISE FLUSHES (ruling R-OD-2). Sets skipped, the
    /// exercise swapped, the round moving the crew on: a record held for an
    /// exercise that is no longer the one in front of the lifter celebrates
    /// at that moment, once, and the store clears.
    ///
    /// A hold only ever arises for the PRESCRIBED row currently being logged
    /// (an unprescribed lift celebrates on the record itself), and every
    /// exercise change drains this store, so at most one payload is ever
    /// here. The loop is ordered anyway so the behaviour stays defined if
    /// that ever stops being true.
    @MainActor
    private func flushPendingPRs(except current: UUID?) async {
        guard !pendingPRs.isEmpty, let userID = selfID else { return }
        let leaving = pendingPRs
            .filter { $0.key != current }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        guard !leaving.isEmpty else { return }
        for (exerciseID, _) in leaving { pendingPRs[exerciseID] = nil }
        for (_, pending) in leaving {
            await firePendingPR(pending, userID: userID, refreshMonthlyCount: true)
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
            await assembleGroupDebrief(session: completed, allSets: allSets)
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

        // Spec §1 lines 2-3: resolved ONCE, here, as the author — the only
        // reads RLS permits. Best-effort: a blip costs the post its
        // trajectory, never the post itself.
        let resolved = await PostTrajectoryResolver.resolve()

        return PumpCheckContext(
            sessionID: session.id,
            summary: PostSummary(
                durationSeconds: duration,
                totalVolumeLbs: Decimal(myVolume),
                exercises: exercises,
                routineName: routineName),
            avgBpm: hrStats?.avg,
            maxBpm: hrStats?.max,
            includeHRDefault: ThemeStore.shared.shareHeartRate && hrStats != nil,
            windowStart: Date(),
            completedAt: session.completedAt,
            trajectory: resolved?.trajectory,
            goalID: resolved?.goalID,
            weekStartString: resolved?.weekStartString)
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
