import SwiftUI

/// While `WarmUpGate.isWarmingUp`, the warm-up screen; then the live view.
/// The whole reason `GroupSessionLiveView` no longer needs a warm-up branch
/// in its page switch (plan task S9) — that switch is three ways again.
///
/// A thin router beside `SessionInProgressView`, which is the precedent: it
/// owns no session logic, only the question of which screen the session is on.
///
/// IT OWNS THE POLL THE WARM-UP PHASE USED TO RIDE ON. `GroupSessionLiveView`
/// polled the session row every ten seconds and carried the warm-up columns on
/// the same cadence; that poll leaves with the phase, so this one takes its
/// place — five seconds while warming up, the lobby's own pre-live idiom
/// (`LobbyView.swift`'s `.task(id:)` loop), never a `Timer`. It is what makes
/// another client's `start_lifting` reach this one. Realtime stays the fast
/// path once the live view mounts and claims its own channels.
struct SessionRunnerView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    /// The freshest session row this screen has seen. The prop is the row the
    /// lobby held when it presented us; `lifting_started_at` flips on another
    /// device.
    @State private var liveSession: WorkoutSession?
    @State private var liveParticipants: [(participant: SessionParticipant, profile: Profile)] = []
    @State private var isStarting = false
    @State private var errorText: String?
    @State private var now = Date()
    /// The session's routine, already worded. Built the way the lobby builds
    /// it (`LobbyView.planRows`) — through `SessionPlanRow(exercise:name:)`,
    /// so the plan card reads the same on both screens.
    @State private var planRows: [SessionPlanRow] = []
    @State private var routineName = ""
    // Check-in — solo only (spec §2's path is check-in → warm-up; a
    // scheduled solo session never passes through a lobby to find the
    // button there). Same shape as `LobbyView`'s: `isCheckingIn` and
    // `showTravelDialog` mirror its state, `initiateCheckIn()`/`checkIn(
    // method:)` below mirror its functions. Review push-5 finding 2.
    @State private var isCheckingIn = false
    @State private var showTravelDialog = false

    private var effective: WorkoutSession { liveSession ?? session }
    private var roster: [(participant: SessionParticipant, profile: Profile)] {
        liveParticipants.isEmpty ? participants : liveParticipants
    }

    /// Show the warm-up screen instead of `SessionInProgressView` — the
    /// runner's own restatement of `SessionRouter`'s `.warmUp` vs. `.live`
    /// split, since the runner is both routes' destination and must not
    /// contradict the route that sent it here (review push-5 finding 2).
    /// `WarmUpGate.isWarmingUp` alone only covers a session already
    /// `in_progress`; `SessionEntryView` also sends a SCHEDULED solo session
    /// here (spec §2, owner decision 3 — solo has no lobby), which needs the
    /// warm-up screen too. A terminal session never does: it self-presents
    /// its recap through `SessionInProgressView`.
    private var warmingUp: Bool {
        effective.state != "completed" && effective.state != "abandoned"
            && effective.liftingStartedAt == nil
    }

    private var selfID: UUID? { appState.currentProfile?.id }

    /// A party of one — `SessionShape.isSolo`'s own question, asked of the
    /// roster this screen already holds. A solo warm-up shows no readiness
    /// row and no talk dock, because there is nobody to be ready with.
    private var isSolo: Bool {
        SessionShape.isSolo(participantCount: roster.count,
                            roomCode: effective.roomCode)
    }

    // MARK: - Check-in (solo only)
    //
    // Wired to the same computation `LobbyView` uses for a crew's check-in
    // window and geofence, so a solo lifter's check-in behaves identically
    // to a crew member's — just reached from this screen instead of the
    // lobby (review push-5 finding 2's fix).

    private var myCheckInState: String? {
        roster.first(where: { $0.participant.userID == selfID })?.participant.checkInState
    }

    private var isCheckedIn: Bool { myCheckInState == "ready" }

    /// Same 20-minute window as `LobbyView.checkInOpensAt`
    /// (`supabase/migrations/20260715000003_checkin_window.sql` enforces it
    /// server-side too). `nil` when the session has no `scheduledFor`.
    private var checkInOpensAt: Date? {
        effective.scheduledFor?.addingTimeInterval(-20 * 60)
    }

    private var canCheckIn: Bool {
        guard let checkInOpensAt else { return true }
        return Date() >= checkInOpensAt
    }

    private var checkInOpensAtText: String {
        guard let checkInOpensAt else { return "" }
        return checkInOpensAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Group {
            if warmingUp {
                WarmUpScreen(
                    session: effective,
                    warmthRows: isSolo ? [] : warmthRows,
                    isSolo: isSolo,
                    isOrganizer: effective.organizerID == selfID,
                    planRows: planRows,
                    // The routine's own name until the BLOCK's rung reaches
                    // this screen — Phase B's, exactly as the lobby's
                    // `planRungLine` says of itself.
                    rungHeadline: routineName,
                    rungDetail: "",
                    // Coach's per-lifter warm-up line is Phase B too; the
                    // card renders without a suggestion and no rule appears.
                    coachLine: nil,
                    blockWeek: 0,
                    blockWeeks: 0,
                    blockMilestone: "",
                    elapsed: WarmUpGate.elapsed(since: effective.startedAt, now: now),
                    // Solo only, and only before check-in — spec §2's path.
                    showsCheckIn: isSolo && !isCheckedIn,
                    isCheckingIn: isCheckingIn,
                    canCheckIn: canCheckIn,
                    checkInOpensAtText: checkInOpensAtText,
                    onCheckIn: { Task { await initiateCheckIn() } },
                    onStartLifting: { Task { await startLifting() } },
                    isStarting: isStarting)
            } else {
                SessionInProgressView(session: effective, participants: roster)
            }
        }
        // The one place a failed `START LIFTING` can say so. An overlay
        // rather than a row in the screen's stack: the warm-up body is a
        // fixed composition and an error must not reflow the plan.
        .overlay(alignment: .bottom) {
            if let errorText, warmingUp {
                Text(errorText)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity)
                    .background(theme.bg.opacity(0.92))
            }
        }
        // The plan, once. It cannot change during a warm-up — the leader
        // picks the routine before Start — so this is a `.task`, not a poll.
        .task { await loadPlan() }
        // THE POLL, five seconds, only while warming up. `.task(id:)` cancels
        // itself the moment the gate flips, so the live view never runs two
        // pollers.
        .task(id: warmingUp) {
            guard warmingUp else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                now = Date()
                if let fresh = try? await SessionRepository.session(id: session.id) {
                    liveSession = fresh
                }
                if let rows = try? await SessionRepository.participants(sessionID: session.id) {
                    liveParticipants = rows
                }
            }
        }
        // Same dialog, same copy, same fallback as `LobbyView`'s: the
        // geofence couldn't confirm the gym, so the lifter confirms instead.
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
    }

    /// The routine, resolved to worded rows. Best-effort, like every other
    /// read on the pre-live path: a failed fetch is a warm-up screen with no
    /// plan card, never an error dialog over a session that is running.
    @MainActor
    private func loadPlan() async {
        guard warmingUp, planRows.isEmpty,
              let routineID = effective.routineID,
              let (routine, exercises) = try? await RoutineRepository.fetch(id: routineID)
        else { return }
        let catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        let byID = Dictionary(catalog.map { ($0.id, $0.name) },
                              uniquingKeysWith: { first, _ in first })
        routineName = routine.name
        planRows = exercises.map { exercise in
            SessionPlanRow(exercise: exercise,
                           name: byID[exercise.exerciseID] ?? "Exercise")
        }
    }

    /// Same flow as `LobbyView.initiateCheckIn()`: try the geofence, fall
    /// back to the travel dialog when it can't confirm the gym. The solo
    /// lifter's only check-in surface (spec §2) — a scheduled solo session
    /// never reaches `LobbyView` at all (plan task S10).
    @MainActor
    private func initiateCheckIn() async {
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
            if let fresh = try? await SessionRepository.participants(sessionID: session.id) {
                liveParticipants = fresh
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var warmthRows: [SessionWarmthRow] {
        roster.map { item in
            SessionWarmthRow(id: item.participant.userID,
                             name: item.profile.username,
                             avatarURL: item.profile.avatarURL,
                             isYou: item.participant.userID == selfID,
                             isWarm: item.participant.warmupReady)
        }
    }

    /// `START LIFTING`.
    ///
    /// THE RPCs ARE UNCHANGED (constraint 18). In the crew frame this is
    /// `markWarmupReady`; when it returns `true` the vote completed unanimity
    /// (or lifting had already begun) and the screen hands off. In the SOLO
    /// frame it is the same call — a party of one satisfies unanimity in one
    /// call, because `mark_warmup_ready`'s `EXISTS … AND NOT warmup_ready`
    /// finds nobody — preceded by `start(sessionID:)` when the session is not
    /// yet `in_progress`.
    @MainActor
    private func startLifting() async {
        isStarting = true
        defer { isStarting = false }
        errorText = nil
        do {
            if effective.state != "in_progress" {
                try await SessionRepository.start(sessionID: session.id)
            }
            _ = try await SessionRepository.markWarmupReady(sessionID: session.id)
            if let fresh = try? await SessionRepository.session(id: session.id) {
                liveSession = fresh
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
