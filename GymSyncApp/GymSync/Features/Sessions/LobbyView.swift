import SwiftUI
import UIKit

// MARK: - LobbyView

struct LobbyView: View {
    let session: WorkoutSession

    #if DEBUG
    /// The catalog's world (plan task S7, global constraint 11). With one set,
    /// `openAndLoad()` and `reload()` return immediately — no repository, no
    /// realtime, no `CheckInService` and no clock is reachable from a frame —
    /// and every presentation value below reads the fixture instead.
    /// `SocialTabView`'s DEBUG init is the shape; `VenueHubView`'s is the
    /// precedent.
    var catalog: LobbyWorld?

    /// `initialParticipants` (plan task S9): `SessionEntryView` already fetched
    /// these rows to route here — passing them on seeds `participants` before
    /// first paint, so the arrival track does not have to wait on `reload()`'s
    /// own round trip to stop being blank. `reload()` still runs and still
    /// refetches; this only removes the first blank frame. Defaulted to `[]`
    /// so the fallback call site (no rows to hand over) is unchanged.
    init(session: WorkoutSession,
         initialParticipants: [(participant: SessionParticipant, profile: Profile)] = []) {
        self.session = session
        self.catalog = nil
        _participants = State(initialValue: initialParticipants)
    }

    /// The catalog's entry point. It takes NO `session:` — the world carries
    /// its own, so a frame cannot be built half from a fixture and half from
    /// a row somebody fetched.
    init(catalog: LobbyWorld) {
        self.session = catalog.session
        self.catalog = catalog
        _currentSession = State(initialValue: catalog.session)
        _groupName = State(initialValue: catalog.groupName)
    }
    #else
    /// See the DEBUG init's doc comment above — same contract, no `catalog`.
    init(session: WorkoutSession,
         initialParticipants: [(participant: SessionParticipant, profile: Profile)] = []) {
        self.session = session
        _participants = State(initialValue: initialParticipants)
    }
    #endif

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme

    // MARK: - State

    @State private var participants: [(participant: SessionParticipant, profile: Profile)] = []
    @State private var routineInfo: (name: String, exercises: [RoutineExercise])? = nil
    /// Task 7 item 1 (pre-GA ledger): the full `Routine` row (not just
    /// `routineInfo`'s name/exercises projection) for this session's
    /// `routineID`, ONLY so `startSession()` can read `visibility`
    /// to decide whether Starting should also fire the group-attempt hook.
    /// See that function's doc comment for the full gating rationale.
    @State private var routineForSession: Routine? = nil
    /// Who has the lobby open, and where each device says it is — user id →
    /// `ArrivalStage.rawValue` (plan task S3).
    ///
    /// It was a `Set<UUID>`, which could only answer "is this lifter's app
    /// open". The arrival track needs to know AT THE GYM from ON THE WAY, and
    /// no column stores that: each device evaluates the geofence for itself
    /// and publishes the answer. A user present with no published stage still
    /// has a key here, so `presenceStages[id] != nil` is the same question the
    /// old `presenceSet.contains(id)` asked.
    @State private var presenceStages: [UUID: String] = [:]
    @State private var realtime = LobbyRealtimeService()
    /// The viewer's own ladder page, for the plan card's rung line (plan task
    /// S6). Nil is the normal case — no active block, or a fetch that did not
    /// land — and prints the routine's name, which is what this card printed
    /// before the rung reached it.
    @State private var rungPage: LadderPageModel?
    private let blockGoalRepository: any BlockGoalRepository = LiveBlockGoalRepository()
    /// THE CREW'S WEEK (owner decision 21, plan task S7). Empty is nil is no
    /// strip — see `crewWeek` below.
    @State private var crewWeekRows: [CrewWeekRow] = []

    @State private var errorText: String?
    @State private var isCheckingIn = false
    @State private var showTravelDialog = false
    @State private var isStarting = false
    @State private var showStartDialog = false
    @State private var navigateToInProgress = false
    /// Set by the exit-unwind onChange right before it pops this lobby — the
    /// onDisappear voice guard reads it to tell a deliberate session exit
    /// (leave voice) apart from browsing away while the session is still
    /// live (keep voice — the SESSION LIVE pill re-enters).
    @State private var exitingSession = false
    /// "Choose routine" picker (user report 2026-07-29 — the lobby had no
    /// path to a routine you'd already built).
    @State private var showRoutinePicker = false
    /// The 1-5 energy picker (plan tasks S5, S7).
    @State private var showEnergyPicker = false
    /// This session's Coach thread, once somebody has tapped the door
    /// (plan task S6). `Identifiable` through `SessionCoachThread`'s own
    /// `threadID`, wrapped so `navigationDestination(item:)` can drive it.
    @State private var openedCoachThread: OpenedCoachThread?
    /// Fix round 3 R-3: `open()` used to navigate unconditionally, even when
    /// `!isReachable(thread)` — the paywall the door is supposed to raise
    /// never appeared. Set instead of `openedCoachThread` in that branch.
    @State private var showCoachPaywall = false
    /// The consensus Start, armed when the last lifter checks in. Held so the
    /// leader tapping first — or the roster changing — can cancel it.
    @State private var consensusStart: Task<Void, Never>?
    /// The style default fires ONCE per lobby, on the organizer's client
    /// (plan task S2). The same one-shot `@State` idiom `consensusStart`
    /// above uses, and for the same reason: `reload()` runs on every realtime
    /// echo and every 5 s poll, so a re-render must not be able to re-write a
    /// choice the crew has since made.
    @State private var hasAppliedStyleDefault = false
    @State private var allExercises: [Exercise] = []
    @State private var currentSession: WorkoutSession?
    @State private var groupName: String?
    /// THE VENUE'S RACK COUNTS, class → count (decision 1). Empty is the
    /// ordinary answer: no venue, or a venue nobody has counted yet. A class
    /// that is ABSENT is unknown, never zero.
    @State private var rackCounts: [String: Int] = [:]
    /// The question is asked ONCE. Skipping silences it for this lobby, the
    /// same one-shot `@State` idiom `hasAppliedStyleDefault` uses and for the
    /// same reason: `reload()` runs on every realtime echo and every 5 s poll.
    @State private var rackAskSkipped = false
    /// What `set_venue_rack_count` said, shown on the question's own line.
    /// Never `errorText`: a refused rack count is not a lobby error and must
    /// not sit where a failed Start would.
    @State private var rackErrorText: String?

    // MARK: - Manage menu state

    @State private var showChangeTimeSheet = false
    @State private var changeTimeDate: Date = Date()

    @State private var showCancelOccurrenceDialog = false
    @State private var showCancelSeriesDialog = false
    @State private var upcomingOccurrenceCount: Int = 0

    @State private var showSeriesEditor = false

    // MARK: - Voice chrome (Phase O Task 5, item 5 — designer follow-up frames)

    @State private var showVoiceConnectedToast = false
    @State private var showVoiceCoachMark = false
    @State private var showVoiceMixerSheet = false

    // MARK: - Session chat (Task 3, Phase F)

    /// No canvas frame depicts a chat affordance for this screen
    /// (proof-frame-05.png's Lobby header shows only the back chevron +
    /// gearshape) — system-designed per task-3-brief.md: a bordered
    /// icon-button toolbar item + sheet, reusing this file's own
    /// `manageMenu` icon-button styling and `changeTimeSheet`'s
    /// NavigationStack-sheet idiom. See docs/design/accepted-deviations.json's
    /// "session-chat" entry.
    @State private var showChatSheet = false

    // MARK: - Check-in window state

    /// Toggled exactly once, by a single scheduled `Task.sleep` (never a repeating/polling
    /// Timer — see the `.task(id:)` on `actionBar`), when the 20-minute check-in window
    /// opens. `canCheckIn` reads live `Date()` on every body evaluation, so this only
    /// needs to force ONE re-render at the right moment for the button to unlock itself.
    @State private var checkInWindowRefreshTick = false

    // MARK: - Computed helpers

    private var selfID: UUID? { appState.currentProfile?.id }
    private var isOrganizer: Bool {
        #if DEBUG
        // A capture has no signed-in profile, so `organizerID == selfID`
        // would be false for every frame and the leader's controls — the
        // Change routine chip, the tappable ready widget — would never
        // render. The world states which side of that line it is on.
        if let catalog { return catalog.isOrganizer }
        #endif
        return (currentSession ?? session).organizerID == selfID
    }

    // MARK: - The arrival track's rows (plan tasks S3, S7)
    //
    // THE LOBBY'S ONE PRESENCE SIGNAL. Spec §3.1 and owner decision 16: there
    // is no separate roster and no separate ready tick, so this is what the
    // track, the energy card, the ready widget, Start's caption and
    // `allReady` all read. One derivation, so the caption can never disagree
    // with the track above it.

    /// Every lifter, staged. `ArrivalLaw` decides; this only supplies the two
    /// facts it takes — the DB's `check_in_state` and the stage that lifter's
    /// own device published.
    private var arrivalRows: [ArrivalRow] {
        #if DEBUG
        if let catalog { return catalog.rows }
        #endif
        return participants.map { item in
            ArrivalRow(
                id: item.participant.userID,
                name: item.profile.username,
                avatarURL: item.profile.avatarURL,
                stage: ArrivalLaw.stage(
                    checkInState: item.participant.checkInState,
                    publishedStage: presenceStages[item.participant.userID]),
                energy: item.participant.energy,
                isYou: item.participant.userID == selfID,
                isLate: ArrivalLaw.isLate(checkInState: item.participant.checkInState))
        }
    }

    /// My own row, when I am in this session.
    private var myArrivalRow: ArrivalRow? { arrivalRows.first(where: \.isYou) }

    private var checkedInCount: Int {
        arrivalRows.filter { $0.stage == .checkedIn }.count
    }

    /// Spec 3.1: "Start anyway" stays the leader's when someone is late
    /// (coordinator fix round 6, item 5) - `startPrimary`'s only reader. Read
    /// through `arrivalRows`, the same one derivation everything else on this
    /// screen reads, so this can never disagree with what the track draws.
    private var hasLateArrival: Bool {
        arrivalRows.contains(where: \.isLate)
    }

    /// The plan card's rows, already worded. `exerciseName(for:)` resolves the
    /// catalog's 1,300 exercises, which a frame cannot reach, so the fixture
    /// supplies worded rows instead (constraint 11).
    private var planRows: [SessionPlanRow] {
        #if DEBUG
        if let catalog { return catalog.planRows }
        #endif
        guard let info = routineInfo else { return [] }
        return info.exercises.map { exercise in
            SessionPlanRow(exercise: exercise, name: exerciseName(for: exercise))
        }
    }

    /// Today's rung, above the plan's rows (spec §3.1, plan task S6).
    ///
    /// THE VIEWER'S OWN rung, worded by `SessionRungLine` from the ladder page
    /// `loadRung()` fetched — the same resolver the warm-up's plan card uses,
    /// so one rung cannot be spelled two ways on two screens. A crewmate's
    /// block goal is not readable and this is not a per-lifter column.
    ///
    /// The routine's own name is still what prints when there is no block:
    /// that is the fallback, not a stand-in.
    ///
    /// `SessionPlanCard` takes ONE string, so the implication ("≈ 214 e1RM")
    /// is dropped here and printed only on the warm-up, whose card has a
    /// second line for it. The lobby card gaining one is a composition change
    /// frame 129 has not been asked for (constraint 14).
    private var planRungLine: String {
        #if DEBUG
        if let catalog { return catalog.rungLine }
        #endif
        return SessionRungLine.resolve(page: rungPage,
                                       routineName: routineInfo?.name ?? "").line
    }

    private var effectiveSession: WorkoutSession { currentSession ?? session }
    private var effectiveSeriesID: UUID? { effectiveSession.seriesID }

    private var isManageVisible: Bool {
        let state = effectiveSession.state
        return isOrganizer && (state == "scheduled" || state == "lobby_open")
    }

    /// **UNCHANGED IN MEANING, restated over the one derivation.**
    /// `ArrivalLaw.stage` returns `.checkedIn` if and only if
    /// `check_in_state == "ready"` — a device may not publish itself into that
    /// stage, which `SessionArrivalTests` asserts — so this is exactly the
    /// shipped `participants.allSatisfy { $0.checkInState == "ready" }`, read
    /// through the same rows the track draws. Reading it twice is how a Start
    /// caption comes to disagree with the track above it.
    private var allReady: Bool {
        let rows = arrivalRows
        return !rows.isEmpty && rows.allSatisfy { $0.stage == .checkedIn }
    }

    private var notReadyCount: Int {
        arrivalRows.filter { $0.stage != .checkedIn }.count
    }

    private var isCheckedIn: Bool { myArrivalRow?.stage == .checkedIn }

    // MARK: - Voice (Task 4 — PTT dock, Dossier §A.1's locked session-state scope)

    /// Session states the spec (Dossier §A.1) says voice should be live for.
    /// Matches the `sessions.state` check constraint enum minus the
    /// non-actionable states (`scheduled`, `completed`, `abandoned`).
    /// `editing`/`voting`/`locked` narrowed out (D7's five-state CHECK,
    /// mechanical cleanup decision 6, plan task S13): the states no longer
    /// exist.
    private static let voiceEligibleStates: Set<String> = [
        "lobby_open", "in_progress"
    ]

    private var isVoiceEligible: Bool {
        Self.voiceEligibleStates.contains(effectiveSession.state)
    }

    @MainActor
    private func joinVoiceIfEligible() async {
        guard isVoiceEligible else { return }
        await VoiceRoomService.shared.join(sessionID: effectiveSession.id)
    }

    /// Other participants' usernames, for `PTTDockRow`'s transmit hero
    /// (Phase O Task 5 item 5) — `VoiceRoomService` only knows LiveKit
    /// identity strings, never real usernames, so this view's own
    /// `Profile` data is what supplies them.
    private var otherParticipantNames: [String] {
        participants
            .filter { $0.participant.userID != selfID }
            .map(\.profile.username)
    }

    /// True once the voice room reaches `.connected` (either sub-state) —
    /// a plain `Bool` proxy over `VoiceRoomState` (which isn't `Equatable`,
    /// so `.onChange(of:)` can't watch `VoiceRoomService.shared.state`
    /// directly) that drives the connected-toast/first-run-coach-mark
    /// trigger below.
    private var isVoiceConnected: Bool {
        if case .connected = VoiceRoomService.shared.state { return true }
        return false
    }

    /// (identity, username) pairs for the voice mixer sheet — same
    /// "VoiceRoomService only knows identity strings, this view supplies
    /// real names" shape as `otherParticipantNames` above.
    private var voiceMixerParticipants: [(identity: String, name: String)] {
        let byIdentity = Dictionary(
            uniqueKeysWithValues: participants.map { ($0.participant.userID.uuidString.lowercased(), $0.profile.username) }
        )
        return VoiceRoomService.shared.connectedParticipantIDs
            .sorted()
            .map { identity in (identity, byIdentity[identity] ?? "Someone") }
    }

    /// Check-in opens 20 minutes before the scheduled start (server-enforced too —
    /// see `supabase/migrations/20260715000003_checkin_window.sql`). `nil` when the
    /// session has no `scheduledFor` (shouldn't happen for a lobby, but fail open
    /// rather than permanently locking the button on unexpected data).
    private var checkInOpensAt: Date? {
        effectiveSession.scheduledFor?.addingTimeInterval(-20 * 60)
    }

    private var canCheckIn: Bool {
        // Read (but don't branch on) `checkInWindowRefreshTick` so SwiftUI's dependency
        // tracking knows this computed property — and therefore `actionBar` — depends on
        // it; the one-shot `.task(id:)` toggle is otherwise never observed, since the
        // real truth here always comes from a fresh `Date()` comparison below.
        let _ = checkInWindowRefreshTick
        guard let checkInOpensAt else { return true }
        return Date() >= checkInOpensAt
    }

    private var checkInOpensAtText: String {
        guard let checkInOpensAt else { return "" }
        return checkInOpensAt.formatted(date: .omitted, time: .shortened)
    }

    private var notReadyDialogTitle: String {
        notReadyCount == 1
            ? "1 person hasn't checked in"
            : "\(notReadyCount) people haven't checked in"
    }

    // MARK: - Body
    //
    // Split into three layered expressions (CI 2026-08-12, twice: the
    // RELEASE-config type-check timeout at `body` survived closure
    // extraction — the ~25-modifier chain itself was the over-budget
    // expression. Same failure mode and fix as SessionLiveView's
    // arenaBase → arenaWithThrow → body layering). Each layer is a
    // separately-checked expression; behavior unchanged.

    /// Layer 1: scroll content + navigation chrome.
    private var lobbyScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Room code banner (canvas: full-width accent fill, large monospaced code)
                roomCodeBanner

                // Voice degraded banner (Dossier §A.2 lobby frame) — sits
                // beside the roster it degrades, not pinned to the dock
                // (contrast the live-session dock, which pins its own copy
                // of this banner above the sticky dock per that frame).
                if case .unavailable = VoiceRoomService.shared.state {
                    GSVoiceUnavailableBanner(retry: {
                        Task { await VoiceRoomService.shared.retry() }
                    })
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }

                // WHO IS WHERE — the lobby's ONLY presence signal (spec §3.1,
                // owner decision 16). It replaces the check-in status card,
                // the participants section, the participant row, the check-in
                // badge and the check-in subtitle: five objects saying one
                // thing, four of them about a roster that no longer exists.
                //
                // ALL-READY (owner ruling 2026-09-12): the track becomes the
                // accent widget and NOTHING ELSE MOVES. Everything below —
                // the plan, the energy, Coach's door — stays exactly where it
                // is in the waiting state.
                if allReady {
                    EveryoneHereCard(rows: arrivalRows,
                                     caption: readyCaption,
                                     isTappable: isOrganizer,
                                     onTap: { Task { await startSession() } })
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                } else {
                    SessionArrivalTrack(rows: arrivalRows)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }

                // Coach's door (spec §3.6, plan task S6). The thread is
                // resolved ON TAP, never on load: a lobby that opened a Coach
                // room every time it appeared would create a thread for a
                // session nobody asked Coach about.
                //
                // No note pre-tap (review push-5 R-18, finding 6/12,
                // deleting `lockedNote`): `openedCoachThread` is only ever
                // set on the reachable branch (`openCoachThread()` presents
                // `PaywallView` on the other one), so a locked-room note
                // could never fire from here even before the paywall's own
                // dormancy made the question moot. A genuine pre-tap
                // indicator needs the reachability check available before a
                // tap, which is Phase B's.
                CoachDoorRow(title: SessionCopy.talkToCoach,
                             detail: SessionCopy.talkToCoachDetail,
                             note: nil,
                             onTap: { Task { await openCoachThread() } })
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // THE WHOLE PLAN, one row per exercise (spec §3.1) — not the
                // first exercise and a "Then:" list. ONE card-level
                // `Change routine` control for the leader (fix round 3 R-7 —
                // ten identical per-row `Swap` chips all opened the same
                // picker) presents the SHIPPED routine picker: spec §3.4
                // mode 1 is what a swap becomes AFTER Start and is Phase
                // B's; before Start the leader is simply choosing the
                // session's routine, which is what the picker already does.
                if !planRows.isEmpty {
                    SessionPlanCard(kicker: SessionCopy.theSession,
                                    rungLine: planRungLine,
                                    rows: planRows,
                                    onChangeRoutine: isOrganizer
                                        ? { showRoutinePicker = true } : nil)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                } else {
                    noRoutineYet
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                // HOW THE CREW FEELS (owner decision 18). The ask belongs to
                // whoever has not answered — me — and disappears once I have;
                // the card never nags about somebody else.
                CrewEnergyCard(rows: arrivalRows,
                               reported: LobbyCopy.energyReported(
                                   reported: arrivalRows.filter { $0.energy != nil }.count,
                                   total: arrivalRows.count),
                               askTitle: myArrivalRow?.energy == nil
                                   ? SessionCopy.howAreYouFeeling : nil,
                               onAsk: { showEnergyPicker = true })
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // HOW THIS SESSION MOVES (spec §1, owner decision 1, plan
                // task S2). The style is the CREW'S decision, not the
                // leader's — every row is tappable for everyone, and the
                // shipped organizer-or-participant UPDATE policy is what
                // grants it. It renders only before Start; see `styleCard`,
                // which owns its own padding for exactly that reason — an
                // empty branch must take no space (the `roomCodeBanner`
                // idiom above).
                styleCard

                // THE CREW'S WEEK (owner addition 2026-09-12, on trial). ONE
                // LINE, removable in one line — that is the deal. Shown in
                // both the waiting and the ready state, directly under the
                // energy widget and above the talk dock.
                if let crewWeek {
                    CrewWeekStrip(week: crewWeek)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

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
        .overlay(alignment: .top) {
            // "Voice connected" toast (Phase O Task 5 item 5) — transient,
            // this view owns the show/hide timer (GSVoiceConnectedToast has
            // no opinion on timing, matching every other voice component's
            // "callers gate visibility" contract).
            if showVoiceConnectedToast {
                GSVoiceConnectedToast(groupName: groupName)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // First-run coach mark (Phase O Task 5 item 5) — sits
                // directly above the dock, per the designer follow-up frame.
                if showVoiceCoachMark {
                    GSVoiceCoachMark(onDismiss: { showVoiceCoachMark = false })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                // ── PUSH-TO-TALK DOCK ────────────────────────────────────
                // Open layout question flagged by Dossier §A.2 (never
                // resolved there): whether the PTT dock replaces, stacks
                // above, or sits below the existing `actionBar`. ASSUMPTION
                // (judgment call, no design ruling to follow): stacks above,
                // matching SessionLiveView's own `PTTDockRow`, which
                // sits between its content and its bottom action bar the
                // same way (SessionLiveView.swift:2885-2894). Fix round
                // 3 R-11: previously cited as "SessionLiveView's
                // soundboard dock" — a literal grep for that word finds
                // nothing, so the precedent is named directly instead.
                if isVoiceEligible {
                    // Same retry closure the degraded banner above receives,
                    // so the dock's RETRY and the banner's Retry are one
                    // action and cannot disagree.
                    PTTDockRow(otherParticipantNames: otherParticipantNames,
                               onRetry: { Task { await VoiceRoomService.shared.retry() } })
                }
                actionBar
            }
        }
        // Pushed detail screen with its own bottom-pinned action bar — see
        // GSComponents.swift's GSHidesDock for why the custom dock can't just
        // reserve more safe-area inset for content reached via push.
        .gsHidesDock()
        .navigationTitle(groupName.map { "Lobby · \($0)" } ?? "Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Header "Connecting voice…" pill (Dossier §A.2 lobby frame).
            if case .connecting = VoiceRoomService.shared.state {
                ToolbarItem(placement: .topBarTrailing) {
                    GSConnectingVoicePill()
                }
            }
            // Voice mixer entry point (Phase O Task 5 item 5) — no canvas
            // frame depicts WHERE the mixer sheet opens from (the frames
            // show only its content), so this follows `chatButton`'s own
            // existing "bordered icon-button toolbar item" idiom
            // immediately beside it; see docs/design/accepted-deviations.json's
            // "voice-mixer-entry-point" entry.
            if isVoiceConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    voiceMixerButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                chatButton
            }
            if isManageVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    manageMenu
                }
            }
        }
    }

    /// Layer 2: lifecycle — load task, voice/scene/state observers, the
    /// pre-live poll, and the disappear voice guard.
    private var lobbyWithLifecycle: some View {
        lobbyScroll
        .task { await openAndLoad() }
        // The viewer's own ladder page, once. A block enrollment does not
        // change while a lobby is open, so this is a `.task`, not a poll —
        // the same reasoning `SessionRunnerView.loadBlock()` carries.
        .task { await loadRung() }
        // The crew's week, once. The window is a whole week and the counts move
        // only when somebody finishes a session, which nobody in this lobby has
        // yet — so a poll would re-read the same seven days every five seconds.
        .task { await loadCrewWeek() }
        .onChange(of: isVoiceConnected) { wasConnected, nowConnected in
            guard nowConnected, !wasConnected else { return }
            // Phase O Task 5 item 5: fires on every genuine `.idle`/
            // `.connecting`/etc -> `.connected` transition, not just the
            // first ever (the toast) — but the coach mark only the first
            // time this device has ever connected voice (marked shown
            // immediately, not on dismiss, so it can never show twice even
            // if the user backs out before tapping "Got it").
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
        .sheet(isPresented: $showVoiceMixerSheet) {
            voiceMixerSheet
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            // Coming back to the app is ONE moment the geofence answer is
            // likely to have changed — the lifter walked in while the phone
            // was in their pocket. Fix round 3 R-9: not the only one; the
            // realtime `onChange` callback and the pre-live poll's
            // routine-drift branch below now republish too. None of this is
            // live geofence monitoring (a background trigger on location
            // change) — that's Phase B. Every path here is a snapshot taken
            // at a moment the lobby already had a reason to re-sync.
            Task { await reload(); await publishOwnStage() }
        }
        // CONSENSUS START (spec §3.1). Watches the roster the way the
        // auto-forward below watches the state: `allReady` turning true arms
        // one cancellable shot, and anything that moves the roster — or the
        // leader tapping first — cancels it.
        .onChange(of: allReady) { _, _ in updateConsensusStart() }
        .onChange(of: isStarting) { _, _ in updateConsensusStart() }
        .onDisappear { consensusStart?.cancel(); consensusStart = nil }
        // Members' start signal (user field test 2026-07-30: only the
        // organizer navigated — everyone else sat on "Waiting for organizer
        // to start…" forever). The organizer's start reaches this client as
        // a sessions-row UPDATE → realtime onChange → reload() refreshes
        // `currentSession`; this observer completes the handoff by pushing
        // the live screen. Fires for late lobby arrivals too (nil →
        // "in_progress" on first reload is a change). `navigateToInProgress`
        // doubles as the voice-persistence signal in onDisappear, so voice
        // carries into the session exactly like the organizer's own push.
        .onChange(of: currentSession?.state) { _, newState in
            // Stale-pill hygiene: a session that ended while the user was
            // browsing elsewhere (swipe-down, then the crew finished it)
            // must not keep advertising SESSION LIVE.
            if newState == "completed" || newState == "abandoned",
               appState.liveGroupSession?.sessionID == session.id {
                appState.liveGroupSession = nil
            }
            guard newState == "in_progress", !navigateToInProgress else { return }
            Task { @MainActor in
                // Same ordering as startSession(): drop the lobby channel
                // before the live screen claims its own.
                await realtime.unsubscribe()
                navigateToInProgress = true
            }
        }
        // Session-exit unwind (user 2026-08-01: "leaving a session should
        // take you back to the Home Screen, not back to the lobby"): the
        // live view flags the session right before it pops (leave, recap
        // Done, member-side completion); when the pop clears this binding,
        // the lobby consumes the flag and pops itself — landing on
        // whatever pushed it (Home, or the group page).
        .onChange(of: navigateToInProgress) { _, showing in
            guard !showing,
                  appState.sessionExitToHomeID == session.id else { return }
            appState.sessionExitToHomeID = nil
            exitingSession = true
            dismiss()
        }
        // The waiting spinner POLLS what it promises (field 2026-07-31: a
        // member sat in the lobby with a dead realtime socket — "Voice
        // unavailable" on the same phone — so the organizer's start UPDATE
        // never arrived and "Waiting for organizer to start…" waited
        // forever). Every 5s while pre-live and on screen; a state flip
        // lands in `currentSession` and the onChange above completes the
        // handoff. The realtime echo remains the fast path.
        .task(id: currentSession?.state ?? session.state) {
            #if DEBUG
            // GLOBAL CONSTRAINT 11, the same guard `openAndLoad`, `reload`,
            // `publishOwnStage`, `applyStyleDefaultIfNeeded` and `pickStyle`
            // carry — this poll was the one entry point in this file without
            // it (final review, finding 5). `LobbyFixtures.waiting`'s session
            // is `lobby_open`, which is IN the pre-live set below, so every
            // lobby frame was firing `SessionRepository.session(id:)` at a
            // fixture UUID every five seconds for as long as the capture ran
            // — Phase A's N3 defect, and now across five frames rather than
            // four (`session-style-choice` joined them).
            if catalog != nil { return }
            #endif
            // `editing`/`voting`/`locked` narrowed out (D7's five-state
            // CHECK, mechanical cleanup decision 6, plan task S13).
            let preLive: Set<String> = ["scheduled", "lobby_open"]
            guard preLive.contains(currentSession?.state ?? session.state) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if let fresh = try? await SessionRepository.session(id: session.id) {
                    // Routine drift needs the FULL reload (routineInfo is
                    // loaded there) — a member polling on a dead socket
                    // must see the organizer's routine pick, not just the
                    // state flip.
                    if fresh.routineID != currentSession?.routineID {
                        await reload()
                        // Fix round 3 R-9: the pre-live poll is this lobby's
                        // stand-in for pull-to-refresh (there is no
                        // `.refreshable` here) — a dead realtime socket is
                        // exactly the case where this device's last
                        // published stage is most likely stale too.
                        await publishOwnStage()
                    } else {
                        currentSession = fresh
                    }
                }
            }
        }
        .onDisappear {
            Task { await realtime.unsubscribe() }
            // Voice room persists across the Lobby -> live-session
            // transition (same session, same `VoiceRoomService` instance —
            // see its own doc comment on why `join()` no-ops while already
            // connecting/connected). `navigateToInProgress` is the exact
            // signal `startSession()` sets right before that push, so it
            // doubles as the identity guard here: only leave voice when this
            // disappearance is NOT that push (i.e. the user backed out of
            // the lobby before starting the session).
            // Sheet-era addendum (2026-08-12): with the live view presented
            // as a SHEET, this onDisappear no longer fires on session entry
            // (the lobby stays "appeared" under a sheet) — it fires on the
            // exit-unwind pop and on the user browsing away. Only leave
            // voice for a deliberate exit or a not-live lobby back-out;
            // browsing away mid-session keeps voice up, matching the
            // SESSION LIVE pill's promise that you're still in the session.
            // (Edge accepted: a session the crew ends while you're browsing
            // leaves voice up until the room itself closes.)
            let sessionLive = (currentSession?.state ?? session.state) == "in_progress"
            if !navigateToInProgress, exitingSession || !sessionLive {
                Task { await VoiceRoomService.shared.leave() }
            }
        }
    }

    /// Layer 3: presentation — sheets, dialogs, the live-session sheet and
    /// the rejoin bar.
    var body: some View {
        lobbyWithLifecycle
        // Routine picker (user report 2026-07-29)
        .sheet(isPresented: $showRoutinePicker) {
            LobbyRoutinePickerSheet(
                currentRoutineID: currentSession?.routineID ?? session.routineID,
                onPick: { routineID in
                    Task {
                        do {
                            try await SessionRepository.setRoutine(sessionID: session.id,
                                                                   routineID: routineID)
                            await reload()
                        } catch let error as GymSyncError {
                            errorText = error.errorDescription
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
            )
        }
        // Session chat sheet (Task 3)
        .sheet(isPresented: $showChatSheet) {
            chatSheet
        }
        // HOW ARE YOU FEELING? (plan tasks S5, S7) — five answers and a
        // cancel, the shape the lobby already raises its other two questions
        // in.
        .confirmationDialog(SessionCopy.howAreYouFeeling,
                            isPresented: $showEnergyPicker,
                            titleVisibility: .visible) {
            energyPickerButtons
        } message: {
            Text("Only your crew sees this, and only for this session.")
        }
        // This session's Coach room (plan task S6). One room for the whole
        // crew, opened find-or-create on the tap.
        //
        // Fix round 3 R-10: messages post and read through the PERSONAL
        // `CoachChatRepository` (append stamps `user_id = me`; `threads()`
        // filters `user_id = me`) — cross-member access here rests entirely
        // on D3/D5's RLS (coach_chat_messages scoped to the thread's
        // participants), not on this view. Acceptable because this thread is
        // only ever reached from the lobby, never from the personal Coach
        // list, so a member can't stumble into another session's room.
        .navigationDestination(item: $openedCoachThread) { opened in
            CoachThreadView(thread: CoachChatThread(
                id: opened.thread.threadID,
                title: SessionCopy.talkToCoach,
                summary: "",
                summarizedThrough: nil,
                updatedAt: effectiveSession.scheduledFor ?? effectiveSession.createdAt))
                .background(theme.bg)
                .navigationTitle(SessionCopy.talkToCoach)
                .navigationBarTitleDisplayMode(.inline)
        }
        // Fix round 3 R-3: the door's paywall, for the branch `open()` takes
        // when the crew can't reach the room. No `highlight`: none of
        // `Monetization.Feature`'s four cases name a session Coach room, and
        // inventing one is a product decision this fix round isn't making.
        .sheet(isPresented: $showCoachPaywall) {
            PaywallView()
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
        // SHEET, not a push (owner 2026-08-12: "you can't swipe down in a
        // group session like you can for a solo session"). Swiping down is
        // now a recoverable browse — the session keeps running, the
        // SESSION LIVE pill (AppState.liveGroupSession) and the lobby's
        // rejoin bar both route back in. The exit-unwind onChange above
        // still distinguishes the two dismissals: a deliberate exit carries
        // sessionExitToHomeID and pops the lobby too; a swipe-down doesn't.
        //
        // Closure bodies extracted to named vars (CI 2026-08-12: inline
        // content pushed `body` past the RELEASE type-check budget —
        // "unable to type-check this expression in reasonable time" on the
        // archive job only; Debug builds stayed green. Same failure mode
        // and fix as WorkoutSessionView's body split, 2026-07-27).
        .sheet(isPresented: $navigateToInProgress) { liveSessionSheetContent }
        .safeAreaInset(edge: .bottom) { rejoinBar }
    }

    /// Sheet content for the live session. `.id` — the live view's @State
    /// (liveSession, my-turn UI) must die with its session: on 2026-07-30/31
    /// a live view whose session prop was swapped underneath kept showing
    /// the OLD session while writing sets into the new one. Identity-pinning
    /// makes prop and state inseparable.
    ///
    /// effectiveSession, not the prop (field 2026-07-31): members' `session`
    /// predates the organizer's routine pick, so the live view opened with
    /// routineID nil. currentSession carries the freshest fetched row.
    ///
    /// No NavigationStack wrapper: the live view is all custom chrome (its
    /// .navigationTitle("") calls are no-ops outside a stack, and its
    /// chat/detail sheets carry their own stacks).
    private var liveSessionSheetContent: some View {
        // `SessionRunnerView`, not `SessionInProgressView`: the warm-up phase
        // is a SCREEN now, not a page inside the live view (plan task S9), and
        // the runner is the router that decides which one the session is on.
        SessionRunnerView(session: effectiveSession, participants: participants)
            .id(effectiveSession.id)
    }

    /// Rejoin bar — after a swipe-down the lobby is what's on screen and its
    /// auto-forward onChange won't refire (state didn't change), so the way
    /// back in must be visible and extruded like every tappable.
    @ViewBuilder
    private var rejoinBar: some View {
        if !navigateToInProgress,
           (currentSession?.state ?? session.state) == "in_progress" {
            Button {
                navigateToInProgress = true
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(theme.bg).frame(width: 8, height: 8)
                    Text("REJOIN — SESSION LIVE")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .kerning(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Chat button + sheet (Task 3, Phase F)
    //
    // `effectiveSession.groupID` is passed straight through as the
    // sub-thread's group_id — ChatView.init(sessionID:groupID:)'s doc
    // comment explains why this MUST be the session's own group_id (nil for
    // a solo/ad-hoc session): the sub-thread INSERT RLS binds it via
    // `IS NOT DISTINCT FROM sessions.group_id`
    // (20260719000011_chat_subthread_lock_hardening.sql #5).

    private var chatButton: some View {
        Button {
            showChatSheet = true
        } label: {
            // Same icon-button sizing/hit-target as `manageMenu`'s gearshape
            // below (44×44 tap target, 18pt regular-weight symbol).
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.text)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var chatSheet: some View {
        NavigationStack {
            ChatView(sessionID: effectiveSession.id, groupID: effectiveSession.groupID)
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

    // MARK: - Voice mixer (Task 5, item 5 — same toolbar-button + sheet
    // idiom as chatButton/chatSheet above)

    private var voiceMixerButton: some View {
        Button {
            showVoiceMixerSheet = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.text)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

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

    // MARK: - Manage Menu (functional items unchanged)

    @ViewBuilder
    private var manageMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.text)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Change Time Sheet

    /// Extracted to `Features/Sessions/SessionTimeSheet.swift` so the
    /// calendar & scheduling page's swipe-to-MOVE renders the same control
    /// instead of a second one (Stream D fix round 1, F1). Chrome only: the
    /// sheet still calls back into `applyReschedule()` here, so what SAVE
    /// does on this screen — reschedule, reload, then EventKit sync with
    /// this screen's own `routineInfo` — is unchanged, and so is every
    /// pixel of the sheet.
    private var changeTimeSheet: some View {
        SessionTimeSheet(
            date: $changeTimeDate,
            onCancel: { showChangeTimeSheet = false },
            onSave: { Task { await applyReschedule() } }
        )
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
            .cornerRadius(GSMetrics.radiusMd)   // redesign: rounded accent surface
        }
    }

    private func exerciseName(for ex: RoutineExercise) -> String {
        allExercises.first(where: { $0.id == ex.exerciseID })?.name ?? "Exercise"
    }

    // MARK: - The crew's week (owner addition 2026-09-12, on trial)

    /// What `CrewWeekStrip` draws, or nil for no strip and no space.
    ///
    /// **THE READ IS `crew_week(p_session_id, p_week_start)`** (plan task S7,
    /// owner decision 21) — one row per participant of THIS session carrying
    /// their weekly session goal and their completed count inside the window
    /// `WeekMath.weekStartISO8601()` names (ruling R-B2-16: the RPC's
    /// `p_week_start` is timestamptz, not date — the client sends the
    /// device-local week-start INSTANT, with its own offset, so the server's
    /// time zone cannot silently pick a different week), gated server-side
    /// on membership of the session. It replaces the Phase A gap this
    /// comment used to describe: the per-member weekly count existed
    /// nowhere, since `SocialTabView`'s bar counts the whole crew and
    /// `group_consistency_honor` counts thirty days.
    ///
    /// NIL WHILE THE ROWS ARE EMPTY, so the strip and its space appear together
    /// or not at all — which is what this property has always promised. A
    /// non-participant, or a read that did not land, is the same nil.
    ///
    /// `doneByDay` IS NIL BY DESIGN (plan decision 2): the RPC returns no
    /// per-day breakdown, so production draws the straight line
    /// `CrewWeekMath.actualSeries` already falls back to — honest about being a
    /// straight line rather than pretending to a shape. The catalog fixture on
    /// frame 135 keeps its shaped one.
    private var crewWeek: CrewWeek? {
        #if DEBUG
        if let catalog { return catalog.crewWeek }
        #endif
        guard !crewWeekRows.isEmpty else { return nil }
        return CrewWeek(
            lifters: crewWeekRows.map { row in
                // The goal is mapped STRAIGHT ACROSS (ruling R-B2-14): the
                // server already returns the EFFECTIVE weekly goal for that
                // week, and re-applying the rule here would apply it twice.
                CrewWeekLifter(id: row.userID, name: row.username,
                               goal: row.goal, done: row.done, doneByDay: nil)
            },
            todayIndex: CrewWeekMath.todayIndex())
    }

    // MARK: - The lobby's own pieces (plan task S7)

    /// The caption on the accent widget. The leader's says it is theirs; the
    /// crew's names the leader — and both say the session starts on its own,
    /// because it does (the consensus Start below). A caption that promised
    /// nothing would leave a crewmate watching a screen that looks stalled.
    private var readyCaption: String {
        if isOrganizer { return LobbyCopy.readyLeaderCaption }
        let leaderID = effectiveSession.organizerID
        let leader = arrivalRows.first { $0.id == leaderID }?.name
        return LobbyCopy.readyCrewmateCaption(
            leaderFirstName: SessionCopy.firstName(leader ?? "the leader"))
    }

    /// The plan card's empty state. A session with no routine is a legible
    /// state, not a blank: the leader picks one, and the copy names the
    /// affordance that exists rather than one that does not.
    private var noRoutineYet: some View {
        VStack(alignment: .leading, spacing: 9) {
            GSSectionHeader(SessionCopy.theSession)
            Text(isOrganizer
                 ? "No routine yet — choose one of yours and the crew sees it here."
                 : "No routine yet. The leader picks one before Start.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
            if isOrganizer {
                Button { showRoutinePicker = true } label: {
                    Text("Choose routine")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    // MARK: - HOW THIS SESSION MOVES (spec §1, owner decision 1, plan task S2)

    /// The card's kicker. A `static` so `LobbyStyleCardTests` can read the
    /// copy without building a view.
    static let styleKicker = "HOW THIS SESSION MOVES"

    /// The rack question's words, `static` for the same reason as the kicker
    /// above: the copy is testable without building a view.
    static let rackQuestion = "How many racks here?"

    /// The equipment class the rack question is about, or `nil` when it must
    /// not be asked at all (decision 1). ALL FOUR conditions:
    ///
    ///   1. the crew is running ROUNDS — stations exist only there, so a rack
    ///      count buys a Freestyle or Together session nothing;
    ///   2. the session KNOWS ITS VENUE (`claim_session_venue`, plan task
    ///      S5) — there is no building to record a count against otherwise;
    ///   3. the first exercise's equipment MAPS to a venue class — `nil`
    ///      means unknown, and the app does not ask about something it could
    ///      not spend;
    ///   4. that class has NO COUNT yet — the number belongs to the building
    ///      and is asked once, not re-asked of every crew that trains there.
    ///
    /// Plus the lifter's own SKIP, which silences it for this lobby.
    ///
    /// GLOBAL CONSTRAINT 11: a catalog world never reaches a repository, and
    /// `LobbyWorld` sets no venue — so frame 129 and frame 136 render exactly
    /// what they render today (constraint 14). The guard below is belt to
    /// that braces, the same shape `applyStyleDefaultIfNeeded()` carries.
    private var rackAskClass: String? {
        #if DEBUG
        if catalog != nil { return nil }
        #endif
        guard !rackAskSkipped,
              effectiveSession.style == .rounds,
              effectiveSession.venueID != nil,
              let first = routineInfo?.exercises.first,
              let equipment = allExercises.first(where: { $0.id == first.exerciseID })?.equipment,
              let equipmentClass = Venue.equipmentClass(for: equipment),
              rackCounts[equipmentClass] == nil
        else { return nil }
        return equipmentClass
    }

    /// The venue's rack counts, read once the session knows its venue.
    ///
    /// Best-effort, like every other read this screen makes: a failure leaves
    /// the dictionary empty, which leaves the cap unknown and the split at
    /// today's `ceil(crew / 3)`. Behind the `catalog != nil` guard every read
    /// in this file carries (global constraint 11).
    @MainActor
    private func loadRackCounts() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard rackCounts.isEmpty, let venueID = effectiveSession.venueID else { return }
        do {
            rackCounts = try await VenueRackRepository.counts(venueID: venueID)
        } catch {
            AppLogger.db.error(
                "rack counts failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Record the answer the crew gave.
    ///
    /// ON A REFUSAL — `P0001`, which is the RPC saying this caller has no
    /// `venue_checkins` row at this venue inside 12 hours — the message lands
    /// on the question's own line, the stepper keeps its value, the count
    /// stays unknown and the cap stays `nil`. START IS NEVER BLOCKED by any
    /// of it: this write is not on the path of anything the lifter is waiting
    /// for.
    @MainActor
    private func saveRackCount(_ equipmentClass: String, count: Int) async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard let venueID = effectiveSession.venueID else { return }
        rackErrorText = nil
        do {
            try await VenueRackRepository.set(venueID: venueID,
                                              equipmentClass: equipmentClass,
                                              count: count)
            // Locally, so the question disappears without waiting for a read.
            rackCounts[equipmentClass] = count
        } catch let error as GymSyncError {
            rackErrorText = error.errorDescription
        } catch {
            rackErrorText = error.localizedDescription
        }
    }

    /// The crew's style choice, above THE CREW'S WEEK.
    ///
    /// **NOT RENDERED AFTER START.** `private.session_round_guard` (plan task
    /// D3) rejects a style write once `lifting_started_at` is stamped, so the
    /// card stops offering one at exactly that moment: the UI never offers a
    /// write the server will reject, and the crew never taps a row that
    /// silently fails.
    ///
    /// Design rule 1: the CARD is the raised surface
    /// (`.gs3DCard(radiusMd, lip 6)`); the three rows inside it are flat,
    /// because furniture inside a raised box stays flat. Design rule 2: the
    /// selected mark is `Color.gsSuccess`, never a second accent — the
    /// lobby's one accent is Start.
    @ViewBuilder
    private var styleCard: some View {
        if effectiveSession.liftingStartedAt == nil {
            VStack(alignment: .leading, spacing: 9) {
                GSSectionHeader(Self.styleKicker)
                // Listed rather than looped over `allCases` on purpose: what
                // the lobby OFFERS is a deliberate choice, and
                // `SessionStyleTests` pins this order as `allCases`' own.
                VStack(spacing: 0) {
                    styleRow(.rounds)
                    GSDivider()
                    styleRow(.freestyle)
                    GSDivider()
                    styleRow(.together)
                }
                // THE RACK QUESTION (decision 1), asked once and quietly, of
                // the only people who can answer it: the crew standing in the
                // building. Flat inside this raised card (rule 1), no accent
                // (rule 2 — the lobby's accent is Start), and it NEVER blocks
                // Start: it is a line under the style rows, not a gate in
                // front of anything.
                if let rackClass = rackAskClass {
                    GSDivider()
                    RackCountAsk(question: Self.rackQuestion,
                                 errorText: rackErrorText,
                                 onSave: { count in
                                     Task { await saveRackCount(rackClass, count: count) }
                                 },
                                 onSkip: { rackAskSkipped = true })
                        .padding(.top, 10)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    /// One flat, tappable row: the glyph, the title, the consequence, and the
    /// tick when it is the crew's current choice.
    ///
    /// The tick is drawn at zero opacity rather than removed, so choosing a
    /// different style cannot re-flow the card — and hidden from
    /// accessibility in the same breath, so a reader does not announce three
    /// checkmarks.
    private func styleRow(_ style: SessionStyle) -> some View {
        Button {
            Task { await pickStyle(style) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: style.copy.glyph)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.copy.title)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text(style.copy.line)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.gsSuccess)
                    .opacity(effectiveSession.style == style ? 1 : 0)
                    .accessibilityHidden(effectiveSession.style != style)
                    .padding(.top, 1)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The routine's rows, reduced to the two columns the default law reads
    /// (`SessionStyleDefault`, the plan's data decision 2).
    ///
    /// `routineInfo.exercises` carries `cardio_minutes`; the CATEGORY lives on
    /// the exercise itself, so this is the same `allExercises` join
    /// `exerciseName(for:)` above performs. An exercise the catalog has not
    /// resolved yet contributes an empty category — neither cardio nor
    /// mobility — which can only push the answer toward `.rounds`. That is the
    /// safe direction: a half-loaded catalog must never auto-switch a crew to
    /// Together.
    private var styleDefaultRows: [(category: String, cardioMinutes: Int?)] {
        guard let info = routineInfo else { return [] }
        return info.exercises.map { exercise in
            (category: allExercises.first(where: { $0.id == exercise.exerciseID })?.category ?? "",
             cardioMinutes: exercise.cardioMinutes)
        }
    }

    /// The one-shot default rule, as a pure function so it can be tested
    /// without a view (plan task S2).
    ///
    /// True only when NOBODY HAS CHOSEN. `rounds` is the column's own DEFAULT
    /// (`20260913000101`), so "the row says rounds" and "the row has never
    /// been set" are the same fact — which is why a session already reading
    /// `freestyle` or `together` is left alone even when the routine derives
    /// something else. A derived default never overrides a decision.
    ///
    /// FREESTYLE IS NEVER WHAT A DEFAULT WRITES (owner decision 1, fix round
    /// 1 / F1 — `LobbyStyleCardTests.testFreestyleIsNeverWrittenByTheDefault`
    /// caught this on run 34781441881). `SessionStyleDefault` can only ever
    /// answer `.rounds` or `.together`, so this refusal changes nothing that
    /// production reaches today — which is exactly why it belongs here rather
    /// than only there: this predicate is the LAST gate before the PATCH, and
    /// the owner's rule is a property of what may be written silently, not of
    /// one function's current return set. A fourth style, or a caller that
    /// derives differently, meets the rule at the gate instead of getting a
    /// crew's Freestyle written for them.
    static func shouldApplyDefault(current: SessionStyle,
                                   derived: SessionStyle,
                                   hasApplied: Bool) -> Bool {
        guard derived != .freestyle else { return false }
        return !hasApplied && current == .rounds && derived != .rounds
    }

    /// Apply the derived default once, from the organizer's client only.
    ///
    /// ONE CLIENT WRITES. Every participant's lobby would derive the same
    /// answer from the same rows, so letting all of them write it would be
    /// four PATCHes racing to agree; the organizer is the one client
    /// guaranteed to exist for a scheduled session.
    ///
    /// GLOBAL CONSTRAINT 11: a catalog build must not PATCH a fixture UUID.
    /// `reload()` already returns early in catalog mode and never reaches
    /// here; the guard below is belt as well as braces, the same shape
    /// `openCoachThread()` uses.
    ///
    /// A failed write is NOT retried — the flag is set before the await, so a
    /// re-render cannot re-fire it. That is the honest behaviour: the column
    /// keeps its `rounds` default and the crew's own tap is the recovery, and
    /// a lobby that kept retrying a PATCH on every 5 s poll would be worse
    /// than a default that did not land.
    @MainActor
    private func applyStyleDefaultIfNeeded() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard isOrganizer, !hasAppliedStyleDefault else { return }
        let rows = styleDefaultRows
        guard !rows.isEmpty else { return }   // no plan yet: nothing to derive from
        let derived = SessionStyleDefault.style(forExercises: rows)
        guard Self.shouldApplyDefault(current: effectiveSession.style,
                                      derived: derived,
                                      hasApplied: hasAppliedStyleDefault) else { return }
        hasAppliedStyleDefault = true
        do {
            try await SessionRepository.setStyle(sessionID: effectiveSession.id, style: derived)
            currentSession?.style = derived
        } catch {
            AppLogger.db.error(
                "style default failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A crewmate's tap. Optimistic, then written.
    ///
    /// No new subscription: the session DB channel
    /// (`LobbyRealtimeService.swift:147-157`) already watches `sessions`
    /// UPDATE, so every other lobby re-reads this row through the path it
    /// already had. This client shows the choice immediately and rolls back
    /// if the write is refused.
    ///
    /// Setting the one-shot flag here too is what stops the derived default
    /// from stomping a deliberate choice on the next `reload()`.
    @MainActor
    private func pickStyle(_ style: SessionStyle) async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        hasAppliedStyleDefault = true
        guard effectiveSession.style != style else { return }
        let previous = effectiveSession.style
        currentSession?.style = style
        do {
            try await SessionRepository.setStyle(sessionID: effectiveSession.id, style: style)
            errorText = nil
        } catch let error as GymSyncError {
            currentSession?.style = previous
            errorText = error.errorDescription
        } catch {
            currentSession?.style = previous
            errorText = error.localizedDescription
        }
    }

    /// `navigationDestination(item:)` needs an `Identifiable`;
    /// `SessionCoachThread` is a plain value, so this is the wrapper rather
    /// than a conformance the model does not need.
    private struct OpenedCoachThread: Identifiable, Hashable {
        let thread: SessionCoachThread
        var id: UUID { thread.threadID }

        static func == (lhs: OpenedCoachThread, rhs: OpenedCoachThread) -> Bool {
            lhs.thread == rhs.thread
        }
        func hash(into hasher: inout Hasher) { hasher.combine(thread.threadID) }
    }

    /// Find-or-create this session's Coach room, then open it (plan task S6).
    ///
    /// ON TAP, not on load — see the door's own comment in `lobbyScroll`. A
    /// catalog frame never reaches this: nothing taps in a capture, and the
    /// guard below is belt as well as braces.
    @MainActor
    private func openCoachThread() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        do {
            let thread = try await SessionCoachThreadRepository.open(
                sessionID: effectiveSession.id)
            // Fix round 3 R-3: branch on reachability instead of navigating
            // unconditionally. Inert today (Monetization.paywallEnabled =
            // false, so isReachable is always true) — this is what makes the
            // branch correct once it flips live, rather than a product
            // change nobody asked for today.
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

    /// The 1-5 picker behind `How are you feeling?` (plan task S5).
    ///
    /// A confirmation dialog rather than a sheet: five choices and a cancel is
    /// exactly what the shape is for, and the lobby already raises two others
    /// this way (the travel dialog, Start anyway).
    @ViewBuilder
    private var energyPickerButtons: some View {
        ForEach([5, 4, 3, 2, 1], id: \.self) { value in
            Button(Self.energyLabel(value)) {
                Task { await setEnergy(value) }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    /// The five answers, in Coach's own register — a number alone is a survey.
    static func energyLabel(_ value: Int) -> String {
        switch value {
        case 5:  return "5 — Ready for anything"
        case 4:  return "4 — Good"
        case 3:  return "3 — Average"
        case 2:  return "2 — Running low"
        default: return "1 — Empty"
        }
    }

    @MainActor
    private func setEnergy(_ value: Int) async {
        do {
            try await SessionRepository.setEnergy(sessionID: effectiveSession.id,
                                                  value: value)
            await reload()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Action bar (pinned bottom)
    //
    // The gold Check In, the talk dock, then Start (rule 6 gives the talk
    // control its home directly above the primary). The old canvas primary
    // named two acts in one label; a button says exactly what happens (rule
    // 9), so it says Start and the count is the line beneath it.

    private var actionBar: some View {
        VStack(spacing: 0) {
            GSDivider()

            VStack(spacing: 8) {
                // Check in — the gold control, now shared with the warm-up
                // screen (plan task S9) so gold's second job is one object.
                if !isCheckedIn {
                    SessionCheckInControl(
                        isCheckingIn: isCheckingIn,
                        canCheckIn: canCheckIn,
                        opensAtText: checkInOpensAtText,
                        onTap: { Task { await initiateCheckIn() } })
                }

                // START.
                //
                // ALL-READY: the accent has moved up the page to the arrival
                // widget, so the foot's Start is the NEUTRAL secondary — same
                // action, one accent on the page (rule 2).
                //
                // WAITING: the accent primary, disabled, captioned with the
                // count. `Start anyway` is the leader's, and the shipped
                // confirmation is what it raises.
                //
                // The crewmate's "Waiting for organizer to start…" row is
                // GONE: the widget's own caption says the same thing and says
                // what else will happen.
                if allReady {
                    // Fix round 3 R-2: this was live for every participant —
                    // `startSession()` (below) has no organizer guard of its
                    // own, so any crewmate's tap could start the session.
                    // Disabled dims it via `GS3DCardStyle`'s own
                    // `isEnabled`-driven opacity (see the struct's doc
                    // comment); the crewmate's readout already lives on the
                    // widget above (`readyCaption` /
                    // `LobbyCopy.readyCrewmateCaption`), so this button adds
                    // no second copy of it.
                    SecondaryStartButton(title: "Start",
                                         note: LobbyCopy.secondaryStartNote,
                                         onTap: { Task { await startSession() } })
                        .disabled(!isOrganizer)
                } else if isOrganizer {
                    startPrimary(enabled: true) { showStartDialog = true }
                } else {
                    startPrimary(enabled: false) {}
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .background(theme.bg)
        }
        // One-shot wake-up when the check-in window opens — NOT a polling Timer.
        // `canCheckIn` already reads live `Date()` on every body evaluation; this just
        // forces the ONE re-render needed at the moment the window actually opens so the
        // button unlocks itself without the user having to background/foreground the app.
        // Keyed on `checkInOpensAt` so a reschedule (which changes `scheduledFor`)
        // correctly cancels and reschedules this wake-up.
        .task(id: checkInOpensAt) {
            guard let checkInOpensAt, checkInOpensAt > Date() else { return }
            try? await Task.sleep(for: .seconds(checkInOpensAt.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            checkInWindowRefreshTick.toggle()
        }
    }

    /// The foot's accent primary while the crew is still arriving.
    ///
    /// LIVE for the leader — spec §3.1 lets them start anyway, and the shipped
    /// confirmation counts who is missing — and DISABLED for everyone else,
    /// because Start is the leader's tap. The caption beneath counts the
    /// CHECKED IN column and nothing else: a button says exactly what happens
    /// (rule 9), so "2 of 4 checked in" is a line under it and not inside it.
    private func startPrimary(enabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            Button(action: action) {
                HStack {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.bg)
                        Text("Starting…")
                            .font(GSFont.bold(15, relativeTo: .body))
                    } else {
                        // Spec 3.1: "Start anyway" for the leader when a
                        // lifter is late (coordinator fix round 6, item 5).
                        Text(isOrganizer && hasLateArrival ? LobbyCopy.startAnyway : "Start")
                            .font(GSFont.bold(15, relativeTo: .body))
                    }
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16)
                // 10.5pt vertical: content + 21 + the 7pt lip keeps the
                // button's exact prior footprint.
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.gs3D(face: isStarting ? theme.accent600 : theme.accent,
                               cornerRadius: GSMetrics.radiusSm))
            .disabled(isStarting || !enabled)

            Text(LobbyCopy.checkedInCaption(checkedIn: checkedInCount,
                                            total: arrivalRows.count))
                .font(GSFont.body(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(theme.neutral500)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Consensus Start (spec §3.1)
    //
    // "Start is the leader's tap, or fires when everyone is checked in." The
    // SERVER has no consensus rule and this plan does not add one —
    // `start_session` is frozen and organizer-gated (constraint 18) — so
    // consensus is the ORGANIZER'S CLIENT firing the tap it would have fired.
    //
    // One shot, cancellable, never a timer: the `checkInWindowRefreshTick`
    // idiom. Everyone else's caption says exactly what will happen
    // (`or it starts on its own`), which is why that caption is not
    // decoration.

    /// Arm or cancel the consensus Start as the roster changes.
    @MainActor
    private func updateConsensusStart() {
        guard isOrganizer, allReady, !isStarting, !navigateToInProgress else {
            consensusStart?.cancel()
            consensusStart = nil
            return
        }
        guard consensusStart == nil else { return }
        consensusStart = Task { @MainActor in
            // Long enough for the leader to reach the button first, short
            // enough that a crew standing at the rack is not waiting on a
            // countdown nobody can see.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, allReady, !isStarting else { return }
            await startSession()
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func openAndLoad() async {
        #if DEBUG
        // Global constraint 11: a frame is a value, never a fetch. No
        // repository, no realtime, no `CheckInService`, no clock.
        if catalog != nil { return }
        #endif
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
            onPresence: { [self] stages in presenceStages = stages },
            // Fix round 3 R-9: also republish on the realtime refresh path,
            // not just at launch and scene-active. `publishStage` no-ops
            // when the stage has not moved, so a burst of unrelated
            // `session_participants` events (someone else checking in) costs
            // this device nothing beyond the `reload()` it was already doing.
            onChange:   { [self] in Task { await reload(); await publishOwnStage() } }
        )
        await publishOwnStage()
    }

    /// Tell the crew where THIS device is (plan task S3, spec §1).
    ///
    /// AT THE GYM is the one arrival fact no column holds: the geofence is
    /// evaluated on each device, so each device publishes the answer for
    /// itself and `ArrivalLaw.stage` folds it in behind the DB's own
    /// `check_in_state`.
    ///
    /// **GLOBAL CONSTRAINT 10 IS THE WHOLE SHAPE OF THIS FUNCTION.** It reads
    /// `CheckInService.locationIfAlreadyAuthorized()`, which returns nil
    /// rather than raising a prompt when authorization is `.notDetermined`,
    /// `.denied` or `.restricted` — a location sheet raised from the lobby's
    /// own `.task` would hang `testLobby()` the way the HealthKit sheet hung
    /// `build-test`. The authorization check comes FIRST, before the gym read,
    /// so the common unauthorized case costs no round trip either.
    ///
    /// Publishing nothing leaves ON THE WAY standing, which `subscribe` has
    /// already sent and which is the honest default: a device that cannot say
    /// where it is has not said it is at the gym.
    ///
    /// `.checkedIn` is never published — that stage belongs to
    /// `session_participants.check_in_state` and nothing else
    /// (`LobbyRealtimeService.publishStage` refuses it).
    ///
    /// Called at the end of `openAndLoad()`, on scene reactivation, from the
    /// realtime `onChange` callback, and from the pre-live poll's
    /// routine-drift branch (fix round 3 R-9 — it used to run only at launch
    /// and scene-active, which undersold how often the geofence answer
    /// actually gets rechecked). Each call is still a snapshot, not a
    /// monitor: nothing here subscribes to location changes in the
    /// background, and `CheckInService.locationIfAlreadyAuthorized()` still
    /// never prompts. A true live trigger is Phase B's.
    @MainActor
    private func publishOwnStage() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard !isCheckedIn,
              let location = await CheckInService.locationIfAlreadyAuthorized(),
              let gym = try? await CheckInService.primaryGym() else { return }
        await realtime.publishStage(
            CheckInService.distanceCheck(gym: gym, location: location)
                ? .atTheGym : .onTheWay)
    }

    /// The viewer's own block ladder, for the plan card's rung line (plan task
    /// S6). Two calls, the same pair `SessionRunnerView.loadBlock()` makes.
    ///
    /// Best-effort, like every other read this screen does: no active block, or
    /// a fetch that did not land, leaves `rungPage` nil and the card prints the
    /// routine's name — never an error, and never an empty line where a rung
    /// would be. Behind the `catalog != nil` guard every read in this file
    /// carries (global constraint 11).
    @MainActor
    private func loadRung() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard rungPage == nil,
              let goal = await blockGoalRepository.activeGoal(),
              let page = await blockGoalRepository.page(goalID: goal.id)
        else { return }
        rungPage = page
    }

    /// THE CREW'S WEEK (plan task S7, owner decision 21).
    ///
    /// Best-effort, like every other read this screen makes: a failure — a
    /// non-participant's `P0001`, an offline device, a decode that did not
    /// match — is LOGGED and leaves `crewWeekRows` empty, which leaves the
    /// lobby without the strip rather than with an error. A lifter who cannot
    /// see a chart has not done anything wrong.
    ///
    /// Behind the `catalog != nil` guard every read in this file carries
    /// (global constraint 11): a frame draws `LobbyFixtures`' week.
    @MainActor
    private func loadCrewWeek() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        guard crewWeekRows.isEmpty else { return }
        do {
            crewWeekRows = try await CrewWeekRepository.week(
                sessionID: effectiveSession.id,
                weekStart: WeekMath.weekStartISO8601())
        } catch {
            AppLogger.db.error(
                "crew_week failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func reload() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
        do {
            currentSession = try? await SessionRepository.session(id: session.id)

            // Fix round 3 R-1: e16c59b (S8) deleted this along with the
            // `async let` proposal fetch it used to run beside, even though
            // its own commit message promised the one remaining read would
            // survive. Without it `participants` never fills: the arrival
            // track is permanently empty, `allReady` never true, and Start
            // is dead.
            participants = try await SessionRepository.participants(sessionID: session.id)

            let effectiveRoutineID = (currentSession ?? session).routineID
            if let routineID = effectiveRoutineID {
                if let (routine, exercises) = try await RoutineRepository.fetch(id: routineID) {
                    routineInfo = (name: routine.name, exercises: exercises)
                    routineForSession = routine
                }
            }
            // Owner 2026-08-28: "sessions booked by coach don't actually
            // carry a routine when checking in. Everything should be
            // provided by Coach." Pre-WeekBooker bookings (and any booking
            // whose routine fetch failed) arrive routine-less - resolve
            // the enrolled block's day and ATTACH it (ProgramToday heals
            // the row), so the athlete under Coaching manages nothing.
            if routineForSession == nil {
                let effective = currentSession ?? session
                if effective.groupID == nil,
                   let resolved = await ProgramToday.resolveRoutine(
                       session: effective, ownerID: effective.organizerID) {
                    routineInfo = (name: resolved.routine.name,
                                   exercises: resolved.exercises)
                    routineForSession = resolved.routine
                }
            }

            if allExercises.isEmpty {
                allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
            }

            if groupName == nil, let groupID = (currentSession ?? session).groupID {
                let groups = (try? await GroupRepository.fetchMany(ids: [groupID])) ?? []
                groupName = groups.first?.name
            }

            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }

        // Auto-join voice once eligibility is known (Task 4) — no-ops once
        // already connecting/connected (VoiceRoomService.join()'s own
        // idempotent guard), so it's safe to call from every reload(),
        // including the presence/realtime-triggered ones, not just the
        // first.
        await joinVoiceIfEligible()

        // The style default (plan task S2). Here rather than in `openAndLoad`
        // because this is where `currentSession`, `routineInfo` and
        // `allExercises` all land — the leader may not have picked a routine
        // when the lobby first opened, and there is nothing to derive from
        // until they have. Its own one-shot flag makes the repeat calls free.
        await applyStyleDefaultIfNeeded()

        // THE VENUE'S RACK COUNTS (plan task S6, decision 1). Here for the
        // same reason as the line above: `currentSession` — and therefore
        // `venueID`, which the check-in's `claim_session_venue` may only just
        // have written — lands in this function. Its own `rackCounts.isEmpty`
        // guard makes the repeat calls free.
        await loadRackCounts()
    }

    // MARK: - Check-In

    @MainActor
    private func initiateCheckIn() async {
        // Defense in depth: the button is already disabled while `!canCheckIn`, but a
        // stale render (or a future call site) must not be able to fire a check-in
        // before the 20-minute window opens. The server enforces this independently too
        // — see supabase/migrations/20260715000003_checkin_window.sql.
        guard canCheckIn else { return }
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
            // Task 7 item 1 (pre-GA ledger, .superpowers/sdd/task-7-brief.md
            // item 1; ledger origin: .superpowers/sdd/progress.md's "PRE-GA
            // LEDGER: (1) group-attempt start hook at LobbyView Start" under
            // Phase L's merge entry) — closes Discover's "Attempt with
            // Friends" entry-less flow: that CTA (`DiscoverWorkoutDetailView.
            // attemptCTAs`) opens `ScheduleSessionView(preloadedRoutine:)`,
            // which seeds `selectedRoutineID` from the Discover routine and
            // splices it into the picker (ScheduleSessionView.swift:14-20,
            // 597-603) — but `SessionRepository.schedule` never calls
            // `start_attempt` (20260723000002_attempt_plumbing.sql:74-114),
            // unlike the SOLO path (`WorkoutSessionView.startIfNeeded()`,
            // WorkoutSessionView.swift:633-661), so a completed group
            // "attempt" never reaches `workout_attempts` and therefore never
            // appears on the leaderboard.
            //
            // Honest v1 scope (organizer-only, no invented consent flow):
            // the RPC's own contract (start_attempt(p_routine_id, p_session_
            // id, p_opt_in)) requires an explicit per-user opt-in choice, and
            // there is genuinely no UI today that collects that choice from
            // GROUP participants — no opt-in prompt at join/lobby time, and
            // (verified by reading it) ScheduleSessionView's Discover-
            // preloaded path carries no opt-in flag either
            // (ScheduleSessionView.swift:16-20; `SessionRepository.schedule`
            // takes no opt-in param). Inventing a multi-participant consent
            // flow here would be new product surface, not a debt fix — out
            // of this item's scope (deferred; a real candidate for Phase D's
            // designed-surface backlog, alongside "discover-detail" in
            // docs/design/accepted-deviations.json). So this wires ONLY the
            // organizer's own attempt, since they're the one who actually
            // clicked "Attempt with Friends" from Discover — the same
            // "explicit intent" standard Solo's confirmationDialog captures,
            // just without a second confirmation prompt (see optIn default
            // below).
            //
            // Gate — fix wave 1 (reviewer Finding 1, 2026-07-19): the original
            // gate used ownership mismatch (`routine.ownerID != selfID`) as a
            // proxy for "reached via Discover," reasoning that ordinary
            // scheduling only ever offers the organizer their OWN routines.
            // That proxy was wrong: Discover shows curators their OWN public
            // routines too, and "Attempt with Friends" works on them from
            // there — so a curator group-attempting their own public routine
            // silently hit the `routine.ownerID != selfID` branch as false
            // and skipped this hook entirely. That is exactly the entry-less
            // bug this item exists to fix, just for a narrower set of
            // organizers (curators of their own public work, not everyone).
            //
            // Fix: gate on the honest, directly-available condition instead —
            // this session's routine (`routineForSession`, the loaded routine
            // model captured in `reload()`, already matched to
            // `effectiveSession.routineID` above) has `visibility == "public"`.
            // No ownership check. This necessarily over-matches relative to
            // "reached via Discover" — it now also fires for a curator
            // re-running their own already-published routine through
            // ordinary scheduling, not just the Discover preload splice. With
            // the optIn fix below (hardcoded `false`, not `true`), that
            // over-match is harmless: an attempt ROW on any public-routine
            // group session is exactly what the leaderboard system wants —
            // Attempt flows are already treated as explicitly separate from
            // ordinary session creation by the RPC's own design rationale
            // (`20260723000002_attempt_plumbing.sql:34-51`, Finding 2 in that
            // migration — the citation here previously pointed at
            // `20260723000003:11-24`, mislabeled "Finding 2"; that's actually
            // Finding 1 in the FIXES migration, about a different check
            // entirely — routine/session binding — corrected) — and public
            // visibility into the leaderboard stays off regardless, until a
            // real per-attempt opt-in surface exists.
            //
            // optIn — fix wave 1 (reviewer Finding 2, 2026-07-19): hardcoded
            // `true` was wrong. `start_attempt`'s `COALESCE(p_opt_in, false)`
            // (`20260723000002_attempt_plumbing.sql:93`, unchanged by the
            // `20260723000003` fix-forward) only controls the stored
            // `is_opt_in_leaderboard` boolean — the `workout_attempts` ROW
            // itself, and its `leaderboard_entries` row (computed
            // unconditionally by the completion recompute trigger regardless
            // of opt-in; opt-in only gates PUBLIC READ visibility, via the
            // `USING (is_opt_in_leaderboard = true OR user_id = auth.uid())` /
            // `EXISTS (... wa.is_opt_in_leaderboard = true)` SELECT RLS
            // policies, `20260723000001_public_workout_repository.sql:
            // 130-143`), get created either way. Forcing `true` bought
            // nothing toward closing the entry-less bug — the row is written
            // regardless of the flag — and cost real consent: no group-flow
            // UI (this hook included) discloses to the organizer that
            // starting the session will make this run visible on a public
            // leaderboard, contradicting the spec's per-attempt opt-in
            // framing (Flow 4's "Show me on the leaderboard?" toggle) and
            // re-creating the exact unconsented-visibility shape item 2 of
            // this same task just un-leaked for the seed fixture.
            //
            // Fix: pass `optIn: false`. Visibility deferred until a real
            // group-flow consent toggle exists (Phase D designed-surface
            // candidate, same status as "discover-detail" in
            // docs/design/accepted-deviations.json) — the organizer (and any
            // other participants) can't yet express the choice anywhere in
            // this flow, so the conservative RPC default is the honest value.
            // The attempt row and its leaderboard_entries row still record
            // (per the RPC contract above); only the PUBLIC READ visibility
            // flag stays off.
            if isOrganizer,
               let routineID = effectiveSession.routineID,
               let routine = routineForSession, routine.id == routineID,
               routine.visibility == "public" {
                do {
                    _ = try await PublicWorkoutRepository.startAttempt(
                        routineID: routineID, sessionID: effectiveSession.id, optIn: false)
                } catch {
                    // Mirrors WorkoutSessionView.startIfNeeded()'s solo idiom
                    // (minus solo's failure toast — best-effort here): a
                    // failed leaderboard opt-in must never block the session
                    // itself from starting.
                    AppLogger.db.error(
                        "group startAttempt failed: \(error.localizedDescription, privacy: .public)")
                }
            }
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

    // MARK: - Manage actions

    @MainActor
    private func applyReschedule() async {
        showChangeTimeSheet = false
        do {
            try await SessionRepository.reschedule(sessionID: session.id, to: changeTimeDate)
            await reload()
            // EventKit sync (Phase H Task 2): organizer-side, gated on the
            // You-tab toggle. Runs AFTER `reload()` so it reads the
            // server-confirmed `scheduledFor` (via `effectiveSession`) and
            // this screen's already-loaded `routineInfo`, rather than
            // reconstructing a session snapshot by hand
            // (`EventKitBridge.syncEvent` updates the mapped event in place
            // when one already exists for this session id — see its doc
            // comment).
            if CalendarSyncPrefsStore.isEnabled() {
                await EventKitBridge.syncEvent(
                    session: effectiveSession,
                    routineName: routineInfo?.name,
                    exerciseCount: routineInfo?.exercises.count
                )
            }
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
            // EventKit sync (Phase H Task 2): best-effort — no-ops quietly
            // if this session was never synced (toggle was off, or it had
            // no scheduledFor). Ungated on the toggle: cleanup should
            // always run regardless of the toggle's CURRENT state, in case
            // it was flipped off/on since this session was scheduled.
            await EventKitBridge.removeEvent(sessionID: session.id)
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
            // Snapshot which occurrence ids are upcoming+scheduled BEFORE
            // the server delete (same filter `loadUpcomingCount()` uses) —
            // `SeriesRepository.cancelSeriesForward` bulk-deletes by
            // series_id server-side and doesn't hand back which session
            // rows it removed, so EventKit sync (below) needs its own
            // pre-delete snapshot to know which mapped events to remove.
            let now = Date()
            let upcomingIDs = ((try? await SeriesRepository.occurrences(seriesID: sid)) ?? [])
                .filter { $0.state == "scheduled" && ($0.scheduledFor ?? .distantPast) > now }
                .map(\.id)

            try await SeriesRepository.cancelSeriesForward(seriesID: sid)

            dismiss()

            // EventKit sync (Phase H Task 2; moved AFTER dismiss in Phase O
            // Task 2): best-effort remove every mapped event for the
            // occurrences just deleted. Ungated on the toggle — same
            // "cleanup always runs" reasoning as `cancelOccurrence()`
            // above. The server delete (already awaited above) is the
            // operation that matters to the caller; this per-occurrence
            // removal loop no longer gates the sheet close, running
            // fire-and-forget in a detached `Task` instead
            // (`EventKitBridge.removeEvent` never throws). If the app is
            // killed mid-loop, the app-foreground `EventKitBridge.
            // reconcile()` sweep IS the safety net here — the deleted
            // sessions are already gone server-side, so reconcile's next
            // pass will find their ids missing from the batch fetch and
            // remove the leftover events itself.
            Task {
                for sessionID in upcomingIDs {
                    await EventKitBridge.removeEvent(sessionID: sessionID)
                }
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Lobby routine picker (user report 2026-07-29)
//
// "You can't select one of the routines you have built." This is that
// path: the caller's own routines, one tap to set the session's routine,
// plus an explicit Freestyle option so a session can be de-assigned again.
// Deliberately a flat list rather than HomeView's card picker — the lobby
// sheet is a quick decision mid-conversation, not a browse.
private struct LobbyRoutinePickerSheet: View {
    let currentRoutineID: UUID?
    let onPick: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var routines: [Routine] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "Freestyle",
                        subtitle: "No routine — log whatever the crew lifts",
                        selected: currentRoutineID == nil) {
                        onPick(nil)
                        dismiss()
                    }
                }

                Section {
                    if loading {
                        HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                            .listRowBackground(theme.bg)
                    } else if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .listRowBackground(theme.bg)
                    } else if routines.isEmpty {
                        Text("You haven't built any routines yet. Library ▸ Routines ▸ New.")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral500)
                            .listRowBackground(theme.bg)
                    } else {
                        ForEach(routines) { routine in
                            row(title: routine.name,
                                subtitle: nil,
                                selected: routine.id == currentRoutineID) {
                                onPick(routine.id)
                                dismiss()
                            }
                        }
                    }
                } header: {
                    GSSectionHeader("Your routines")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Choose routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(theme.accent)
                }
            }
            .task { await load() }
        }
    }

    private func row(title: String, subtitle: String?, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.surface)
        .listRowSeparatorTint(theme.divider)
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { loading = false; return }
        loading = true
        defer { loading = false }
        do {
            routines = try await RoutineRepository.fetchAll(ownerID: userID)
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
