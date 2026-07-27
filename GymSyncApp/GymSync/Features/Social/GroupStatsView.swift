import SwiftUI

// MARK: - GroupStatsView
//
// GroupView's Stats sub-tab (Phase F Task 5) — spec Flow 5 (master spec
// docs/superpowers/specs/2026-06-28-gymsync-design.md ~798-805): "Stats —
// collective metrics (total sessions, PRs, volume), per-member
// leaderboards." Phase spec §3 (2026-07-16-social-finishers-design.md
// ~17-18) adds the group streak tile, deferred from Phase S Task 5:
// `group_streaks` was already live (member-gated RLS) but GroupView had no
// clean home for it among Chat/Members/Sessions until this dedicated
// sub-tab existed — see the now-removed placement-decision comment above
// `GroupView.SubTab` this task fulfills.
//
// Frame check: proof-frame-22.png ("Members") and proof-frame-19.png
// (already mapped to "Friends" in docs/design/frame-map.json) were
// rendered and inspected for this task — neither depicts a collective-
// metrics/leaderboard/streak surface. System-designed, recorded in
// docs/design/accepted-deviations.json ("group-stats"):
//   - Collective tiles row (SESSIONS / TOTAL LBS / PRS): `GSStatTile`
//     3-tile row, same shape/default 20pt size and PRs-tile accent color as
//     Home's canonical `StatTilesRow.loadedRow` (Workouts this week /
//     Lifetime lbs / PRs this month) — the closest existing "3 collective
//     metrics in a row" precedent in this codebase.
//   - Group streak card: mirrors `StatsTabView.streakCardView` verbatim in
//     shape (GSCard + GSSectionHeader("...") + current/longest GSStatTile
//     pair, 🔥-prefixed current-streak value + accent700 color while
//     live), swapped from `UserStreak`/`StreakRepository.userStreak(userID:)`
//     to `GroupStreak`/`StreakRepository.groupStreak(groupID:)`.
//   - Leaderboard rows: mirror `GroupRecapView.leaderboardRow`'s shape
//     (initials-square avatar, name, "volume · N PR" line) minus that
//     view's numeric rank and kudos chip — neither concept applies to an
//     all-time aggregate viewed outside a live session. Self-row "You"
//     substitution + tint follows `BurpeeLedgerView.crewDebtRow`'s idiom
//     (same screen family — GroupView's Sessions/Stats sub-tabs).
//
// Data: two independent RPCs (`GroupRepository.stats`/`memberStats`,
// 20260720000003_group_stats_rpc.sql) plus the existing group streak read
// (`StreakRepository.groupStreak`) — three independent fetches, no
// client-side re-aggregation between them (see the migration's shape-
// decision comment for why the scalar totals are computed server-side
// rather than summed here from the leaderboard rows).
struct GroupStatsView: View {
    let group: GymGroup

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var stats: GroupStats?
    @State private var members: [GroupMemberStat] = []
    @State private var groupStreak: GroupStreak?
    @State private var isLoading = true
    @State private var errorText: String?

    private var selfID: UUID? { appState.currentProfile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                collectiveTilesRow
                streakCard
                leaderboardSection

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Collective tiles — SESSIONS / TOTAL LBS / PRS
    // (StatTilesRow.loadedRow's 3-tile HStack idiom: default 20pt GSStatTile
    // size, PRs tile accented — same treatment as Home's "PRs this month".)

    private var collectiveTilesRow: some View {
        HStack(spacing: 8) {
            GSStatTile(value: "\(stats?.sessionCount ?? 0)", label: "Sessions")
            GSStatTile(
                value: "\(StatMath.compactNumber(Units.fromPounds(stats?.totalVolume ?? 0, to: ThemeStore.shared.weightUnit))) \(ThemeStore.shared.weightUnit.label)",
                label: "Total \(ThemeStore.shared.weightUnit.label)"
            )
            GSStatTile(
                value: "\(stats?.totalPRs ?? 0)",
                label: "PRs",
                valueColor: theme.accent700
            )
        }
    }

    // MARK: - Group Streak card (StatsTabView.streakCardView's idiom,
    // swapped to the group-scoped read)

    @ViewBuilder
    private var streakCard: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader("Group streak")
                HStack(spacing: 8) {
                    GSStatTile(
                        value: currentStreakValue,
                        label: "Current streak",
                        valueColor: streakValueColor
                    )
                    GSStatTile(
                        value: "\(groupStreak?.longestStreak ?? 0)",
                        label: "Longest streak"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var isStreakLive: Bool { (groupStreak?.currentStreak ?? 0) > 0 }

    /// Same explicit `guard`/`return` shape as `StatsTabView.streakValueColor`
    /// (that file's comment: no precedent found for a `Color`-ternary
    /// directly into a `Color?` parameter, so this stays unambiguous under
    /// CI-only compilation).
    private var streakValueColor: Color? {
        guard isStreakLive else { return nil }
        return theme.accent700
    }

    /// "🔥 N" while live — same glyph as `StatsTabView.currentStreakValue`
    /// and the backend's own celebratory copy
    /// (20260719000008_streak_pushes.sql's push_streak_milestone_group).
    private var currentStreakValue: String {
        let current = groupStreak?.currentStreak ?? 0
        return isStreakLive ? "🔥 \(current)" : "\(current)"
    }

    // MARK: - Leaderboard · By Volume (GroupRecapView.leaderboardRow's row
    // shape, minus rank/kudos — see type doc comment)

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Leaderboard · By Volume")
                .padding(.bottom, 8)

            if members.isEmpty {
                if !isLoading {
                    Text("No activity yet.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        leaderboardRow(member)
                        if member.id != members.last?.id {
                            Rectangle().fill(theme.divider).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func leaderboardRow(_ member: GroupMemberStat) -> some View {
        let isMe = member.userID == selfID
        let displayName = isMe ? "You" : member.username

        return HStack(spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(theme.neutral700)
                    .frame(width: 32, height: 32)
                Text(Self.initials(from: member.username))
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)

                HStack(spacing: 6) {
                    Text("\(formatVolumeFull(Units.fromPounds(member.volume, to: ThemeStore.shared.weightUnit))) \(ThemeStore.shared.weightUnit.label)")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    if member.prCount > 0 {
                        Text("· \(member.prCount) PR\(member.prCount == 1 ? "" : "s")")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .background(isMe ? theme.text.opacity(0.04) : Color.clear)
    }

    // MARK: - Helpers

    /// Same split-on-spaces algorithm as `BurpeeLedgerView.initials(from:)`
    /// (replicated, not shared, for the same reason that file gives: no
    /// trivially-accessible static helper elsewhere).
    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    /// Comma-grouped, zero-decimal volume — same `NumberFormatter` shape as
    /// `StatsTabView.volumeString`/`GroupSessionLiveView.formatVolumeFull`
    /// (documented duplication across this codebase; row-level volume
    /// mirrors GroupRecapView's leaderboard row, which also uses the "full"
    /// comma-grouped form rather than `StatMath.compactNumber`'s abbreviated
    /// tile form).
    private func formatVolumeFull(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = NSDecimalNumber(decimal: value).doubleValue
        return formatter.string(from: NSNumber(value: raw)) ?? "0"
    }

    // MARK: - Data loading

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let statsTask = GroupRepository.stats(groupID: group.id)
            async let membersTask = GroupRepository.memberStats(groupID: group.id)
            let (fetchedStats, fetchedMembers) = try await (statsTask, membersTask)
            stats = fetchedStats
            members = fetchedMembers
            groupStreak = try? await StreakRepository.groupStreak(groupID: group.id)
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
