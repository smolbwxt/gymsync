import SwiftUI

// Canvas: Solo workout "In Progress" screen
// - Header bar: routine name + elapsed time + Finish button
// - Accent-filled exercise card (EXERCISE N OF M / Set N of M / name / target)
// - Logged sets table: SET | REPS | WEIGHT | RPE columns, checkmark for completed rows
// - "Log Set N" ghost-style bottom anchor button
struct WorkoutSessionView: View {
    // Optional to support the Home "No routine" solo-start option (Task 5):
    // a nil routine starts an untargeted session (routineExercises empty,
    // startSolo(routineID: nil)) using this exact same view — no parallel
    // session-start path was introduced.
    let routine: Routine?
    let routineExercises: [RoutineExercise]
    let allExercises: [Exercise]
    /// Non-nil only for a Discover "Attempt Solo" launch — carries the
    /// user's "Show me on the leaderboard?" choice. `startIfNeeded()` calls
    /// `start_attempt` right after creating the solo session, matching the
    /// backend contract (`.superpowers/sdd/task-2-report.md`: "call AFTER
    /// creating the session with that routine"). `nil` for every other
    /// launch of this view (Home's Start Solo Workout / a routine's own
    /// "Start Workout") — those never touch `workout_attempts` at all.
    /// Defaulted so every pre-existing call site (`HomeView.swift`,
    /// `RoutinesListView.swift`) is source-compatible unchanged.
    let attemptOptIn: Bool?

    init(routine: Routine?, routineExercises: [RoutineExercise], allExercises: [Exercise], attemptOptIn: Bool? = nil) {
        self.routine = routine
        self.routineExercises = routineExercises
        self.allExercises = allExercises
        self.attemptOptIn = attemptOptIn
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var session: WorkoutSession?
    @State private var loggedSets: [SetLog] = []
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 1
    @State private var showLogSheet = false
    @State private var errorText: String?
    @State private var completed = false
    // Full-screen, USER-DISMISSED PR celebration (p29) — shared with GroupSessionLiveView
    // via PRCelebrationOverlay (Phase P Task 1). Replaces the old 2s auto-dismissing
    // "isPRToast" banner, mirroring the same takeover GroupSessionLiveView already did.
    @State private var isPROverlay = false
    @State private var prOverlayExerciseName: String = ""
    @State private var prOverlayWeight: Decimal = 0
    @State private var prOverlayReps: Int = 0
    @State private var prOverlayPriorBest: Decimal = 0
    /// Always nil in the solo path — mirrors `GroupSessionLiveView`'s pre-resolution state.
    /// Solo has no established `countSince` plumbing wired to this view; see Task 2 report
    /// for the decision not to invent that ordering here (badge suppressed, by design).
    @State private var prOverlayMonthlyCount: Int? = nil
    @State private var setStartedAt: Date = .now
    /// End of the current rest window (started right after a set is logged,
    /// using that exercise's `restSeconds`). Cleared once the lifter starts
    /// logging the next set — same "no polling Timer" pattern as the elapsed
    /// header clock: `Text(timerInterval:countsDown:)` renders itself live.
    @State private var restEndAt: Date?
    /// PRs achieved this session — consumed by the recap view (Task 9).
    @State private var sessionPRs: [PersonalRecord] = []
    /// The completed session record (has `completedAt`) — captured by `endSession()`
    /// so the recap's duration hero can compute `completedAt - startedAt`.
    @State private var completedSession: WorkoutSession?
    /// True only when `HealthKitBridge.exportWorkout` succeeded. Phase U
    /// Task 4 suppressed the recap's "Synced to Apple Health" card until
    /// Phase H shipped it (write-only until now); `recapHealthSummary` below
    /// reads this to decide whether that card renders at all — a failed
    /// export means no card, never a card claiming a sync that didn't
    /// happen. Export itself never blocks completion on failure.
    @State private var healthSynced: Bool = false
    /// Fallback rest duration for exercises with no per-exercise `restSeconds`
    /// configured (e.g. a routine item where rest was left unset) — read from
    /// `user_settings.default_rest_seconds` in `.task`, falls back to the
    /// column's own default (120) if the fetch hasn't resolved yet or fails.
    /// Canvas Completion Task 2 wiring: previously such exercises got no rest
    /// timer at all (`re.restSeconds.map { ... }` at the call site below was
    /// `nil`-guarded away); now they use the user's configured default.
    @State private var defaultRestSeconds: Int = 120
    /// Minor finding 2 (review): a failed leaderboard opt-in (`start_attempt`)
    /// used to be log-only — the user never learned their "show me on the
    /// leaderboard" choice silently didn't take. Non-blocking transient
    /// notice, same "@State String?, overlay + `.animation`, auto-clear after
    /// a fixed delay" shape as `GroupSessionLiveView`'s incoming-sound pill
    /// (`soundOverlayText` / `showSoundOverlay(_:)`,
    /// `GroupSessionLiveView.swift:68,502-522,1577-1583) — reused rather than
    /// inventing a new toast component. Never blocks `startIfNeeded()` or the
    /// workout itself (see that function's catch block below).
    @State private var attemptOptInFailedText: String? = nil

    private var currentRoutineExercise: RoutineExercise? {
        guard currentExerciseIndex < routineExercises.count else { return nil }
        return routineExercises[currentExerciseIndex]
    }

    private var currentExercise: Exercise? {
        guard let re = currentRoutineExercise else { return nil }
        return allExercises.first { $0.id == re.exerciseID }
    }

    var body: some View {
        ZStack {
            Group {
                if completed {
                    // Canvas: "Workout Complete" recap (frame 17) — extracted to
                    // `SoloRecapView` (Phase U Task 4) so the debug catalog can
                    // construct it directly with fixture data; see that type for
                    // the full layout. Every value below is derived from state
                    // this view already holds (§B.10) — no new queries.
                    SoloRecapView(
                        kicker: recapKicker,
                        durationText: recapDurationText,
                        subline: recapSubline,
                        totalLbsText: recapTotalLbsHeroText,
                        setCount: recapNonPenaltySets.count,
                        prCount: sessionPRs.count,
                        heaviestPR: recapHeaviestPR,
                        exerciseSummaries: exerciseSummaries,
                        healthSummary: recapHealthSummary,
                        shareSummary: recapShareSummary,
                        onDone: { dismiss() }
                    )
                } else {
                    liveSessionBody
                }
            }

            // ── PR CELEBRATION (full-screen, user-dismissed — p29) ─────────
            // Sibling of the completed/live `Group` above — NOT a child of
            // `liveSessionBody`'s own ZStack — so it survives the `completed`
            // transition. When the session's LAST set is also a PR, `log()` sets
            // `isPROverlay = true` and then `endSession()` flips `completed = true`,
            // which structurally unmounts `liveSessionBody`; an overlay nested
            // inside it would vanish before the user could dismiss it (bug found
            // in Phase U Task 4 review — pre-refactor this was a flat ZStack
            // sibling too, which is why it survived back then). Same "direct
            // ZStack child gated on its own bool" idiom as GroupSessionLiveView;
            // user-dismissed only, no auto-timeout.
            if isPROverlay {
                PRCelebrationOverlay(
                    exerciseName: prOverlayExerciseName,
                    weight: prOverlayWeight,
                    reps: prOverlayReps,
                    priorBest: prOverlayPriorBest,
                    monthlyCount: prOverlayMonthlyCount,
                    onDismiss: {
                        withAnimation(.easeIn(duration: 0.2)) { isPROverlay = false }
                    }
                )
                .transition(.opacity)
            }
        }
        .background(theme.bg)
        // Minor finding 2: non-blocking "couldn't join the leaderboard"
        // notice — same transient-pill idiom + placement style as
        // GroupSessionLiveView's incoming-sound overlay (that one docks at
        // `.bottom`, above its dock area; `.top` here since this view's
        // bottom is already occupied by the sticky "Log Set N" button).
        .overlay(alignment: .top) {
            if let txt = attemptOptInFailedText {
                Text(txt)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.neutral700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(theme.surface)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                    .padding(.top, 8)
                    .transition(.opacity)
                    .id(txt)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: attemptOptInFailedText)
        // Pushed from Home's "Start Solo Workout" / a routine's "Start Workout";
        // the sticky "Log Set N" / "Done" CTA is a bottom-pinned ZStack overlay,
        // not a safeAreaInset — see GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .navigationTitle(routine?.name ?? "Freeform Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!completed)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !completed {
                // Canvas "In Progress" elapsed timer — state-driven from `startedAt`,
                // ZERO Swift Timers (same `Text(_:style:.timer)` pattern as the 3b
                // chess clock in GroupSessionLiveView).
                ToolbarItem(placement: .navigationBarLeading) {
                    if let startedAt = session?.startedAt {
                        Text(startedAt, style: .timer)
                            .font(GSFont.bold(14, relativeTo: .caption))
                            .foregroundStyle(theme.text)
                            .monospacedDigit()
                    }
                }
                // Canvas: solid neutral "Finish" button (not the accent-outlined
                // "End" bordered treatment previously used here).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await endSession() }
                    } label: {
                        Text("Finish")
                            .font(GSFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.neutral400)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await startIfNeeded() }
        .task { await loadDefaultRestSeconds() }
        .sheet(isPresented: $showLogSheet) {
            if let ex = currentExercise, let re = currentRoutineExercise {
                LogSetSheet(
                    exercise: ex,
                    setIndex: currentSetIndex,
                    defaultReps: re.targetReps,
                    defaultWeight: re.targetWeight
                ) { reps, weight, rpe, isFailed, note in
                    Task { await log(reps: reps, weight: weight, rpe: rpe,
                                     isFailed: isFailed, note: note) }
                }
            }
        }
    }

    // Canvas: "In Progress" live session — exercise header/table/rest-timer,
    // freeform empty state, loading spinner, and sticky "Log Set N" footer.
    // The `!completed` guard on the sticky "Log Set N" button was dropped
    // since this whole computed property only ever renders while `!completed`.
    // The PR celebration overlay used to live in this ZStack too (pre-Task-4
    // and through the first cut of Phase U Task 4), but a last-set PR could
    // set `isPROverlay = true` right before `endSession()` set `completed =
    // true`, unmounting this whole view out from under the still-undismissed
    // overlay. It now lives one level up, as a sibling of the `completed` ?
    // `SoloRecapView` : `liveSessionBody` switch in `body` — see the comment
    // there.
    private var liveSessionBody: some View {
        ZStack(alignment: .bottom) {
            // Main scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let ex = currentExercise, let re = currentRoutineExercise {
                        // Canvas: accent-filled exercise header card
                        exerciseHeaderCard(ex: ex, re: re)

                        // Canvas: logged sets table
                        loggedSetsTable

                        restTimerRow

                    } else if session != nil && routineExercises.isEmpty {
                        freeformEmptyState
                    } else {
                        HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                            .padding(.top, 40)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .caption))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 14)
                // bottom padding so content isn't hidden behind sticky Log Set button
                .padding(.bottom, 88)
            }

            // Canvas: sticky "Log Set N" button anchored at screen bottom
            if currentExercise != nil {
                VStack(spacing: 0) {
                    GSDivider()
                    Button {
                        setStartedAt = .now
                        restEndAt = nil
                        showLogSheet = true
                    } label: {
                        Text("Log Set \(currentSetIndex)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                }
                .background(theme.bg)
            }
        }
    }

    // Canvas: accent-filled card — "EXERCISE N OF M" kicker / "Set N of M" trailing /
    //         large exercise name / "Target X × Y · rest Z:00" sub-line
    private func exerciseHeaderCard(ex: Exercise, re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("EXERCISE \(currentExerciseIndex + 1) OF \(routineExercises.count)")
                    .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(theme.bg.opacity(0.85))
                Spacer()
                Text("Set \(currentSetIndex) of \(re.targetSets ?? 1)")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
            Text(ex.name)
                .font(GSFont.heading(28, relativeTo: .title))
                .foregroundStyle(theme.bg)
                .lineLimit(2)

            // Target line
            let targetParts: [String] = [
                re.targetWeight.map { "\($0)" },
                re.targetReps.map { "× \($0)" },
                re.restSeconds.map { "· rest \(formatRest($0))" }
            ].compactMap { $0 }
            if !targetParts.isEmpty {
                Text("Target " + targetParts.joined(separator: " "))
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
        .padding(.horizontal, 16)
    }

    // Canvas: Logged sets — columnar table SET | REPS | WEIGHT | RPE with header row
    private var loggedSetsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LOGGED")
                .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral700)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // Column header
            loggedRowCells(
                col0: Text("SET").font(GSFont.bodyMedium(9, relativeTo: .caption2)).tracking(0.5).foregroundStyle(theme.neutral500),
                col1: Text("REPS").font(GSFont.bodyMedium(9, relativeTo: .caption2)).tracking(0.5).foregroundStyle(theme.neutral500),
                col2: Text("WEIGHT").font(GSFont.bodyMedium(9, relativeTo: .caption2)).tracking(0.5).foregroundStyle(theme.neutral500),
                col3: Text("RPE").font(GSFont.bodyMedium(9, relativeTo: .caption2)).tracking(0.5).foregroundStyle(theme.neutral500)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 5)

            GSDivider().padding(.horizontal, 16)

            // Completed sets
            let currentExSets = loggedSets.filter { $0.exerciseID == currentRoutineExercise?.exerciseID }
            ForEach(currentExSets) { log in
                loggedRowCells(
                    // Phase O Task 3 — syncing indicator (system-designed, no canvas
                    // frame; see docs/design/accepted-deviations.json's
                    // "offline-syncing-indicator" entry). Swaps the normal checkmark
                    // for a rotate-arrows glyph while `log.id` is still queued in
                    // OfflineSetLogQueue — same "read the singleton directly" idiom
                    // ConnectivityMonitor.shared.isOnline already uses elsewhere.
                    col0: Group {
                        if OfflineSetLogQueue.shared.pendingSetLogIDs.contains(log.id) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.accent700)
                        }
                    },
                    col1: Text("\(log.reps ?? 0)")
                              .font(GSFont.heading(15, relativeTo: .body))
                              .foregroundStyle(theme.text),
                    col2: Text(log.weight.map { "\($0)" } ?? "—")
                              .font(GSFont.heading(15, relativeTo: .body))
                              .foregroundStyle(theme.text),
                    col3: Text(log.rpe.map { "\($0)" } ?? "—")
                              .font(GSFont.heading(15, relativeTo: .body))
                              .foregroundStyle(theme.text)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                GSDivider().padding(.horizontal, 16)
            }

            // Current pending set row — muted dashes
            let pendingSetNum = currentExSets.count + 1
            if let re = currentRoutineExercise, pendingSetNum <= (re.targetSets ?? 1) {
                loggedRowCells(
                    col0: Text("\(pendingSetNum)")
                              .font(GSFont.heading(13, relativeTo: .body))
                              .foregroundStyle(theme.accent700),
                    col1: Text("—").font(GSFont.heading(15, relativeTo: .body)).foregroundStyle(theme.neutral500),
                    col2: Text("—").font(GSFont.heading(15, relativeTo: .body)).foregroundStyle(theme.neutral500),
                    col3: Text("—").font(GSFont.heading(15, relativeTo: .body)).foregroundStyle(theme.neutral500)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(theme.accent.opacity(0.1))
            }
        }
    }

    // 4-column grid layout matching canvas: 28px / 1fr / 1fr / 1fr
    @ViewBuilder
    private func loggedRowCells<C0: View, C1: View, C2: View, C3: View>(
        col0: C0, col1: C1, col2: C2, col3: C3
    ) -> some View {
        HStack(spacing: 0) {
            col0.frame(width: 28, alignment: .leading)
            col1.frame(maxWidth: .infinity, alignment: .leading)
            col2.frame(maxWidth: .infinity, alignment: .leading)
            col3.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Canvas: "Rest running / Next set in mm:ss" row — shown after a set is
    // logged, until the lifter taps "Log Set" for the next one.
    @ViewBuilder
    private var restTimerRow: some View {
        if let restEndAt, restEndAt > .now {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accent700)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest running")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text("Next set in")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Text(timerInterval: Date.now...restEndAt, countsDown: true)
                    .font(GSFont.heading(24, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            .padding(16)
            .background(theme.surface)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Recap (Dossier §A.4)
    //
    // The recap's rendering (header, accent hero, PR card, by-exercise
    // breakdown, Apple Health card, Done footer) lives in
    // `SoloRecapView.swift` (extracted Phase U Task 4, canvas frame 17
    // alignment) — `body`, above, constructs it from the computed properties
    // in the "Recap data" section below. The original inline "Synced to
    // Apple Health" card (`appleHealthCard`, `appleHealthMetaText`) was
    // removed rather than moved when this view was extracted: the design
    // doc's "Recap adjudication" called for that row to render absent until
    // Phase H shipped it. Phase H restores it as `SoloRecapView.healthCard`,
    // driven by `recapHealthSummary` below (built from `healthSynced` +
    // `HealthKitBridge.estimatedCalories`) — `HealthKitBridge.exportWorkout`
    // in `endSession()` is unchanged.

    // Canvas: "No routine" (freeform) session — no set-logging UI exists yet.
    // Replaces the indefinite spinner (which read as broken, per Task 5
    // review) with an explanation once the session has actually loaded.
    // Only the loaded-but-empty state renders this; the genuinely-loading
    // state (session == nil) still shows the spinner above.
    private var freeformEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Freeform session")
                .font(GSFont.bold(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text("Set logging for freeform workouts is coming soon. Tap End to finish this session.")
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Recap data (Dossier §B.10 — derived from state already held by the view)

    /// Non-penalty sets logged this session — backs the hero SETS stat.
    private var recapNonPenaltySets: [SetLog] {
        loggedSets.filter { !$0.isPenalty }
    }

    /// `loggedSets` grouped by exercise (excluding penalty), preserving first-logged
    /// order. Builds `SoloRecapView.ExerciseSummary` rows directly (that type used to
    /// be a private nested struct on this view — moved to `SoloRecapView.swift` in
    /// Phase U Task 4 so the catalog can construct fixture rows from outside this view).
    private var exerciseSummaries: [SoloRecapView.ExerciseSummary] {
        var order: [UUID] = []
        var setsByExercise: [UUID: [SetLog]] = [:]
        for log in loggedSets where !log.isPenalty {
            if setsByExercise[log.exerciseID] == nil {
                order.append(log.exerciseID)
                setsByExercise[log.exerciseID] = []
            }
            setsByExercise[log.exerciseID]?.append(log)
        }
        let prExerciseIDs = Set(sessionPRs.map { $0.exerciseID })
        return order.map { exerciseID in
            let sets = setsByExercise[exerciseID] ?? []
            let name = allExercises.first { $0.id == exerciseID }?.name ?? "Exercise"
            // Top-set value derives from completed sets only (excludes isFailed) — set
            // COUNT above still includes failed sets, matching penalty exclusion as-is.
            let topSet = sets.filter { !$0.isFailed }.max { ($0.weight ?? 0) < ($1.weight ?? 0) }
            return SoloRecapView.ExerciseSummary(
                id: exerciseID,
                name: name,
                setCount: sets.count,
                topWeight: topSet?.weight,
                topReps: topSet?.reps,
                isPR: prExerciseIDs.contains(exerciseID)
            )
        }
    }

    /// The heaviest PR this session — the only one the recap's celebration card shows.
    private var heaviestSessionPR: PersonalRecord? {
        sessionPRs.max { $0.weight < $1.weight }
    }

    /// Adapts `heaviestSessionPR` (+ the `allExercises` name lookup the old inline
    /// `prCelebrationCard(_:)` used) into `SoloRecapView`'s display-ready shape.
    private var recapHeaviestPR: SoloRecapView.HeaviestPR? {
        guard let pr = heaviestSessionPR else { return nil }
        return SoloRecapView.HeaviestPR(
            exerciseName: exerciseName(for: pr.exerciseID),
            weight: pr.weight,
            reps: pr.reps,
            previousBest: pr.previousBest
        )
    }

    private var recapKicker: String {
        routine?.name.uppercased() ?? "SOLO WORKOUT"
    }

    private var recapDurationInterval: TimeInterval {
        guard let start = completedSession?.startedAt, let end = completedSession?.completedAt else { return 0 }
        return HealthKitBridge.duration(from: start, to: end)
    }

    private var recapDurationText: String {
        formatDuration(recapDurationInterval)
    }

    private var recapSubline: String {
        let date = completedSession?.completedAt ?? Date()
        return "\(formatRecapDate(date)) · solo"
    }

    private var recapTotalLbsText: String {
        StatMath.compactNumber(Decimal(HealthKitBridge.totalVolume(from: loggedSets)))
    }

    /// Comma-grouped ("7,240") variant of the hero's TOTAL LBS figure — mirrors
    /// StatsTabView's `volumeString` convention. Small stat tiles elsewhere (Home,
    /// You, Stats weekly) and the ShareLink summary keep the compact ("7.2k") form
    /// via `recapTotalLbsText`; only the recap hero cell uses this.
    private var recapTotalLbsHeroText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = HealthKitBridge.totalVolume(from: loggedSets)
        return formatter.string(from: NSNumber(value: raw)) ?? "0"
    }

    private var recapShareSummary: String {
        let title = routine?.name ?? "Solo Workout"
        return "\(title) — \(recapDurationText), \(recapTotalLbsText) lbs, \(recapNonPenaltySets.count) sets"
    }

    /// Display-ready fields for `SoloRecapView`'s "Synced to Apple Health"
    /// card (Phase H). `nil` — no card — when the export didn't succeed
    /// (`healthSynced`'s doc comment); minutes/calories are independently
    /// derived from `recapDurationInterval` via `HealthKitBridge`'s pure
    /// helpers, same source the hero's own `recapDurationText` reads.
    private var recapHealthSummary: SoloRecapView.HealthSummary? {
        guard healthSynced else { return nil }
        let minutes = recapDurationInterval / 60.0
        let calories = HealthKitBridge.estimatedCalories(minutes: minutes)
        return SoloRecapView.HealthSummary(
            minutesText: "\(Int(minutes.rounded())) min",
            caloriesText: "\(calories) kcal"
        )
    }

    // MARK: - Helpers

    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// "m:ss" under an hour, "h:mm:ss" at/above an hour — recap duration hero + share text.
    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// "Friday, July 11" — recap subline.
    private func formatRecapDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private func exerciseName(for exerciseID: UUID) -> String {
        allExercises.first { $0.id == exerciseID }?.name ?? "Exercise"
    }

    @MainActor
    private func startIfNeeded() async {
        guard session == nil else { return }
        do {
            let newSession = try await SessionRepository.startSolo(routineID: routine?.id)
            session = newSession
            // Discover "Attempt Solo" only: start the leaderboard attempt
            // AFTER the session exists (backend contract — see
            // `attemptOptIn`'s doc comment). Best-effort: a failed
            // attempt-start must never block the workout itself — the user
            // just won't appear on the leaderboard for this run, same
            // best-effort idiom as `loadDefaultRestSeconds` below.
            if let attemptOptIn, let routineID = routine?.id {
                do {
                    _ = try await PublicWorkoutRepository.startAttempt(
                        routineID: routineID, sessionID: newSession.id, optIn: attemptOptIn)
                } catch {
                    AppLogger.db.error("startAttempt failed: \(error.localizedDescription, privacy: .public)")
                    // Minor finding 2: surface it — fire-and-forget (not
                    // awaited) so this transient notice's own display/clear
                    // lifecycle never delays `startIfNeeded()` returning or
                    // blocks the workout, matching `showSoundOverlay`'s own
                    // call sites in GroupSessionLiveView.
                    Task { await showAttemptOptInFailedNotice() }
                }
            }
        }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    /// Show the "couldn't join the leaderboard" transient notice for 3
    /// seconds. Same shape as `GroupSessionLiveView.showSoundOverlay(_:)`.
    @MainActor
    private func showAttemptOptInFailedNotice() async {
        let text = "Couldn't join the leaderboard for this attempt."
        attemptOptInFailedText = text
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if attemptOptInFailedText == text { attemptOptInFailedText = nil }
    }

    /// Best-effort — a failed fetch must never block workout start; the
    /// `@State` initializer's 120 fallback covers that case (mirrors the
    /// `defaultRestSeconds = 120` fallback documented on the column itself).
    @MainActor
    private func loadDefaultRestSeconds() async {
        if let settings = try? await UserSettingsRepository.get() {
            defaultRestSeconds = settings.defaultRestSeconds
        }
    }

    @MainActor
    private func log(reps: Int?, weight: Decimal?, rpe: Decimal?, isFailed: Bool, note: String?) async {
        guard let session, let re = currentRoutineExercise,
              let userID = appState.currentProfile?.id else { return }

        let log = SetLog(
            id: UUID(),
            userID: userID,
            sessionID: session.id,
            exerciseID: re.exerciseID,
            setIndex: currentSetIndex,
            reps: reps, weight: weight, rpe: rpe,
            isFailed: isFailed, isPenalty: false,
            note: note, loggedAt: Date()
        )
        do {
            // Prior max MUST be captured BEFORE the insert below — querying it after
            // logSet() would fold the just-inserted set's own weight into the max
            // (self-comparison), making `weight > priorBest` always false for a
            // genuine new max and silently suppressing the PR celebration. Mirrors
            // GroupSessionLiveView.logSetAndAdvance's identical ordering.
            var isPR = false
            var priorBest: Decimal = 0
            if !isFailed, let weight, weight > 0 {
                // Phase O Task 3 (offline set logging, master spec §6.4): this is a
                // READ that requires connectivity. Without this catch, an offline
                // attempt throws HERE — before the actual set-log write below is ever
                // reached — meaning an offline lifter could never log a single
                // non-failed, weighted set (the common case). Only `.network` gets
                // this tolerant treatment; every other error (validation,
                // unauthorized, …) still aborts exactly as before.
                do {
                    priorBest = try await priorMax(exerciseID: re.exerciseID,
                                                   weight: weight, userID: userID)
                    isPR = weight > priorBest
                } catch let error as GymSyncError {
                    guard case .network = error else { throw error }
                    // Offline — PR check skipped (best-effort, never blocks logging;
                    // mirrors the PersonalRecordRepository.record fallback below,
                    // which already tolerates a failed PR-record insert the same way).
                }
            }

            do {
                try await SessionRepository.logSet(log)
                // Cheap drain (brief's "after each successful online submit") —
                // opportunistically flushes any earlier queued sets now that we know
                // we're online. Fire-and-forget: never blocks this submit.
                Task { await OfflineSetLogQueue.shared.replay() }
            } catch let error as GymSyncError {
                guard case .network = error else { throw error }
                // Offline — queue for replay instead of losing the set. The rest of
                // this function proceeds exactly as the success path (optimistic UI:
                // PR overlay, set-index advance, rest timer) since, from the lifter's
                // perspective, the set IS saved (just not confirmed server-side yet).
                OfflineSetLogQueue.shared.enqueue(log)
            }
            loggedSets.append(log)

            if isPR, let weight {
                let repsForOverlay = reps ?? 0
                // Full-screen, user-dismissed celebration (p29) — content comes from data
                // already known at this point (no need to wait on the record insert below),
                // same as GroupSessionLiveView.showPROverlay.
                showPROverlay(exerciseName: exerciseName(for: re.exerciseID), weight: weight,
                              reps: repsForOverlay, priorBest: priorBest)
                // Best-effort PR record — a failed insert must never block or delay
                // set logging (which already happened above). Fall back to a local
                // record so the recap (Task 9) still has the PR if the write failed.
                if let record = try? await PersonalRecordRepository.record(
                    exerciseID: re.exerciseID,
                    weight: weight,
                    reps: repsForOverlay,
                    previousBest: priorBest,
                    sessionID: session.id
                ) {
                    sessionPRs.append(record)
                } else {
                    sessionPRs.append(PersonalRecord(
                        id: UUID(),
                        userID: userID,
                        exerciseID: re.exerciseID,
                        weight: weight,
                        reps: repsForOverlay,
                        previousBest: priorBest,
                        sessionID: session.id,
                        achievedAt: Date()
                    ))
                }
            }

            let targetSets = re.targetSets ?? 1
            if currentSetIndex >= targetSets {
                currentSetIndex = 1
                currentExerciseIndex += 1
            } else {
                currentSetIndex += 1
            }
            if currentExerciseIndex >= routineExercises.count {
                restEndAt = nil
                await endSession()
            } else {
                // Per-exercise rest wins when configured; otherwise fall back
                // to the user's default_rest_seconds (Canvas Completion Task 2)
                // rather than showing no rest timer at all.
                let restSeconds = re.restSeconds ?? defaultRestSeconds
                if restSeconds > 0 {
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    /// Show the full-screen, USER-DISMISSED PR celebration (p29) — no auto-timeout.
    /// Mirrors `GroupSessionLiveView.showPROverlay`'s field-setting shape; `monthlyCount`
    /// stays `nil` here (see `prOverlayMonthlyCount`'s declaration for why).
    @MainActor
    private func showPROverlay(exerciseName: String, weight: Decimal, reps: Int, priorBest: Decimal) {
        prOverlayExerciseName = exerciseName
        prOverlayWeight = weight
        prOverlayReps = reps
        prOverlayPriorBest = priorBest
        prOverlayMonthlyCount = nil
        withAnimation(.easeOut(duration: 0.25)) { isPROverlay = true }
    }

    private func priorMax(exerciseID: UUID, weight: Decimal, userID: UUID) async throws -> Decimal {
        let history = try await SessionRepository.exerciseHistory(userID: userID,
                                                                   exerciseID: exerciseID,
                                                                   limit: 200)
        return history
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { $0.weight }
            .max() ?? 0
    }

    @MainActor
    private func endSession() async {
        guard let session else { return }
        do {
            let completedResult = try await SessionRepository.complete(sessionID: session.id)
            let logs = try await SessionRepository.setLogs(sessionID: completedResult.id)
            completedSession = completedResult

            // Permission failure must never block completion — `try?` stays here.
            try? await HealthKitBridge.requestPermission()

            // Export result IS surfaced (into `healthSynced`, for Phase H to read
            // later — see that property's doc comment), but a failure still must
            // not block completion — do/catch, not `throw`.
            do {
                try await HealthKitBridge.exportWorkout(session: completedResult, setLogs: logs)
                healthSynced = true
            } catch {
                healthSynced = false
            }

            self.completed = true
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
