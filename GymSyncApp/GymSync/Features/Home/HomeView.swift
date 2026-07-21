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
    /// Redesign: feeds the streak-ring widget (proof: ring fills toward the
    /// next milestone). Fetched alongside the other Home data in `refresh()`.
    @State private var userStreak: UserStreak?
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
                // Redesign (all-tabs proof): bento of floating widgets on the
                // Onyx ground — consistent 12pt rhythm, no full-width divider
                // rules between sections. Every data/action path from the old
                // layout is preserved; only the arrangement changed.
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    replayFailureNotice
                    primaryCTASection
                    prAndStreakRow
                    calendarWidget
                    if !activeCampaigns.isEmpty {
                        campaignsSection
                    }
                    statTileRow
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

    // MARK: - Primary CTA (redesign: context-aware + persistent solo)
    //
    // Smart primary: when a session is scheduled TODAY, the hero card is
    // "Join {session}" (NavigationLink → LobbyView — the app's single session
    // entry point); the persistent "Start solo workout" secondary sits right
    // beneath it so a spontaneous lift is always one predictable tap. When
    // nothing is on today, the hero IS the solo start (today's-routine info
    // folded into its subtitle — absorbs the old standalone routine card).

    private var todaysSession: WorkoutSession? {
        upcomingSessions.first { session in
            guard let when = session.scheduledFor else { return false }
            return Calendar.current.isDateInToday(when)
        }
    }

    @ViewBuilder
    private var primaryCTASection: some View {
        VStack(spacing: 9) {
            if let session = todaysSession {
                NavigationLink {
                    LobbyView(session: session)
                } label: {
                    ctaCard(
                        title: "Join \(routineLabel(for: session))",
                        subtitle: ctaSubtitle(for: session)
                    )
                }
                .buttonStyle(.plain)
                soloSecondaryButton
            } else {
                Button {
                    routinePickerPreselected = todaysRoutine
                    showRoutinePicker = true
                } label: {
                    ctaCard(title: "Start Solo Workout", subtitle: soloSubtitle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func ctaCard(title: String, subtitle: String) -> some View {
        GSCard(bordered: false) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(GSFont.bold(17, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(GSFont.body(12.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.bg)
                            .offset(x: 1)
                    )
            }
            .padding(18)
        }
        .contentShape(Rectangle())
    }

    private var soloSecondaryButton: some View {
        Button {
            routinePickerPreselected = nil
            showRoutinePicker = true
        } label: {
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Start solo workout")
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.text)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.divider, lineWidth: 1)
        )
    }

    private func ctaSubtitle(for session: WorkoutSession) -> String {
        let who = session.groupID.flatMap { gid in groups.first(where: { $0.id == gid })?.name } ?? "Session"
        if let when = session.scheduledFor {
            return "\(who) · \(when.formatted(.dateTime.hour().minute()))"
        }
        return who
    }

    private var soloSubtitle: String {
        if let routine = todaysRoutine {
            return "\(routine.name) · \(todaysRoutineExercises.count) exercises · ~\(StatMath.estimatedMinutes(exerciseCount: todaysRoutineExercises.count)) min"
        }
        return "Pick a routine or go freestyle"
    }

    // MARK: - PR + Streak row (redesign: the hero pair)

    private static let streakMilestones = [7, 14, 30, 60, 100, 365]

    private var prAndStreakRow: some View {
        HStack(alignment: .top, spacing: 11) {
            prWidget
            streakWidget
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var prWidget: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let pr = recentPRs.first {
                    let exerciseName = allExercises.first(where: { $0.id == pr.exerciseID })?.name ?? "Exercise"
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("NEW PR")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.3)
                    }
                    .foregroundStyle(theme.accent)
                    Text(exerciseName)
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .padding(.top, 8)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(trimmedDecimal(pr.weight))
                            .font(GSFont.heading(27, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                        Text("lbs")
                            .font(GSFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.top, 5)
                    Text("\(pr.reps) reps · +\(trimmedDecimal(pr.weight - pr.previousBest)) on your best")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .padding(.top, 4)
                } else {
                    // Null state (spec §6): card-anchored, inviting, no CTA —
                    // the start action is directly above in the hero.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.neutral300)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "flame.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.accent)
                        )
                    Text("No PRs yet")
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .padding(.top, 9)
                    Text("Log a lift and your first personal record lands here.")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }

    private var streakWidget: some View {
        let current = userStreak?.currentStreak ?? 0
        let next = Self.streakMilestones.first(where: { $0 > current }) ?? Self.streakMilestones.last!
        let progress = min(1, Double(current) / Double(next))
        return GSCard(bordered: false) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(theme.neutral300, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(current > 0 ? theme.accent : theme.neutral500)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(current)")
                        .font(GSFont.heading(24, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text("day streak")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                    Text(current > 0 ? "\(next - current) to badge" : "start one today")
                        .font(GSFont.bold(10.5, relativeTo: .caption2))
                        .foregroundStyle(current > 0 ? theme.accent : theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current) day streak, \(next - current) days to the next badge")
    }

    // MARK: - Training calendar (redesign: replaces the Upcoming list)

    private var calendarWidget: some View {
        TrainingCalendarWidget(
            completedSessions: historySessions,
            upcomingSessions: upcomingSessions,
            groups: groups,
            titleFor: { routineLabel(for: $0) },
            onSchedule: { showScheduleSheet = true },
            onFindCrew: { appState.selectedTab = .social }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
            .buttonStyle(.plain)
        } else {
            campaignCardBody(campaign, joined: false)
        }
    }

    private func campaignCardBody(_ campaign: Campaign, joined: Bool) -> some View {
        GSCard(bordered: false) {
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
                        Text("Community: \(trimmedDecimal(community.volumeLifted)) lbs")
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

    // (Redesign: the old standalone "+ Schedule Session" button and the
    // "Upcoming Sessions" list were absorbed into `TrainingCalendarWidget` —
    // the calendar header carries the schedule action, and upcoming sessions
    // render as group-avatared rows inside the widget.)

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
        async let campaignsFetch = fetchActiveCampaigns(userID: userID)
        async let streakFetch    = fetchStreak(userID: userID)

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
        let campaigns = await campaignsFetch
        activeCampaigns = campaigns ?? []
        if let streak = await streakFetch { userStreak = streak }
        await loadCampaignJoinState(for: activeCampaigns)

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
