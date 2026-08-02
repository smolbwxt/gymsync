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
                // Declutter round (user feedback 2026-07-21): stat tiles
                // removed (Stats tab owns the numbers), schedule promoted to
                // its own widget above the calendar, calendar extended.
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    replayFailureNotice
                    primaryCTASection
                    checkInAndStreakRow
                    scheduleWidget
                    calendarWidget
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
            .gsSpotlight(.home)
            .task {
                await refresh()
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
            .sheet(isPresented: $showRoutinePicker) {
                RoutinePickerSheet(routines: ownedRoutines, initialRoutine: routinePickerPreselected)
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
            // Same 30-min missed cutoff as the check-in widget: a missed
            // session must not keep the "Join …" hero alive all day.
            guard session.state == "in_progress" || Date.now <= when.addingTimeInterval(30 * 60) else { return false }
            return Calendar.current.isDateInToday(when)
        }
    }

    @ViewBuilder
    private var primaryCTASection: some View {
        VStack(spacing: 9) {
            if let session = todaysSession {
                NavigationLink {
                    // .id — see navigateToJoined's destination comment: the
                    // computed session re-resolving must rebuild the lobby,
                    // never mutate a pushed one in place.
                    LobbyView(session: session)
                        .id(session.id)
                } label: {
                    ctaCard(
                        title: "Join \(routineLabel(for: session))",
                        subtitle: ctaSubtitle(for: session)
                    )
                }
                .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: GSMetrics.radiusMd))
            }
            // ONE architecture in every state (user 2026-07-31: "I don't
            // think we should change the widget architecture at all from
            // pre-check-in to post"): the solo start is ALWAYS this pill
            // row, the burpee debt always emerges beside it when owed, and
            // only the Join hero comes and goes with an actual session.
            // (Replaces the old no-session branch's big Start Solo Workout
            // hero — the morph between the two shapes was the complaint.)
            soloSecondaryButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // Declutter round: the solo start is a LITTLE BIGGER everywhere it
    // appears (user feedback) — taller hero card, larger play circle, and a
    // weightier secondary button.
    //
    // 2026-08 visual-language pass: the hero is a BUTTON, so it wears the
    // extruded 3D style on the theme's raised face (theme.surface was
    // invisible as 3D against the page ground — owner field report);
    // vertical padding drops 22 → 18.5 so content + 37 + the 7pt lip keeps
    // the card's exact prior footprint. Subtitle rides neutral700 — the
    // lighter raised face washed out neutral500.
    private func ctaCard(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GSFont.bold(19, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Circle()
                .fill(theme.accent)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.bg)
                        .offset(x: 1)
                )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18.5)
    }

    // Redesign fix (2026-07-23 screenshot): the solo button read as a
    // translucent outline pill among solid widgets — now it IS a widget:
    // solid surface fill, widget radius, no border.
    private var soloSecondaryButton: some View {
        // Burpee debt (user direction 2026-07-25): when you owe burpees, the
        // start button CONCEDES real estate and the counter EMERGES beside
        // it — Duolingo-style, springy rather than a hard swap. At zero debt
        // the widget doesn't exist at all, so it never taxes a new user's
        // home screen (burpee debt is group-scoped: a brand-new user owes
        // nothing by construction).
        HStack(spacing: 10) {
            Button {
                routinePickerPreselected = nil
                showRoutinePicker = true
            } label: {
                HStack(spacing: 7) {
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    // Always "solo" (user 2026-07-31: dropping the word when
                    // the debt badge appeared made the widget ambiguous —
                    // it fits fine beside the 96pt badge).
                    Text("Start solo workout")
                        .font(GSFont.bold(15, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.text)
                // 55pt face + the style's 7pt lip = exactly the row's fixed
                // 62pt — the pill and the burpee badge stay shoulder-to-
                // shoulder (the badge still fills the row flat: it's a
                // status widget, not a CTA).
                .frame(height: 55)
                .contentShape(Rectangle())
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: GSMetrics.radiusMd))
            .gsSpotlightTarget(.home)

            if burpeesOwed > 0 {
                burpeeOwedWidget
                    // Emerges from the right edge with a slight scale pop —
                    // the button's width animates in the same transaction,
                    // so it reads as one element yielding space to another.
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .trailing)
                                .combined(with: .opacity)
                                .combined(with: .move(edge: .trailing)),
                            removal: .scale(scale: 0.7, anchor: .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
        // One fixed row height so the start pill and the debt badge stand
        // shoulder-to-shoulder (user 2026-07-31: the pill sat visibly
        // shorter than the badge beside it).
        .frame(height: 62)
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: burpeesOwed > 0)
    }

    /// The debt counter. Fixed width so the start button's concession is a
    /// predictable amount rather than a text-length-dependent jitter.
    /// 3D pass (2026-08): STATIC extrusion — it's a status widget, not a
    /// CTA, so it doesn't sink; accent face + derived darker lip (accent
    /// reads in every palette). lipHeight 7 — the solo pill beside it is a
    /// 55pt face on a 7pt lip, so a 7pt lip here lands both face/lip seams
    /// on the same line inside the row's fixed 62pt.
    private var burpeeOwedWidget: some View {
        Button {
            showBurpeeLedger = true
        } label: {
            VStack(spacing: 1) {
                Text("\(burpeesOwed)")
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.bg)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("burpees")
                    .font(GSFont.bold(9.5, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(theme.bg.opacity(0.8))
            }
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            // Accent, not gold (user 2026-07-31): gold is the CHECK-IN
            // signal color and nothing else gets to wear it. Accent =
            // "yours to act on" — a debt is exactly that.
            .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 7, face: theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You owe \(burpeesOwed) burpees. Open the burpee ledger.")
    }

    // MARK: - Schedule widget (declutter round: its own widget above the calendar)

    private var scheduleWidget: some View {
        Button {
            showScheduleSheet = true
        } label: {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.neutral300)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule a session")
                        .font(GSFont.bold(15.5, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Plan your next lift — solo or with a crew")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gsDiscovery(.homeSchedule)
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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

    // MARK: - Check-in + Streak row (redesign v2, user feedback 2026-07-21)
    //
    // The PR widget was replaced: Home's hero pair is forward-looking now.
    // PRs still celebrate via the full-screen overlay at the moment they
    // happen and live permanently on Stats — a backward-looking trophy was
    // the least useful thing in this slot. The check-in widget shows the
    // NEXT session with a live countdown, and flips into an accent "Check
    // in" action the moment the session is actually joinable (lobby_open /
    // in_progress — check-in opens when the organizer opens the lobby, an
    // event, so the countdown targets the scheduled start and the button
    // activates on live state).
    //
    // Equal heights: both cards' content stretches to `maxHeight: .infinity`
    // inside an HStack that is `fixedSize(vertical: true)` — the row sizes to
    // the taller card and the shorter one fills to match (the v1 mismatch was
    // exactly this missing constraint).

    private static let streakMilestones = [7, 14, 30, 60, 100, 365]

    private var checkInAndStreakRow: some View {
        HStack(alignment: .top, spacing: 11) {
            checkInWidget
            streakWidget
        }
        .fixedSize(horizontal: false, vertical: true)
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

    /// Gold ready-state palette — a STATUS color, deliberately independent of
    /// the user's accent (spec §4's two-color-system discipline: status is a
    /// third, fixed semantic).
    private static let goldTop = Color.gsHex(0xF6C945)
    private static let goldBottom = Color.gsHex(0xDCA426)
    private static let goldInk = Color.gsHex(0x261A02)

    @State private var checkInShimmer = false

    @ViewBuilder
    private var checkInWidget: some View {
        // TimelineView OUTERMOST (missed-cutoff fix): the candidate itself is
        // re-selected every 30s, so a session that crosses the 30-min missed
        // line drops out live — the gold shimmer can no longer run forever on
        // an event nobody started.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            // 3D pass (2026-08): every state of this slot is an extruded
            // card that sinks on press (`.gs3DCardStyle`) — the two links
            // are split so the gold state can wear its own gold face
            // (derived darker lip, the accent-face path) while the
            // countdown/empty states ride the theme's raised pair.
            if let session = nextActionableSession(now: context.date) {
                if checkInAvailable(session, now: context.date) {
                    NavigationLink {
                        // .id — the TimelineView re-resolves this session
                        // every 30s; a pushed lobby must be rebuilt, not
                        // re-propped (the exact route that wrote 14 sets
                        // into a scheduled future occurrence, field bug
                        // 2026-07-30/31).
                        LobbyView(session: session)
                            .id(session.id)
                    } label: {
                        goldCheckInCard(session)
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd,
                                                face: Self.goldBottom))
                } else {
                    NavigationLink {
                        // .id — same rebuild-not-reprop rule as above.
                        LobbyView(session: session)
                            .id(session.id)
                    } label: {
                        countdownBody(session, now: context.date)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(15)
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                }
            } else {
                // Empty state is a POINTER, not a dead card (user feedback
                // 2026-07-25): with nothing scheduled, this slot offers the
                // step that's actually missing. Deliberately NOT gold —
                // gold means "the window is open, act now", and borrowing
                // that urgency for an invitation would devalue it.
                Button {
                    if hasNoCrew { appState.selectedTab = .social }
                    else { showScheduleSheet = true }
                } label: {
                    checkInEmptyBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(15)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
            }
        }
    }

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

    /// Scheduling is offered ahead of finding a crew whenever the user has
    /// any routine to run: a solo lift is achievable alone in the next hour,
    /// while joining a crew depends on other people. Someone with neither a
    /// crew nor a routine gets pointed at people first — a brand-new user
    /// with nothing to run benefits more from a group than an empty calendar.
    private var hasNoCrew: Bool { groups.isEmpty && ownedRoutines.isEmpty }

    /// The gold shimmering ready-state (user feedback 2026-07-23): when the
    /// 20-minute window opens, the whole widget turns gold with a slow
    /// diagonal shimmer sweep — unmissable "you can act now".
    private func goldCheckInCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                Text("CHECK-IN OPEN")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.3)
            }
            .foregroundStyle(Self.goldInk.opacity(0.75))

            Text(routineLabel(for: session))
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(Self.goldInk)
                .lineLimit(1)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Text("Check in")
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.gsHex(0xFFE9A8))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Self.goldInk)
            .cornerRadius(11)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(15)
        // 3D pass: the gradient stays the card's visible face — it sits
        // exactly over the style's solid goldBottom face plate, whose only
        // remaining jobs are the derived dark-amber lip and the sink. The
        // style's clipShape rounds gradient + shimmer together (this
        // replaces the old .cornerRadius here).
        .background(
            LinearGradient(colors: [Self.goldTop, Self.goldBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        // Shimmer: a soft diagonal highlight band sweeping across every ~2.4s.
        .overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.4), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .rotationEffect(.degrees(22))
                    .offset(x: checkInShimmer ? geo.size.width + 90 : -140)
                    .animation(.linear(duration: 2.4).repeatForever(autoreverses: false),
                               value: checkInShimmer)
            }
            .allowsHitTesting(false)
        )
        .onAppear { checkInShimmer = true }
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

    @ViewBuilder
    private func countdownBody(_ session: WorkoutSession, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text("NEXT SESSION")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.3)
            }
            .foregroundStyle(theme.accent)

            Text(routineLabel(for: session))
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.top, 8)

            if let opensAt = checkInOpensAt(session), opensAt > now {
                Text(compactCountdown(to: opensAt, from: now))
                    .font(GSFont.heading(30, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                    .padding(.top, 5)
                Text("until check-in · opens \(opensAt.formatted(date: .omitted, time: .shortened))")
                    .font(GSFont.body(10.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
                    .padding(.top, 3)
            } else {
                // Window has passed but state hasn't flipped live yet.
                Text("Starting soon")
                    .font(GSFont.heading(18, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .padding(.top, 8)
                Text("waiting for the organizer")
                    .font(GSFont.body(10.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
    }

    private var checkInEmptyBody: some View {
        // Redesign (2026-07-25): was a quiet "Nothing scheduled" dead end.
        // Now it names the next step and is tappable — see checkInWidget.
        let crewFirst = hasNoCrew
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: crewFirst ? "person.2" : "calendar.badge.plus")
                    .font(.system(size: 10, weight: .bold))
                Text(crewFirst ? "GET STARTED" : "NEXT SESSION")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.3)
            }
            .foregroundStyle(theme.neutral500)

            Text(crewFirst ? "Find your crew" : "Schedule a workout")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .padding(.top, 9)

            Text(crewFirst
                 ? "Train with friends — shared sessions and live turns."
                 : "Pick a day and a routine, then check in when you arrive.")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            HStack(spacing: 5) {
                Text(crewFirst ? "Go to Social" : "Schedule")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.accent)
            .padding(.top, 8)
        }
    }

    /// No widget renders a bare zero (user feedback 2026-07-25: a new user's
    /// home shouldn't open by scoring them on a game they haven't started).
    /// Instead the streak card becomes an invitation — and "never trained"
    /// and "streak lapsed" are deliberately DIFFERENT invitations: telling
    /// someone who trained for three weeks to "schedule your first lift"
    /// would be both wrong and a little insulting.
    private var streakWidget: some View {
        let current = userStreak?.currentStreak ?? 0
        if current == 0 {
            return AnyView(streakInviteWidget(hasTrainedBefore: hasEverTrained))
        }
        return AnyView(streakCountWidget(current: current))
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

    private func streakCountWidget(current: Int) -> some View {
        // BUG FIX (spotted in the 2026-07-25 CI capture: the test account's
        // 627-day streak rendered "-262 to badge"): once a streak passes the
        // LAST milestone there is no next one, and the old
        // `?? streakMilestones.last!` fallback subtracted a smaller number
        // from a bigger one. Past every badge the ring is simply full and
        // the subtitle celebrates instead of counting down to the past.
        let next = Self.streakMilestones.first(where: { $0 > current })
        let progress = next.map { min(1, Double(current) / Double($0)) } ?? 1
        // Static extrusion — the count card isn't tappable, so it sits
        // still while its invite sibling (a Button) sinks. Same radius/lip
        // as the check-in card beside it, so the fixedSize row's equal
        // heights land on equal FACE heights too.
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(theme.neutral300, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "flame.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(current)")
                    .font(GSFont.heading(24, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Text("day streak")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                Text(next.map { "\($0 - current) to badge" } ?? "every badge earned")
                    .font(GSFont.bold(10.5, relativeTo: .caption2))
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(15)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(next.map { "\(current) day streak, \($0 - current) days to the next badge" }
                            ?? "\(current) day streak, every badge earned")
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
        lastRefreshedAt = .now
        let userID = appState.currentProfile?.id

        // Single parallel batch: all 8 fetches are declared up front so they
        // all start together (cost = max of all 8, not wave1 + wave2). Each
        // fetch keeps the same best-effort isolation as before — failures
        // are swallowed independently and stale data is left in place.
        async let sessionsFetch  = SessionRepository.upcoming()
        async let groupsFetch    = GroupRepository.myGroups()
        async let historyFetch   = fetchHistory(userID: userID)
        async let routinesFetch  = fetchOwnedRoutines(userID: userID)
        async let prCountFetch   = fetchPRCountThisMonth(userID: userID)
        async let profileFetch   = fetchProfile(userID: userID)
        async let campaignsFetch = fetchActiveCampaigns(userID: userID)
        async let streakFetch    = fetchStreak(userID: userID)

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

        // ── single commit (no awaits until after this block) ──
        if let sessions { upcomingSessions = sessions }
        if let fetchedGroups { groups = fetchedGroups }
        if let history { historySessions = history }
        if let routines { ownedRoutines = routines }
        if let prCount { prsThisMonth = prCount }
        if let refreshedProfile { profile = refreshedProfile }
        activeCampaigns = campaigns ?? []
        if let streak { userStreak = streak }
        statsLoading = false

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
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .overlay(
                selected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.accent, lineWidth: 2)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
