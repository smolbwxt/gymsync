import SwiftUI

/// While `WarmUpGate.isWarmingUp`, the warm-up screen; then the live view.
/// The whole reason `SessionLiveView` no longer needs a warm-up branch
/// in its page switch (plan task S9) — that switch is three ways again.
///
/// A thin router beside `SessionInProgressView`, which is the precedent: it
/// owns no session logic, only the question of which screen the session is on.
///
/// IT OWNS THE POLL THE WARM-UP PHASE USED TO RIDE ON. `SessionLiveView`
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
    /// This runner's own copy of the catalog `loadPlan()` resolves names
    /// against — a per-instance cache (review push-5 N3), not the
    /// process-wide `ExerciseRepository.fetchAll()` static R-18 added and
    /// this fix round removed: that static was an unsynchronised global
    /// written from `nonisolated async` contexts with other concurrent
    /// first callers, and never invalidated. `loadPlan()`'s own
    /// `planRows.isEmpty` guard already keeps this view from fetching twice
    /// in the ordinary case; this exists so the shared repository carries
    /// none of that risk for a perf nit that is this one view's to own.
    @State private var exerciseCatalog: [Exercise]?
    // The athlete's own block. Review push-5 R-17: HONEST FRAMES applies to
    // production too, not just fixtures — the strip is absent (blockWeeks
    // stays 0) rather than wrong when there is no active block or the fetch
    // fails, matching `loadPlan()`'s own best-effort contract.
    //
    // `BlockLadderStrip` still renders in the SOLO frame only — `crewBody`
    // draws no strip — but the page itself is now read on both, because the
    // RUNG is a personal fact each lifter has their own of (plan task S6).
    @State private var blockWeek = 0
    @State private var blockWeeks = 0
    @State private var blockMilestone = ""
    /// The ladder page `loadBlock()` already fetched, kept so the rung line can
    /// be worded from it. No second round trip.
    @State private var rungPage: LadderPageModel?
    private let blockGoalRepository: any BlockGoalRepository = LiveBlockGoalRepository()
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

    /// Show the warm-up screen instead of `SessionInProgressView` —
    /// `WarmUpGate.showsWarmUp`, the runner's own restatement of
    /// `SessionRouter`'s `.warmUp` vs. `.live` split, since the runner is
    /// both routes' destination and must not contradict the route that sent
    /// it here (review push-5 finding 2; named and tested as of N1 rather
    /// than inlined here a second time).
    private var warmingUp: Bool {
        WarmUpGate.showsWarmUp(state: effective.state,
                               liftingStartedAt: effective.liftingStartedAt)
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
                    warmthRows: isSolo ? [] : warmthRows,
                    isSolo: isSolo,
                    isOrganizer: effective.organizerID == selfID,
                    planRows: planRows,
                    // THE BLOCK'S RUNG, arrived (plan task S6). The viewer's
                    // own, on the solo frame and the crew one alike; the
                    // routine's name is still what prints when there is no
                    // block behind the session.
                    rungHeadline: rungLine.line,
                    rungDetail: rungLine.detail,
                    // Coach's per-lifter warm-up line is Phase B too; the
                    // card renders without a suggestion and no rule appears.
                    coachLine: nil,
                    blockWeek: blockWeek,
                    blockWeeks: blockWeeks,
                    blockMilestone: blockMilestone,
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
        // The block ladder, once, solo only. Same reasoning as the plan
        // above: a block enrollment does not change mid-warm-up.
        .task { await loadBlock() }
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

    /// Today's rung, worded from the page this screen already fetched.
    ///
    /// `SessionRungLine.resolve` is the same resolver the lobby's plan card
    /// uses, so one rung cannot be spelled two ways on two screens.
    private var rungLine: SessionRungLine.Resolved {
        SessionRungLine.resolve(page: rungPage, routineName: routineName)
    }

    /// The athlete's own block ladder. Best-effort: no active block, or a
    /// failed fetch, leaves `blockWeeks == 0` and `rungPage` nil, which is what
    /// makes `WarmUpScreen` show no strip at all and the plan card fall back to
    /// the routine's name — rather than a wrong or an empty one (review push-5
    /// R-17 — HONEST FRAMES for code, not just for the catalog's fixtures).
    ///
    /// THE `isSolo` RESTRICTION IS GONE (plan task S6). It was here because
    /// `BlockLadderStrip` renders in the solo frame only, and it still does —
    /// `crewBody` draws no strip. But the RUNG is a personal fact, one each
    /// lifter has their own of, and the crew warm-up's plan card prints it too,
    /// so the crew frame now pays the same one round trip the solo frame does.
    /// Nothing about the crew frame's composition changed; a line that said the
    /// routine's name says the week's rung.
    @MainActor
    private func loadBlock() async {
        guard warmingUp, rungPage == nil,
              let goal = await blockGoalRepository.activeGoal(),
              let page = await blockGoalRepository.page(goalID: goal.id)
        else { return }
        rungPage = page
        blockWeek = page.weekNumber
        blockWeeks = page.weekCount
        blockMilestone = page.headline
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
        if exerciseCatalog == nil {
            exerciseCatalog = (try? await ExerciseRepository.fetchAll()) ?? []
        }
        let catalog = exerciseCatalog ?? []
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
    /// THE RPCs ARE UNCHANGED (constraint 18). In the SOLO frame this is
    /// `markWarmupReady` — a party of one satisfies unanimity in one call,
    /// because `mark_warmup_ready`'s `EXISTS … AND NOT warmup_ready` finds
    /// nobody — preceded by `start(sessionID:)` when the session is not yet
    /// `in_progress`.
    ///
    /// In the CREW frame it depends on who taps: the ORGANIZER's tap calls
    /// `startLifting` (`start_lifting`, the AFK escape hatch,
    /// `SessionRepository.swift:798-813`) and ends the warm-up for
    /// everyone regardless of unanimity — restoring the capability
    /// `SessionLiveView.forceStartLifting()` used to give the leader,
    /// which S9 removed with the rest of that view's warm-up branch and
    /// nothing replaced (review push-4/5 finding 3, R-15). A CREWMATE's tap
    /// still calls `markWarmupReady`: the readiness row and
    /// `WarmUpGate.leaderNote` are what make that tap cost something,
    /// unchanged. Not a new `forceStartLifting()` — the same primary, the
    /// same private method, branched on role.
    @MainActor
    private func startLifting() async {
        isStarting = true
        defer { isStarting = false }
        errorText = nil
        do {
            if effective.state != "in_progress" {
                try await SessionRepository.start(sessionID: session.id)
            }
            if !isSolo, effective.organizerID == selfID {
                _ = try await SessionRepository.startLifting(sessionID: session.id)
            } else {
                _ = try await SessionRepository.markWarmupReady(sessionID: session.id)
            }
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
