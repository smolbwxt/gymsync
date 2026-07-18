import SwiftUI

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var refreshedProfile: Profile?
    @State private var weeklyVolumes: [Decimal] = Array(repeating: 0, count: 6)
    @State private var recentPRs: [PersonalRecord] = []
    @State private var monthTrendPercent: Double?
    @State private var userStreak: UserStreak?
    // Body weight card (Phase H Task 3)
    @State private var bodyWeightLogs: [BodyWeightLog] = []
    @State private var selectedBodyWeightRange: TrendRange = .sixMonths
    @State private var showingBodyWeightLogSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Lifetime Volume Card ───────────────────────────────────
                    GSCard(bordered: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            GSSectionHeader("Lifetime volume")
                            Text(volumeString)
                                .font(GSFont.heading(34, relativeTo: .largeTitle))
                                .foregroundStyle(theme.text)
                                .monospacedDigit()
                            if let monthTrendPercent {
                                Text("\(monthTrendPercent >= 0 ? "▲" : "▼") \(abs(Int(monthTrendPercent.rounded())))% vs last month")
                                    .font(GSFont.body(12, relativeTo: .caption))
                                    .foregroundStyle(theme.accent700)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    GSDivider()
                        .padding(.vertical, 16)

                    // ── Weekly Volume Card ──────────────────────────────────────
                    weeklyVolumeCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Streak Card (Task 5, Phase S) ───────────────────────────
                    streakCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Recent PRs Table ────────────────────────────────────────
                    recentPRsCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Body Weight Card (Task 3, Phase H) ──────────────────────
                    bodyWeightCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Recent Activity Row ────────────────────────────────────
                    GSSectionHeader("Recent Activity")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    NavigationLink { ActivityFeedView() } label: {
                        HStack {
                            Text("Activity")
                                .font(GSFont.bodyMedium(15, relativeTo: .body))
                                .foregroundStyle(theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(theme.surface)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    GSDivider()
                        .padding(.vertical, 16)

                    // ── Per-Exercise History ───────────────────────────────────
                    GSSectionHeader("Per-Exercise History")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    if exercises.isEmpty {
                        Text("No exercises yet.")
                            .font(GSFont.body(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    } else {
                        ForEach(exercises) { ex in
                            NavigationLink { ExerciseHistoryView(exercise: ex) } label: {
                                HStack {
                                    Text(ex.name)
                                        .font(GSFont.bodyMedium(15, relativeTo: .body))
                                        .foregroundStyle(theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(theme.surface)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            GSDivider()
                                .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                exercises = (try? await ExerciseRepository.fetchAll()) ?? []
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
                await loadStreak()
                await loadBodyWeight()
            }
            .refreshable {
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
                await loadStreak()
                await loadBodyWeight()
            }
            .sheet(isPresented: $showingBodyWeightLogSheet) {
                BodyWeightLogSheet(onLogged: { Task { await loadBodyWeight() } })
            }
        }
    }

    private var volumeString: String {
        let profile = refreshedProfile ?? appState.currentProfile
        let vol = profile?.lifetimeVolumeLifted ?? 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = NSDecimalNumber(decimal: vol).doubleValue
        return "\(formatter.string(from: NSNumber(value: raw)) ?? "0") lbs"
    }

    // MARK: - Weekly Volume Card (Task 6)

    @ViewBuilder
    private var weeklyVolumeCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader("Weekly volume")

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(weeklyVolumes.enumerated()), id: \.offset) { index, volume in
                        Rectangle()
                            .fill(index == weeklyVolumes.count - 1 ? theme.accent : theme.neutral400)
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight(for: volume))
                    }
                }
                .frame(height: 76, alignment: .bottom)

                HStack(spacing: 8) {
                    ForEach(0..<weeklyVolumes.count, id: \.self) { index in
                        Text("W\(index + 1)")
                            .font(GSFont.body(9, relativeTo: .caption2))
                            .foregroundStyle(index == weeklyVolumes.count - 1 ? theme.accent700 : theme.neutral700)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    /// Bar height in points for a 76pt-tall chart: proportional to the max
    /// week's volume (max week = full 76pt), with a 2pt floor for zero-volume
    /// weeks (and for the degenerate all-zero case).
    private func barHeight(for volume: Decimal) -> CGFloat {
        guard volume > 0 else { return 2 }
        let maxVolume = weeklyVolumes.max() ?? 0
        guard maxVolume > 0 else { return 2 }
        let ratio = NSDecimalNumber(decimal: volume / maxVolume).doubleValue
        return max(CGFloat(ratio) * 76, 2)
    }

    // MARK: - Streak Card (Task 5, Phase S)
    //
    // Current + longest streak from `user_streaks` (StreakRepository —
    // Models/Streak.swift), master-spec'd to live on Stats
    // (docs/superpowers/specs/2026-06-28-gymsync-design.md:553-579 for the
    // schema, Flow 7 for the lifecycle). No canvas frame exists for this yet
    // — uses GSCard + GSStatTile with the canonical 20pt tile size (Home tab
    // default, positioned between You-tab's 18pt and hero values). Recorded
    // as an accepted deviation (docs/design/accepted-deviations.json,
    // "tab-stats") pending a designer frame.
    //
    // Zero-state: no `user_streaks` row (a user who has never carried a
    // scheduled session to a 'ready' completion) renders as a plain "0" —
    // `userStreak` stays nil and both tiles fall back via `?? 0`, same
    // graceful-zero pattern `volumeString`/`recentPRsCardView` already use
    // elsewhere on this screen.
    @ViewBuilder
    private var streakCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader("Streak")
                HStack(spacing: 8) {
                    GSStatTile(
                        value: currentStreakValue,
                        label: "Current streak",
                        valueColor: streakValueColor
                    )
                    GSStatTile(
                        value: "\(userStreak?.longestStreak ?? 0)",
                        label: "Longest streak"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var isStreakLive: Bool { (userStreak?.currentStreak ?? 0) > 0 }

    /// Accent color for the current-streak tile's value while live, `nil`
    /// (falls back to `GSStatTile`'s own `theme.text` default) once broken —
    /// explicit `guard`/`return` rather than a ternary passed straight into
    /// the optional `valueColor:` parameter, to leave no ambiguity about
    /// which `Color?` this resolves to.
    private var streakValueColor: Color? {
        guard isStreakLive else { return nil }
        return theme.accent700
    }

    /// "🔥 N" for a live streak — the same flame the backend's own
    /// celebratory copy uses for this exact concept
    /// (20260719000008_streak_pushes.sql's push_streak_milestone_group:
    /// "🔥 Crew streak: N sessions strong!"), reused here rather than
    /// inventing a different glyph for the same idea. Plain "0" (no flame)
    /// once the streak is broken or never started — a dead streak isn't a
    /// "live" one worth decorating.
    private var currentStreakValue: String {
        let current = userStreak?.currentStreak ?? 0
        return isStreakLive ? "🔥 \(current)" : "\(current)"
    }

    // MARK: - Recent PRs Card (Task 6)

    @ViewBuilder
    private var recentPRsCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                GSSectionHeader("Recent PRs")

                if recentPRs.isEmpty {
                    Text("No PRs yet — go set one.")
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 10)
                } else {
                    HStack {
                        Text("Exercise").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Best").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral700)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    Rectangle().fill(theme.divider).frame(height: 1)

                    ForEach(Array(recentPRs.enumerated()), id: \.element.id) { index, pr in
                        HStack {
                            Text(exerciseName(for: pr.exerciseID))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(trimmedDecimal(pr.weight)) lbs")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(shortDate(pr.achievedAt))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .padding(.vertical, 8)

                        if index < recentPRs.count - 1 {
                            Rectangle().fill(theme.divider).frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    // MARK: - Body Weight Card (Task 3, Phase H)
    //
    // `body_weight_logs` (20260724000001_body_weight_logs.sql) — master-spec'd
    // to live on Stats ("body weight trend",
    // docs/superpowers/specs/2026-06-28-gymsync-design.md:692). No canvas
    // frame exists for this card or its log sheet — system-designed,
    // extends the existing "tab-stats" accepted deviation (same GSCard/
    // GSSectionHeader rhythm as the weekly-volume/streak/recent-PRs cards
    // already on this screen); see docs/design/accepted-deviations.json.
    // The trend chart itself reuses `TrendChartView` verbatim (Features/
    // Stats/TrendChartView.swift:21-27's init — title/data/selectedRange —
    // same call shape `ExerciseHistoryView` already uses for its Est. 1RM
    // trend), and the "+ Log" header button mirrors
    // `RoutinesListView.yourRoutinesHeader`'s "+ New" button shape
    // (Features/Library/RoutinesListView.swift:83-104).
    //
    // Fix wave 1 (reviewer Findings 1 + 2): this card used to be a bare
    // VStack sitting on top of `TrendChartView`'s own internal
    // `GSCard(bordered: true)` — two visually disconnected pieces with a
    // border style no sibling card on this screen uses (every sibling —
    // `weeklyVolumeCardView` line 167, `streakCardView` line 224,
    // `recentPRsCardView` line 272, Lifetime Volume line 22 — is ONE
    // `GSCard(bordered: false) { header + content }.padding(16)`). Now
    // wrapped in that same single `GSCard(bordered: false)`, with
    // `TrendChartView(embedInCard: false, title: "")` so the chart
    // contributes only its range picker + chart line, no nested
    // card/border/padding and no second header of its own (fix wave 2 —
    // see the comment at the call site below) — `ExerciseHistoryView` (the only
    // other `TrendChartView` consumer, swift:76-78) doesn't pass
    // `embedInCard` at all, so it keeps the default `true` and its exact
    // prior rendering. `latestBodyWeightText` below adds the headline
    // number this card was missing relative to its "big number" sibling,
    // Lifetime Volume (`volumeString`, line 25-33) — wired from
    // `StatMath.formattedBodyWeight` (Models/StatMath.swift:181), which had
    // zero production call sites before this (Finding 2).
    @ViewBuilder
    private var bodyWeightCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GSSectionHeader("Body Weight")
                    Spacer()
                    Button {
                        showingBodyWeightLogSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Log").font(GSFont.bold(13, relativeTo: .subheadline))
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let latestBodyWeightText {
                    Text(latestBodyWeightText)
                        .font(GSFont.heading(34, relativeTo: .largeTitle))
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                }

                // `title: ""` — the card's own "Body Weight" header row
                // above is this card's single title; a second inner "Weight"
                // header would duplicate it (no sibling card stacks two
                // titles). TrendChartView omits the GSSectionHeader entirely
                // for an empty title (TrendChartView.swift:24-31), leaving
                // the range picker right-aligned on its own row above the
                // chart — same top-right position it occupies everywhere
                // else (fix wave 2).
                TrendChartView(
                    title: "",
                    data: bodyWeightChartData,
                    selectedRange: $selectedBodyWeightRange,
                    embedInCard: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var bodyWeightChartData: [(Date, Double)] {
        StatMath.bodyWeightTrendPoints(logs: bodyWeightLogs)
    }

    /// Headline "182.4 lbs" for the most recent log — `nil` (no headline)
    /// when there are no logs yet, matching the chart's own "Not enough
    /// data yet." empty state (TrendChartView.swift:53-56) rather than
    /// duplicating a second empty-state message. `bodyWeightLogs` is
    /// most-recent-first (`BodyWeightLogRepository.recent`'s documented
    /// order, Models/BodyWeightLog.swift:31-36), so `.first` is the latest
    /// entry without needing to re-sort.
    private var latestBodyWeightText: String? {
        guard let latest = bodyWeightLogs.first else { return nil }
        return StatMath.formattedBodyWeight(latest.weight, unit: latest.unit)
    }

    private func exerciseName(for id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "Exercise"
    }

    private func trimmedDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Data loading (Task 6)

    @MainActor
    private func loadWeeklyVolumeAndPRs() async {
        guard let userID = appState.currentProfile?.id else { return }
        let currentWeekStart = StatMath.startOfWeek(containing: .now, calendar: .current)
        // Widened to the start of last calendar month (min 35d) so the same
        // fetch also backs the "vs last month" trend line, not just the 6
        // weekly bars — avoids a second network round-trip.
        let currentMonthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now)
        ) ?? .now
        let lastMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
        let weeklyWindowStart = Calendar.current.date(byAdding: .day, value: -35, to: currentWeekStart) ?? currentWeekStart
        let since = min(weeklyWindowStart, lastMonthStart)
        let logs = (try? await SessionRepository.recentSetLogs(userID: userID, since: since)) ?? []
        weeklyVolumes = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: .current)
        monthTrendPercent = StatMath.monthOverMonthVolumeChangePercent(logs: logs, calendar: .current)
        recentPRs = (try? await PersonalRecordRepository.recent(userID: userID, limit: 5)) ?? []
    }

    @MainActor
    private func loadStreak() async {
        guard let userID = appState.currentProfile?.id else { return }
        userStreak = try? await StreakRepository.userStreak(userID: userID)
    }

    @MainActor
    private func loadBodyWeight() async {
        guard let userID = appState.currentProfile?.id else { return }
        bodyWeightLogs = (try? await BodyWeightLogRepository.recent(userID: userID)) ?? []
    }
}
