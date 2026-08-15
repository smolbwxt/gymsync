import SwiftUI
import Charts

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var refreshedProfile: Profile?
    @State private var weeklyVolumes: [Decimal] = Array(repeating: 0, count: 6)
    /// The workout ledger (owner 2026-08-16: "what people actually care
    /// about... the ledger of their workouts"): recent completed sessions
    /// with abbreviated aggregates; rows open the recap-language detail.
    @State private var ledgerEntries: [LedgerEntry] = []
    /// Exercises the lifter has actually attempted (derived from PR rows -
    /// every qualifying set mints one), most recent first. The PR widget's
    /// destination list.
    @State private var attemptedExercises: [Exercise] = []
    /// Rolling-load cursor: how many days back the ledger has fetched.
    /// Starts at the free window (owner: 30 days free, beyond is Pro).
    @State private var ledgerDaysLoaded = Monetization.freeHistoryDays
    @State private var ledgerLoadingMore = false
    @State private var ledgerExhausted = false
    @State private var showLedgerPaywall = false

    /// True when the next window is behind the Pro line for this user —
    /// renders the upsell row instead of silently stopping. Always false
    /// while the paywall is dormant.
    private var ledgerGated: Bool {
        !ledgerExhausted
            && !Monetization.allows(.deepHistory, profile: appState.currentProfile)
    }
    @State private var monthTrendPercent: Double?
    @State private var userStreak: UserStreak?
    // Body weight card (Phase H Task 3)
    @State private var bodyWeightLogs: [BodyWeightLog] = []
    @State private var selectedBodyWeightRange: TrendRange = .sixMonths
    @State private var showingBodyWeightLogSheet = false

    /// `true` (default) keeps the legacy tab-root form: own `NavigationStack`,
    /// hidden nav bar, in-content "Stats" title. Pass `false` when PUSHING
    /// this view inside an existing stack (YouTabView's STATS widget) — the
    /// content renders bare so the OUTER stack keeps its system bar (back
    /// chevron + edge-swipe; the build-445 "stuck on Stats" report was this
    /// view's nested stack swallowing that bar) and supplies the inline
    /// title; internal pushes (Activity, per-exercise history) ride the
    /// outer stack.
    var embedsInOwnStack: Bool = true

    var body: some View {
        if embedsInOwnStack {
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)   // redesign v2: in-content title
            }
        } else {
            content
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Redesign v2 (tab-root form only): in-content title
                    // replaces the nav-bar title (the empty bar row wasted
                    // vertical space — user feedback). Pushed form gets an
                    // inline bar title from the push site instead.
                    if embedsInOwnStack {
                        Text("Stats")
                            .font(GSFont.heading(24, relativeTo: .title))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    }

                    // ── The Ledger (owner 2026-08-16: leads the page) ──────────
                    GSSectionHeader("Ledger")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    if ledgerEntries.isEmpty {
                        Text("Finished workouts land here — abbreviated, tap for the full picture.")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(ledgerEntries) { entry in
                                NavigationLink {
                                    CompletedSessionView(session: entry.session)
                                } label: {
                                    ledgerRow(entry)
                                }
                                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                                // Rolling load (owner 2026-08-16): reaching
                                // the last row fetches the next window.
                                .onAppear {
                                    if entry.id == ledgerEntries.last?.id {
                                        Task { await loadMoreLedger() }
                                    }
                                }
                            }
                            if ledgerLoadingMore {
                                ProgressView().tint(theme.accent)
                                    .padding(.vertical, 8)
                            } else if ledgerGated {
                                // The 30-day line (owner: free ledger = 30
                                // days; everything beyond is Pro). Inert
                                // while the paywall is dormant.
                                Button {
                                    showLedgerPaywall = true
                                } label: {
                                    Text("Older workouts are PRO — the full ledger, all time.")
                                        .font(GSFont.bold(13, relativeTo: .subheadline))
                                        .foregroundStyle(Color.gsHex(0xE8C33A))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    // ── Personal records (→ attempted lifts → trend + history) ─
                    NavigationLink {
                        AttemptedExercisesView(exercises: attemptedExercises)
                            .background(theme.bg)
                            .navigationTitle("Personal records")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            GSSectionHeader("Personal records")
                            Text(attemptedExercises.isEmpty
                                 ? "Every lift you attempt builds a record page."
                                 : "\(attemptedExercises.count) lifts — trend graphs and full history per exercise.")
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral700)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // ── Lifetime Volume Card ───────────────────────────────────
                    // gs3D pass (2026-08-13): the zero-radius GSCards were
                    // this screen's whole debt — every card joins the
                    // extruded face/lip language, and text follows the
                    // owner's default-color law (trend line included).
                    VStack(alignment: .leading, spacing: 4) {
                        GSSectionHeader("Lifetime volume")
                        Text(volumeString)
                            .font(GSFont.heading(34, relativeTo: .largeTitle))
                            .foregroundStyle(theme.text)
                            .monospacedDigit()
                        if let monthTrendPercent {
                            Text("\(monthTrendPercent >= 0 ? "▲" : "▼") \(abs(Int(monthTrendPercent.rounded())))% vs last month")
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral700)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .gs3DCard(cornerRadius: GSMetrics.radiusMd)
                    .padding(.horizontal, 16)
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

                    // ── Body Weight Card (Task 3, Phase H) ──────────────────────
                    bodyWeightCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Recent Activity Row (redesign: rounded card row) ───────
                    NavigationLink { ActivityFeedView() } label: {
                        navRow(title: "Activity")
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .contentMargins(.bottom, 88, for: .scrollContent)   // dock clearance (user bug report)
            .gsSpotlight(.stats)
            .task {
                exercises = (try? await ExerciseRepository.fetchAll()) ?? []
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
                await loadLedger()
                await loadStreak()
                await loadBodyWeight()
            }
            .refreshable {
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
                await loadLedger()
                await loadStreak()
                await loadBodyWeight()
            }
            .sheet(isPresented: $showingBodyWeightLogSheet) {
                BodyWeightLogSheet(onLogged: { Task { await loadBodyWeight() } })
            }
            .sheet(isPresented: $showLedgerPaywall) {
                PaywallView(highlight: .deepHistory)
            }
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
        Group {
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
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    // MARK: - Shared nav row (redesign)

    /// Nav-row LABEL only — the extruded chrome comes from the enclosing
    /// NavigationLink's `.gs3DCardStyle` (crew-row precedent: a surface
    /// fill here would paint over the face). Default text per the owner's
    /// color law.
    private func navRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(GSFont.bodyMedium(15, relativeTo: .body))
                .foregroundStyle(theme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Streak")
            HStack(spacing: 8) {
                // Default value color (owner's text law, 2026-08-12) — the
                // old live-streak accent tint retired with the sweep.
                GSStatTile(
                    value: currentStreakValue,
                    label: "Current streak"
                )
                GSStatTile(
                    value: "\(userStreak?.longestStreak ?? 0)",
                    label: "Longest streak"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// Plain "N" — the redesign's emoji sweep (spec §7) replaced the "🔥 N"
    /// tile value, and the owner's default-text law (2026-08-12) later
    /// retired the live-streak accent tint too. The backend's push copy
    /// keeps its own 🔥 — that's message text, not UI chrome.
    private var currentStreakValue: String {
        "\(userStreak?.currentStreak ?? 0)"
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
        Group {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GSSectionHeader("Body Weight")
                    Spacer()
                    // Extruded like every tappable (design law) — the
                    // compact gs3D anatomy MyRackView's RACK control uses.
                    Button {
                        showingBodyWeightLogSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Log").font(GSFont.bold(13, relativeTo: .subheadline))
                        }
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                    }
                    .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 10, lipHeight: 5))
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
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
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
        // Attempted lifts: distinct exercises across the PR ledger (every
        // qualifying set mints a record), most recent first.
        let prs = (try? await PersonalRecordRepository.recent(userID: userID, limit: 400)) ?? []
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for pr in prs where !seen.contains(pr.exerciseID) {
            seen.insert(pr.exerciseID)
            ordered.append(pr.exerciseID)
        }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        attemptedExercises = ordered.compactMap { byID[$0] }
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

    // MARK: - The Ledger (owner 2026-08-16)

    struct LedgerEntry: Identifiable {
        let session: WorkoutSession
        let routineName: String?
        let sets: Int
        let volumePounds: Decimal
        let minutes: Int?
        var id: UUID { session.id }
    }

    private func ledgerRow(_ entry: LedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(entry.routineName ?? "Freeform workout")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text((entry.session.startedAt ?? entry.session.scheduledFor ?? .now)
                    .formatted(.dateTime.month(.abbreviated).day()))
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Text(ledgerMetaLine(entry))
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func ledgerMetaLine(_ entry: LedgerEntry) -> String {
        var parts = ["\(entry.sets) sets"]
        if entry.volumePounds > 0 {
            let unit = ThemeStore.shared.weightUnit
            parts.append("\(StatMath.compactNumber(Units.fromPounds(entry.volumePounds, to: unit))) \(unit.label)")
        }
        if let minutes = entry.minutes, minutes > 0 {
            parts.append("~\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    /// One windowed logs fetch (`ledgerDaysLoaded` deep) → per-session
    /// aggregates → the session rows. Duration derives from the logs' own
    /// timestamps (first to last set) — honest for how long the lifting
    /// actually ran. Rolling load re-runs this with a deeper window; the
    /// rebuild is O(total) but a ledger's volume stays small.
    @MainActor
    private func loadLedger() async {
        guard let userID = appState.currentProfile?.id else { return }
        let since = Calendar.current.date(byAdding: .day, value: -ledgerDaysLoaded, to: .now) ?? .now
        let logs = (try? await SessionRepository.recentSetLogs(userID: userID, since: since)) ?? []
        let bySession = Dictionary(grouping: logs.filter { !$0.isPenalty }, by: \.sessionID)
        guard !bySession.isEmpty else { return }
        let sessions = (try? await SessionRepository.byIDs(Array(bySession.keys))) ?? []
        let names = ((try? await RoutineRepository.fetchAll(ownerID: userID)) ?? [])
            .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
        ledgerEntries = sessions
            .map { session -> LedgerEntry in
                let sessionLogs = bySession[session.id] ?? []
                let volume = sessionLogs.reduce(Decimal(0)) { acc, log in
                    acc + (log.effectiveWeightPounds ?? 0) * Decimal(log.completedReps ?? 0)
                }
                let times = sessionLogs.map(\.loggedAt)
                let minutes: Int?
                if let first = times.min(), let last = times.max(), last > first {
                    minutes = Int(last.timeIntervalSince(first) / 60)
                } else {
                    minutes = nil
                }
                return LedgerEntry(
                    session: session,
                    routineName: session.routineID.flatMap { names[$0] },
                    sets: sessionLogs.count,
                    volumePounds: volume,
                    minutes: minutes)
            }
            .sorted { ($0.session.startedAt ?? .distantPast) > ($1.session.startedAt ?? .distantPast) }
    }

    /// Rolling load: extend the window 30 days at a time. Free users stop
    /// at the 30-day line (`ledgerGated` renders the Pro row instead);
    /// a lifting gap of up to ~90 days is bridged before calling the
    /// history exhausted, and three years is the hard floor.
    @MainActor
    private func loadMoreLedger() async {
        guard !ledgerLoadingMore, !ledgerExhausted, !ledgerGated,
              ledgerDaysLoaded < 1095 else { return }
        ledgerLoadingMore = true
        defer { ledgerLoadingMore = false }
        var grew = false
        for _ in 0..<3 {
            ledgerDaysLoaded += 30
            let before = ledgerEntries.count
            await loadLedger()
            if ledgerEntries.count > before { grew = true; break }
        }
        if !grew { ledgerExhausted = true }
    }
}

// MARK: - AttemptedExercisesView (the PR widget's destination)

/// The populated list of lifts you've actually attempted (owner
/// 2026-08-16) — each row opens the per-exercise page: est-1RM trend
/// graph up top, the time series below, exactly the existing
/// ExerciseHistoryView language.
struct AttemptedExercisesView: View {
    @Environment(\.gsTheme) private var theme
    let exercises: [Exercise]
    /// nil = the signed-in lifter; a trainer passes the client's id.
    var subjectID: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if exercises.isEmpty {
                    Text("Nothing attempted yet — records build as you train.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 40)
                } else {
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            ExerciseHistoryView(exercise: exercise, subjectID: subjectID)
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .font(GSFont.bold(14, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.neutral500)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                    }
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }
}
