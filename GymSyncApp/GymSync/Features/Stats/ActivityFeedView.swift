import SwiftUI

/// Pushed "Activity" screen — canvas frame 45. Month-grouped list of the
/// calling user's completed sessions, sourced from the `activity_feed`
/// SECURITY DEFINER RPC (Task 2, `20260719000002_activity_feed_rpc.sql`,
/// called via `SessionRepository.activityFeed(limit:)`). Reached from
/// `StatsTabView`'s "Recent Activity" row (retitled "Activity" to match this
/// frame's title — see that file).
///
/// Replaces an earlier placeholder that fetched `SessionRepository.history()`
/// directly and rendered a generic "Workout" card per row — this is the only
/// call site being repointed; `history()` itself is left in place since
/// `HomeView`/`GroupView` still use it for their own (non-feed) session
/// lists.
struct ActivityFeedView: View {
    @Environment(\.gsTheme) private var theme

    @State private var rows: [ActivityFeedRow] = []
    @State private var isLoading = true
    /// Set only when a load attempt with an EMPTY `rows` fails — mirrors
    /// `FriendsView.friendsLoadFailed`'s contract: a background refresh
    /// failure that leaves previously-loaded rows on screen stays silent
    /// (no error card), so a transient blip never wipes a populated feed.
    @State private var loadFailed = false

    private struct MonthSection: Identifiable {
        let id: String   // "2026-07" — stable grouping key
        let title: String // "JULY 2026" — uppercased "MMMM yyyy"
        let rows: [ActivityFeedRow]
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Groups `rows` (already ordered `completed_at desc` by the RPC) into
    /// contiguous month sections by encounter order — a plain `Dictionary`
    /// grouping would lose that ordering, so this walks the array once
    /// instead, matching the RPC's guaranteed sort rather than re-sorting.
    private var monthSections: [MonthSection] {
        var sections: [MonthSection] = []
        var currentKey: String?
        var currentTitle = ""
        var currentRows: [ActivityFeedRow] = []
        let calendar = Calendar.current

        for row in rows {
            let comps = calendar.dateComponents([.year, .month], from: row.completedAt)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != currentKey {
                if let currentKey {
                    sections.append(MonthSection(id: currentKey, title: currentTitle, rows: currentRows))
                }
                currentKey = key
                currentTitle = Self.monthTitleFormatter.string(from: row.completedAt).uppercased()
                currentRows = [row]
            } else {
                currentRows.append(row)
            }
        }
        if let currentKey {
            sections.append(MonthSection(id: currentKey, title: currentTitle, rows: currentRows))
        }
        return sections
    }

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(theme.accent)
                    Spacer()
                }
                .padding(.top, 60)
            } else if rows.isEmpty {
                if loadFailed {
                    GSErrorCard(
                        message: "Check your connection and try again.",
                        retry: { Task { await load() } }
                    )
                    .padding(16)
                } else {
                    GSEmptyState(
                        icon: "figure.strengthtraining.traditional",
                        title: "No activity yet",
                        message: "Complete a workout to see it here."
                    )
                    .padding(.top, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(monthSections) { section in
                            GSSectionHeader(section.title)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 10)

                            ForEach(section.rows) { row in
                                rowView(row)
                                GSDivider()
                                    .padding(.horizontal, 16)
                            }
                        }
                        Spacer(minLength: 24)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.bg)
            }
        }
        .background(theme.bg)
        // Pushed from StatsTabView's "Recent Activity" row — see
        // GSComponents.swift's GSHidesDock (same pattern ExerciseHistoryView
        // uses for its own Stats-pushed destination).
        .gsHidesDock()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func rowView(_ row: ActivityFeedRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Text(Self.dayFormatter.string(from: row.completedAt))
                    .font(GSFont.heading(24, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Text(Self.weekdayFormatter.string(from: row.completedAt).uppercased())
                    .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral500)
            }
            .frame(width: 36)

            Rectangle()
                .fill(theme.divider)
                .frame(width: 1, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    GSTag(text: row.isGroup ? "Group" : "Solo", style: row.isGroup ? .accent : .neutral)
                    Text(row.displayName)
                        .font(GSFont.heading(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                Text(metaText(for: row))
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer(minLength: 8)

            if row.prCount > 0 {
                GSTag(text: "\(row.prCount) PR", style: .accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        // One composed element per row for VoiceOver + the UI test's
        // defensive row query, mirroring GSSettingsRow's rationale
        // (GSComponents.swift) rather than leaving the chip/name/meta/PR-tag
        // texts as separate elements.
        .accessibilityElement(children: .combine)
    }

    private func metaText(for row: ActivityFeedRow) -> String {
        let duration = Self.durationText(from: row.startedAt, to: row.completedAt)
        let volume = "\(StatMath.compactNumber(row.volume)) lbs"
        let sets = "\(row.setCount) set\(row.setCount == 1 ? "" : "s")"
        return "\(duration) · \(volume) · \(sets)"
    }

    /// "M:SS" duration, uncapped at 60 minutes (frame 45 shows "61:20", not
    /// "1:01:20") — deliberately NOT `CompletedSessionView.durationString`'s
    /// hour-rollover formatter, which would render that case wrong for this
    /// frame. Falls back to an em dash when `start` is absent (see
    /// `ActivityFeedRow.startedAt`'s doc comment).
    private static func durationText(from start: Date?, to end: Date) -> String {
        guard let start else { return "—" }
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await SessionRepository.activityFeed(limit: 50)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
