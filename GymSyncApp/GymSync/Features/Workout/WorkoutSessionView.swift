import SwiftUI
import UserNotifications

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

    /// Called instead of `dismiss()` when the lifter taps Done on the recap
    /// (user report 2026-07-28: finishing a workout dropped them back on the
    /// routine picker they started from). A presenter that lives inside a
    /// SHEET passes its own sheet-dismiss here, because `dismiss()` from a
    /// pushed child only pops the push — it cannot close the sheet around it.
    /// Either way the session ends by selecting Home (see `finishSession`).
    var onFinished: (() -> Void)?

    init(routine: Routine?, routineExercises: [RoutineExercise], allExercises: [Exercise],
         attemptOptIn: Bool? = nil, onFinished: (() -> Void)? = nil) {
        self.routine = routine
        self.routineExercises = routineExercises
        self.allExercises = allExercises
        self.attemptOptIn = attemptOptIn
        self.onFinished = onFinished
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

    /// Freeform (no-routine) session: exercises the lifter picks as they go.
    /// Synthesized `RoutineExercise` values (no `routines` row exists — the
    /// `routineID` is a throwaway UUID and never persisted; `set_logs` only
    /// ever stores `exerciseID`) so the ENTIRE existing logging path —
    /// header card, logged table, LogSetSheet, offline queue, PR detection,
    /// rest timer — is reused unchanged instead of a parallel freeform path.
    /// Full user settings (unit preference) — widened from the old
    /// rest-seconds-only fetch; nil until the best-effort load resolves.
    @State private var sessionSettings: UserSettings?
    /// "Last time: 225×5, 225×5 · Jul 20" per exercise — fetched lazily the
    /// first time each exercise becomes current, cached for the session.
    @State private var lastTimeByExercise: [UUID: String] = [:]
    /// The set queued for deletion (confirmation dialog).
    @State private var setPendingDeletion: SetLog?
    /// The set being edited (sheet(item:) — reuses LogSetSheet prefilled).
    @State private var editingSet: SetLog?

    @State private var freeformExercises: [RoutineExercise] = []
    @State private var showExercisePicker = false
    @State private var pickerCatalog: [Exercise] = []

    /// True for a session started with no routine (Home's "Start solo
    /// workout" without picking one). Same condition the old placeholder
    /// empty state used.
    private var isFreeform: Bool { routineExercises.isEmpty }

    /// The exercise list driving the whole screen — the routine's when there
    /// is one, the lifter's running freeform picks otherwise.
    private var activeExercises: [RoutineExercise] {
        isFreeform ? freeformExercises : routineExercises
    }

    private var currentRoutineExercise: RoutineExercise? {
        guard currentExerciseIndex < activeExercises.count else { return nil }
        return activeExercises[currentExerciseIndex]
    }

    /// Name lookups must span BOTH sources: `allExercises` is the routine's
    /// own exercises (and is EMPTY on the freeform launch), while
    /// `pickerCatalog` is the full catalog fetched only for freeform. A
    /// freeform-picked exercise resolves solely through the latter — without
    /// this union `currentExercise` stays nil and the screen never leaves
    /// its empty state.
    private var exerciseCatalog: [Exercise] { allExercises + pickerCatalog }

    private var currentExercise: Exercise? {
        guard let re = currentRoutineExercise else { return nil }
        return exerciseCatalog.first { $0.id == re.exerciseID }
    }

    // Body split (compiler type-check timeout, CI 2026-07-27): the single
    // expression grew past what the type checker will attempt. The
    // completed/live switch and the PR overlay each get their own named
    // sub-view; body stays a small ZStack + modifier chain.
    var body: some View {
        ZStack {
            sessionContent
            prOverlayLayer
        }
        .background(theme.bg)
        .gsSpotlight(.workout)   // fires on arrival — never mid-lift
        .overlay(alignment: .top) { attemptOptInNotice }
        .animation(.easeInOut(duration: 0.25), value: attemptOptInFailedText)
        .gsHidesDock()
        .navigationTitle(routine?.name ?? "Freeform Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!completed)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { sessionToolbar }
        .task { await startIfNeeded() }
        .task { await loadDefaultRestSeconds() }
        .task { await loadPickerCatalogIfFreeform() }
        .task(id: currentRoutineExercise?.exerciseID) {
            barLoaderPounds = nil   // stale loaded weight must not prefill the next exercise
            await loadLastTime()
        }
        .onChange(of: restEndAt) { handleRestWindowChange() }
        .onDisappear {
            // Only when the session is truly over — a mid-rest lock/
            // background must keep the cue (that IS the feature).
            if completed { RestNotification.cancel() }
        }
        .confirmationDialog(
            "Delete this set?",
            isPresented: Binding(get: { setPendingDeletion != nil },
                                 set: { if !$0 { setPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            deleteDialogButtons
        } message: {
            Text("Removes it from your log, volume and history.")
        }
        .sheet(isPresented: $showExercisePicker) { exercisePickerSheet }
        .sheet(isPresented: $showLogSheet) { logSheet }
        .sheet(item: $editingSet) { log in editSheet(for: log) }
    }

    @ViewBuilder
    private var sessionContent: some View {
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
                        unit: sessionSettings?.weightUnit ?? .lbs,
                        pumpCheck: pumpCheckContext,
                        onDone: { finishSession() }
                    )
                    // The Duolingo-placement slot: fires AFTER the recap
                    // lands, never over the celebration. Dormant today;
                    // becomes the Pro upsell when the paywall flips (and is
                    // where ads would go if ever revisited).
                    .completionInterstitial(profile: appState.currentProfile)
                } else {
                    liveSessionBody
                }
        }
    }

    // ── PR CELEBRATION (full-screen, user-dismissed — p29) ─────────
    // Sibling of the completed/live content — NOT a child of
    // `liveSessionBody`'s own ZStack — so it survives the `completed`
    // transition. When the session's LAST set is also a PR, `log()` sets
    // `isPROverlay = true` and then `endSession()` flips `completed = true`,
    // which structurally unmounts `liveSessionBody`; an overlay nested
    // inside it would vanish before the user could dismiss it (bug found
    // in Phase U Task 4 review). User-dismissed only, no auto-timeout.
    @ViewBuilder
    private var prOverlayLayer: some View {
        if isPROverlay {
            PRCelebrationOverlay(
                exerciseName: prOverlayExerciseName,
                weight: prOverlayWeight,
                reps: prOverlayReps,
                priorBest: prOverlayPriorBest,
                monthlyCount: prOverlayMonthlyCount,
                unit: sessionSettings?.weightUnit ?? .lbs,
                onDismiss: {
                    withAnimation(.easeIn(duration: 0.2)) { isPROverlay = false }
                }
            )
            .transition(.opacity)
        }
    }

    // Minor finding 2: non-blocking "couldn't join the leaderboard" notice —
    // transient pill at `.top` (bottom is the sticky "Log Set N" button).
    @ViewBuilder
    private var attemptOptInNotice: some View {
        if let txt = attemptOptInFailedText {
            Text(txt)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.neutral700)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                .padding(.top, 8)
                .transition(.opacity)
                .id(txt)
        }
    }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        if !completed {
            // Canvas "In Progress" elapsed timer — state-driven from
            // `startedAt`, ZERO Swift Timers.
            ToolbarItem(placement: .navigationBarLeading) {
                if let startedAt = session?.startedAt {
                    Text(startedAt, style: .timer)
                        .font(GSFont.bold(14, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Plain label ONLY (user screenshot 2026-07-27): the system
                // wraps toolbar items in its own capsule chrome, and this
                // button also painted a square neutral400 box inside it —
                // double chrome, with the system oval overflowing the header.
                // The leading timer is a bare label and renders correctly;
                // this now matches it (the only toolbar item app-wide that
                // drew its own background).
                Button {
                    Task { await endSession() }
                } label: {
                    Text("Finish")
                        .font(GSFont.bold(14, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var deleteDialogButtons: some View {
        Button("Delete set", role: .destructive) {
            if let log = setPendingDeletion { Task { await deleteSet(log) } }
        }
        Button("Keep it", role: .cancel) { setPendingDeletion = nil }
    }

    private var exercisePickerSheet: some View {
        // Reuses the programs enrollment picker rather than a second
        // search-list implementation.
        ExercisePickSheet(
            exercises: pickerCatalog.isEmpty ? allExercises : pickerCatalog,
            onPick: { exercise in
                addFreeformExercise(exercise)
                showExercisePicker = false
            }
        )
    }

    @ViewBuilder
    private var logSheet: some View {
        if let ex = currentExercise, let re = currentRoutineExercise {
            LogSetSheet(
                exercise: ex,
                setIndex: currentSetIndex,
                defaultReps: re.targetReps,
                // Loaded bar wins over the routine target: if the lifter
                // dialed a weight into Load-the-bar, THAT is what's on the
                // bar (both strings are canonical pounds — LogSetSheet's
                // prefill converts to the display unit on appear).
                defaultWeight: barLoaderPounds.map { "\($0)" } ?? re.targetWeight,
                unit: sessionSettings?.weightUnit ?? .lbs
            ) { reps, weight, rpe, isFailed, note in
                Task { await log(reps: reps, weight: weight, rpe: rpe,
                                 isFailed: isFailed, note: note) }
            }
            // Fresh identity per presentation (exercise / set / loaded
            // weight). Without this SwiftUI reuses the sheet's @State
            // between presentations and the prefill silently keeps the
            // PREVIOUS set's values — the bar-loader→log-weight bug
            // (user report 2026-07-28).
            .id("\(re.exerciseID)-\(currentSetIndex)-\(barLoaderPounds.map { "\($0)" } ?? "t")")
        }
    }

    /// Edit reuses LogSetSheet with the previous entry seeded — fixing one
    /// field never costs re-entering the other four. The sheet returns
    /// values through the same onLog closure shape; commit routes to
    /// applyEdit instead of log.
    private func editSheet(for log: SetLog) -> some View {
        let exercise = exerciseCatalog.first { $0.id == log.exerciseID }
        return LogSetSheet(
            exercise: exercise ?? Exercise(
                id: log.exerciseID, name: "Exercise", slug: "",
                category: "", primaryMuscle: "", secondaryMuscles: [],
                equipment: "", defaultUnit: "lbs", demoVideoURL: nil
            ),
            setIndex: log.setIndex,
            defaultReps: log.reps.map(String.init),
            defaultWeight: log.weight.map { "\($0)" },
            unit: sessionSettings?.weightUnit ?? .lbs,
            defaultRPE: log.rpe.map { NSDecimalNumber(decimal: $0).doubleValue },
            defaultIsFailed: log.isFailed,
            defaultNote: log.note
        ) { reps, weight, rpe, isFailed, note in
            Task {
                await applyEdit(to: log, reps: reps, weight: weight,
                                rpe: rpe, isFailed: isFailed, note: note)
            }
        }
    }

    @MainActor
    private func applyEdit(to original: SetLog, reps: Int?, weight: Decimal?,
                           rpe: Decimal?, isFailed: Bool, note: String?) async {
        editingSet = nil
        var updated = original
        updated.reps = reps
        updated.weight = weight
        updated.rpe = rpe
        updated.isFailed = isFailed
        updated.note = note

        if OfflineSetLogQueue.shared.pendingSetLogIDs.contains(original.id) {
            // Never reached the server: swap the queued copy (discard +
            // re-enqueue keeps the same id, so the syncing chip and any
            // later delete still line up).
            OfflineSetLogQueue.shared.discard(id: original.id)
            OfflineSetLogQueue.shared.enqueue(updated)
        } else {
            do {
                try await SessionRepository.updateSet(updated)
            } catch {
                errorText = ErrorMapping.map(error).errorDescription
                return
            }
        }
        if let idx = loggedSets.firstIndex(where: { $0.id == original.id }) {
            loggedSets[idx] = updated
        }
        // Same deliberate scope as delete: PR records born from the ORIGINAL
        // values are not recomputed here (migration 20260730000003 header).
    }

    /// Rest-over cue for a LOCKED phone: one observer covers every
    /// restEndAt assignment site — any future window schedules, any clear
    /// cancels.
    private func handleRestWindowChange() {
        if let restEndAt, restEndAt > .now {
            RestNotification.schedule(
                at: restEndAt,
                exerciseName: currentExercise?.name ?? "your next set",
                setNumber: currentSetIndex
            )
        } else {
            RestNotification.cancel()
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
                    // Redesign (deep-screens proof): live elapsed timer at the
                    // top — self-updating Text(timerInterval:), no Timer.
                    if let startedAt = session?.startedAt, !completed {
                        VStack(spacing: 2) {
                            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false, showsHours: true)
                                .font(GSFont.heading(30, relativeTo: .largeTitle))
                                .foregroundStyle(theme.text)
                                .monospacedDigit()
                            Text("ELAPSED")
                                .font(GSFont.bold(9.5, relativeTo: .caption2))
                                .tracking(1.6)
                                .foregroundStyle(theme.neutral500)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let ex = currentExercise, let re = currentRoutineExercise {
                        // Canvas: accent-filled exercise header card
                        exerciseHeaderCard(ex: ex, re: re)

                        // "Load the bar" widget (user direction 2026-07-26)
                        // — barbell lifts only; a plate stack on a dumbbell
                        // curl is noise. Collapsed card so the logged table
                        // stays the screen's spine.
                        if ex.equipment.lowercased() == "barbell" {
                            barLoaderCard(re: re)
                        }

                        // Canvas: logged sets table
                        loggedSetsTable

                        restTimerRow

                    } else if session != nil && activeExercises.isEmpty {
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
                    .gsSpotlightTarget(.workout)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    // Freeform advances between exercises by hand — a routine
                    // does it automatically off targetSets, so this control
                    // only exists here.
                    if isFreeform {
                        Button {
                            showExercisePicker = true
                        } label: {
                            Text("Next exercise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GSSecondaryButtonStyle(fontSize: 14, verticalPadding: 10))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 22)
                .background(theme.bg)
            }
        }
    }

    // MARK: - Delete set / last time / rest notification (V1 polish round)

    @MainActor
    private func deleteSet(_ log: SetLog) async {
        setPendingDeletion = nil
        // Queue first: a still-pending set must leave the offline queue or
        // the next replay would resurrect it server-side after the UI
        // showed it gone. Then the server delete (no-op if never synced).
        OfflineSetLogQueue.shared.discard(id: log.id)
        do {
            try await SessionRepository.deleteSet(id: log.id)
        } catch let error as GymSyncError {
            // Offline: the queue discard already handled the unsynced case;
            // a synced set deleted while offline stays visible server-side —
            // surface rather than pretend.
            if case .network = error {} else {
                errorText = ErrorMapping.map(error).errorDescription
                return
            }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
            return
        }
        loggedSets.removeAll { $0.id == log.id }
        // Keep the set counter honest: the next set number is derived from
        // how many sets THIS exercise now has.
        if log.exerciseID == currentRoutineExercise?.exerciseID {
            let count = loggedSets.filter { $0.exerciseID == log.exerciseID }.count
            currentSetIndex = count + 1
        }
        // Deliberately NOT touching sessionPRs / personal_records here — a
        // PR the user already saw celebrated silently vanishing is its own
        // surprise; recompute is a scoped follow-up (migration header).
    }

    /// "225×5, 225×5, 220×4 · Jul 20" — the previous SESSION's sets for the
    /// current exercise. The single most-asked mid-workout question.
    @MainActor
    private func loadLastTime() async {
        guard let re = currentRoutineExercise,
              lastTimeByExercise[re.exerciseID] == nil,
              let userID = appState.currentProfile?.id,
              let sessionID = session?.id else { return }
        guard let logs = try? await SessionRepository.exerciseHistory(
            userID: userID, exerciseID: re.exerciseID, limit: 60) else { return }
        // Most recent PRIOR session (exclude the live one), newest first.
        let prior = logs.filter { $0.sessionID != sessionID }
        guard let lastSession = prior.max(by: { $0.loggedAt < $1.loggedAt })?.sessionID else {
            lastTimeByExercise[re.exerciseID] = ""   // sentinel: looked, none
            return
        }
        let sets = prior.filter { $0.sessionID == lastSession }
            .sorted { $0.setIndex < $1.setIndex }
        let unit = sessionSettings?.weightUnit ?? .lbs
        let parts = sets.prefix(5).map { log -> String in
            let w = log.weight.map {
                Units.format(pounds: $0, unit: unit, rounded: false, includeUnit: false)
            } ?? "—"
            return "\(w)×\(log.reps ?? 0)"
        }
        let when = sets.first?.loggedAt.formatted(.dateTime.month(.abbreviated).day()) ?? ""
        lastTimeByExercise[re.exerciseID] = parts.isEmpty ? "" : "\(parts.joined(separator: ", ")) · \(when)"
    }

    /// One pending local notification, replaced on every schedule — fires
    /// when rest ends so a LOCKED phone still gets the cue (the on-screen
    /// countdown covers the foreground). Uses the push authorization the
    /// user already granted; silently does nothing without it.
    private enum RestNotification {
        static let id = "rest-timer-done"

        static func schedule(at date: Date, exerciseName: String, setNumber: Int) {
            let content = UNMutableNotificationContent()
            content.title = "Rest over"
            content.body = "Up next: set \(setNumber) — \(exerciseName)"
            content.sound = .default
            let seconds = max(1, date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        static func cancel() {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    // MARK: - Bar loader (barbell exercises only)

    @State private var showBarLoader = false

    /// The weight currently dialed into the bar-loader widget, canonical
    /// pounds (user request 2026-07-27: loading the bar populates the log
    /// sheet). Cleared on exercise change — the bar you loaded was for THAT
    /// exercise, and `loadLastTime`'s `.task(id:)` already fires exactly
    /// there.
    @State private var barLoaderPounds: Decimal?

    /// Prefill priority: the exercise's programmed target, else the last
    /// set logged for THIS exercise — both canonical pounds already.
    private func barLoaderPrefill(re: RoutineExercise) -> Decimal? {
        if let target = re.targetWeight, let parsed = Decimal(string: target), parsed > 0 {
            return parsed
        }
        return loggedSets.last { $0.exerciseID == re.exerciseID && !$0.isFailed }?.weight
    }

    /// Collapsed state redesigned 2026-07-27 (user request): a larger card
    /// with a `GSBarLoaderMini` preview on the right — the loaded bar for
    /// the prefill weight (target, else last set) readable at a glance
    /// before ever expanding. Same bar/plate sources as `BarLoaderWidget`
    /// itself: custom inventory only in the persisted unit, else the unit's
    /// standard set.
    private func barLoaderCard(re: RoutineExercise) -> some View {
        let unit = sessionSettings?.weightUnit ?? .lbs
        let plates: [Decimal] = {
            if let custom = sessionSettings?.plateInventory, !custom.isEmpty {
                return custom.sorted(by: >)
            }
            return unit.standardPlates
        }()
        var barConverted = Units.fromPounds(sessionSettings?.barWeightLbs ?? 45, to: unit)
        var barInUnit = Decimal()
        NSDecimalRound(&barInUnit, &barConverted, 2, .plain)
        let prefill = barLoaderPrefill(re: re)
        let targetInUnit = prefill.map { Units.fromPounds($0, to: unit) } ?? barInUnit

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showBarLoader.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: "scalemass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text("Load the bar")
                                .font(GSFont.bold(15, relativeTo: .body))
                                .foregroundStyle(theme.text)
                        }
                        Text(prefill.map { "\(Units.format(pounds: $0, unit: unit, rounded: false)) · plates & warm-up" }
                             ?? "Plates & warm-up ramp")
                            .font(GSFont.body(11.5, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    Spacer(minLength: 8)
                    GSBarLoaderMini(target: targetInUnit, barWeight: barInUnit,
                                    plates: plates, unit: unit)
                    Image(systemName: showBarLoader ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.neutral500)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showBarLoader {
                BarLoaderWidget(initialPounds: prefill,
                                onEnteredPoundsChange: { barLoaderPounds = $0 })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusMd)
        .padding(.horizontal, 16)
    }

    // Canvas: accent-filled card — "EXERCISE N OF M" kicker / "Set N of M" trailing /
    //         large exercise name / "Target X × Y · rest Z:00" sub-line
    private func exerciseHeaderCard(ex: Exercise, re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // Freeform has no planned total — "EXERCISE 2" and a bare set
                // counter, since "OF 2" would imply a plan the lifter never
                // made (and would keep changing as they add exercises).
                Text(isFreeform
                     ? "EXERCISE \(currentExerciseIndex + 1)"
                     : "EXERCISE \(currentExerciseIndex + 1) OF \(activeExercises.count)")
                    .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(theme.bg.opacity(0.85))
                Spacer()
                Text(isFreeform ? "Set \(currentSetIndex)" : "Set \(currentSetIndex) of \(re.targetSets ?? 1)")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
            Text(ex.name)
                .font(GSFont.heading(28, relativeTo: .title))
                .foregroundStyle(theme.bg)
                .lineLimit(2)

            // Target line (units sweep: target weight is stored pounds,
            // shown in the user's unit). A reps-only target reads
            // "Target 5 reps", not the dangling "Target × 5" (user
            // screenshot 2026-07-27, weight-less QA routine).
            let unit = sessionSettings?.weightUnit ?? .lbs
            let weightPart = re.targetWeight.flatMap { Decimal(string: $0) }.map {
                Units.format(pounds: $0, unit: unit, rounded: false, includeUnit: false)
            }
            let targetParts: [String] = [
                weightPart,
                re.targetReps.map { weightPart == nil ? "\($0) reps" : "× \($0)" },
                re.restSeconds.map { "· rest \(formatRest($0))" }
            ].compactMap { $0 }
            if !targetParts.isEmpty {
                Text("Target " + targetParts.joined(separator: " "))
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }

            // "Last time" — the most-asked mid-workout question, answered
            // where the lifter is looking. Empty-string sentinel = looked
            // and found no prior session; nil = still loading (show nothing
            // either way, never a spinner on this card).
            if let lastTime = lastTimeByExercise[re.exerciseID], !lastTime.isEmpty {
                Text("Last time: \(lastTime)")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
        .cornerRadius(GSMetrics.radiusMd)   // redesign: rounded accent hero
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
                    // Units sweep: stored pounds, displayed in the user's
                    // unit (unrounded — this is what they LOGGED, not a
                    // suggestion to snap).
                    col2: Text(log.weight.map {
                                  Units.format(pounds: $0,
                                               unit: sessionSettings?.weightUnit ?? .lbs,
                                               rounded: false, includeUnit: false)
                              } ?? "—")
                              .font(GSFont.heading(15, relativeTo: .body))
                              .foregroundStyle(theme.text),
                    col3: Text(log.rpe.map { "\($0)" } ?? "—")
                              .font(GSFont.heading(15, relativeTo: .body))
                              .foregroundStyle(theme.text)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                // Delete-set (V1 gap review: a fat-fingered 2255 was
                // PERMANENT). Long-press → confirm; context menu rather
                // than swipe because these rows live in a ScrollView, not
                // a List, and hand-rolled swipe gestures fight the scroll.
                .contextMenu {
                    Button {
                        editingSet = log
                    } label: {
                        Label("Edit set", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        setPendingDeletion = log
                    } label: {
                        Label("Delete set", systemImage: "trash")
                    }
                }

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
                // Elevation, NOT a color wash (user bug report 2026-07-26:
                // "rectangle miscolor"). A low-opacity accent over the Onyx
                // near-black ground doesn't read as a tint — it resolves to
                // a muddy band whose hue depends on the user's accent (10%
                // coral over #0A0B0D lands on dark maroon). Onyx expresses
                // "this row is active" through surface contrast, and the
                // accent-colored set number already carries the signal.
                .background(theme.surface)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Freeform session")
                .font(GSFont.bold(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text("No routine — pick exercises as you go. Everything you log counts toward your stats and PRs.")
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
            Button {
                showExercisePicker = true
            } label: {
                Text("Pick an exercise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 12))
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
            let name = exerciseCatalog.first { $0.id == exerciseID }?.name ?? "Exercise"
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

    /// Units sweep: total volume is accumulated in stored-lbs — converted to
    /// the user's unit before formatting (both the compact and hero forms).
    private var recapTotalVolumeInUnit: Double {
        Units.fromPounds(HealthKitBridge.totalVolume(from: loggedSets),
                         to: sessionSettings?.weightUnit ?? .lbs)
    }

    private var recapTotalLbsText: String {
        StatMath.compactNumber(Decimal(recapTotalVolumeInUnit))
    }

    /// Comma-grouped ("7,240") variant of the hero's TOTAL LBS/KG figure —
    /// mirrors StatsTabView's `volumeString` convention. Small stat tiles
    /// elsewhere (Home, You, Stats weekly) and the ShareLink summary keep the
    /// compact ("7.2k") form via `recapTotalLbsText`; only the recap hero
    /// cell uses this.
    private var recapTotalLbsHeroText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: recapTotalVolumeInUnit)) ?? "0"
    }

    private var recapShareSummary: String {
        let title = routine?.name ?? "Solo Workout"
        let unitLabel = (sessionSettings?.weightUnit ?? .lbs).label
        return "\(title) — \(recapDurationText), \(recapTotalLbsText) \(unitLabel), \(recapNonPenaltySets.count) sets"
    }

    /// Display-ready fields for `SoloRecapView`'s "Synced to Apple Health"
    /// card (Phase H). `nil` — no card — when the export didn't succeed
    /// (`healthSynced`'s doc comment); minutes/calories are independently
    /// derived from `recapDurationInterval` via `HealthKitBridge`'s pure
    /// helpers, same source the hero's own `recapDurationText` reads.
    /// Avg/max HR over the session window from Apple Health (any source
    /// device) — set best-effort in endSession.
    @State private var recapHRStats: (avg: Int, max: Int)?

    /// Pump Check window anchor — set in `endSession` right before
    /// `completed` flips, i.e. the instant the recap mounts.
    @State private var recapAppearedAt: Date?

    private var recapHealthSummary: SoloRecapView.HealthSummary? {
        guard healthSynced else { return nil }
        let minutes = recapDurationInterval / 60.0
        let calories = HealthKitBridge.estimatedCalories(minutes: minutes)
        return SoloRecapView.HealthSummary(
            minutesText: "\(Int(minutes.rounded())) min",
            caloriesText: "\(calories) kcal",
            hrText: recapHRStats.map { "avg \($0.avg) · max \($0.max) bpm" }
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
        exerciseCatalog.first { $0.id == exerciseID }?.name ?? "Exercise"
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
            // Widened (units sweep): keep the whole settings object so the
            // logged table / header can format in the user's unit.
            sessionSettings = settings
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
                // Cheap drain — this task's own design decision (not a brief
                // requirement; the brief contains no "after each successful
                // online submit" phrase — reviewer Finding 4, fix wave 1):
                // opportunistically flushes any earlier queued sets now that we
                // know we're online. Fire-and-forget: never blocks this submit.
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

            // Freeform has no planned set count, so it must NEVER auto-advance
            // or auto-end: `targetSets ?? 1` would fire after the very first
            // set, walk past the (length-1) list, and end the workout. The
            // lifter drives progression here — Log Set N+1, or "Next
            // exercise", or Finish.
            if isFreeform {
                currentSetIndex += 1
                let restSeconds = defaultRestSeconds
                if restSeconds > 0 {
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
                return
            }

            let targetSets = re.targetSets ?? 1
            if currentSetIndex >= targetSets {
                currentSetIndex = 1
                currentExerciseIndex += 1
            } else {
                currentSetIndex += 1
            }
            if currentExerciseIndex >= activeExercises.count {
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

    // MARK: - Freeform exercise picking

    /// Appends a synthesized `RoutineExercise` for `exercise` and moves to
    /// it. Nothing here is persisted — `set_logs` rows carry `exerciseID`
    /// alone, so a freeform session needs no `routines`/`routine_exercises`
    /// row to be fully recorded (and to feed PRs, stats, and program
    /// baselines exactly like a routine-driven set).
    @MainActor
    private func addFreeformExercise(_ exercise: Exercise) {
        let synthesized = RoutineExercise(
            id: UUID(),
            routineID: UUID(),
            exerciseID: exercise.id,
            position: freeformExercises.count + 1,
            targetSets: nil,
            targetReps: nil,
            targetWeight: nil,
            restSeconds: nil,
            notes: nil
        )
        freeformExercises.append(synthesized)
        currentExerciseIndex = freeformExercises.count - 1
        currentSetIndex = 1
        restEndAt = nil
    }

    /// The freeform picker needs the whole catalog; `allExercises` is only
    /// the routine's own exercises on a routine-driven launch and is empty
    /// on the Home no-routine path.
    @MainActor
    private func loadPickerCatalogIfFreeform() async {
        guard isFreeform, pickerCatalog.isEmpty else { return }
        pickerCatalog = (try? await ExerciseRepository.fetchAll()) ?? []
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

            // HR backfill (2026-07-27): any watch brand whose companion app
            // syncs to Apple Health lights up recap heart rate — the
            // non-live half of "everyone gets HR". Best-effort; a strap
            // that synced late simply shows nothing this time.
            if let start = completedResult.startedAt, let end = completedResult.completedAt {
                recapHRStats = await HealthKitBridge.heartRateStats(start: start, end: end)
            }

            // Pump Check window anchor: the 1:00 countdown starts the
            // moment the recap becomes visible.
            recapAppearedAt = Date()
            self.completed = true
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    /// Leaving a finished workout lands on HOME, not on whatever menu the
    /// lifter happened to start from (user report 2026-07-28: finishing a
    /// solo workout returned them to the routine picker). Home is the screen
    /// that makes sense after training — it's where the streak, the stats
    /// tiles and the next scheduled session live.
    ///
    /// `onFinished` (when a sheet-based presenter supplied one) tears the
    /// presentation down; otherwise this pops the push. The tab switch runs
    /// either way, so every entry point — Home's picker sheet, a routine
    /// detail push, a Discover attempt — ends in the same place.
    private func finishSession() {
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
        appState.selectedTab = .home
    }

    // MARK: - Pump Check (spec 2026-07-27, P2)

    /// Post-ready payload for the recap's composer card — nil until the
    /// session is actually complete.
    private var pumpCheckContext: PumpCheckContext? {
        guard let session = completedSession, let windowStart = recapAppearedAt else { return nil }
        return PumpCheckContext(
            sessionID: session.id,
            summary: buildPostSummary(),
            avgBpm: recapHRStats?.avg,
            maxBpm: recapHRStats?.max,
            includeHRDefault: ThemeStore.shared.shareHeartRate && recapHRStats != nil,
            windowStart: windowStart)
    }

    /// The immutable snapshot frozen into the post: non-penalty sets
    /// grouped by exercise in first-logged order, canonical-lbs weights
    /// (the FEED converts to each viewer's unit). A set is marked PR when
    /// it carries the exercise's session-PR weight.
    private func buildPostSummary() -> PostSummary {
        var order: [UUID] = []
        var byExercise: [UUID: [SetLog]] = [:]
        for log in loggedSets where !log.isPenalty {
            if byExercise[log.exerciseID] == nil { order.append(log.exerciseID) }
            byExercise[log.exerciseID, default: []].append(log)
        }
        // Multiple PRs for one exercise across a session are possible
        // (each new max) — the heaviest is THE session PR for that lift.
        let prWeight = Dictionary(sessionPRs.map { ($0.exerciseID, $0.weight) },
                                  uniquingKeysWith: max)
        let exercises = order.map { id -> PostSummary.ExerciseEntry in
            let sets = (byExercise[id] ?? [])
                .sorted { $0.setIndex < $1.setIndex }
                .map { log in
                    PostSummary.ExerciseEntry.SetEntry(
                        weightLbs: log.weight,
                        reps: log.reps,
                        isPR: !log.isFailed && log.weight != nil && log.weight == prWeight[id],
                        isFailed: log.isFailed)
                }
            return PostSummary.ExerciseEntry(
                name: exerciseName(for: id),
                equipment: exerciseCatalog.first { $0.id == id }?.equipment ?? "",
                sets: sets)
        }
        return PostSummary(
            durationSeconds: Int(recapDurationInterval),
            totalVolumeLbs: Decimal(HealthKitBridge.totalVolume(from: loggedSets)),
            exercises: exercises)
    }
}
