import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    // MARK: - Injected repositories (production plan, Task 0's interface)
    //
    // Defaulted, so `HomeView()` at `RootView.swift:495` is unchanged and a
    // test or a preview can hand in its own. Integration task **I1** swaps
    // these defaults for Stream A's live implementations; until then Home is
    // correct rather than half-built — an empty friends repository IS the
    // shipping state of the crew pulse (owner ruling 2), and the stub goal
    // repository renders the design's own fixture numbers.

    /// Who from the crew is lifting right now.
    var friendsRepository: any FriendsLiveRepository = EmptyFriendsLiveRepository()

    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var groups: [GymGroup] = []
    @State private var showScheduleSheet = false
    /// "?" FAQ sheet (owner 2026-08-14) — see HelpSheet.swift.
    @State private var showHelp = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joinedSession: WorkoutSession?
    @State private var navigateToJoined = false

    // MARK: - Canvas content state (Task 5)
    @State private var historySessions: [WorkoutSession] = []
    @State private var ownedRoutines: [Routine] = []
    /// Outstanding burpee debt across all the user's groups, and the group
    /// carrying the most of it (the ledger is group-scoped, so the Home
    /// widget has to pick one to open).
    ///
    /// MUST come from `SessionRepository.burpeeLedger`'s netted
    /// `CrewDebt.outstanding`, never `youOweSummary.total`:
    /// `session_participants.burpees_owed` is written once by
    /// `evaluate_lateness` and NEVER decremented, so the raw total keeps
    /// reporting debt the user already paid off — a permanently wrong
    /// number parked on the home screen.
    /// Staleness bookkeeping for the retained-tab refresh (see the
    /// `selectedTab` onChange in `body`).
    @State private var lastRefreshedAt: Date = .distantPast
    static let tabRefreshTTL: TimeInterval = 60

    @State private var burpeesOwed = 0
    @State private var burpeeDebtGroup: GymGroup?
    @State private var showBurpeeLedger = false
    @State private var prsThisMonth: Int = 0
    /// Redesign: feeds the streak-ring widget (proof: ring fills toward the
    /// next milestone). Fetched alongside the other Home data in `refresh()`.
    @State private var userStreak: UserStreak?
    /// Commit signal for the next actionable GROUP session (20260811000001,
    /// owner feedback 2026-08-11): nil = hasn't said.
    @State private var nextCommitStatus: SessionCommitment.Status?
    /// Weekly-goal editor sheet for the intraweek streak widget.
    @State private var showGoalSheet = false
    @State private var profile: Profile?
    @State private var todaysRoutine: Routine?
    @State private var todaysRoutineExercises: [RoutineExercise] = []
    @State private var showRoutinePicker = false
    @State private var routinePickerPreselected: Routine?

    // MARK: - Home v3 state (production plan, stream B)
    //
    // Design: docs/superpowers/specs/2026-09-06-home-v3-production-and
    // -weekly-goal-design.md §A — variation 08a, the composition the owner
    // approved. These three are DECLARED here by task B1 because the
    // composition below reads them; their fetches arrive with tasks B4
    // (friends-live) and B6 (the weekly goal), which is why an empty
    // `friendsLive` renders no crew-pulse strip at all (owner ruling 2) and
    // a nil `weeklyGoal` renders the strip's invitation line.

    /// Who from the crew is mid-session right now. Empty = the strip is
    /// absent and the page shifts up; there is no "nobody's training" state.
    @State private var friendsLive: [FriendLive] = []
    /// This week's goal, or nil when no goal row exists yet.
    @State private var weeklyGoal: WeeklyGoal?
    /// Everything the goal strip renders, already resolved upstream — no
    /// view on this page does goal arithmetic.
    @State private var goalProgress: WeeklyGoalProgress = .init()
    /// The Coach tile's destination. Home is inside a `NavigationStack`, so
    /// this is a local push — deliberately NOT an `AppState.PendingRoute`
    /// case, which is the push deep-link enum and this is not one.
    @State private var showCoach = false
    /// The enrolled block, for the Coach tile's week line. nil = no block,
    /// and the tile drops to the next rung of its precedence.
    @State private var activeProgram: ProgramEnrollment?
    /// The calendar card's destination (design §C).
    @State private var showCalendarPage = false

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

    // MARK: - Campaigns carousel state (Phase C Task 2, Flow 8 :866)
    @State private var activeCampaigns: [Campaign] = []
    @State private var joinedCampaignIDs: Set<UUID> = []
    @State private var campaignProgressByID: [UUID: CampaignProgress] = [:]
    @State private var campaignCommunityByID: [UUID: CampaignCommunityProgress] = [:]
    @State private var joiningCampaignIDs: Set<UUID> = []
    @State private var campaignJoinErrorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                // Home v3, variation 08a — the composition the owner
                // approved (design: docs/superpowers/specs/2026-09-06-home
                // -v3-production-and-weekly-goal-design.md §A), sourced from
                // `HomeV3TargetsAboveCalendarView` and the shared
                // `HomeV3Frame` it renders inside. Same 16 pt page margins
                // and 12 pt rhythm as before; strips sit 2 pt tighter to
                // what follows them (`homeV3Strip()`'s rule).
                //
                // The greeting is PRODUCTION's, not the fixture header: it
                // carries the "?" help door and the avatar tap, which
                // `HomeV2GreetingHeader` does not.
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    replayFailureNotice
                    oneButtonSection
                    tilePairSection
                        .gsSpotlightTarget(key: "tour.home.streak")
                    crewPulseSection
                    goalStripSection
                        .gsSpotlightTarget(key: "tour.home.goal")
                    calendarCardSection
                        .gsSpotlightTarget(key: "tour.home.calendar")
                    if !activeCampaigns.isEmpty {
                        campaignsSection
                    }
                    joinWithCodeSection
                }
            }
            // Dock clearance (user bug report): the bottom tab dock was
            // clipping the last content on every tab — give the scroll
            // content an explicit bottom margin the dock's height.
            .contentMargins(.bottom, 88, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            // Redesign v2 (user feedback 2026-07-21): the "Home" nav-bar title
            // is gone — the greeting header IS this screen's header, and the
            // empty bar row wasted vertical space. Pushed destinations
            // (LobbyView etc.) re-show their own nav bars.
            .toolbar(.hidden, for: .navigationBar)
            // Tour (owner 2026-08-14): the old single .home tip grew into
            // the four-step walk — start → schedule → calendar → streak.
            .gsSpotlightTour(GuidanceTours.home)
            .task {
                // Launch-readiness accounting — RootView holds the launch
                // overlay while initial tab fetches are in flight.
                appState.beginLaunchFetch()
                await refresh()
                appState.endLaunchFetch()
                await consumePendingRouteIfNeeded()
            }
            .refreshable { await refresh() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await refresh() }
            }
            // Tab retention (RootView) means `.task` no longer re-fires on
            // every tab switch — without this, a retained Home would sit on
            // hour-old data indefinitely. TTL'd so re-tapping the tab
            // repeatedly doesn't hammer the network: instant switching is
            // the point, and a refetch inside the window would put the
            // piecewise re-render right back.
            .onChange(of: appState.selectedTab) {
                guard appState.selectedTab == .home,
                      Date.now.timeIntervalSince(lastRefreshedAt) > Self.tabRefreshTTL else { return }
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
            .sheet(isPresented: $showHelp) {
                HelpSheet()
            }
            .sheet(isPresented: $showRoutinePicker) {
                RoutinePickerSheet(routines: ownedRoutines, initialRoutine: routinePickerPreselected)
            }
            // The weekly-goal editor, moved off `weeklyGoalWidget` (deleted
            // with the wide streak card) and onto the page root — it is the
            // tap target of BOTH `HomeStreakTile` and, until Stream C's
            // editor lands, `HomeWeeklyGoalStrip`.
            .sheet(isPresented: $showGoalSheet) {
                // The editor seeds from the STANDING goal (what next week
                // will be), not the effective one — that's the value being
                // edited.
                WeeklyGoalSheet(initial: profile?.weeklySessionGoal ?? 3) { updated in
                    profile = updated
                }
            }
            // Coach's front door. Reachable elsewhere only from the You
            // tab's own `showCoach` push (`YouTabView.swift:124-131`); the
            // Coach tile is Home's.
            .navigationDestination(isPresented: $showCoach) {
                CoachHomeView()
                    .background(theme.bg)
                    .navigationTitle("Coach")
                    .navigationBarTitleDisplayMode(.inline)
            }
            // The calendar card is a door (design language rule 4): the
            // whole card, its `+` and its chevron all land on this one page,
            // seeded with what Home already fetched so it paints instantly.
            .navigationDestination(isPresented: $showCalendarPage) {
                CalendarSchedulingView(completedSessions: historySessions,
                                       upcomingSessions: upcomingSessions,
                                       groups: groups)
            }
            .navigationDestination(isPresented: $navigateToJoined) {
                if let session = joinedSession {
                    // .id pins the lobby's SwiftUI identity to the session
                    // (field bug 2026-07-30/31: a pushed lobby whose computed
                    // session re-resolved kept its @State — including
                    // navigateToInProgress and the live view's session —
                    // and wrote sets into the NEXT SCHEDULED occurrence).
                    LobbyView(session: session)
                        .id(session.id)
                }
            }
            // Burpee widget destination — the ledger is group-scoped, so it
            // opens the group carrying the most outstanding debt.
            .navigationDestination(isPresented: $showBurpeeLedger) {
                if let group = burpeeDebtGroup {
                    BurpeeLedgerView(group: group)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(GSFont.heading(24, relativeTo: .largeTitle))
                    .foregroundStyle(theme.text)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 0)
            // "?" help (owner 2026-08-14): the anti-onboarding — an
            // extruded button opening the FAQ/walkthrough sheet, so help
            // lives at the moment of confusion instead of a front-loaded
            // data dump.
            Button {
                showHelp = true
            } label: {
                Text("?")
                    .font(GSFont.bold(16, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                               cornerRadius: 10, lipHeight: 4))
            .accessibilityLabel("Help")

            // Redesign: profile avatar (initials) — taps through to the You tab.
            Button {
                appState.selectedTab = .you
            } label: {
                Circle()
                    .fill(theme.surface)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(theme.divider, lineWidth: 1))
                    .overlay(
                        Text(avatarInitials)
                            .font(GSFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var avatarInitials: String {
        let name = firstName
        guard !name.isEmpty else { return "?" }
        return String(name.prefix(2)).uppercased()
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

    // MARK: - The one button (design §A item 3)
    //
    // ONE primary, five states, and none of them starts a workout by itself
    // (design language rule 5): every state lands on a screen where the
    // lifter can still do something different. It replaces the join hero,
    // the gold check-in tile, the countdown tile and the empty tile — four
    // shapes that used to morph into each other — with one shape that only
    // changes what it says.
    //
    // State resolution reuses what this screen already computes:
    // `nextActionableSession(now:)`, `checkInAvailable(_:now:)`,
    // `checkInOpensAt(_:)`, `compactCountdown(to:from:)` and
    // `ProgramToday.resolveRoutine`'s result (`todaysRoutine`). No new
    // fetch, and no timing rule is touched — the 20-minute window and the
    // 30-minute missed cutoff are exactly where they were.
    //
    // `todaysSession` went with the join hero it existed to feed. It held a
    // SECOND copy of the 30-minute cutoff, and the button reads the first
    // one — `nextActionableSession(now:)`, untouched below. Keeping an
    // unreachable duplicate of a timing rule is how two answers to the same
    // question start.

    /// 08a's top row: the one button, and — only when the primary is about a
    /// session with other people — the quiet solo escape under it (design
    /// language rule 5; a solo primary already opens the start screen, so
    /// the pill would be a second door to the same room).
    ///
    /// It stays inside the `TimelineView(.periodic(by: 30))` the check-in
    /// widget used to own, at the SAME cadence: the `.checkInOpens`
    /// countdown has to stay live, and re-selecting the candidate session
    /// every 30 s is what lets a session that crosses the 30-minute missed
    /// line drop out of the button on its own.
    private var oneButtonSection: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let session = nextActionableSession(now: context.date)
            let state = oneButtonState(for: session, now: context.date)
            VStack(spacing: 9) {
                HomeOneButton(state: state,
                              commitChip: commitChip(for: state, session: session)) {
                    performOneButtonAction(state, session: session)
                }
                .gsSpotlightTarget(.home)

                if state.isCrewState {
                    HomeSoloRow(
                        burpeesOwed: burpeesOwed,
                        onStartSolo: {
                            routinePickerPreselected = nil
                            showRoutinePicker = true
                        },
                        onOpenLedger: { showBurpeeLedger = true }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    /// The plan's state table, resolved by `HomeOneButtonResolver`. Every
    /// rule it needs is applied HERE by the helpers that already existed, so
    /// the resolver owns branch order and nothing else.
    private func oneButtonState(for session: WorkoutSession?, now: Date) -> HomeOneButtonState {
        HomeOneButtonResolver.state(next: session.map { oneButtonInput(for: $0, now: now) },
                                    todaysRoutineName: todaysRoutine?.name)
    }

    private func oneButtonInput(for session: WorkoutSession, now: Date) -> HomeOneButtonInput {
        let opensAt = checkInOpensAt(session)
        return HomeOneButtonInput(
            isInProgress: session.state == "in_progress",
            startedAtLabel: session.startedAt.map { $0.formatted(.dateTime.hour().minute()) },
            isGroupSession: session.groupID != nil,
            checkInAvailable: checkInAvailable(session, now: now),
            opensInLabel: opensAt.flatMap { now < $0 ? compactCountdown(to: $0, from: now) : nil },
            crewName: crewName(for: session),
            routineName: routineLabel(for: session),
            timeLabel: session.scheduledFor.map { $0.formatted(.dateTime.hour().minute()) } ?? ""
        )
    }

    /// The crew a session belongs to, or `Solo`. Same lookup
    /// `pushWatchIdleStateIfNoLiveSession` makes, kept separate from
    /// `routineLabel(for:)` for the reason that function's doc comment gives.
    private func crewName(for session: WorkoutSession) -> String {
        session.groupID.flatMap { gid in groups.first(where: { $0.id == gid })?.name } ?? "Solo"
    }

    /// The commit chip, kept from the deleted countdown card because the
    /// Home inventory calls it the only glance-level commit status in the
    /// app. Only on `.checkInOpens`, and only for a crew session — a solo
    /// lift has nobody to commit to. It is NOT a nested button: the whole
    /// one button already routes to the crew room, where committing lives.
    private func commitChip(for state: HomeOneButtonState,
                            session: WorkoutSession?) -> HomeOneButtonCommitChip? {
        guard case .checkInOpens = state, session?.groupID != nil else { return nil }
        switch nextCommitStatus {
        case nil:        return .commit
        case .committed: return .committed
        case .out:       return .out
        }
    }

    /// Every state opens a SCREEN; none starts a workout (design language
    /// rule 5). `.startRoutine` lands on the picker with today's routine
    /// preselected — the lifter can still run something else.
    private func performOneButtonAction(_ state: HomeOneButtonState,
                                        session: WorkoutSession?) {
        switch state {
        case .joinSession, .checkIn:
            if let session { openLobby(session) }
        case .checkInOpens:
            guard let session else { return }
            if let groupID = session.groupID {
                // The crew room, where committing lives (owner feedback
                // 2026-08-11) — the countdown card never committed directly
                // and neither does this.
                appState.pendingRoute = .chat(groupID: groupID)
                appState.selectedTab = .social
            } else {
                openLobby(session)
            }
        case .startRoutine, .startWorkout:
            routinePickerPreselected = todaysRoutine
            showRoutinePicker = true
        }
    }

    /// Home's one lobby push. `.id(session.id)` on the destination is
    /// load-bearing — see `navigateToJoined`'s destination comment for the
    /// 2026-07-30 field bug it exists to prevent.
    private func openLobby(_ session: WorkoutSession) {
        joinedSession = session
        navigateToJoined = true
    }

    // MARK: - Tile pair, crew pulse, goal strip, calendar (design §A items 5-8)
    //
    // Equal heights in the tile row: both tiles stretch to
    // `maxHeight: .infinity` inside an `HStack` that is
    // `fixedSize(vertical: true)`, so the row sizes to the taller tile and
    // the shorter one fills — the same constraint the old check-in/streak
    // row carried, at `HomeV3Metrics`' 10 pt gap.

    private var tilePairSection: some View {
        HStack(alignment: .top, spacing: HomeV3Metrics.tileGap) {
            streakSlot
            coachSlot
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// No widget renders a bare zero (user feedback 2026-07-25): someone who
    /// has never trained gets the invitation, not a 0-streak tile. The
    /// branch is production's own — only the trained side becomes the v3
    /// tile, whose slot grid wraps every 5 in ROWS where the wide card
    /// wrapped in columns.
    @ViewBuilder
    private var streakSlot: some View {
        if hasEverTrained {
            HomeStreakTile(streak: userStreak?.currentStreak ?? 0,
                           daysDone: daysThisWeek,
                           // Anti-goalpost rule (owner 2026-08-12): the tile
                           // renders the EFFECTIVE goal — an edit made
                           // mid-week lands next week, never this one.
                           goal: profile?.effectiveWeeklyGoal ?? 3) {
                showGoalSheet = true
            }
        } else {
            streakInviteWidget(hasTrainedBefore: false)
        }
    }

    /// Coach's tile. The sentence and the badge are task B3's; the route is
    /// the composition's, because a tile that opens nothing is not a tile.
    private var coachSlot: some View {
        HomeCoachTile(sentence: coachSentence,
                      waiting: coachWaiting) {
            showCoach = true
        }
    }

    /// Owner ruling 2: the crew pulse renders ONLY when a friend is actually
    /// lifting. When nobody is, nothing renders at all and everything below
    /// shifts up — no empty state and no reserved gap. The 2 pt-tighter foot
    /// is 08a's `homeV3Strip()`: a strip belongs to what follows it.
    @ViewBuilder
    private var crewPulseSection: some View {
        if let friend = friendsLive.first {
            HomeCrewPulseStrip(initials: friend.initials,
                               headline: crewPulseHeadline(friend),
                               detail: crewPulseDetail(friend)) {
                openFriendLive(friend)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    /// This week's goal. `kind == nil` is the invitation line — the only
    /// state in which the strip shows something other than a reading.
    ///
    /// Until Stream C's `WeeklyGoalEditorSheet` lands the tap opens the
    /// existing weekly-goal sheet, so the strip is never inert; integration
    /// task I1 swaps the destination.
    private var goalStripSection: some View {
        HomeWeeklyGoalStrip(kind: weeklyGoal?.kind, progress: goalProgress) {
            showGoalSheet = true
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - The Coach tile (task B3)
    //
    // NO EXISTING "HOME COACH SENTENCE" PATH WAS FOUND, so this task decides
    // one. Grepped: `BlockProgression` (`Models/BlockProgression.swift:40`)
    // is per-lift and returns `Decision`/`CoachNote`, not a Home line;
    // `CoachHomeView` builds its own from the thread. The precedence below
    // is the plan's, first rung that produces text:
    //
    //   (a) a proposed change to a user-set goal — ABSENT. The plan names
    //       `WeeklyGoalRepository.propose(_:)`, which the Task 0 interface
    //       does not have (`goal`, `progress`, `save`, `clearToCoach`), and
    //       Stream A owns that file. It arrives at integration I1; the rung
    //       is written here as a comment rather than invented as a guess.
    //   (b) today's routine, as a first-person line;
    //   (c) the block's week;
    //   (d) a static invitation.
    //
    // One sentence, first person, Coach's own voice (design language rule 7).

    private var coachSentence: String {
        if let line = todaysRoutineSentence { return line }
        if let line = blockWeekSentence { return line }
        return "Tell me how the week's going and I'll shape the next one."
    }

    /// (b) "Pull A today — take 185 × 8, then we climb."
    ///
    /// The routine is whatever `ProgramToday.resolveRoutine` settled on, so
    /// the tile and the one button are talking about the same lift. The
    /// generator names its routines `Coach · Pull A`; the prefix is Coach's
    /// own signature and reads wrong inside Coach's own sentence, so it goes.
    private var todaysRoutineSentence: String? {
        guard let routine = todaysRoutine else { return nil }
        let name = routine.name.hasPrefix("Coach · ")
            ? String(routine.name.dropFirst("Coach · ".count))
            : routine.name
        // The first prescribed working weight, when the block wrote one.
        let opener = todaysRoutineExercises.first { exercise in
            guard let weight = exercise.targetWeight else { return false }
            return !weight.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let opener, let weight = opener.targetWeight else {
            return "\(name) today. Log the sets and I'll take it from there."
        }
        guard let reps = repsLabel(for: opener) else {
            return "\(name) today — take \(weight), then we climb."
        }
        return "\(name) today — take \(weight) × \(reps), then we climb."
    }

    /// The prescription's rep target: the generated range if it has one, the
    /// legacy text otherwise, and nothing at all for a cardio or to-failure
    /// row — neither of which reads as `× n`.
    private func repsLabel(for exercise: RoutineExercise) -> String? {
        if exercise.targetFailure || exercise.cardioMinutes != nil { return nil }
        if let low = exercise.targetRepsLow {
            guard let high = exercise.targetRepsHigh, high != low else { return "\(low)" }
            return "\(low)-\(high)"
        }
        guard let reps = exercise.targetReps?.trimmingCharacters(in: .whitespaces),
              !reps.isEmpty else { return nil }
        return reps
    }

    /// (c) "Week 2 of 6. 3 days on the books."
    ///
    /// The week is counted from the enrollment's own start day and clamped
    /// to the block's length — a block a lifter has run past its last week
    /// says "week 6 of 6", never "week 8 of 6". The days are the sessions
    /// already scheduled inside the week the streak tile is counting, so the
    /// two agree.
    private var blockWeekSentence: String? {
        guard let program = activeProgram, program.endedAt == nil, program.weeks > 0 else { return nil }
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: program.startedOn),
                                              to: calendar.startOfDay(for: .now)).day ?? 0
        let week = min(max(1, elapsed / 7 + 1), program.weeks)
        let booked = Set(upcomingSessions.compactMap { session -> Date? in
            guard let when = session.scheduledFor,
                  calendar.isDate(when, equalTo: .now, toGranularity: .weekOfYear)
            else { return nil }
            return calendar.startOfDay(for: when)
        }).count
        guard booked > 0 else { return "Week \(week) of \(program.weeks). Nothing on the books yet." }
        return "Week \(week) of \(program.weeks). \(booked) \(booked == 1 ? "day" : "days") on the books."
    }

    /// The accent count badge. `nil` — no badge at all.
    ///
    /// `coach_chat_threads` (`20260824000005_coach_chat_threads.sql`) carries
    /// NO unread count, and none of `CoachChat`'s functions returns one. A
    /// badge that always reads `1` is worse than no badge (design language
    /// rule 4: badges point, they do not shout), so this does not invent a
    /// number. It becomes a real count the day the column exists.
    private var coachWaiting: Int? { nil }

    /// `{Name} is lifting now` — the design's copy, verbatim.
    private func crewPulseHeadline(_ friend: FriendLive) -> String {
        "\(friend.displayName) is lifting now"
    }

    /// `{Crew} · {when}` for a crew session, `Solo` otherwise.
    private func crewPulseDetail(_ friend: FriendLive) -> String {
        guard let groupName = friend.groupName else { return "Solo" }
        guard let startedAt = friend.startedAt else { return groupName }
        return "\(groupName) · \(startedAt.formatted(.dateTime.hour().minute()))"
    }

    /// Tap on the crew pulse: that session's LOBBY when you are one of its
    /// participants, the crew room otherwise.
    ///
    /// Participation is asked at TAP TIME rather than carried on
    /// `FriendLive`, for two reasons. `SessionRepository.upcoming()` filters
    /// to `scheduled | lobby_open | editing | voting | locked`, so a session
    /// that is actually `in_progress` — the only kind this strip shows — is
    /// never in `upcomingSessions` and cannot be checked against it. And the
    /// answer only matters for the one row a lifter actually presses, so
    /// asking for all of them on every refresh would be work for nothing.
    private func openFriendLive(_ friend: FriendLive) {
        Task { await routeToFriendLive(friend) }
    }

    @MainActor
    private func routeToFriendLive(_ friend: FriendLive) async {
        if let userID = appState.currentProfile?.id,
           let rows = try? await SessionRepository.participants(sessionID: friend.sessionID),
           rows.contains(where: { $0.participant.userID == userID }),
           let session = try? await SessionRepository.session(id: friend.sessionID) {
            openLobby(session)
            return
        }
        // Not yours to walk into — the crew room is where you ask.
        guard let groupID = friend.groupID else { return }
        appState.pendingRoute = .chat(groupID: groupID)
        appState.selectedTab = .social
    }

    /// The calendar as a door (design §A item 8): three months of dots, the
    /// `{n} UPCOMING` count, the `+`, the chevron — and NO appointment rows.
    /// The itinerary they used to hold is written out on the page the card
    /// opens.
    private var calendarCardSection: some View {
        HomeCalendarCard(months: calendarMonths,
                         appointments: calendarAppointments,
                         showsAppointments: false) {
            showCalendarPage = true
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// The soonest ACTIONABLE upcoming session (repository order is
    /// soonest-first). A session is considered MISSED — and skipped — 30
    /// minutes after its scheduled start unless it actually went live
    /// (user feedback 2026-07-24: the gold shimmer ran forever on missed
    /// events). The widget then falls through to the next session, or the
    /// empty state.
    private func nextActionableSession(now: Date) -> WorkoutSession? {
        upcomingSessions.first { session in
            if session.state == "in_progress" { return true }
            guard let when = session.scheduledFor else { return true }
            return now <= when.addingTimeInterval(30 * 60)
        }
    }

    /// When check-in opens: 20 minutes before the scheduled start — the SAME
    /// rule LobbyView.canCheckIn enforces (server-enforced too, migration
    /// 20260715000003_checkin_window.sql). Session STATE is deliberately not
    /// the signal: sessions can sit `lobby_open` hours early, which is exactly
    /// the false-"Check in" bug the first on-device round caught.
    private func checkInOpensAt(_ session: WorkoutSession) -> Date? {
        session.scheduledFor?.addingTimeInterval(-20 * 60)
    }

    /// True when check-in is genuinely available NOW: the session is live, or
    /// the 20-minute window has opened. No `scheduledFor` fails open —
    /// mirroring LobbyView, whose button would be actionable there too.
    private func checkInAvailable(_ session: WorkoutSession, now: Date) -> Bool {
        if session.state == "in_progress" { return true }
        guard let opensAt = checkInOpensAt(session) else { return true }
        return now >= opensAt
    }

    // (`goldTop`/`goldBottom`/`goldInk`, `checkInShimmer`, `checkInWidget`,
    // `goldCheckInCard`, `countdownBody`, `checkInEmptyBody` and
    // `commitControl` were deleted with the check-in tile — the one button
    // carries all four of their states now, and `HomeV2Gold` carries the
    // palette. `commitControl`'s three faces survive as
    // `HomeOneButtonCommitChip`.)

    /// Sums the user's OUTSTANDING debt across every group and remembers the
    /// group holding the most of it (the tap target). Best-effort per group:
    /// one group's failure must never blank a real debt in another, and a
    /// total failure simply leaves the widget absent — never a wrong number.
    @MainActor
    private func loadBurpeeDebt() async {
        guard let userID = profile?.id ?? appState.currentProfile?.id, !groups.isEmpty else {
            burpeesOwed = 0
            burpeeDebtGroup = nil
            return
        }
        var total = 0
        var worst: (group: GymGroup, amount: Int)?
        for group in groups {
            guard let debts = try? await SessionRepository.burpeeLedger(groupID: group.id),
                  let mine = debts.first(where: { $0.userID == userID }),
                  mine.outstanding > 0 else { continue }
            total += mine.outstanding
            if mine.outstanding > (worst?.amount ?? 0) { worst = (group, mine.outstanding) }
        }
        burpeesOwed = total
        burpeeDebtGroup = worst?.group
    }

    /// Compact countdown units (user feedback 2026-07-23): two significant
    /// figures max — "3d", "12h", "45m" — targeting when check-in OPENS.
    private func compactCountdown(to target: Date, from now: Date) -> String {
        let seconds = max(0, target.timeIntervalSince(now))
        let days = Int(seconds / 86400)
        if days >= 1 { return "\(days)d" }
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "\(hours)h" }
        return "\(max(1, Int(ceil(seconds / 60))))m"
    }

    /// DISTINCT training days this calendar week. The rule now lives in
    /// `WeeklyGoalProgressMath` so the streak tile and the goal strip cannot
    /// give two answers about the same week — the design's agreement law.
    private var daysThisWeek: Int {
        WeeklyGoalProgressMath.daysThisWeek(completed: historySessions)
    }

    /// True once the user has any completed session in history — the
    /// never-started vs lapsed discriminator. `historySessions` is already
    /// loaded for the calendar widget, so this costs no extra fetch.
    private var hasEverTrained: Bool {
        historySessions.contains { $0.completedAt != nil }
    }

    private func streakInviteWidget(hasTrainedBefore: Bool) -> some View {
        Button {
            // Never trained -> scheduling is the achievable next step (a solo
            // lift needs nobody else). Lapsed -> same destination, different
            // framing.
            showScheduleSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(theme.neutral300, lineWidth: 4)
                    Image(systemName: "flame")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hasTrainedBefore ? "Start a new streak" : "Schedule your first lift")
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hasTrainedBefore ? "Train this week to get it going again" : "Two sessions a week builds one")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(15)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasTrainedBefore
                            ? "Start a new streak. Schedule a workout."
                            : "Schedule your first lift.")
    }

    // (streakCountWidget deleted 2026-08-12 — dead since the weekly-goal
    // widget replaced it; the wiring audit confirmed zero call sites.)

    // MARK: - The calendar card's data
    //
    // The mapping lives in `HomeCalendarCardModel` so it can be tested
    // without a view (task B7), and so Stream D's calendar page draws its
    // grid from the SAME function — the door and the room must not
    // disagree about which day was trained.

    private var calendarMonths: [HomeCalendarCard.Month] {
        HomeCalendarCardModel.months(completed: historySessions,
                                     upcoming: upcomingSessions)
    }

    private var calendarAppointments: [HomeCalendarCard.Appointment] {
        HomeCalendarCardModel.appointments(upcoming: upcomingSessions,
                                           groups: groups,
                                           title: { routineLabel(for: $0) })
    }

    // MARK: - Campaigns carousel (Phase C Task 2)
    //
    // Flow 8 (spec :866): "Home tab surfaces a 'Campaigns you might like'
    // carousel when one is starting soon." "Active campaigns only" per the
    // task brief — `activeCampaigns` (populated in `refresh()`) is already
    // filtered to the active half of `CampaignRepository.activeAndUpcoming(
    // )`'s result, so this section renders nothing at all when zero
    // campaigns are currently active (no empty-state chrome, same "absent
    // entirely when empty" posture `LibraryTabView.featuredShelf` already
    // uses for its own optional shelf). No canvas frame depicts this
    // carousel — see `docs/design/accepted-deviations.json`'s
    // "home-campaigns-carousel" entry.
    //
    // Shelf shape borrows `LibraryTabView.featuredShelf`'s kicker +
    // horizontal-scroll-of-cards idiom (`LibraryTabView.swift:118-155`): a
    // single card renders full-width (no scroll chrome needed for one item),
    // 2+ renders as a horizontal `ScrollView`.
    private var campaignsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent700)
                Text("Campaigns you might like")
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text.opacity(0.6))
            }
            .padding(.horizontal, 16)

            if activeCampaigns.count == 1, let only = activeCampaigns.first {
                campaignCard(only)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeCampaigns) { campaign in
                            campaignCard(campaign)
                                .frame(width: 260)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let campaignJoinErrorText {
                Text(campaignJoinErrorText)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    /// ONE card design (per task brief) covering both states — a `joined`
    /// branch inside the SAME card body, not two separate card views.
    /// Joined: whole card is a `NavigationLink` to the detail screen — same
    /// "whole bordered card navigates" idiom as `upcomingCard`
    /// (`HomeView.swift:369-413`). Unjoined: the card is NOT wrapped in a
    /// NavigationLink at all — it carries its own inline "Join Campaign"
    /// button instead, same "button lives directly on a non-navigating
    /// card, fires immediately, no confirmation" idiom as `LibraryTabView.
    /// heroCard`'s "Add to my routines" button (`LibraryTabView.swift:199-
    /// 213`) — chosen deliberately over nesting a `Button` inside a
    /// `NavigationLink`'s label (a known SwiftUI gesture-conflict hazard
    /// neither existing idiom in this codebase risks) and matches Flow 8's
    /// own "no commitment beyond opt-in" framing for why a one-tap join
    /// needs no confirmation step.
    @ViewBuilder
    private func campaignCard(_ campaign: Campaign) -> some View {
        if joinedCampaignIDs.contains(campaign.id) {
            NavigationLink {
                CampaignDetailView(campaign: campaign)
            } label: {
                campaignCardBody(campaign, joined: true)
            }
            // 3D pass (2026-08 sweep): the joined card navigates, so it
            // sinks on press.
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        } else {
            // Not a link (it carries its own inline "Join Campaign" CTA), so
            // it wears the STATIC extrusion — identical at rest, no travel.
            campaignCardBody(campaign, joined: false)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    // 3D pass (2026-08 sweep): the extruded chrome comes from the CALL SITE
    // (`.gs3DCardStyle` when joined/tappable, `.gs3DCard` otherwise) — the
    // old wrapping GSCard would have painted flat surface over the face.
    private func campaignCardBody(_ campaign: Campaign, joined: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAMPAIGN")
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral700)
            Text(campaign.name)
                .font(GSFont.heading(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if joined {
                if let resolved = campaign.individualTarget?.resolvedTarget {
                    let achieved = CampaignProgressMath.achievedCount(
                        progress: campaignProgressByID[campaign.id], target: campaign.individualTarget) ?? 0
                    Text("Your progress: \(achieved)/\(resolved.count) \(resolved.unitLabel)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                if let community = campaignCommunityByID[campaign.id] {
                    Text("Community: \(trimmedDecimal(Units.fromPounds(community.volumeLifted, to: ThemeStore.shared.weightUnit))) \(ThemeStore.shared.weightUnit.label)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            } else {
                Text(campaign.description ?? "Join a seasonal challenge with the community.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(2)
                Button {
                    Task { await joinCampaignFromHome(campaign) }
                } label: {
                    HStack {
                        Text("Join Campaign")
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 13, verticalPadding: 10))
                .disabled(joiningCampaignIDs.contains(campaign.id))
                .opacity(joiningCampaignIDs.contains(campaign.id) ? 0.6 : 1)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    // (Declutter round, 2026-07-21 feedback: the Home stat-tile row was
    // REMOVED — Stats owns the numbers; the calendar consumes the space.
    // `StatTilesRow` the component lives on (CatalogHostView still renders
    // its frame-41 states), and `refresh()` still saves the offline
    // snapshot. The old standalone schedule button and Upcoming list were
    // previously absorbed into `TrainingCalendarWidget`; schedule is now
    // `scheduleWidget` above the calendar.)

    // MARK: - Join with Code Section

    private var joinWithCodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Join with Code")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            // gs3D pass (2026-08-13): the last flat Home card joins the
            // extruded language (static — the Join button is the tappable).
            Group {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .gs3DCard(cornerRadius: GSMetrics.radiusMd)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        lastRefreshedAt = .now
        let userID = appState.currentProfile?.id

        // Single parallel batch: every fetch is declared up front so they
        // all start together (cost = max of them all, not wave1 + wave2).
        // Each fetch keeps the same best-effort isolation as before —
        // failures are swallowed independently and stale data is left in
        // place. Home v3's own fetches join this batch and nowhere else.
        async let sessionsFetch  = SessionRepository.upcoming()
        async let groupsFetch    = GroupRepository.myGroups()
        async let historyFetch   = fetchHistory(userID: userID)
        async let routinesFetch  = fetchOwnedRoutines(userID: userID)
        async let prCountFetch   = fetchPRCountThisMonth(userID: userID)
        async let profileFetch   = fetchProfile(userID: userID)
        async let campaignsFetch = fetchActiveCampaigns(userID: userID)
        async let streakFetch    = fetchStreak(userID: userID)
        async let programFetch   = fetchActiveProgram(userID: userID)
        async let friendsFetch   = fetchFriendsLive(userID: userID)

        // Perf (user report 2026-07-25: "things load incrementally over a
        // fraction of a second"): every `await` is a suspension point, so
        // the OLD interleaving — await, assign, await, assign — produced up
        // to 8 separate render passes and the screen visibly ASSEMBLED.
        // The fetches were already parallel; only the assignment order was
        // wrong. Now ALL awaits resolve first, then all `@State` writes run
        // back-to-back with no suspension between them, which SwiftUI
        // coalesces into a single render: the screen arrives whole.
        let sessions        = try? await sessionsFetch
        let fetchedGroups   = try? await groupsFetch
        let history         = await historyFetch
        let routines        = await routinesFetch
        let prCount         = await prCountFetch
        let refreshedProfile = await profileFetch
        let campaigns       = await campaignsFetch
        let streak          = await streakFetch
        let program         = await programFetch
        let friends         = await friendsFetch

        // ── single commit (no awaits until after this block) ──
        if let sessions { upcomingSessions = sessions }
        if let fetchedGroups { groups = fetchedGroups }
        if let history { historySessions = history }
        if let routines { ownedRoutines = routines }
        if let prCount { prsThisMonth = prCount }
        if let refreshedProfile { profile = refreshedProfile }
        activeCampaigns = campaigns ?? []
        if let streak { userStreak = streak }
        activeProgram = program
        friendsLive = friends
        statsLoading = false

        // Commit signal for the next actionable group session (Phase B,
        // 2026-08-11) — depends on `upcomingSessions` from the commit block
        // above, so it deliberately runs after the single-render pass.
        if let next = nextActionableSession(now: .now), next.groupID != nil {
            let rows = (try? await CommitmentRepository.commitments(sessionID: next.id)) ?? []
            nextCommitStatus = rows.first { $0.userID == userID }?.status
        } else {
            nextCommitStatus = nil
        }

        // Phase W Task 3 (watch-hr design §2, "Idle state") — see
        // `pushWatchIdleStateIfNoLiveSession()`'s own doc comment for the
        // "cheap trigger" reasoning. Runs after the commit above since the
        // idle payload's session-name derivation needs BOTH
        // `upcomingSessions` and `groups`. Gated on `userID != nil` — a
        // signed-out pass must never push a signed-in user's stale state to
        // a paired Watch (the shared-device leak class `OfflineSetLogQueue`'s
        // own user-scoping fix already exists to prevent elsewhere).
        if userID != nil { pushWatchIdleStateIfNoLiveSession() }

        // Secondary passes: these paint additive detail (campaign join
        // buttons, the burpee widget) and are deliberately left OUTSIDE the
        // commit — blocking the whole screen on them would trade one late
        // element for a slower first paint of everything.
        await loadCampaignJoinState(for: activeCampaigns)
        await loadBurpeeDebt()

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
    /// exactly (`HomeView.swift:~370-386`: group name if resolvable, else
    /// "Session") — NOT `routineLabel(for:)` (`HomeView.swift:~659`, fixed
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
        // Limit 60 (was 20): the calendar widget renders 12 weeks of dot-grid
        // texture, so it needs deeper history than the old stat tiles did.
        return try? await SessionRepository.history(userID: userID, limit: 60)
    }

    /// Redesign: feeds the streak-ring widget. `try?` on the throwing
    /// `UserStreak?` return double-wraps; the trailing `?? nil` flattens it.
    private func fetchStreak(userID: UUID?) async -> UserStreak? {
        guard let userID else { return nil }
        return (try? await StreakRepository.userStreak(userID: userID)) ?? nil
    }

    /// The enrolled block, for the Coach tile's week line (task B3). Same
    /// double-wrap flattening as `fetchStreak` — `active()` throws AND
    /// returns an optional. `userID` is only a signed-in gate here;
    /// `ProgramRepository.active()` scopes itself to the current user.
    private func fetchActiveProgram(userID: UUID?) async -> ProgramEnrollment? {
        guard userID != nil else { return nil }
        return (try? await ProgramRepository.active()) ?? nil
    }

    /// Who from the crew is mid-session (task B4). Non-throwing by
    /// construction: the protocol returns `[]` rather than an error, because
    /// "nobody is lifting" and "the query failed" render the same thing —
    /// no strip at all.
    private func fetchFriendsLive(userID: UUID?) async -> [FriendLive] {
        guard userID != nil else { return [] }
        return await friendsRepository.live()
    }

    private func fetchOwnedRoutines(userID: UUID?) async -> [Routine]? {
        guard let userID else { return nil }
        return try? await RoutineRepository.fetchAll(ownerID: userID)
    }

    // (fetchAllExercises/fetchRecentPRs removed with the Home PR widget —
    // redesign v2; RoutinePickerSheet fetches its own exercise list.)

    private func fetchPRCountThisMonth(userID: UUID?) async -> Int? {
        guard let userID else { return nil }
        return try? await PersonalRecordRepository.countSince(userID: userID, date: StatMath.startOfMonth())
    }

    private func fetchProfile(userID: UUID?) async -> Profile? {
        guard let userID else { return nil }
        return try? await ProfileRepository.refresh(userID: userID)
    }

    // MARK: - Campaigns (Phase C Task 2)

    private func fetchActiveCampaigns(userID: UUID?) async -> [Campaign]? {
        guard userID != nil else { return nil }
        guard let result = try? await CampaignRepository.activeAndUpcoming() else { return nil }
        return result.active
    }

    /// Batched joined-state lookup, then per-joined-campaign progress +
    /// community totals — sequential per-campaign awaits (not a
    /// `TaskGroup`), deliberately: the campaign design's own scale note
    /// (spec :1375, "1-2 active seasonal campaigns at a time") bounds this
    /// to at most a couple of round trips in practice, so the added
    /// concurrency complexity of a `TaskGroup` isn't worth it here.
    @MainActor
    private func loadCampaignJoinState(for campaigns: [Campaign]) async {
        guard !campaigns.isEmpty else {
            joinedCampaignIDs = []
            campaignProgressByID = [:]
            campaignCommunityByID = [:]
            return
        }
        let joined = (try? await CampaignRepository.myParticipations(campaignIDs: campaigns.map(\.id))) ?? []
        joinedCampaignIDs = joined
        for campaign in campaigns where joined.contains(campaign.id) {
            campaignProgressByID[campaign.id] = try? await CampaignRepository.myProgress(campaignID: campaign.id)
            campaignCommunityByID[campaign.id] = try? await CampaignRepository.communityProgress(campaignID: campaign.id)
        }
    }

    /// The Home card's inline "Join Campaign" button action —
    /// `campaignCardBody`'s doc comment explains why this fires immediately
    /// with no confirmation step. Best-effort refresh of that one campaign's
    /// progress/community state on success so the card's `joined` branch
    /// renders real (zero-state) numbers immediately rather than waiting
    /// for the next full `refresh()` pass.
    @MainActor
    private func joinCampaignFromHome(_ campaign: Campaign) async {
        guard !joiningCampaignIDs.contains(campaign.id) else { return }
        joiningCampaignIDs.insert(campaign.id)
        campaignJoinErrorText = nil
        defer { joiningCampaignIDs.remove(campaign.id) }
        do {
            try await CampaignRepository.join(campaignID: campaign.id)
            joinedCampaignIDs.insert(campaign.id)
            campaignProgressByID[campaign.id] = try? await CampaignRepository.myProgress(campaignID: campaign.id)
            campaignCommunityByID[campaign.id] = try? await CampaignRepository.communityProgress(campaignID: campaign.id)
        } catch {
            campaignJoinErrorText = ErrorMapping.map(error).errorDescription
        }
    }

    @MainActor
    private func loadTodaysRoutine() async {
        // The enrolled block owns "today" (owner 2026-08-28: "Home leads
        // with today's booked session from the enrollment, and the dead
        // last-used path is deleted"). The old guess - last-used routine,
        // else an arbitrary owned one - showed a stale routine on the
        // primary surface right after Coach built a new block.
        guard let userID = appState.currentProfile?.id else {
            todaysRoutine = nil
            todaysRoutineExercises = []
            return
        }
        let todaysSolo = upcomingSessions.first { s in
            s.groupID == nil
                && (s.scheduledFor.map { Calendar.current.isDateInToday($0) } ?? false)
        }
        if let resolved = await ProgramToday.resolveRoutine(session: todaysSolo,
                                                            ownerID: userID) {
            todaysRoutine = resolved.routine
            todaysRoutineExercises = resolved.exercises
        } else {
            // No block: the card offers the picker, honestly.
            todaysRoutine = nil
            todaysRoutineExercises = []
        }
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
    let initialRoutine: Routine?

    @Environment(\.gsTheme) private var theme
    /// This view IS the sheet's root, so this dismisses the SHEET (a
    /// `dismiss()` captured inside the pushed session would only pop the
    /// push). Handed to `WorkoutSessionView.onFinished` so completing a
    /// workout exits all the way out instead of landing back on this picker.
    @Environment(\.dismiss) private var dismissPicker

    /// Seeded from the caller's fetched list, then locally owned so a routine
    /// built in-sheet (Build Routine push below) appears immediately.
    @State private var routines: [Routine]
    @State private var chosenRoutine: Routine?
    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var startNavigation = false
    @State private var showBuilder = false

    // Today's-routine card opens this sheet PAUSED: `chosenRoutine` seeds from
    // `initialRoutine` purely for the visible preselection/highlight below — it no
    // longer auto-starts. The user must tap a row (the preselected one or another)
    // to actually start. Start Solo Workout still passes `initialRoutine: nil`, so
    // this seeds to nil and the list opens with nothing highlighted — unchanged.
    init(routines: [Routine], initialRoutine: Routine?) {
        _routines = State(initialValue: routines)
        self.initialRoutine = initialRoutine
        _chosenRoutine = State(initialValue: initialRoutine)
    }

    // Redesign (user feedback 2026-07-21: the picker didn't follow the app's
    // language, and a no-routines user hit a dead end): Onyx card rows in a
    // ScrollView — freestyle card, routine cards with a selected ring — plus
    // a "Build Routine" top action ALWAYS available, and a card-anchored
    // empty state whose CTA routes into the real RoutineBuilderView.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Freestyle — always first.
                    pickCard(
                        icon: "bolt.fill",
                        title: "Freestyle",
                        subtitle: "No routine — log whatever you lift",
                        selected: false
                    ) {
                        Task { await start(routine: nil) }
                    }
                    .padding(.top, 6)

                    if routines.isEmpty {
                        GSEmptyState(
                            icon: "list.bullet.rectangle",
                            title: "No routines yet",
                            message: "Build a routine once and start it with one tap every session after.",
                            ctaTitle: "Build a routine",
                            action: { showBuilder = true }
                        )
                        .padding(.top, 14)
                    } else {
                        GSSectionHeader("Your routines")
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        VStack(spacing: 8) {
                            ForEach(routines) { routine in
                                let isSelected = routine.id == chosenRoutine?.id
                                pickCard(
                                    icon: "list.bullet",
                                    title: routine.name,
                                    subtitle: nil,
                                    selected: isSelected
                                ) {
                                    Task { await start(routine: routine) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBuilder = true
                    } label: {
                        Text("Build Routine")
                            .font(GSFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .navigationDestination(isPresented: $showBuilder) {
                RoutineBuilderView(editing: nil) { newRoutine in
                    routines.insert(newRoutine, at: 0)
                    chosenRoutine = newRoutine
                    showBuilder = false
                }
            }
            .navigationDestination(isPresented: $startNavigation) {
                WorkoutSessionView(routine: chosenRoutine,
                                   routineExercises: routineExercises,
                                   allExercises: allExercises,
                                   // Finishing must close this whole SHEET,
                                   // not just pop back to the picker the
                                   // lifter chose from (user report
                                   // 2026-07-28). `dismiss()` inside the
                                   // pushed session only pops the push, so
                                   // the sheet's own dismiss is handed down.
                                   onFinished: { dismissPicker() })
            }
        }
    }

    private func pickCard(icon: String, title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.neutral300)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(14)
            .frame(minHeight: 44)
            .overlay(
                selected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.accent, lineWidth: 2)
                    : nil
            )
            .contentShape(Rectangle())
        }
        // gs3D pass (2026-08-13): the flat surface rows become sinking
        // extruded cards — the label sheds its own fill so it can't paint
        // over the face; the selected accent ring rides as an overlay.
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
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

// MARK: - WeeklyGoalSheet (2026-08-11)

// The intraweek widget's goal editor: sessions per week, 1–14, saved to
// profiles.weekly_session_goal (20260811000003).
private struct WeeklyGoalSheet: View {
    let initial: Int
    let onSaved: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @State private var goal: Int
    @State private var saving = false
    @State private var errorText: String?

    init(initial: Int, onSaved: @escaping (Profile) -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        _goal = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("How many days a week are you holding yourself to?")
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Stepper(value: $goal, in: 1...14) {
                    Text("\(goal) DAY\(goal == 1 ? "" : "S") / WEEK")
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                }
                // Anti-goalpost rule (owner 2026-08-12) — say it up front so
                // the unchanged widget doesn't read as a save failure.
                Text("Takes effect next week. This week's goal stays locked — no moving the goalposts mid-week.")
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "SAVING…" : "SET THE GOAL")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(saving)
                Spacer()
            }
            .padding(16)
            .background(theme.bg)
            .navigationTitle("Weekly Goal")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let updated = try await ProfileRepository.updateWeeklySessionGoal(goal)
            onSaved(updated)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
