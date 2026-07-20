import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var groups: [GymGroup] = []
    @State private var showScheduleSheet = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joinedSession: WorkoutSession?
    @State private var navigateToJoined = false

    // MARK: - Canvas content state (Task 5)
    @State private var historySessions: [WorkoutSession] = []
    @State private var ownedRoutines: [Routine] = []
    @State private var allExercises: [Exercise] = []
    @State private var recentPRs: [PersonalRecord] = []
    @State private var prsThisMonth: Int = 0
    @State private var profile: Profile?
    @State private var todaysRoutine: Routine?
    @State private var todaysRoutineExercises: [RoutineExercise] = []
    @State private var showRoutinePicker = false
    @State private var routinePickerPreselected: Routine?

    // MARK: - Stat-tile row state (Phase U Task 5 / frame 41)
    //
    // `statsLoading` starts `true` and flips to `false` once `refresh()`'s
    // first pass completes (success or failure) — it only gates the
    // LOADING·SKELETON state for the initial cold-start fetch, matching the
    // frame's "while the stats fetch is in flight" wording; a later
    // pull-to-refresh already has SwiftUI's native refresh spinner and
    // doesn't re-show the skeleton (see `statTilesRowState`'s doc comment).
    // `connectivity` follows the same `@State = .shared` idiom SocialTabView
    // already uses for `ConnectivityMonitor.shared` (SocialTabView.swift:16).
    @State private var statsLoading = true
    @State private var connectivity = ConnectivityMonitor.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    replayFailureNotice
                    startSoloWorkoutButton
                    if let pr = recentPRs.first {
                        prCardView(pr)
                    }
                    if let routine = todaysRoutine {
                        todaysRoutineCardView(routine)
                    }
                    statTileRow
                    GSDivider()
                    scheduleButton
                    GSDivider()
                    upcomingSection
                    GSDivider()
                    joinWithCodeSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await refresh()
                await consumePendingRouteIfNeeded()
            }
            .refreshable { await refresh() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await refresh() }
            }
            .onChange(of: appState.pendingRoute) {
                Task { await consumePendingRouteIfNeeded() }
            }
            .sheet(isPresented: $showScheduleSheet) {
                ScheduleSessionView { newSession in
                    upcomingSessions.insert(newSession, at: 0)
                }
            }
            .sheet(isPresented: $showRoutinePicker) {
                RoutinePickerSheet(routines: ownedRoutines, initialRoutine: routinePickerPreselected)
            }
            .navigationDestination(isPresented: $navigateToJoined) {
                if let session = joinedSession {
                    LobbyView(session: session)
                }
            }
        }
    }

    // MARK: - Push deep-link routing (Phase 3d Task 5)

    /// Consumes `.lobby`/`.session` — both resolve to `LobbyView(session:)`,
    /// the app's single entry point for a session regardless of its current
    /// state (see `upcomingSection`'s existing NavigationLink, which routes
    /// every session there whether scheduled or in_progress). Clears
    /// `pendingRoute` immediately so a later `.onChange` firing (or this
    /// `.task` re-running) doesn't re-navigate.
    private func consumePendingRouteIfNeeded() async {
        let sessionID: UUID?
        switch appState.pendingRoute {
        case .lobby(let id), .session(let id): sessionID = id
        default: sessionID = nil
        }
        guard let sessionID else { return }
        appState.pendingRoute = nil
        // Task 6 item 7 (reliability/debt roll-up — .superpowers/sdd/
        // progress.md:249, "dedupe re-push when deep-linked session already
        // open"): a second push for a session the user has ALREADY
        // deep-linked into (e.g. `your_turn` and `session_reminder_15min`
        // landing close together, or a duplicate enqueue) would otherwise
        // re-fetch and re-set `navigateToJoined = true` — harmless if the
        // destination is already popped, but if the user is CURRENTLY
        // looking at that exact LobbyView, this re-trigger has no visible
        // effect either way EXCEPT it discards `joinedSession` and
        // re-fetches from network for no reason. Skip the redundant
        // round trip and no-op re-navigation when it's the same session
        // that's already the active deep-link target.
        if navigateToJoined, joinedSession?.id == sessionID { return }
        guard let session = try? await SessionRepository.session(id: sessionID) else { return }
        joinedSession = session
        navigateToJoined = true
    }

    // MARK: - Replay-failure notice (debt-zero sprint item 2)
    //
    // `OfflineSetLogQueue.lastPermanentFailure` (Services/
    // OfflineSetLogQueue.swift) is set whenever a background `replay()`
    // pass permanently drops a queued set (RLS denial, validation failure,
    // or an `.unauthorized` escalation past `maxUnauthorizedAttempts`) with
    // NO existing observable surface — that property's own doc comment:
    // "today it's paired with an AppLogger.workout line as the actual,
    // honest surfacing mechanism." HomeView is the render site: the one
    // always-visible surface regardless of which screen the set was
    // originally logged from (a background replay pass can drop an item
    // long after `WorkoutSessionView`/`GroupSessionLiveView` — the screens
    // that queued it — have been backgrounded or dismissed). Reuses
    // `GSInlineNoticeBanner` (DesignSystem/GSComponents.swift) — the same
    // component `GroupSessionLiveView`'s offline-queue notice already
    // uses — via this task's additive `icon`/`onDismiss` parameters,
    // rather than inventing a new banner type. Read directly off the
    // `@Observable` singleton like every other direct-read precedent in
    // this codebase (`ConnectivityMonitor.shared`, `ThemeStore.shared`) —
    // no environment plumbing, no local `@State` mirror needed.
    // Catalog/deviation record: extends the "offline-syncing-indicator"
    // entry in docs/design/accepted-deviations.json (same "live SwiftData
    // queue, not deterministically fixturable" judgment call already made
    // there for the sibling "Saved on this phone" notice) rather than
    // opening a new entry.
    @ViewBuilder
    private var replayFailureNotice: some View {
        if OfflineSetLogQueue.shared.lastPermanentFailure != nil {
            GSInlineNoticeBanner(
                title: "A set couldn't sync and was removed —",
                message: "check your session history.",
                icon: "exclamationmark.circle",
                onDismiss: { OfflineSetLogQueue.shared.clearLastPermanentFailure() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(GSFont.heading(28, relativeTo: .largeTitle))
                .foregroundStyle(theme.text)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// "Good {morning/afternoon/evening}, {first name}" — first name comes from
    /// `appState.currentProfile.displayName`'s first word, falling back to the
    /// username when no display name is set.
    private var greetingText: String {
        "Good \(timeOfDayGreeting), \(firstName)"
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    private var firstName: String {
        guard let profile = appState.currentProfile else { return "" }
        let name = profile.displayName?.trimmingCharacters(in: .whitespaces)
        if let name, !name.isEmpty {
            return String(name.split(separator: " ").first ?? Substring(name))
        }
        return profile.username
    }

    // MARK: - Start Solo Workout CTA (Task 5 — canvas content)

    private var startSoloWorkoutButton: some View {
        Button {
            routinePickerPreselected = nil
            showRoutinePicker = true
        } label: {
            Text("Start Solo Workout")
        }
        .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - PR Card (Task 5 — canvas content)

    @ViewBuilder
    private func prCardView(_ pr: PersonalRecord) -> some View {
        let exerciseName = allExercises.first(where: { $0.id == pr.exerciseID })?.name ?? "Exercise"
        GSCard(bordered: false, backgroundColor: theme.accent100) {
            VStack(alignment: .leading, spacing: 4) {
                GSSectionHeader("🔥 New personal record")
                Text("\(exerciseName) — \(trimmedDecimal(pr.weight)) lbs × \(pr.reps)")
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text("Beat previous best by \(trimmedDecimal(pr.weight - pr.previousBest)) lbs")
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Today's Routine Card (Task 5 — canvas content)

    @ViewBuilder
    private func todaysRoutineCardView(_ routine: Routine) -> some View {
        Button {
            routinePickerPreselected = routine
            showRoutinePicker = true
        } label: {
            GSCard(bordered: false) {
                VStack(alignment: .leading, spacing: 4) {
                    GSSectionHeader("Today's routine")
                    Text(routine.name)
                        .font(GSFont.heading(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    if !todaysRoutineBody.isEmpty {
                        Text(todaysRoutineBody)
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                    }
                    Text("\(todaysRoutineExercises.count) exercises · ~\(StatMath.estimatedMinutes(exerciseCount: todaysRoutineExercises.count)) min")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var todaysRoutineBody: String {
        let names = todaysRoutineExercises
            .sorted { $0.position < $1.position }
            .compactMap { re in allExercises.first(where: { $0.id == re.exerciseID })?.name }
        guard !names.isEmpty else { return "" }
        if names.count <= 3 {
            return names.joined(separator: " · ")
        }
        let shown = names.prefix(3).joined(separator: " · ")
        return "\(shown) +\(names.count - 3) more"
    }

    // MARK: - Stat Tile Row (Task 5 canvas content; states = Phase U frame 41)

    private var statTileRow: some View {
        StatTilesRow(state: statTilesRowState) {
            // Same action as `startSoloWorkoutButton` below — no new
            // session-start path, just the existing routine-picker sheet.
            routinePickerPreselected = nil
            showRoutinePicker = true
        }
    }

    /// Precedence: LOADING (cold-start fetch in flight) beats everything;
    /// then OFFLINE·STALE-CACHE, but only when there's actually cached
    /// activity worth showing as stale (an offline cold start with nothing
    /// ever cached — or a cache that only ever recorded zeros, e.g. a
    /// brand-new user's first online load — has nothing meaningfully
    /// "stale" to render, so it falls through to the friendlier zero-card
    /// CTA below); then FIRST-SESSION·ZERO (no completed sessions ever —
    /// `historySessions` is `SessionRepository.history`, filtered to
    /// `state = completed`, HomeView.swift's `fetchHistory`); else LOADED.
    private var statTilesRowState: StatTilesRowState {
        if statsLoading { return .loading }
        if !connectivity.isOnline {
            let snapshot = StatTilesSnapshotStore.load()
            if snapshot.hasActivity { return .offlineStale(snapshot) }
        }
        if historySessions.isEmpty { return .firstSessionZero }
        return .loaded(
            workoutsThisWeek: StatMath.workoutsThisWeek(sessions: historySessions),
            lifetimeLbs: profile?.lifetimeVolumeLifted ?? 0,
            prsThisMonth: prsThisMonth
        )
    }

    // MARK: - Schedule Button

    private var scheduleButton: some View {
        Button {
            showScheduleSheet = true
        } label: {
            Text("+ Schedule Session")
        }
        .buttonStyle(GSPrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Upcoming Sessions")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if upcomingSessions.isEmpty {
                Text("No upcoming sessions — schedule one above.")
                    .font(GSFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(upcomingSessions) { session in
                    NavigationLink {
                        LobbyView(session: session)
                    } label: {
                        upcomingCard(session)
                    }
                    .buttonStyle(.plain)
                    GSDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingCard(_ session: WorkoutSession) -> some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Kicker: group name or "Session"
                HStack(spacing: 6) {
                    if let groupID = session.groupID,
                       let group = groups.first(where: { $0.id == groupID }) {
                        Text(group.name.uppercased())
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    } else {
                        Text("SESSION")
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    }
                    if session.seriesID != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.accent700)
                    }
                }
                // Title: routine label
                Text(routineLabel(for: session))
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                // Meta: scheduled time or status
                if let scheduledFor = session.scheduledFor {
                    Text(scheduledFor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                } else {
                    Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Join with Code Section

    private var joinWithCodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Join with Code")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            GSCard(bordered: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("6-character code", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(GSFont.bodyMedium(16, relativeTo: .body))
                            .foregroundStyle(theme.text)
                            .onChange(of: joinCode) {
                                let uppercased = joinCode.uppercased()
                                if joinCode != uppercased { joinCode = uppercased }
                                if joinCode.count > 6 { joinCode = String(joinCode.prefix(6)) }
                            }
                        Button("Join") {
                            Task { await joinByCode() }
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(width: 72)
                        .disabled(joinCode.count != 6 || isJoining)
                        .opacity(joinCode.count != 6 || isJoining ? 0.4 : 1)
                    }
                    if isJoining {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(theme.accent)
                            Text("Joining…")
                                .font(GSFont.body(14, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    if let joinError {
                        Text(joinError)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        let userID = appState.currentProfile?.id

        // Single parallel batch: all 8 fetches are declared up front so they
        // all start together (cost = max of all 8, not wave1 + wave2). Each
        // fetch keeps the same best-effort isolation as before — failures
        // are swallowed independently and stale data is left in place.
        async let sessionsFetch  = SessionRepository.upcoming()
        async let groupsFetch    = GroupRepository.myGroups()
        async let historyFetch   = fetchHistory(userID: userID)
        async let routinesFetch  = fetchOwnedRoutines(userID: userID)
        async let exercisesFetch = fetchAllExercises(userID: userID)
        async let prsFetch       = fetchRecentPRs(userID: userID)
        async let prCountFetch   = fetchPRCountThisMonth(userID: userID)
        async let profileFetch   = fetchProfile(userID: userID)

        if let sessions = try? await sessionsFetch { upcomingSessions = sessions }
        if let fetchedGroups = try? await groupsFetch { groups = fetchedGroups }
        // Phase W Task 3 (watch-hr design §2, "Idle state") — see
        // `pushWatchIdleStateIfNoLiveSession()`'s own doc comment for the
        // "cheap trigger" reasoning. Placed after BOTH fetches above
        // (not right after `upcomingSessions`) since the idle payload's
        // session-name derivation needs `groups` too. Gated on `userID !=
        // nil` — same guard `loadTodaysRoutine()` uses below for the
        // identical reason: a signed-out pass through this function must
        // never push a signed-in user's stale `upcomingSessions`/`groups`
        // state to a paired Watch (the shared-device leak class
        // `OfflineSetLogQueue`'s own user-scoping fix already exists to
        // prevent elsewhere in this codebase — same discipline, applied
        // here at the source instead of after the fact).
        if userID != nil { pushWatchIdleStateIfNoLiveSession() }
        let history = await historyFetch
        if let history { historySessions = history }
        if let routines = await routinesFetch { ownedRoutines = routines }
        if let exercises = await exercisesFetch { allExercises = exercises }
        if let prs = await prsFetch { recentPRs = prs }
        let prCount = await prCountFetch
        if let prCount { prsThisMonth = prCount }
        let refreshedProfile = await profileFetch
        if let refreshedProfile { profile = refreshedProfile }

        // Phase U frame 41 (OFFLINE·STALE-CACHE): cache whichever of the 3
        // stat-tile fields succeeded THIS pass — `nil` means that fetch
        // failed/was skipped (e.g. signed out), and
        // `StatTilesSnapshotStore.save` preserves whatever was already
        // cached for that field rather than clobbering it. `statsLoading`
        // drops to `false` after this first pass regardless of success —
        // see its declaration's doc comment for why it never flips back.
        StatTilesSnapshotStore.save(
            workoutsThisWeek: history.map { StatMath.workoutsThisWeek(sessions: $0) },
            lifetimeLbs: refreshedProfile?.lifetimeVolumeLifted,
            prsThisMonth: prCount
        )
        statsLoading = false

        // Matches the previous early-return guard: the Task 5 additions (and
        // the routine lookup that depends on them) only ran when signed in.
        if userID != nil {
            await loadTodaysRoutine()
        }
    }

    // MARK: - Watch idle state (Phase W Task 3, watch-hr design §2)

    /// The "cheap trigger" chosen for the Watch's idle surface (design §2:
    /// "next scheduled session or 'no session' — needs a small additive
    /// idle payload pushed on a cheap trigger (app foreground / schedule
    /// change... do NOT build a scheduling-sync subsystem)"). Piggybacks
    /// `refresh()`'s ALREADY-FETCHED `upcomingSessions`/`groups` — no new
    /// network call, no new subsystem — and `refresh()` itself already
    /// fires on app foreground (`.onChange(of: scenePhase == .active)`),
    /// pull-to-refresh, and initial `.task`, so this rides all three for
    /// free.
    ///
    /// Guarded on `appState.activeSessionID == nil`
    /// (`App/AppState.swift:51`) — the SAME flag `GroupSessionLiveView`
    /// sets on `.onAppear` and clears on `.onDisappear` for an actually-live
    /// session. This guard is LOAD-BEARING, not decorative:
    /// `WCSession.updateApplicationContext` replaces the Watch's ENTIRE
    /// current context on every call (`WatchIdleStatePayload`'s own doc
    /// comment) — without this guard, a `HomeView` refresh racing behind an
    /// open `GroupSessionLiveView` (e.g. a background tab reload) could
    /// stomp the Watch's real, live `sessionState` context with stale idle
    /// info.
    ///
    /// Session-name derivation mirrors `upcomingCard`'s own kicker text
    /// exactly (`HomeView.swift:334-346`: group name if resolvable, else
    /// "Session") — NOT `routineLabel(for:)` (`HomeView.swift:613`, fixed
    /// in the debt-zero sprint to resolve a real name from `ownedRoutines`
    /// when possible, honest "Workout" fallback otherwise — see its own
    /// doc comment). Kept separate deliberately, not swapped in here too:
    /// `routineLabel`'s lookup only resolves routines the CURRENT user
    /// owns, so a session on someone else's routine would silently fall
    /// back to "Workout" — worse for THIS payload's purpose than the
    /// group-name-or-"Session" kicker text, which resolves correctly for
    /// every session the current user can see on Home regardless of who
    /// owns the routine.
    private func pushWatchIdleStateIfNoLiveSession() {
        guard appState.activeSessionID == nil else { return }
        WatchConnectivityBridge.shared.activateIfNeeded()
        let next = upcomingSessions.first
        let nextName: String? = next.map { session in
            if let groupID = session.groupID, let group = groups.first(where: { $0.id == groupID }) {
                return group.name
            }
            return "Session"
        }
        let payload = WatchIdleStatePayload(nextSessionName: nextName, nextSessionAt: next?.scheduledFor)
        WatchConnectivityBridge.shared.updateIdleState(payload)
    }

    // MARK: - Task 5 fetch helpers (userID-gated, best-effort)

    private func fetchHistory(userID: UUID?) async -> [WorkoutSession]? {
        guard let userID else { return nil }
        return try? await SessionRepository.history(userID: userID, limit: 20)
    }

    private func fetchOwnedRoutines(userID: UUID?) async -> [Routine]? {
        guard let userID else { return nil }
        return try? await RoutineRepository.fetchAll(ownerID: userID)
    }

    private func fetchAllExercises(userID: UUID?) async -> [Exercise]? {
        guard userID != nil else { return nil }
        return try? await ExerciseRepository.fetchAll()
    }

    private func fetchRecentPRs(userID: UUID?) async -> [PersonalRecord]? {
        guard let userID else { return nil }
        return try? await PersonalRecordRepository.recent(userID: userID, limit: 1)
    }

    private func fetchPRCountThisMonth(userID: UUID?) async -> Int? {
        guard let userID else { return nil }
        return try? await PersonalRecordRepository.countSince(userID: userID, date: StatMath.startOfMonth())
    }

    private func fetchProfile(userID: UUID?) async -> Profile? {
        guard let userID else { return nil }
        return try? await ProfileRepository.refresh(userID: userID)
    }

    @MainActor
    private func loadTodaysRoutine() async {
        let targetID = historySessions.first(where: { $0.routineID != nil })?.routineID ?? ownedRoutines.first?.id
        guard let targetID,
              let (routine, exercises) = try? await RoutineRepository.fetch(id: targetID) else {
            todaysRoutine = nil
            todaysRoutineExercises = []
            return
        }
        todaysRoutine = routine
        todaysRoutineExercises = exercises
    }

    @MainActor
    private func joinByCode() async {
        guard joinCode.count == 6 else { return }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let session = try await SessionRepository.joinByCode(joinCode)
            joinCode = ""
            joinedSession = session
            navigateToJoined = true
        } catch let error as GymSyncError {
            joinError = error.errorDescription
        } catch {
            joinError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Debt-zero sprint item 4 (T3-era placeholder fix — this function
    /// previously returned the fixed string "Workout" unconditionally for
    /// every session, real routine or not). No new eager-loading network
    /// call is added: `ownedRoutines` is ALREADY fetched every `refresh()`
    /// pass for other Task 5 canvas content (the "Today's routine" card,
    /// `RoutinePickerSheet`) — the exact same already-fetched-data reuse
    /// `pushWatchIdleStateIfNoLiveSession`'s kicker-text derivation uses for
    /// `groups.first(where:)` just above. Only covers routines the CURRENT
    /// user owns (`RoutineRepository.fetchAll(ownerID:)`) — a session tied
    /// to a routine owned by someone else (e.g. a group organizer's
    /// routine this user merely participates in) still falls through to
    /// the honest "Workout" fallback, same as before, rather than guessing
    /// or adding a second per-session network round trip just for this
    /// label.
    private func routineLabel(for session: WorkoutSession) -> String {
        guard let routineID = session.routineID,
              let routine = ownedRoutines.first(where: { $0.id == routineID }) else {
            return "Workout"
        }
        return routine.name
    }

    private func trimmedDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

// MARK: - Routine Picker Sheet
//
// Task 5: the "Start Solo Workout" CTA and the "Today's routine" card both
// route through this sheet. It reuses the EXACT solo-start mechanism already
// used by Library/Workout's `RoutineDetailChoice`
// (`WorkoutSessionView(routine:routineExercises:allExercises:)`) — no new
// session-start path was built. "No routine" starts an untargeted session by
// passing `routine: nil` (see the Task 5 deviation note in
// `WorkoutSessionView.swift`, where `routine` was widened from `Routine` to
// `Routine?` to make that representable).

private struct RoutinePickerSheet: View {
    let routines: [Routine]
    let initialRoutine: Routine?

    @Environment(\.gsTheme) private var theme

    @State private var chosenRoutine: Routine?
    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var startNavigation = false

    // Today's-routine card opens this sheet PAUSED: `chosenRoutine` seeds from
    // `initialRoutine` purely for the visible preselection/highlight below — it no
    // longer auto-starts. The user must tap a row (the preselected one or another)
    // to actually start. Start Solo Workout still passes `initialRoutine: nil`, so
    // this seeds to nil and the list opens with nothing highlighted — unchanged.
    init(routines: [Routine], initialRoutine: Routine?) {
        self.routines = routines
        self.initialRoutine = initialRoutine
        _chosenRoutine = State(initialValue: initialRoutine)
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    Task { await start(routine: nil) }
                } label: {
                    Text("No routine")
                        .font(GSFont.bodyMedium(16, relativeTo: .body))
                        .foregroundStyle(theme.text)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .listRowBackground(theme.bg)

                ForEach(routines) { routine in
                    let isSelected = routine.id == chosenRoutine?.id
                    Button {
                        Task { await start(routine: routine) }
                    } label: {
                        HStack {
                            Text(routine.name)
                                .font(GSFont.bodyMedium(16, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .listRowBackground(isSelected ? theme.accent100 : theme.bg)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $startNavigation) {
                WorkoutSessionView(routine: chosenRoutine,
                                   routineExercises: routineExercises,
                                   allExercises: allExercises)
            }
        }
    }

    @MainActor
    private func start(routine: Routine?) async {
        allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
        if let routine {
            routineExercises = (try? await RoutineRepository.fetch(id: routine.id))?.1 ?? []
        } else {
            routineExercises = []
        }
        chosenRoutine = routine
        startNavigation = true
    }
}
