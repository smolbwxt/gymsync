import SwiftUI
import Charts

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var exerciseSearchText = ""
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
                    // Redesign v2: in-content title replaces the nav-bar title
                    // (the empty bar row wasted vertical space — user feedback).
                    Text("Stats")
                        .font(GSFont.heading(24, relativeTo: .title))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

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
                    .padding(.bottom, 12)
                    .gsSpotlightTarget(.stats)

                    // ── Weekly Volume Card ──────────────────────────────────────
                    weeklyVolumeCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Streak Card (Task 5, Phase S) ───────────────────────────
                    streakCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Recent PRs ─────────────────────────────────────────────
                    recentPRsCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Body Weight Card (Task 3, Phase H) ──────────────────────
                    bodyWeightCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Recent Activity Row (redesign: rounded card row) ───────
                    NavigationLink { ActivityFeedView() } label: {
                        navRow(title: "Activity", tint: theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // ── Per-Exercise History ───────────────────────────────────
                    GSSectionHeader("Per-Exercise History")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    if exercises.isEmpty {
                        // Null state (spec §6): card-anchored, never a bare float.
                        GSCard(bordered: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No exercises yet")
                                    .font(GSFont.bold(14, relativeTo: .subheadline))
                                    .foregroundStyle(theme.text)
                                Text("Exercise history builds automatically as you train.")
                                    .font(GSFont.body(12, relativeTo: .caption))
                                    .foregroundStyle(theme.neutral500)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    } else {
                        // Shared in-content search field shape (ExercisesListView
                        // idiom) — the history list is the full catalog.
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                            TextField("Search exercises", text: $exerciseSearchText)
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(theme.surface)
                        .cornerRadius(GSMetrics.radiusSm)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                        VStack(spacing: 8) {
                            ForEach(filteredExercises) { ex in
                                NavigationLink { ExerciseHistoryView(exercise: ex) } label: {
                                    navRow(title: ex.name, tint: theme.text)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .contentMargins(.bottom, 88, for: .scrollContent)   // dock clearance (user bug report)
            .toolbar(.hidden, for: .navigationBar)   // redesign v2: in-content title above
            .gsSpotlight(.stats)
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

    private var filteredExercises: [Exercise] {
        exerciseSearchText.isEmpty ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(exerciseSearchText) }
    }

    private var volumeString: String {
        let profile = refreshedProfile ?? appState.currentProfile
        let vol = profile?.lifetimeVolumeLifted ?? 0
        let unit = ThemeStore.shared.weightUnit
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        // Units sweep: volume is a mass aggregate (not a loadable target) —
        // plain conversion, no plate snapping.
        let raw = Units.fromPounds(NSDecimalNumber(decimal: vol).doubleValue, to: unit)
        return "\(formatter.string(from: NSNumber(value: raw)) ?? "0") \(unit.label)"
    }

    // MARK: - Weekly Volume Card (Task 6; redesign: area chart)
    //
    // Redesign (all-tabs proof): the 6 discrete bars become a smooth accent
    // area chart — gradient fill under an accent line with an emphasized
    // latest point, axes hidden, W1…W6 labels below. Same `weeklyVolumes`
    // data, purely a presentation change. All-zero data renders the honest
    // empty message instead of a flat line pretending to be a trend.

    @ViewBuilder
    private var weeklyVolumeCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader("Weekly volume")

                if weeklyVolumes.allSatisfy({ $0 == 0 }) {
                    Text("No sessions logged yet — your first workout starts the trend.")
                        .font(GSFont.body(12.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.vertical, 20)
                } else {
                    Chart {
                        ForEach(Array(weeklyVolumes.enumerated()), id: \.offset) { index, volume in
                            let v = NSDecimalNumber(decimal: volume).doubleValue
                            AreaMark(x: .value("Week", index), y: .value("Volume", v))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [theme.accent.opacity(0.28), theme.accent.opacity(0)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                            LineMark(x: .value("Week", index), y: .value("Volume", v))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            if index == weeklyVolumes.count - 1 {
                                PointMark(x: .value("Week", index), y: .value("Volume", v))
                                    .foregroundStyle(theme.accent)
                                    .symbolSize(46)
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 110)

                    HStack(spacing: 8) {
                        ForEach(0..<weeklyVolumes.count, id: \.self) { index in
                            Text("W\(index + 1)")
                                .font(GSFont.body(9, relativeTo: .caption2))
                                .foregroundStyle(index == weeklyVolumes.count - 1 ? theme.accent : theme.neutral700)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    // MARK: - Shared nav row (redesign)

    /// Rounded surface nav row — the card-anchored replacement for the old
    /// square edge-to-edge rows (Activity, per-exercise history).
    private func navRow(title: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(GSFont.bodyMedium(15, relativeTo: .body))
                .foregroundStyle(tint)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusSm)
        .contentShape(Rectangle())
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

    /// Plain "N" — the redesign's emoji sweep (spec §7) replaced the "🔥 N"
    /// tile value: liveness is signaled by the accent `streakValueColor`
    /// above (and by Home's streak-ring flame, which uses `flame.fill`, the
    /// SF Symbol form). The backend's push copy keeps its own 🔥 — that's
    /// message text, not UI chrome.
    private var currentStreakValue: String {
        "\(userStreak?.currentStreak ?? 0)"
    }

    // MARK: - Recent PRs Card (Task 6)

    @ViewBuilder
    private var recentPRsCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                GSSectionHeader("Recent PRs")

                if recentPRs.isEmpty {
                    // Null state (spec §6): stays inside the card, invitational.
                    Text("No PRs yet — your first record lands here.")
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 10)
                } else {
                    // Redesign (all-tabs proof): accent up-arrow rows replace
                    // the three-column table — lift · weight · date.
                    ForEach(Array(recentPRs.enumerated()), id: \.element.id) { index, pr in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(theme.accent)
                            Text(exerciseName(for: pr.exerciseID))
                                .font(GSFont.bold(13.5, relativeTo: .subheadline))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Units.format(pounds: pr.weight, unit: ThemeStore.shared.weightUnit, rounded: false))
                                .font(GSFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(theme.text)
                                .monospacedDigit()
                            Text(shortDate(pr.achievedAt))
                                .font(GSFont.body(11, relativeTo: .caption2))
                                .foregroundStyle(theme.neutral500)
                                .frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, 10)

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
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.accent, lineWidth: 1))
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
                //
                // `valueLabel: "Weight"` (Phase O Task 2): without this,
                // TrendChartView's chart marks/a11y default to "Est. 1RM" —
                // correct for ExerciseHistoryView's trend but wrong here
                // (this card has nothing to do with 1RM estimation), so
                // VoiceOver was announcing every body-weight data point
                // with the wrong label.
                TrendChartView(
                    title: "",
                    data: bodyWeightChartData,
                    selectedRange: $selectedBodyWeightRange,
                    embedInCard: false,
                    valueLabel: "Weight"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var bodyWeightChartData: [(Date, Double)] {
        // Units sweep: points are stored-lbs — convert for a kg user so any
        // value the chart surfaces matches the headline's unit.
        let unit = ThemeStore.shared.weightUnit
        return StatMath.bodyWeightTrendPoints(logs: bodyWeightLogs)
            .map { ($0.0, Units.fromPounds($0.1, to: unit)) }
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
        // Units sweep: rows store canonical pounds (BodyWeightLogSheet
        // converts on entry) — format in the user's display unit, 1dp.
        return Units.formatBodyWeight(pounds: latest.weight, unit: ThemeStore.shared.weightUnit)
    }

    private func exerciseName(for id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "Exercise"
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
