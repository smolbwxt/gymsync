import SwiftUI

// MARK: - CampaignDetailView
//
// Phase C Task 2 — reached from `CampaignsTabView`'s rows and `HomeView`'s
// carousel card. Flow 8 (spec :867): "Campaign detail page: description,
// dates, curated workout list, current community progress bar, individual
// target, per-campaign leaderboard." Curated workout list closes here (Phase
// C Task 3, folded in from the T2 review's ruling) — `curated_routine_ids`
// resolves to `PublicWorkout` rows via `PublicWorkoutRepository.
// workoutsByIDs(_:)` (`Models/PublicWorkout.swift`), rendered by
// `curatedWorkoutsSection` below and tapping through to
// `DiscoverWorkoutDetailView`, the same "existing routine detail/attempt
// surface" Discover itself navigates to (`DiscoverView.swift:66-71`).
//
// No canvas frame exists for this screen (see `CampaignsTabView.swift`'s
// own header for the grep). System-designed: leaderboard row shape mirrors
// `GroupRecapView.leaderboardRow` (rank + `GSInitialsAvatar` + name + metric,
// `Features/Sessions/GroupRecapView.swift:323-364`) minus the kudos chip
// (campaigns have no kudos concept); progress bars are a small bespoke
// flat-rectangle fill (no existing progress-bar component in this codebase
// to reuse — grepped `DesignSystem/GSComponents.swift` for one before
// building this).
struct CampaignDetailView: View {
    let campaign: Campaign

    @Environment(\.gsTheme) private var theme

    @State private var myParticipation: CampaignParticipant?
    @State private var myProgress: CampaignProgress?
    @State private var community: CampaignCommunityProgress?
    @State private var leaderboard: [CampaignLeaderboardRow] = []
    @State private var curatedWorkouts: [PublicWorkout] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var joinLeaveInFlight = false
    @State private var joinLeaveErrorText: String?
    @State private var liveService = CampaignLiveService()

    #if DEBUG
    /// Debug-only — same idiom as `CampaignsTabView.catalogSkipLoad`.
    var catalogSkipLoad = false
    #endif

    private var isJoined: Bool { myParticipation != nil }

    /// An ended campaign is a frozen historical record (Flow 8 :884), not
    /// something to join or leave — suppress the join/leave CTA and the
    /// (pointless) live subscription when the window has closed. Reachable
    /// only via the Campaigns sub-tab's "Past" section, which only lists
    /// campaigns the user already participated in (Opus pre-GA closeout).
    private var isEnded: Bool { campaign.windowState() == .ended }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else if let errorText {
                    GSErrorCard(message: errorText) { Task { await loadAll() } }
                        .padding(16)
                } else {
                    // Flow 8's own field order (spec :867): "description,
                    // dates, curated workout list, current community
                    // progress bar, individual target, per-campaign
                    // leaderboard" — header (description/dates) already
                    // rendered above; curated list comes next, ahead of the
                    // progress bars.
                    if !curatedWorkouts.isEmpty {
                        curatedWorkoutsSection
                    }
                    communitySection
                    if isJoined {
                        myProgressSection
                        leaderboardSection
                    }
                    if !isEnded {
                        joinLeaveSection
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(theme.bg)
        .navigationTitle(campaign.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAll()
            #if DEBUG
            // Same guard ChatView.load() uses to skip its own realtime
            // `.subscribe()` call in catalog-fixture mode (`Features/Social/
            // ChatView.swift:790-792,817` — the early-return there sits
            // ahead of its own subscribe call in the SAME function; this
            // view splits load/subscribe across two awaits, so the guard is
            // repeated here rather than folded into `loadAll()`, which has
            // callers — `join()`/`leave()`/the error-card retry — that must
            // NOT skip re-loading data just because this is a debug build).
            if catalogSkipLoad { return }
            #endif
            // Live community progress bar (Flow 8 :879, "Updated live via a
            // postgres_changes subscription on the Campaigns detail page").
            // Channel-guard doctrine reasoning: CampaignLiveService.swift's
            // own header. Ended campaigns never tick (their progress is
            // frozen), so skip the subscription entirely.
            guard !isEnded else { return }
            await liveService.subscribe(campaignID: campaign.id) {
                Task { await refreshProgress() }
            }
        }
        .onDisappear {
            Task { await liveService.unsubscribe() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(campaign.name)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            if let description = campaign.description, !description.isEmpty {
                Text(description)
                    .font(GSFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
            }
            HStack(spacing: 8) {
                Text(dateRangeText)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                GSTag(text: windowStateLabel, style: windowStateTagStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var dateRangeText: String {
        let start = campaign.startsAt.formatted(.dateTime.month(.abbreviated).day().year())
        let end = campaign.endsAt.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    /// `Campaign.windowState()` drives the header's status chip — the
    /// hermetically-tested date-window state machine (`CampaignTests.swift`)
    /// gets a real caller here, not just test coverage. Flow 8's Completion
    /// section (:884) names the ended state explicitly ("leaderboard is
    /// frozen; final community total is displayed as historical fact"), so
    /// surfacing "Ended" is the honest signal for why the leaderboard below
    /// stops moving rather than leaving that unexplained.
    private var windowStateLabel: String {
        switch campaign.windowState() {
        case .upcoming: return "Upcoming"
        case .active: return "Active"
        case .ended: return "Ended"
        }
    }

    private var windowStateTagStyle: GSTagStyle {
        campaign.windowState() == .active ? .accent : .neutral
    }

    // MARK: - Curated workout list (Flow 8 :867 — closes the header's own
    // former scope-out note, Phase C Task 3)
    //
    // Empty `curated_routine_ids` -> section hidden entirely (checked at the
    // call site above, `!curatedWorkouts.isEmpty`) — no empty-state noise
    // for a campaign that names no workouts.
    //
    // Row shape: name + owner caption + FEATURED tag, borrowed from
    // `DiscoverView.workoutCard`'s content fields (`DiscoverView.swift:133-
    // 183`) but as a compact tappable ROW (not a grid card with an image
    // placeholder) — this is one supplementary section within a scrolling
    // detail page, not its own grid destination, same "smaller local re-
    // implementation, not a cross-file extraction" convention this file
    // already uses for `leaderboardRow`/`communitySection` above (each
    // borrows a shape and cites it rather than sharing a component).
    // Divider-between-rows + chevron-affordance idiom reused directly from
    // this file's own `leaderboardSection`/`DiscoverView.topLiftersRow`.
    private var curatedWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Workouts")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            ForEach(Array(curatedWorkouts.enumerated()), id: \.element.id) { index, workout in
                NavigationLink {
                    DiscoverWorkoutDetailView(workout: workout)
                } label: {
                    curatedWorkoutRow(workout)
                }
                .buttonStyle(.plain)
                if index < curatedWorkouts.count - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 16)
                }
            }
        }
    }

    private func curatedWorkoutRow(_ workout: PublicWorkout) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workout.routine.name)
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    if workout.isFeatured {
                        GSTag(text: "FEATURED", style: .accent)
                    }
                }
                Text("by \(workout.ownerUsername)")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Community progress (Flow 8 :877-880)

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Community Progress")
            let achieved = community?.volumeLifted ?? 0
            if let target = campaign.globalTarget?.target, target > 0 {
                CampaignProgressBar(fraction: min(1, max(0, decimalToDouble(achieved) / target)))
                Text("Together we've moved \(formattedNumber(achieved)) lbs of the \(formattedNumber(Decimal(target))) lb goal.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                Text("\(formattedNumber(achieved)) lbs lifted so far by the community.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - My progress + completion badge (Flow 8 :882-884)

    private var myProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Your Progress")
            if let resolved = campaign.individualTarget?.resolvedTarget {
                let achieved = CampaignProgressMath.achievedCount(progress: myProgress, target: campaign.individualTarget) ?? 0
                let fraction = CampaignProgressMath.fractionComplete(progress: myProgress, target: campaign.individualTarget) ?? 0
                CampaignProgressBar(fraction: fraction)
                HStack(spacing: 8) {
                    Text("\(achieved)/\(resolved.count) \(resolved.unitLabel)")
                        .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    if CampaignProgressMath.isComplete(progress: myProgress, target: campaign.individualTarget) {
                        GSTag(text: "🌊 Completed", style: .accent)
                    }
                }
            } else {
                Text("\(formattedNumber(myProgress?.volumeLifted ?? 0)) lbs lifted")
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - Leaderboard (participants-only — CampaignRepository.leaderboard's own adjudication)

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Leaderboard")
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
            if leaderboard.isEmpty {
                Text("No progress yet — be the first to log a session.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
            } else {
                ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, row in
                    leaderboardRow(rank: index + 1, row: row)
                    if index < leaderboard.count - 1 {
                        Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func leaderboardRow(rank: Int, row: CampaignLeaderboardRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 18, alignment: .leading)

            GSInitialsAvatar(name: row.username, avatarURL: row.avatarURL, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text("\(formattedNumber(row.volumeLifted)) lbs")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Join / Leave CTA

    private var joinLeaveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isJoined {
                Button("Leave Campaign") { Task { await leave() } }
                    .buttonStyle(GSSecondaryButtonStyle())
                    .disabled(joinLeaveInFlight)
                    .opacity(joinLeaveInFlight ? 0.6 : 1)
            } else {
                Button("Join Campaign") { Task { await join() } }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .disabled(joinLeaveInFlight)
                    .opacity(joinLeaveInFlight ? 0.6 : 1)
            }
            if let joinLeaveErrorText {
                Text(joinLeaveErrorText)
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - Data

    @MainActor
    private func loadAll() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        errorText = nil
        do {
            // Community aggregate is visible to any caller who can see the
            // campaign at all (Task 1 item 8's gate); participation decides
            // whether the leaderboard/my-progress calls below are even
            // attempted — CampaignRepository.leaderboard's own doc comment
            // explains why a non-participant must not call it at all rather
            // than rendering its (always-empty, RLS-denied) result.
            // Curated workouts is best-effort (try?, same posture as
            // DiscoverView.load()'s attemptCounts fetch,
            // `DiscoverView.swift:207-208`) — a transient failure here
            // shouldn't blank the whole detail page over a supplementary
            // section; it just renders as if `curated_routine_ids` were empty.
            async let participationFetch = CampaignRepository.myParticipation(campaignID: campaign.id)
            async let communityFetch = CampaignRepository.communityProgress(campaignID: campaign.id)
            async let curatedFetch: [PublicWorkout] = (try? await PublicWorkoutRepository.workoutsByIDs(
                campaign.curatedRoutineIDs
            )) ?? []
            let participation = try await participationFetch
            myParticipation = participation
            community = try await communityFetch
            curatedWorkouts = await curatedFetch
            if participation != nil {
                async let progressFetch = CampaignRepository.myProgress(campaignID: campaign.id)
                async let leaderboardFetch = CampaignRepository.leaderboard(campaignID: campaign.id)
                myProgress = try await progressFetch
                leaderboard = try await leaderboardFetch
            } else {
                myProgress = nil
                leaderboard = []
            }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
        loading = false
    }

    /// Live-tick refresh (postgres_changes callback) — best-effort, same
    /// "failures leave stale data in place" posture as `HomeView.refresh`'s
    /// per-field `try?`s, so a transient refetch failure never blanks an
    /// already-rendered bar.
    @MainActor
    private func refreshProgress() async {
        community = (try? await CampaignRepository.communityProgress(campaignID: campaign.id)) ?? community
        if isJoined {
            myProgress = (try? await CampaignRepository.myProgress(campaignID: campaign.id)) ?? myProgress
            leaderboard = (try? await CampaignRepository.leaderboard(campaignID: campaign.id)) ?? leaderboard
        }
    }

    @MainActor
    private func join() async {
        guard !joinLeaveInFlight else { return }
        joinLeaveInFlight = true
        joinLeaveErrorText = nil
        defer { joinLeaveInFlight = false }
        do {
            try await CampaignRepository.join(campaignID: campaign.id)
            await loadAll()
        } catch {
            joinLeaveErrorText = ErrorMapping.map(error).errorDescription
        }
    }

    @MainActor
    private func leave() async {
        guard !joinLeaveInFlight else { return }
        joinLeaveInFlight = true
        joinLeaveErrorText = nil
        defer { joinLeaveInFlight = false }
        do {
            try await CampaignRepository.leave(campaignID: campaign.id)
            await loadAll()
        } catch {
            joinLeaveErrorText = ErrorMapping.map(error).errorDescription
        }
    }

    // MARK: - Formatting helpers

    private func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func formattedNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

/// Flat-rectangle progress bar — theme.neutral300 track, theme.accent fill.
/// No existing progress-bar component in `DesignSystem/GSComponents.swift`
/// to reuse (grepped before building this); matches the codebase's
/// established "flat rectangle, zero corner radius" visual language
/// (`GSCard`, `GSTag`, `GSDivider` all share it).
private struct CampaignProgressBar: View {
    let fraction: Double
    @Environment(\.gsTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.neutral300)
                Rectangle().fill(theme.accent)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Catalog fixture seam (`campaign-detail-*` catalog cases)

#if DEBUG
extension CampaignDetailView {
    /// Debug-only seam for the design-parity screen catalog — same idiom as
    /// `CampaignsTabView`'s own fixture init. `campaign` is a plain `let`
    /// (not `@State`), set directly like any other stored property this
    /// same-file extension init can see.
    init(
        campaign: Campaign,
        catalogFixtureParticipation participation: CampaignParticipant?,
        catalogFixtureProgress progress: CampaignProgress?,
        catalogFixtureCommunity community: CampaignCommunityProgress,
        catalogFixtureLeaderboard leaderboard: [CampaignLeaderboardRow] = [],
        catalogFixtureCuratedWorkouts curatedWorkouts: [PublicWorkout] = []
    ) {
        self.campaign = campaign
        _myParticipation = State(initialValue: participation)
        _myProgress = State(initialValue: progress)
        _community = State(initialValue: community)
        _leaderboard = State(initialValue: leaderboard)
        _curatedWorkouts = State(initialValue: curatedWorkouts)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
}
#endif
