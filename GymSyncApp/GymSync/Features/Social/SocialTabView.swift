import SwiftUI

struct SocialTabView: View {
    @State private var groups: [GymGroup] = []
    @State private var unread: Set<UUID> = []
    /// Crew-widget bar meta per group (owner 2026-08-12) — fed by refresh().
    @State private var barByGroup: [UUID: CrewBarMeta] = [:]
    @State private var previews: [UUID: String] = [:]
    @State private var friendCount = 0
    @State private var pendingCount = 0
    /// Redesign: per-group `group_stats` aggregates feeding the hub hero
    /// ("your crews have moved X lbs") and each group card's volume meta.
    @State private var showCreateGroup = false
    // Also doubles as the "did the last groups load fail" flag (Canvas
    // Completion Task 4) — it's already a String? set from `refresh()`'s
    // catch block, so a second dedicated Bool would just duplicate it.
    @State private var errorText: String?
    @State private var friendRealtime = FriendRealtimeService()
    // Canvas Completion Task 4 — drives the "Reconnecting…" pill below.
    @State private var connectivity = ConnectivityMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    // Push deep-link routing (Phase 3d Task 5) — programmatic navigation
    // targets consumed from `appState.pendingRoute`.
    @State private var pendingChatGroup: GymGroup?
    @State private var navigateToFriends = false
    // Canvas Completion Task 4 fix round 1 — the full-tab "No crew yet"
    // moment's CTA navigates through this SEPARATE destination (rather than
    // reusing `navigateToFriends`, which also serves the push-route deep
    // link and must keep landing on a plain, unfocused `FriendsView()`) so
    // only this specific entry point focuses the add-friend field.
    @State private var navigateToFriendsFocused = false
    /// Staleness bookkeeping for the retained-tab refresh (RootView holds
    /// every visited tab alive, so `.task` fires once per app run).
    @State private var lastRefreshedAt: Date = .distantPast

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Redesign v2: in-content title replaces the nav-bar title.
                        Text("Crews")
                            .font(GSFont.heading(24, relativeTo: .title))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        // Offline pill (Canvas Completion Task 4 — proof
                        // p30-empty-offline). Anchored at the top of this
                        // screen's content, matching the canvas frame — see
                        // ConnectivityMonitor.swift's doc comment for why this
                        // isn't a RootView-wide overlay.
                        if !connectivity.isOnline {
                            GSOfflineBanner()
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                        }

                        // Canvas Completion Task 4 fix round 1 (proof
                        // p30-empty-offline, full-tab "No crew yet" moment):
                        // when there are truly NO friends AND NO groups, the
                        // proof draws a single full-screen centered empty
                        // state instead of the Friends row + Groups section —
                        // there's nothing for either to summarize yet. Gated
                        // on `errorText == nil` so an actual load failure
                        // still surfaces via the existing GSErrorCard path
                        // below (in the `else` branch) rather than being
                        // masked by this friendlier empty state.
                        if groups.isEmpty && friendCount == 0 && errorText == nil {
                            // Redesign v2 (user feedback 2026-07-21): TOP-anchored
                            // — the card-anchored empty state sits right under the
                            // title like any other content (the old ~28%-viewport
                            // spacer was a leftover from the centered-float era).
                            GSEmptyState(
                                icon: "person.2",
                                title: "No crew yet",
                                message: "Add a friend by username or start a group — then take turns on the bar together.",
                                ctaTitle: "Add your first friend",
                                action: { navigateToFriendsFocused = true }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            // (Recorded deviation: the proof's secondary "Enter a
                            // room code" link stays omitted — no such feature
                            // exists for friends/groups; HomeView's session
                            // join-by-code is an unrelated domain.)

                            Spacer(minLength: 0)
                        } else {
                            // Owner 2026-08-13: the crews ARE the tab — the
                            // cumulative-stats hero is gone and "Your crews"
                            // leads, with the Friends/Feed/Local hub rows
                            // demoted below the crew list.
                            GSSectionHeader("Your crews")
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            // Canvas Completion Task 4 (proof p30/p31): the blank-list
                            // error card only replaces the plain empty state when the
                            // list is ACTUALLY blank because the load failed — a
                            // refresh failure with existing groups on screen leaves
                            // them in place (best-effort, unchanged) and only surfaces
                            // the small red caption below.
                            //
                            // Fix round 1: this compact "No groups yet" card is now
                            // only reachable for the groups-empty-but-has-friends
                            // case — the both-empty case is handled by the full-tab
                            // moment above.
                            if groups.isEmpty {
                                if errorText != nil {
                                    GSErrorCard(
                                        title: "Couldn't load your groups",
                                        message: errorText ?? "Check your connection and try again.",
                                        retry: { Task { await refresh() } }
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                } else {
                                    GSEmptyState(
                                        icon: "person.3",
                                        title: "No crews yet",
                                        message: "Start a crew — then take turns on the bar together.",
                                        ctaTitle: "+ New Crew",
                                        action: { showCreateGroup = true }
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                }
                            }

                            VStack(spacing: 8) {
                                ForEach(groups) { group in
                                    NavigationLink {
                                        // Crew room (v7.4 design handoff) — the
                                        // group's front page; GroupView survives
                                        // behind its MANAGE toolbar item.
                                        CrewRoomView(group: group)
                                    } label: {
                                        groupRow(group)
                                    }
                                    // 3D pass (2026-08 sweep): group rows sink
                                    // like the hub rows above.
                                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                                    .padding(.horizontal, 16)
                                }
                            }

                            // New Group button — hidden in the true empty case since
                            // GSEmptyState above already surfaces an equivalent "+ New
                            // Group" CTA (avoids showing the same action twice). Still
                            // shown during the blank-list-plus-error case (GSErrorCard
                            // has no group-creation CTA of its own) and whenever the
                            // list has content.
                            if !groups.isEmpty || errorText != nil {
                                Button {
                                    showCreateGroup = true
                                } label: {
                                    Text("+ New Crew")
                                }
                                .buttonStyle(GSSecondaryButtonStyle())
                                .gsSpotlightTarget(.social)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            }

                            // Friends row (redesign: rounded card row) —
                            // now BELOW the crew list with Feed/Local.
                            NavigationLink {
                                FriendsView()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(theme.text)
                                    Text("Friends")
                                        .font(GSFont.bold(14, relativeTo: .headline))
                                        .foregroundStyle(theme.text)
                                    Spacer()
                                    if pendingCount > 0 {
                                        GSTag(text: "\(pendingCount) new", style: .accent)
                                    }
                                    Text("\(friendCount)")
                                        .font(GSFont.body(13, relativeTo: .subheadline))
                                        .foregroundStyle(theme.neutral500)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            // 3D pass (2026-08 sweep): tappable hub row —
                            // extruded face + lip + press-sink. The old
                            // `.background(theme.surface).cornerRadius(...)`
                            // is gone: the style paints the face (flat
                            // surface over it would hide the extrusion).
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                            // Pump Check feed row (spec 2026-07-27, P3) —
                            // same card idiom as Friends/Local. Pushes the
                            // full feed; posts are friends-only by RLS.
                            NavigationLink {
                                PumpFeedView()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(theme.text)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Feed")
                                            .font(GSFont.bold(14, relativeTo: .headline))
                                            .foregroundStyle(theme.text)
                                        Text("Pump checks from your friends")
                                            .font(GSFont.body(11, relativeTo: .caption))
                                            .foregroundStyle(theme.neutral500)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            // 3D pass (2026-08 sweep) — see the Friends row.
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                            .gsDiscovery(.socialFeed, cornerRadius: GSMetrics.radiusSm)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Local hubs row (Venue Hubs H1) — the spec's
                            // "Social tab gets a Local section" (:691),
                            // mirroring the Friends row's card idiom above.
                            NavigationLink {
                                LocalHubsView()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(theme.text)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Local")
                                            .font(GSFont.bold(14, relativeTo: .headline))
                                            .foregroundStyle(theme.text)
                                        Text("Who's at your gym")
                                            .font(GSFont.body(11, relativeTo: .caption))
                                            .foregroundStyle(theme.neutral500)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            // 3D pass (2026-08 sweep) — see the Friends row.
                            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                            .gsDiscovery(.socialLocal, cornerRadius: GSMetrics.radiusSm)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)

                            // Non-blank-list case only — the blank-list case already
                            // surfaced this same message via GSErrorCard above, so
                            // showing it again here would be redundant.
                            if let errorText, !groups.isEmpty {
                                Text(errorText)
                                    .font(GSFont.body(12, relativeTo: .footnote))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    // `alignment: .top` is LOAD-BEARING (user bug report:
                    // "starts correctly then snaps to center-center"): a bare
                    // .frame(minHeight:) centers content shorter than the
                    // frame, so the empty state jumped to vertical center the
                    // moment loading resolved. Top-pin it.
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                // Dock clearance (user bug report): bottom margin so the tab
                // dock never clips the last content.
                .contentMargins(.bottom, 88, for: .scrollContent)
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)   // redesign v2: in-content title above
            .gsSpotlight(.social)
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { newGroup in
                    groups.insert(newGroup, at: 0)
                }
            }
            .task {
                await refresh()
                if let me = await SupabaseService.shared.currentUserID() {
                    await friendRealtime.subscribe(userID: me) {
                        Task { await refresh() }
                    }
                }
                await consumePendingRouteIfNeeded()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await refresh()
                    if let me = await SupabaseService.shared.currentUserID() {
                        await friendRealtime.subscribe(userID: me) {
                            Task { await refresh() }
                        }
                    }
                }
            }
            .onChange(of: appState.pendingRoute) {
                Task { await consumePendingRouteIfNeeded() }
            }
            // Tab retention (RootView): `.task` no longer re-fires per tab
            // switch, so re-selection refreshes on a TTL instead. Note the
            // `.onDisappear` below now only fires on real teardown (sign-out
            // / app exit), NOT on tab switches — which is the better
            // behavior here: the friend-request subscription stays live
            // while you're on other tabs instead of churning per switch.
            .onChange(of: appState.selectedTab) {
                guard appState.selectedTab == .social,
                      Date.now.timeIntervalSince(lastRefreshedAt) > 60 else { return }
                Task { await refresh() }
            }
            .onDisappear { Task { await friendRealtime.unsubscribe() } }
            .refreshable { await refresh() }
            .navigationDestination(item: $pendingChatGroup) { group in
                // Chat push deep link lands on the crew room (chat is one tap
                // in) — same destination as the group rows above.
                CrewRoomView(group: group)
            }
            .navigationDestination(isPresented: $navigateToFriends) {
                FriendsView()
            }
            // Canvas Completion Task 4 fix round 1 — separate destination
            // (see `navigateToFriendsFocused`'s declaration) so only the
            // full-tab "No crew yet" CTA lands with the add-friend field
            // focused; the push-route deep link above is untouched.
            .navigationDestination(isPresented: $navigateToFriendsFocused) {
                FriendsView(focusAddFieldOnAppear: true)
            }
        }
    }

    // MARK: - Push deep-link routing (Phase 3d Task 5)

    /// Consumes `.chat`/`.friends`. Clears `pendingRoute` immediately so a
    /// later `.onChange` firing (or this `.task` re-running) doesn't
    /// re-navigate. `.chat`'s group fetch can legitimately come back empty
    /// (e.g. the user left the group between the push firing and the tap) —
    /// silently no-ops rather than surfacing an error for that edge case.
    private func consumePendingRouteIfNeeded() async {
        switch appState.pendingRoute {
        case .friends:
            appState.pendingRoute = nil
            navigateToFriends = true
        case .chat(let groupID):
            appState.pendingRoute = nil
            let groups = (try? await GroupRepository.fetchMany(ids: [groupID])) ?? []
            pendingChatGroup = groups.first
        default:
            break
        }
    }

    /// Per-crew bar meta for the widget (owner 2026-08-12: "each group
    /// should have its own separate widget, with the bar represented to
    /// denote progress from a distance"). Same derivation as CrewRoomView's
    /// routines-together card — the glance and the room never disagree.
    struct CrewBarMeta: Sendable {
        let completedThisWeek: Int
        let plannedThisWeek: Int
        let nextLift: Date?
    }

    /// Crew widget (replaces the old chat-preview row, owner 2026-08-12):
    /// name row + the crew's iron rendered small + a next-lift meta line.
    /// Remaining work is bare sleeve, never ghost plates (standing
    /// decision) — the count lives in the meta line. Chat is one tap away
    /// in the room.
    private func groupRow(_ group: GymGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                GSInitialsAvatar(
                    name: group.name,
                    avatarURL: group.avatarURL,
                    size: 28,
                    fill: GSGroupColor.color(for: group.id),
                    ink: GSGroupColor.onColor(for: group.id)
                )
                Text(group.name)
                    .font(GSFont.bold(14.5, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if unread.contains(group.id) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 9, height: 9)
                }
            }

            crewBar(completed: barByGroup[group.id]?.completedThisWeek ?? 0)

            Text(crewMetaLine(group))
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .kerning(0.8)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // 3D pass (2026-08 sweep): chrome comes from the NavigationLink's
        // `.gs3DCardStyle` — this is the LABEL only (a flat surface fill
        // here would paint over the extruded face).
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The room's iron at widget scale: collar, the crew's shared plates
    /// (uniform iron, one per routine completed together this week), bare
    /// sleeve for the work remaining.
    private func crewBar(completed: Int) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.neutral500.opacity(0.55))
                .frame(height: 5)
            HStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.neutral500)
                    .frame(width: 6, height: 16)
                ForEach(0..<min(completed, 10), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gsHex(0x53585F))
                        .frame(width: 7, height: 20)
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1.5)
                }
            }
        }
        .frame(height: 22)
    }

    private func crewMetaLine(_ group: GymGroup) -> String {
        let meta = barByGroup[group.id]
        let done = meta?.completedThisWeek ?? 0
        let together = "\(done) TOGETHER THIS WK"
        if let next = meta?.nextLift {
            let when = next.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return "\(together) · NEXT LIFT \(when.uppercased())"
        }
        return "\(together) · NO LIFT SCHEDULED"
    }

    private func refresh() async {
        lastRefreshedAt = .now
        do {
            groups = try await GroupRepository.myGroups()
            friendCount = try await FriendRepository.friends().count
            pendingCount = try await FriendRepository.incomingRequests().count
            let currentGroups = groups

            // Single latest-message fetch per group feeds both the unread badge
            // and the preview line (was 2 fetches/group across two task groups).
            var unreadIDs: Set<UUID> = []
            var previewsByGroup: [UUID: String] = [:]
            await withTaskGroup(of: (UUID, Bool, String?).self) { taskGroup in
                for group in currentGroups {
                    taskGroup.addTask {
                        let latest = try? await ChatRepository.messages(groupID: group.id, limit: 1)
                        let message = latest?.first
                        let isUnread = (try? await ChatRepository.hasUnread(latest: message, groupID: group.id)) == true
                        let preview = message.flatMap(Self.previewText(for:))
                        return (group.id, isUnread, preview)
                    }
                }
                for await (id, isUnread, text) in taskGroup {
                    if isUnread {
                        unreadIDs.insert(id)
                    }
                    if let text {
                        previewsByGroup[id] = text
                    }
                }
            }
            unread = unreadIDs
            previews = previewsByGroup

            // Crew-widget bar meta (owner 2026-08-12): same derivation as
            // CrewRoomView's routines-together card — completed = this
            // week's completed sessions, next lift = earliest upcoming.
            // Best-effort per group, stale entries preserved on failure.
            var barMeta = barByGroup
            await withTaskGroup(of: (UUID, CrewBarMeta?).self) { taskGroup in
                for group in currentGroups {
                    taskGroup.addTask {
                        guard let sessions = try? await SessionRepository.groupSessions(groupID: group.id) else {
                            return (group.id, nil)
                        }
                        let calendar = Calendar.current
                        let now = Date.now
                        func inThisWeek(_ date: Date?) -> Bool {
                            guard let date else { return false }
                            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
                        }
                        let upcomingStates: Set<String> = [
                            "scheduled", "lobby_open", "editing", "voting", "locked", "in_progress"
                        ]
                        let completed = sessions.filter { $0.state == "completed" && inThisWeek($0.scheduledFor) }.count
                        let upcoming = sessions.filter { upcomingStates.contains($0.state) && inThisWeek($0.scheduledFor) }.count
                        let next = sessions
                            .filter { upcomingStates.contains($0.state) }
                            .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
                            .first?.scheduledFor
                        return (group.id, CrewBarMeta(completedThisWeek: completed,
                                                      plannedThisWeek: completed + upcoming,
                                                      nextLift: next))
                    }
                }
                for await (id, meta) in taskGroup {
                    if let meta { barMeta[id] = meta }
                }
            }
            barByGroup = barMeta

            errorText = nil
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Maps a chat message to its group-row preview line.
    /// text/soundboard_echo/system kinds show the body as-is; image and audio
    /// kinds show a fixed placeholder (no body to display). Plain words, no
    /// emoji — redesign emoji sweep (spec §7: attachment labels lose 📷/🎤).
    private static func previewText(for message: ChatMessage) -> String? {
        switch message.kind {
        case .image: return "Photo"
        case .audio: return "Voice message"
        case .soundboardEcho: return nil  // echoes retired 2026-08-11 (hidden, not deleted)
        case .text, .systemPR, .systemSession, .systemLate, .systemLeaderboard:
            return message.body
        }
    }
}

// MARK: - GSInitialsAvatar

/// Square, zero-radius initials avatar replacing the circle variant.
/// Used in group rows (36 px) and group header (30 px inside GroupView).
///
/// Phase F Task 6: upgraded to avatar-or-initials. When `avatarURL` is
/// non-nil, renders the real photo via `AsyncImage` (`.resizable()
/// .scaledToFill()` + `.frame(size,size).clipped()` — the exact idiom
/// `GroupView.membersList`/`SocialTabView.groupRow` already hand-rolled for
/// group avatars pre-this-task; those two call sites were simplified to
/// route through here instead of duplicating the same AsyncImage block a
/// third time). `AsyncImage(url:content:placeholder:)`'s 2-closure form
/// shows `placeholder` both while loading AND on failure (no separate error
/// phase) — same fallback-on-failure behavior the pre-existing call sites
/// already relied on. All pre-Task-6 call sites pass no `avatarURL` and are
/// visually unchanged (the `if let avatarURL` branch is simply never taken).
struct GSInitialsAvatar: View {
    private let initialsText: String
    let avatarURL: URL?
    var size: CGFloat = 34
    /// Redesign (spec §4): GROUP avatars carry the group's identity color
    /// (`GSGroupColor`), independent of the user's accent. `nil` keeps the
    /// pre-redesign accent fill for non-group callers.
    var fill: Color? = nil
    var ink: Color? = nil

    @Environment(\.gsTheme) private var theme

    /// Initials computed by splitting `name` on spaces (up to 2 words'
    /// first letters). Every call site in this codebase uses this single
    /// init — a precomputed-initials overload was considered for
    /// `YouTabView`'s profile-row avatar (whose own displayName-priority
    /// initials algorithm and 19pt `.heading` font diverge from this
    /// component's fixed formula) but that row was left as its own local
    /// AsyncImage-with-initials block instead, to avoid silently changing
    /// its typography — see that file's `profileRow` doc comment. No other
    /// caller needs anything but name-splitting, so that overload was
    /// dropped rather than kept unused.
    init(name: String, avatarURL: URL? = nil, size: CGFloat = 34, fill: Color? = nil, ink: Color? = nil) {
        let parts = name.split(separator: " ").prefix(2)
        self.initialsText = parts.map { String($0.prefix(1)).uppercased() }.joined()
        self.avatarURL = avatarURL
        self.size = size
        self.fill = fill
        self.ink = ink
    }

    var body: some View {
        // Redesign: rounded avatar tile (was zero-radius square).
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
                .frame(width: size, height: size)
                .clipped()
            } else {
                initialsView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }

    private var initialsView: some View {
        Text(initialsText)
            .font(GSFont.bold(size * 0.31, relativeTo: .caption))
            .foregroundStyle(ink ?? theme.bg)
            .frame(width: size, height: size)
            .background(fill ?? theme.accent)
    }
}

// (Legacy InitialsAvatar deleted 2026-08-12 — the wiring audit found zero
// remaining callers; GSInitialsAvatar is the only avatar component.)

