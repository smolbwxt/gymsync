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

    init(session: WorkoutSession) {
        self.session = session
        self.catalog = nil
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
    #endif

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
    @State private var showProposalComposer = false
    /// "Choose routine" picker (user report 2026-07-29 — the lobby had no
    /// path to a routine you'd already built).
    @State private var showRoutinePicker = false
    /// The 1-5 energy picker (plan tasks S5, S7).
    @State private var showEnergyPicker = false
    /// This session's Coach thread, once somebody has tapped the door
    /// (plan task S6). `Identifiable` through `SessionCoachThread`'s own
    /// `threadID`, wrapped so `navigationDestination(item:)` can drive it.
    @State private var openedCoachThread: OpenedCoachThread?
    /// The consensus Start, armed when the last lifter checks in. Held so the
    /// leader tapping first — or the roster changing — can cancel it.
    @State private var consensusStart: Task<Void, Never>?
    @State private var allExercises: [Exercise] = []
    @State private var currentSession: WorkoutSession?
    @State private var groupName: String?
    @State private var primaryGymName: String?

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
        // would be false for every frame and the leader's controls — the Swap
        // chips, the tappable ready widget — would never render. The world
        // states which side of that line it is on.
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

    /// Today's rung, above the plan's rows. The routine's own name until the
    /// block's rung reaches this screen — Phase B's, not this plan's.
    private var planRungLine: String {
        #if DEBUG
        if let catalog { return catalog.rungLine }
        #endif
        return routineInfo?.name ?? ""
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
    private static let voiceEligibleStates: Set<String> = [
        "lobby_open", "editing", "voting", "locked", "in_progress"
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
    // expression. Same failure mode and fix as GroupSessionLiveView's
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
                CoachDoorRow(title: SessionCopy.talkToCoach,
                             detail: SessionCopy.talkToCoachDetail,
                             note: coachDoorNote,
                             onTap: { Task { await openCoachThread() } })
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // THE WHOLE PLAN, one row per exercise (spec §3.1) — not the
                // first exercise and a "Then:" list. `Swap` per row for the
                // leader presents the SHIPPED routine picker: spec §3.4 mode 1
                // is what a swap becomes AFTER Start and is Phase B's; before
                // Start the leader is simply choosing the session's routine,
                // which is what the picker already does.
                if !planRows.isEmpty {
                    SessionPlanCard(kicker: SessionCopy.theSession,
                                    rungLine: planRungLine,
                                    rows: planRows,
                                    showsSwap: isOrganizer,
                                    onSwap: { _ in showRoutinePicker = true })
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
                // matching how GroupSessionLiveView already stacks its own
                // soundboard dock above its bottom action bar.
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
            Task { await reload() }
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
            let preLive: Set<String> = ["scheduled", "lobby_open", "editing", "voting", "locked"]
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
        // Proposal composer sheet
        .sheet(isPresented: $showProposalComposer) {
            proposalComposerSheet
        }
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
        SessionInProgressView(session: effectiveSession, participants: participants)
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

    private func exerciseName(for ex: RoutineExercise) -> String {
        allExercises.first(where: { $0.id == ex.exerciseID })?.name ?? "Exercise"
    }

    // MARK: - The crew's week (owner addition 2026-09-12, on trial)

    /// What `CrewWeekStrip` draws, or nil for no strip and no space.
    ///
    /// **NIL IN PRODUCTION TODAY, and that is a wiring gap rather than a
    /// design choice.** The strip needs two facts per crew member: their
    /// weekly session GOAL and their COMPLETED COUNT this week. The goals are
    /// already in hand — `SessionRepository.participants(sessionID:)` fetches
    /// each member's `Profile`, which carries `weeklySessionGoal`. The counts
    /// are not, and no shipped read supplies them:
    ///
    ///   * `SocialTabView`'s crew bar counts sessions for the WHOLE CREW, not
    ///     per member (`SocialTabView.swift:635-650`);
    ///   * `group_consistency_honor` is per member but over THIRTY DAYS
    ///     (`CrewHonor.swift:73`, migration 20260911000001) — right shape,
    ///     wrong window, and a 30-day count printed under a "this week"
    ///     kicker would be wrong data wearing a right label.
    ///
    /// The ruling was explicit: add no tables, policies or RPCs for this. So
    /// production renders nothing and the catalog frames render the fixture,
    /// which is what the owner asked to see. Wiring it is a Phase B item.
    private var crewWeek: CrewWeek? {
        #if DEBUG
        if let catalog { return catalog.crewWeek }
        #endif
        return nil
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

    /// Why Coach's door is not open, or nil when it is. Nil today: the
    /// paywall is dormant, so `SessionCoachThreadRepository.isReachable` is
    /// true for everyone (`CrewCoachEngine`'s convention).
    private var coachDoorNote: String? {
        openedCoachThread.map { SessionCoachThreadRepository.lockedNote($0.thread) } ?? nil
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
            openedCoachThread = OpenedCoachThread(thread: thread)
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

    /// Check-in gold — HomeView's ready-state palette (`goldTop`/`goldInk`),
    /// the fixed STATUS color that means "check-in, act now" and nothing
    /// else. The lobby's Check In button is the check-in action itself, so
    /// it wears the gold face (3D pass 2026-08); the lip derives from the
    /// face — never a lighter tint.
    private static let checkInGold = Color.gsHex(0xF6C945)
    private static let checkInGoldInk = Color.gsHex(0x261A02)

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
                                    .tint(Self.checkInGoldInk)
                                Text("Checking in…")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            } else if !canCheckIn {
                                Image(systemName: "clock")
                                    .font(.system(size: 15))
                                Text("Check-in opens at \(checkInOpensAtText)")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            } else {
                                Image(systemName: "location.circle.fill")
                                    .font(.system(size: 15))
                                Text("Check In")
                                    .font(GSFont.bold(15, relativeTo: .body))
                            }
                            Spacer()
                        }
                        .foregroundStyle(Self.checkInGoldInk)
                        .padding(.horizontal, 16)
                        // 8.5pt vertical (was 12): content + 17 + the 7pt
                        // lip keeps the button's exact prior footprint.
                        .padding(.vertical, 8.5)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.gs3D(face: Self.checkInGold, cornerRadius: GSMetrics.radiusSm))
                    .disabled(isCheckingIn || !canCheckIn)
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
                    SecondaryStartButton(title: "Start",
                                         note: LobbyCopy.secondaryStartNote,
                                         onTap: { Task { await startSession() } })
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
                        Text("Start")
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
            onChange:   { [self] in Task { await reload() } }
        )
    }

    @MainActor
    private func reload() async {
        #if DEBUG
        if catalog != nil { return }
        #endif
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

            if primaryGymName == nil {
                primaryGymName = (try? await CheckInService.primaryGym())?.name
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

// MARK: - ProposalComposerView

/// Inline sheet for proposing a new exercise to the session's routine.
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
    @State private var pickerSearchText = ""
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
                        pickerSearchText = ""
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

    private var filteredPickerExercises: [Exercise] {
        pickerSearchText.isEmpty ? allExercises
            : allExercises.filter { $0.name.localizedCaseInsensitiveContains(pickerSearchText) }
    }

    private var exercisePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Shared in-content search field shape (ExercisesListView /
                // ExercisePickSheet idiom).
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                    TextField("Search exercises", text: $pickerSearchText)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusSm)
                .padding(16)

                List(filteredPickerExercises, id: \.id) { ex in
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
            }
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
