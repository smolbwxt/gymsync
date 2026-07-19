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
    @State private var groupName: String?
    @State private var primaryGymName: String?

    // MARK: - Manage menu state

    @State private var showChangeTimeSheet = false
    @State private var changeTimeDate: Date = Date()

    @State private var showCancelOccurrenceDialog = false
    @State private var showCancelSeriesDialog = false
    @State private var upcomingOccurrenceCount: Int = 0

    @State private var showSeriesEditor = false

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

    private var checkInStatusSubtitle: String {
        guard isCheckedIn else { return "Tap Check In below" }
        guard let primaryGymName else { return "Geofence confirmed" }
        return "\(primaryGymName) · Geofence confirmed"
    }

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
            VStack(spacing: 0) {
                // ── PUSH-TO-TALK DOCK ────────────────────────────────────
                // Open layout question flagged by Dossier §A.2 (never
                // resolved there): whether the PTT dock replaces, stacks
                // above, or sits below the existing `actionBar`. ASSUMPTION
                // (judgment call, no design ruling to follow): stacks above,
                // matching how GroupSessionLiveView already stacks its own
                // soundboard dock above its bottom action bar.
                if isVoiceEligible {
                    PTTDockRow()
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
            ToolbarItem(placement: .topBarTrailing) {
                chatButton
            }
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
            if !navigateToInProgress {
                Task { await VoiceRoomService.shared.leave() }
            }
        }
        // Proposal composer sheet
        .sheet(isPresented: $showProposalComposer) {
            proposalComposerSheet
        }
        // Session chat sheet (Task 3)
        .sheet(isPresented: $showChatSheet) {
            chatSheet
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
                Text(checkInStatusSubtitle)
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
                if !participants.isEmpty {
                    Text("\(readyCount) of \(participants.count) ready")
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
        // Speaking ring (Task 4, Dossier §A.2 lobby "Who's here · voice on"
        // strip's "talking" state) — accent border + animated bars + label,
        // driven by `speakingParticipantIDs` (LiveKit identity = user UUID
        // string, per T1).
        let identity = item.participant.userID.uuidString.lowercased()
        let voice = VoiceRoomService.shared
        let isSpeaking = voice.speakingParticipantIDs.contains(identity)

        // Phase O Task 5 item 4 ("muted-others roster rows"): VoiceRoomService
        // now exposes a roster (connectedParticipantIDs) plus both mute-state
        // sets, closing the gap this doc comment used to describe (git blame:
        // "it exposes no roster of who else has joined the room at all, so
        // the strip's 'listening'/'muted' sub-states for OTHER participants
        // can't be rendered honestly here"). A participant not in
        // `connectedParticipantIDs` at all still falls through to the
        // unchanged check-in-only row below — that "haven't joined voice"
        // case is still not a "muted" state. "Muted" covers EITHER they
        // muted their own mic (remoteMutedParticipantIDs) OR you've locally
        // silenced them via the voice mixer sheet
        // (locallyMutedParticipantIDs) — live-voice frame 2's roster rows
        // use one shared "muted" caption for both, so this does too.
        let isInVoiceRoom = voice.connectedParticipantIDs.contains(identity)
        let isMuted = isInVoiceRoom && !isSpeaking &&
            (voice.remoteMutedParticipantIDs.contains(identity) || voice.locallyMutedParticipantIDs.contains(identity))

        return HStack(spacing: 10) {
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
                // Avatar glow while talking — the blessed frames' solid 3px
                // accent-30% spread (`box-shadow:0 0 0 3px`, live-voice
                // frame 2's audible-now rows), drawn as an oversized
                // background rect since the avatars are square/zero-radius.
                .background {
                    if isSpeaking {
                        Rectangle()
                            .fill(theme.accent.opacity(0.3))
                            .frame(width: 38, height: 38)
                    }
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

            if isSpeaking {
                HStack(spacing: 4) {
                    GSTalkingBars(color: theme.accent700, barWidth: 2, maxHeight: 10)
                    Text("talking")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .foregroundStyle(theme.accent700)
                }
            } else if isMuted {
                // Live-voice frame 2's dimmed "muted" caption (no bars) —
                // Phase O Task 5 item 4.
                Text("muted")
                    .font(GSFont.body(9, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            // Check-in status tag or burpees
            checkInBadge(for: item.participant)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(isSpeaking ? theme.accent : theme.divider, lineWidth: isSpeaking ? 2 : 1))
        .opacity(isMuted ? 0.7 : 1)
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
                // Canvas: accent tag "Ready"
                GSTag(text: "Ready", style: .accent)
            case "invited":
                // Canvas: outlined "Pending" pill for not-yet-arrived
                GSTag(text: "Pending", style: .outline)
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var routineContent: some View {
        if let info = routineInfo, let first = info.exercises.first {
            VStack(alignment: .leading, spacing: 8) {
                Text(info.name)
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("FIRST UP")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.accent)
                    Text(exerciseName(for: first))
                        .font(GSFont.bold(16, relativeTo: .title3))
                        .foregroundStyle(theme.text)

                    HStack(spacing: 6) {
                        if let equipment = exerciseEquipment(for: first) {
                            GSTag(text: equipment, style: .outline)
                        }
                        if let sets = first.targetSets {
                            GSTag(text: "\(sets) sets each", style: .outline)
                        }
                    }

                    let rest = info.exercises.dropFirst()
                    if !rest.isEmpty {
                        Text("Then: \(rest.map { exerciseName(for: $0) }.joined(separator: " · "))")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
            }
        } else {
            Text("No routine — propose one below.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
        }
    }

    private func exerciseName(for ex: RoutineExercise) -> String {
        allExercises.first(where: { $0.id == ex.exerciseID })?.name ?? "Exercise"
    }

    private func exerciseEquipment(for ex: RoutineExercise) -> String? {
        allExercises.first(where: { $0.id == ex.exerciseID })?.equipment.capitalized
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
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(theme.accent100)
                        .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingIn || !canCheckIn)
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
                        }
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(isStarting ? theme.accent600 : theme.accent)
                        .contentShape(Rectangle())
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
