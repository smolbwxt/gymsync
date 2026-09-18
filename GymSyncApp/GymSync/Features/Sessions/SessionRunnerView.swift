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
    /// The session's routine rows, and the names `loadPlan()` resolved for
    /// them. The WORDED rows are derived (`planRows` below) rather than stored,
    /// so Accept's set reduction re-renders the card the moment it is tapped
    /// (plan decision 5) without a second pass over the routine.
    @State private var planExercises: [RoutineExercise] = []
    @State private var planNames: [UUID: String] = [:]
    /// `Exercise.primaryMuscle` per plan row — the readiness signal's one
    /// question of the catalog `loadPlan()` already fetched.
    @State private var planMuscles: [UUID: String] = [:]
    @State private var routineName = ""
    /// This runner's own copy of the catalog `loadPlan()` resolves names
    /// against — a per-instance cache (review push-5 N3), not the
    /// process-wide `ExerciseRepository.fetchAll()` static R-18 added and
    /// this fix round removed: that static was an unsynchronised global
    /// written from `nonisolated async` contexts with other concurrent
    /// first callers, and never invalidated. `loadPlan()`'s own
    /// `planExercises.isEmpty` guard already keeps this view from fetching twice
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
    // COACH'S READINESS SIGNAL (plan task S8, decision 4). Three reads that
    // already exist, each best-effort and each independently optional: a term
    // that did not land is nil, never an error, and a signal with every term
    // nil produces no suggestion. NO HEALTHKIT AND NO LOCATION (constraint 10)
    // — there is no sleep source in this app and this task does not invent one.
    @State private var lastSessionMeanRPE: Double?
    @State private var daysSinceLastSession: Int?
    @State private var openProbeMuscles: Set<String> = []
    /// Decline clears the suggestion for the session and records nothing.
    @State private var suggestionDeclined = false
    /// Accept's effect (decision 5): in memory, passed down to the live body
    /// so one array of rows carries it — and, since 2026-09-18's decision 3,
    /// WRITTEN to my own participant row and re-seeded from it, so a relaunch
    /// mid-session comes back to the dose the athlete agreed to.
    @State private var todaysScale: TodaysScale?
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
                    // COACH'S READINESS SUGGESTION (plan task S8). Nil is the
                    // normal case: no suggestion, no rule, and the card is the
                    // one B1 shipped.
                    coachSuggestion: coachSuggestion,
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
                    onAcceptSuggestion: { acceptSuggestion() },
                    onDeclineSuggestion: { suggestionDeclined = true },
                    isStarting: isStarting)
            } else {
                SessionInProgressView(session: effective, participants: roster,
                                      todaysScale: todaysScale)
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
        // The block ladder, once. Same reasoning as the plan above: a block
        // enrollment does not change mid-warm-up.
        .task { await loadBlock() }
        // Coach's two remaining reads, once (plan task S8). Their own task, so
        // the plan card is not held behind them and an order between the three
        // is never assumed — `coachSuggestion` is derived and simply answers
        // differently as each lands.
        .task { await loadReadiness() }
        // DECISION 3: the accepted scale outlives a relaunch. The rows the
        // view was handed already carry `todays_scale`, so the seed costs
        // no round trip at all; the poll below re-seeds from fresh rows.
        .task { seedTodaysScale(from: roster) }
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
                    seedTodaysScale(from: rows)
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

    /// The plan, worded — with today's accepted reduction layered on, so the
    /// card re-renders the moment Accept is tapped and both screens print the
    /// number through the one `SessionPlanRow.prescription(for:)`.
    /// THE LAYERING IS `RoutineLayering`'s (plan task S7), not this file's
    /// own copy of it. The warm-up has no swaps to apply — the crew votes in
    /// the live body, not here — so it names only the layer it has, and the
    /// row it hands to `SessionPlanRow` is built by the same function the
    /// live body builds its rows with.
    /// The warm-up applies no swaps — the crew votes in the live body, not
    /// here — so `exerciseID` is untouched by the layering and the name
    /// lookup still reads the row's own id.
    private var planRows: [SessionPlanRow] {
        RoutineLayering.apply(planExercises, todaysScale: todaysScale).map { row in
            SessionPlanRow(exercise: row,
                           name: planNames[row.exerciseID] ?? "Exercise")
        }
    }

    /// The current rung's own standing, for the signal.
    private var rungStatus: RungStatus? {
        guard let page = rungPage else { return nil }
        return page.rows.first(where: { $0.weekNumber == page.weekNumber })?.status
    }

    /// Coach's suggestion, DERIVED — never stored.
    ///
    /// The three reads land in any order on three independent tasks, and a
    /// stored suggestion would have to be recomputed by whichever finished
    /// last. This asks the pure rule every time the body evaluates, which is
    /// also what makes Accept and Decline take effect with no second call:
    /// both set state this reads.
    private var coachSuggestion: WarmUpReadiness.Suggestion? {
        guard !suggestionDeclined, todaysScale == nil else { return nil }
        return WarmUpReadiness.suggestion(signal: WarmUpReadiness.Signal(
            rungStatus: rungStatus,
            reachesMilestone: rungPage?.reachesMilestone ?? true,
            lastSessionMeanRPE: lastSessionMeanRPE,
            daysSinceLastSession: daysSinceLastSession,
            openProbeMuscles: openProbeMuscles,
            planRows: planExercises.map { exercise in
                WarmUpReadiness.PlanRow(
                    exerciseID: exercise.exerciseID,
                    name: planNames[exercise.exerciseID] ?? "Exercise",
                    muscle: planMuscles[exercise.exerciseID],
                    targetSets: exercise.targetSets,
                    targetReps: exercise.targetReps)
            }))
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
        guard warmingUp, planExercises.isEmpty,
              let routineID = effective.routineID,
              let (routine, exercises) = try? await RoutineRepository.fetch(id: routineID)
        else { return }
        if exerciseCatalog == nil {
            exerciseCatalog = (try? await ExerciseRepository.fetchAll()) ?? []
        }
        let catalog = exerciseCatalog ?? []
        routineName = routine.name
        planNames = Dictionary(catalog.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        // The same catalog, asked its other question (plan task S8): which
        // muscle each row trains, so an open recovery probe can be matched
        // against today's plan without a second fetch.
        planMuscles = Dictionary(catalog.map { ($0.id, $0.primaryMuscle) },
                                 uniquingKeysWith: { first, _ in first })
        planExercises = exercises
    }

    /// LAST SESSION'S EFFORT AND OPEN SORENESS (plan task S8, decision 4).
    ///
    /// Two reads that already exist, both best-effort: a failure yields nil for
    /// its own term and never an error on a screen that is about to start a
    /// workout. `recentSetLogs` already filters failed and penalty sets, so the
    /// mean is over the sets that were actually worked.
    ///
    /// THE MEAN IS OF THE MOST RECENT LOGGED DAY, not of the fortnight: "how
    /// hard was last session" is a question about one session, and averaging
    /// fourteen days of them answers a different one.
    @MainActor
    private func loadReadiness() async {
        guard warmingUp, let userID = selfID else { return }
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        if let logs = try? await SessionRepository.recentSetLogs(userID: userID, since: since),
           let last = logs.last?.loggedAt {
            let lastDay = logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: last) }
            let rpes = lastDay.compactMap { log in
                log.rpe.map { NSDecimalNumber(decimal: $0).doubleValue }
            }
            if !rpes.isEmpty {
                lastSessionMeanRPE = rpes.reduce(0, +) / Double(rpes.count)
            }
            daysSinceLastSession = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: Date())).day
        }
        if let probes = try? await RecoveryProbeRepository.open() {
            openProbeMuscles = Set(probes.map { $0.muscle.lowercased() })
        }
    }

    /// Accept (plan decision 5). Applies today's set count for that exercise
    /// IN MEMORY, SYNCHRONOUSLY: the plan card and the live body's THE
    /// SESSION · WHERE WE ARE both re-render from the same array, on this
    /// turn.
    ///
    /// Also persists the accepted scale to the lifter's own participant row
    /// (decision 3), but in a DETACHED `Task`, best-effort — this function
    /// itself still awaits nothing and stays the synchronous
    /// `onChangeRoutine: { showRoutinePicker = true }` shape the lobby's own
    /// card control uses, not the `Task { await … }` shape the two round
    /// trips beside it need. A failed write costs only relaunch survival:
    /// the in-memory value set below is what every screen reads for the
    /// rest of this session regardless.
    private func acceptSuggestion() {
        guard let suggestion = coachSuggestion else { return }
        let scale = TodaysScale(exerciseID: suggestion.exerciseID,
                                setsInstead: suggestion.setsInstead)
        todaysScale = scale
        // DECISION 3 (owner 2026-09-18, "Yes"): and it outlives a relaunch.
        // Detached and best-effort, so this function stays the synchronous
        // one its doc argues for and a failed write changes nothing the
        // athlete can see — the in-memory value above is what every screen
        // reads, and B2's behaviour is what remains if the row never lands.
        Task { try? await SessionRepository.setTodaysScale(sessionID: session.id,
                                                           scale: scale) }
    }

    /// Re-seed the accepted scale from MY OWN participant row (decision 3).
    ///
    /// The runner already fetches the participant rows for the warmth track,
    /// so `todays_scale` rides along and a relaunch costs no extra round
    /// trip. ONLY WHEN NOTHING IS HELD: a poll landing a second after Accept
    /// must never overwrite the tap with a row written milliseconds later,
    /// and `coachSuggestion` already returns nil once `todaysScale != nil`,
    /// so a seeded scale also suppresses the card exactly as an accepted one
    /// does.
    ///
    /// `suggestionDeclined` is DELIBERATELY NOT PERSISTED, and this is where
    /// a reader would look for it: a declined suggestion returning after a
    /// relaunch is a second column and a second question nobody has asked.
    private func seedTodaysScale(from rows: [(participant: SessionParticipant, profile: Profile)]) {
        guard todaysScale == nil, let selfID,
              let mine = rows.first(where: { $0.participant.userID == selfID }),
              let stored = mine.participant.todaysScale else { return }
        todaysScale = stored
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
                seedTodaysScale(from: fresh)
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
