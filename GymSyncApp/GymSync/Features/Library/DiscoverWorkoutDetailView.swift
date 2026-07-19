import SwiftUI

// MARK: - DiscoverWorkoutDetailView
//
// Phase L Task 3 — public workout detail. Master spec Flow 4
// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:790-797`):
// "Workout detail page shows description, scoring metrics, leaderboard
// (sortable by Time / Total Volume / Top Set / Recent — default sort set by
// creator). Two big CTAs: Attempt Solo... and Attempt with Friends...
// 'Show me on leaderboard' toggle is opt-in per attempt."
//
// Exercise-list row shape reuses `RoutineBuilderView.exerciseRow`'s header
// idiom (name + primary-muscle/equipment caption,
// `Features/Library/RoutineBuilderView.swift:230-251`) minus the
// drag-handle/editable-stat-tiles/remove-button chrome — this is someone
// else's published routine, read-only, not an editor.
//
// Leaderboard row shape reuses `GroupRecapView.leaderboardRow`'s rank +
// avatar + name + metric idiom (`Features/Sessions/GroupRecapView.swift:
// 323-359`), swapping its kudos chip for the "✏️ edited" indicator this
// task's brief calls for, and its `initials`-string avatar for
// `GSInitialsAvatar` (`Features/Social/SocialTabView.swift:387-432`, the
// avatar-or-real-photo idiom this task's brief names explicitly).
//
// Report/Block toolbar: `RoutineModerationToolbar` (Phase M Task 2's
// implementation extracted for this exact reuse —
// `Features/Moderation/RoutineModerationToolbar.swift`). Unlike
// `RoutinesListView`'s `RoutineDetailChoice` (whose only reachable path is
// always the caller's OWN routine, so the menu was always inert there),
// EVERY routine reachable through Discover belongs to someone else by
// construction (`visibility='public'`, not necessarily the viewer's own),
// so this is the surface's first genuinely live use.
//
// No canvas frame exists for this screen — same "Discover undesigned"
// finding as `DiscoverView`; see `docs/design/accepted-deviations.json`'s
// "discover-detail" entry.
struct DiscoverWorkoutDetailView: View {
    let workout: PublicWorkout

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var routineExercises: [RoutineExercise] = []
    @State private var allExercises: [Exercise] = []
    @State private var leaderboardEntries: [LeaderboardEntryRow] = []
    @State private var loading = true
    @State private var errorText: String?
    // Deliberately separate from `errorText` above — same reasoning as
    // `RoutineDetailChoice`'s identically-named state (RoutinesListView.
    // swift): a failed block/report action shouldn't blank the whole screen.
    @State private var moderationErrorText: String?

    @State private var selectedSort: SortMetric

    // MARK: - Attempt Solo
    @State private var showAttemptOptInDialog = false
    @State private var startingAttemptOptIn: Bool?
    @State private var startAttemptNavigation = false

    // MARK: - Attempt with Friends
    @State private var showScheduleSheet = false

    #if DEBUG
    /// Debug-only: skips the live `.task` fetch for `CatalogHostView`'s
    /// `discover-detail` state — same seam idiom as `DiscoverView.
    /// catalogSkipLoad` / `ChatView.catalogSkipLoad`.
    var catalogSkipLoad = false
    #endif

    /// Sort options a leaderboard can be viewed by. Raw values match the
    /// `routines.default_sort`/`scoring_metrics` CHECK constraint's value set
    /// verbatim (`20260723000001_public_workout_repository.sql:31-34`:
    /// `'time','volume','top_set'` for scoring_metrics, +'recent' for
    /// default_sort) so `SortMetric(rawValue:)` round-trips both DB columns
    /// directly.
    enum SortMetric: String, CaseIterable, Identifiable {
        case time, volume
        case topSet = "top_set"
        case recent

        var id: String { rawValue }

        var label: String {
            switch self {
            case .time: return "Time"
            case .volume: return "Volume"
            case .topSet: return "Top Set"
            case .recent: return "Recent"
            }
        }
    }

    init(workout: PublicWorkout) {
        self.workout = workout
        _selectedSort = State(initialValue: Self.initialSort(for: workout))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else if let errorText {
                    Text(errorText)
                        .font(GSFont.body(14))
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    if let moderationErrorText {
                        Text(moderationErrorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }

                    headerSection

                    if !orderedExercises.isEmpty {
                        exerciseListSection
                    }

                    attemptCTAs

                    GSDivider()

                    leaderboardSection
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle(workout.routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .routineModerationToolbar(
            ownerID: workout.routine.ownerID,
            routineID: workout.routine.id,
            // Honest check, not a hardcoded `false`: Discover's routines are
            // NOT the caller's own on every reachable path today, but a
            // curator viewing their OWN published/featured routine through
            // Discover is a real (if rare) future case this still handles
            // correctly.
            isOwnContent: workout.routine.ownerID == appState.currentProfile?.id,
            moderationErrorText: $moderationErrorText
        )
        .confirmationDialog(
            "Show me on the leaderboard?",
            isPresented: $showAttemptOptInDialog,
            titleVisibility: .visible
        ) {
            Button("Yes, show me") { Task { await beginSoloAttempt(optIn: true) } }
            Button("No, keep private") { Task { await beginSoloAttempt(optIn: false) } }
            Button("Cancel", role: .cancel) {}
        }
        // Attempt Solo — Flow 3 with the routine pre-selected (Flow 4:
        // "launches Flow 3 with the public routine pre-selected"). Reuses
        // this screen's ALREADY-loaded `routineExercises`/`allExercises`
        // (loaded once by `load()` for the exercise-list section above) —
        // same mechanism `HomeView.RoutinePickerSheet.start(routine:)` uses
        // (fetch once, hand straight to `WorkoutSessionView`,
        // `HomeView.swift:628-637`), just without a redundant second fetch
        // since the data is already in hand. `WorkoutSessionView` itself
        // creates the solo session (`startIfNeeded()` ->
        // `SessionRepository.startSolo(routineID:)`) and, because
        // `attemptOptIn` is non-nil here, calls `start_attempt` right after
        // (see that view's doc comment).
        .navigationDestination(isPresented: $startAttemptNavigation) {
            WorkoutSessionView(
                routine: workout.routine,
                routineExercises: routineExercises,
                allExercises: allExercises,
                attemptOptIn: startingAttemptOptIn
            )
        }
        // Attempt with Friends — Flow 2's schedule sheet, pre-loaded with
        // this routine (Flow 4: "launches Flow 2 schedule sheet
        // pre-loaded"). `onScheduled: { _ in }` is deliberate, not a stub:
        // scheduling a GROUP attempt never creates a `workout_attempts` row
        // here — see this view's own doc comment on `showScheduleSheet`
        // above for why that's a documented follow-up, not this task's
        // scope. `ScheduleSessionView` dismisses itself on success
        // (`schedule()`'s own `dismiss()` call); the new session shows up
        // through Home's existing Upcoming Sessions list like any other
        // scheduled session.
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleSessionView(preloadedRoutine: workout.routine) { _ in }
        }
        .task { await load() }
    }

    // MARK: - Header (description + metric chips)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.routine.name)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            Text("by \(workout.ownerUsername)")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)

            if let description = workout.routine.description, !description.isEmpty {
                Text(description)
                    .font(GSFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
            }

            if let metrics = workout.scoringMetrics, !metrics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(metrics, id: \.self) { metric in
                        GSTag(text: DiscoverView.metricLabel(metric), style: .accent)
                    }
                }
            }
        }
    }

    // MARK: - Exercise list (read-only; reuses RoutineBuilderView.exerciseRow's idiom)

    private var orderedExercises: [RoutineExercise] {
        routineExercises.sorted { $0.position < $1.position }
    }

    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Exercises")
            VStack(spacing: 8) {
                ForEach(orderedExercises) { re in
                    exerciseRow(re)
                }
            }
        }
    }

    private func exerciseRow(_ re: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == re.exerciseID }
        let summary = targetSummary(re)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? "Exercise")
                    .font(GSFont.heading(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                if let ex {
                    Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
            }
            Spacer()
            if !summary.isEmpty {
                Text(summary)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .padding(12)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private func targetSummary(_ re: RoutineExercise) -> String {
        var parts: [String] = []
        if let sets = re.targetSets { parts.append("\(sets) sets") }
        if let reps = re.targetReps, !reps.isEmpty { parts.append(reps) }
        if let weight = re.targetWeight, !weight.isEmpty { parts.append(weight) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Attempt CTAs

    private var attemptCTAs: some View {
        VStack(spacing: 8) {
            Button {
                showAttemptOptInDialog = true
            } label: {
                Text("Attempt Solo")
            }
            .buttonStyle(GSPrimaryButtonStyle())

            Button {
                showScheduleSheet = true
            } label: {
                Text("Attempt with Friends")
            }
            .buttonStyle(GSSecondaryButtonStyle())
        }
    }

    @MainActor
    private func beginSoloAttempt(optIn: Bool) async {
        startingAttemptOptIn = optIn
        startAttemptNavigation = true
    }

    // MARK: - Leaderboard

    /// Which sort tabs to OFFER — filtered to the routine's OWN
    /// `scoring_metrics`, per this task's brief ("the UI applies the
    /// routine's scoring_metrics filter for which sort options to offer")
    /// PLUS "Recent" always. "Top Set" is further gated on
    /// `scoring_top_set_exercise_id` actually being set — `scoring_metrics`
    /// containing `'top_set'` with no chosen exercise is a real (if
    /// curator-error) data state the CHECK constraint doesn't rule out, and
    /// offering a Top Set tab with nothing to rank by would be a dead tab.
    static func offeredSorts(for workout: PublicWorkout) -> [SortMetric] {
        let scoring = Set(workout.scoringMetrics ?? [])
        var result: [SortMetric] = []
        if scoring.contains("time") { result.append(.time) }
        if scoring.contains("volume") { result.append(.volume) }
        if scoring.contains("top_set"), workout.scoringTopSetExerciseID != nil {
            result.append(.topSet)
        }
        result.append(.recent)
        return result
    }

    /// Default tab = the routine's own `default_sort` (Flow 4: "default sort
    /// set by creator") when it's actually one of the offered tabs; "Recent"
    /// otherwise (an unset/invalid default_sort, or a default_sort the
    /// routine's own scoring_metrics doesn't actually offer).
    private static func initialSort(for workout: PublicWorkout) -> SortMetric {
        let offered = offeredSorts(for: workout)
        guard let raw = workout.defaultSort, let parsed = SortMetric(rawValue: raw),
              offered.contains(parsed) else {
            return .recent
        }
        return parsed
    }

    /// Client-side sort over ONE fetch (`load()`'s `leaderboardEntries`) —
    /// judgment call (brief: "server-side order via the query or client
    /// sort; judge, cite"): re-fetching per segmented-control tap would be
    /// 4x the network calls for no benefit (`PublicWorkoutRepository.
    /// leaderboard`'s own doc comment). Rank-metric semantics mirror Task
    /// 2's server-side `leaderboard_rank_and_passed` decision (`.superpowers/
    /// sdd/task-2-report.md`'s "Rank-metric decision"): time ASC, volume
    /// DESC, top_set DESC on the routine's chosen exercise, recent = most
    /// recently computed first. Entries missing the selected metric are
    /// dropped from that tab's ranking (never shown with a fabricated rank).
    private var sortedEntries: [LeaderboardEntryRow] {
        switch selectedSort {
        case .time:
            return leaderboardEntries
                .filter { $0.timeSeconds != nil }
                .sorted { $0.timeSeconds! < $1.timeSeconds! }
        case .volume:
            return leaderboardEntries
                .filter { $0.totalVolume != nil }
                .sorted { $0.totalVolume! > $1.totalVolume! }
        case .topSet:
            guard let exerciseID = workout.scoringTopSetExerciseID else { return [] }
            let key = exerciseID.uuidString.lowercased()
            return leaderboardEntries
                .compactMap { entry -> (LeaderboardEntryRow, Decimal)? in
                    guard let weight = entry.topSets?[key] else { return nil }
                    return (entry, weight)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        case .recent:
            return leaderboardEntries.sorted { $0.computedAt > $1.computedAt }
        }
    }

    /// The row value shown for the CURRENTLY selected sort tab — e.g. a row
    /// shows its Time when the Time tab is active, its Volume when the
    /// Volume tab is active. "Recent" has no scored metric of its own
    /// (Task 2's `leaderboard_rank_and_passed` returns NULL rank for it too)
    /// — shows a relative "how long ago" instead, the one thing "Recent"
    /// actually orders by.
    private func metricValueText(_ entry: LeaderboardEntryRow) -> String {
        switch selectedSort {
        case .time:
            guard let seconds = entry.timeSeconds else { return "—" }
            return Self.formatMMSS(seconds)
        case .volume:
            guard let volume = entry.totalVolume else { return "—" }
            return "\(formatVolume(volume)) lbs"
        case .topSet:
            guard let exerciseID = workout.scoringTopSetExerciseID,
                  let weight = entry.topSets?[exerciseID.uuidString.lowercased()] else { return "—" }
            return "\(formatVolume(weight)) lbs"
        case .recent:
            return relativeDateText(entry.computedAt)
        }
    }

    private static func formatMMSS(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// Comma-grouped, zero-decimal — same shape as `GroupStatsView.
    /// formatVolumeFull`/`GroupRecapView`'s row volume text (documented
    /// duplication across this codebase; every leaderboard-row volume
    /// display uses this exact `NumberFormatter` recipe).
    private func formatVolume(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = NSDecimalNumber(decimal: value).doubleValue
        return formatter.string(from: NSNumber(value: raw)) ?? "0"
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Leaderboard")
                .padding(.bottom, 8)

            sortSegmentedControl
                .padding(.bottom, 8)

            let entries = sortedEntries
            if leaderboardEntries.isEmpty {
                Text("No attempts yet — be the first")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else if entries.isEmpty {
                Text("No \(selectedSort.label) data for these attempts yet")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        leaderboardRow(rank: index + 1, entry: entry)
                        if index < entries.count - 1 {
                            Rectangle().fill(theme.divider).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // Canvas idiom: `LibraryTabView.segmentedControl`'s flat-rectangle,
    // 1px-divider-border segmented control (`Features/Library/
    // LibraryTabView.swift:65-76`), reimplemented locally (that one is
    // `private` to its own file) since this screen needs a dynamic,
    // per-routine tab COUNT (2-4 tabs depending on `scoring_metrics`) rather
    // than a fixed 2.
    private var sortSegmentedControl: some View {
        let offered = Self.offeredSorts(for: workout)
        return HStack(spacing: 0) {
            ForEach(Array(offered.enumerated()), id: \.element.id) { index, metric in
                sortSegmentOption(metric)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle().fill(theme.divider).frame(width: 1)
                        }
                    }
            }
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private func sortSegmentOption(_ metric: SortMetric) -> some View {
        let isSelected = selectedSort == metric
        return Button {
            selectedSort = metric
        } label: {
            Text(metric.label)
                .font(GSFont.bodyMedium(12, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? theme.bg : theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(isSelected ? theme.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func leaderboardRow(rank: Int, entry: LeaderboardEntryRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 20, alignment: .leading)

            GSInitialsAvatar(name: entry.username, avatarURL: entry.avatarURL, size: 32)

            Text(entry.username)
                .font(GSFont.bold(13, relativeTo: .body))
                .foregroundStyle(theme.text)

            if entry.isEdited {
                // Flow 6 (`:836`): "an '✏️ edited' indicator appears next to
                // the entry" — session duration was corrected post-hoc,
                // time_seconds stays locked to the original.
                Text("✏️")
                    .font(.system(size: 12))
            }

            Spacer()

            Text(metricValueText(entry))
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        do {
            async let exercisesFetch = ExerciseRepository.fetchAll()
            async let routineFetch = RoutineRepository.fetch(id: workout.routine.id)
            // Task 7 item 3: pass the routine's own ranking axis through so
            // the server-side LIMIT(200) is taken along the metric this
            // leaderboard is actually judged by, not a hardcoded recency
            // window — see `leaderboard()`'s own doc comment for the full
            // fix rationale.
            async let leaderboardFetch = PublicWorkoutRepository.leaderboard(
                routineID: workout.routine.id,
                defaultSort: workout.defaultSort,
                topSetExerciseID: workout.scoringTopSetExerciseID)
            let (exercises, routineResult, entries) = try await (exercisesFetch, routineFetch, leaderboardFetch)
            allExercises = exercises
            if let (_, exs) = routineResult {
                routineExercises = exs
            }
            leaderboardEntries = entries
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Catalog fixture seam (`discover-detail` catalog case)

#if DEBUG
extension DiscoverWorkoutDetailView {
    /// Debug-only seam — same idiom as `DiscoverView`'s fixture init above
    /// it in this task; `_selectedSort`'s initial value is still derived via
    /// `initialSort(for:)` so the fixture faithfully exercises the same
    /// default-tab logic the live path uses.
    init(catalogFixtureWorkout workout: PublicWorkout,
         catalogFixtureRoutineExercises routineExercises: [RoutineExercise],
         catalogFixtureAllExercises allExercises: [Exercise],
         catalogFixtureLeaderboard leaderboard: [LeaderboardEntryRow]) {
        self.workout = workout
        _selectedSort = State(initialValue: Self.initialSort(for: workout))
        _routineExercises = State(initialValue: routineExercises)
        _allExercises = State(initialValue: allExercises)
        _leaderboardEntries = State(initialValue: leaderboard)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
}
#endif
