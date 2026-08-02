import SwiftUI
import UIKit
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

    /// Re-entrancy guard for the log CTA (user report 2026-08-02: "sometimes
    /// the app hangs, and instinctively users will just hit the log button
    /// multiple times. This advances the set without them actually being
    /// completed"). The CTA stays tappable for the whole round trip, so a
    /// slow submit used to accept N taps and advance the set counter N times.
    /// `GroupSessionLiveView` has carried this guard since its own report;
    /// solo never got it.
    @State private var isLoggingSet = false

    // Solo fixed page (2026-07-30) — inline entry state, replacing the
    // log sheet for routine sessions (the sheet remains for edit mode).
    @State private var soloWeight = ""
    @State private var soloReps = ""
    @State private var soloRPE: Double = 7.0
    @State private var soloFailed = false
    @State private var soloWidgetPage = 0
    @State private var soloLoaderOpen = false
    /// Success-haptic trigger for `.sensoryFeedback` — a count (not a Bool)
    /// so every logged set fires, including two in a row.
    @State private var logHapticTick = 0
    @State private var soloShowHRPairing = false

    // Solo ladder wiring (queue item, 2026-07-30): prior-performance
    // history + active enrollment feed WorkingWeight.suggest and the
    // structured LAST TIME card. One fetch, both consumers — mirrors the
    // group screen's identical pair.
    @State private var soloPriorSets: [SetLog] = []

    /// PR baseline per exercise, prefetched off the critical path (see
    /// `priorMax`). Kept current locally after each log — the only new data
    /// that can move this number mid-session is a set we just wrote
    /// ourselves, so a fresh read to learn our own weight would be wasteful
    /// and would put a network round trip right back in front of the CTA.
    @State private var priorBestByExercise: [UUID: Decimal] = [:]
    @State private var soloEnrollment: ProgramEnrollment?
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
    /// TRANSIT flag for the current rest window (2026-08): true when the
    /// set just logged closed out its exercise, so the window was extended
    /// by `TransitWindow.seconds` and the rest page labels it "TRANSIT ·
    /// SET UP YOUR STATION". Set alongside every routine-path `restEndAt`
    /// assignment; only read while a window is active.
    @State private var soloRestIsTransit = false
    /// Solo warm-up (2026-08): end of the warm-up window shown before the
    /// first set — `started_at + soloWarmupMinutes`. Nil when no duration
    /// is configured (the default), once skipped, or once lapsed. Routine
    /// sessions only (freeform has no fixed-page slot to host it).
    @State private var soloWarmupEndsAt: Date?
    /// UserDefaults-backed duration (`SoloWarmupStore`) — DEFAULT 0, so
    /// solo behavior is unchanged until the lifter opts in via the − / +
    /// control on the warm-up page itself.
    @State private var soloWarmupMinutes: Int = SoloWarmupStore.minutes
    /// Session-local HR history behind the rest screen's YOUR RECOVERY
    /// card — fed by `.onChange(of: soloBLEBPM)`; the math lives in
    /// RecoveryBuffer (unit-tested, shared with the group spectate page).
    @State private var soloRecoveryBuffer = RecoveryBuffer()
    /// Pre-session est-1RM ceilings per exercise for the rest screen's
    /// LOAD · % SELF line — fetched lazily after each log, cached for the
    /// session (the past doesn't change mid-workout).
    @State private var soloCeilings: [UUID: Decimal] = [:]
    @State private var isLoadingSoloStats = false
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
        .sensoryFeedback(.success, trigger: logHapticTick)
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
            // Ladder inputs (best-effort; absence just means fewer rungs).
            if let re = currentRoutineExercise,
               let userID = appState.currentProfile?.id {
                soloPriorSets = (try? await SessionRepository.exerciseHistory(
                    userID: userID, exerciseID: re.exerciseID, limit: 30)) ?? []
                // PR baseline, fetched HERE rather than at log time — this is
                // the latency fix: by the time the CTA is pressed the answer
                // is already in memory, so logging is one write and nothing
                // else. Best-effort; `priorMax` still has a live fallback.
                if priorBestByExercise[re.exerciseID] == nil,
                   let best = try? await SessionRepository.bestWeight(
                    userID: userID, exerciseID: re.exerciseID) {
                    priorBestByExercise[re.exerciseID] = best
                }
            } else {
                soloPriorSets = []
            }
            if soloEnrollment == nil {
                soloEnrollment = try? await ProgramRepository.active()
            }
            soloPrefill()
        }
        .onChange(of: restEndAt) { handleRestWindowChange() }
        // Solo warm-up auto-end (2026-08): the guarded-sleep shape
        // `handleRestWindowChange` uses — only the still-current window
        // clears itself, so a skip (or a − adjustment that already ended
        // it) is never re-cleared.
        .task(id: soloWarmupEndsAt) {
            guard let until = soloWarmupEndsAt, until > .now else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.1))
            guard !Task.isCancelled else { return }
            if soloWarmupEndsAt == until { soloWarmupEndsAt = nil }
        }
        .onChange(of: soloBLEBPM) { _, newValue in
            guard let newValue else { return }
            soloRecoveryBuffer.append(bpm: newValue, at: Date().timeIntervalSinceReferenceDate)
        }
        // LOAD · % SELF ceilings refresh after every log — covers entering
        // the rest screen with fresh numbers.
        .onChange(of: loggedSets.count) { _, _ in
            Task { await loadSoloCeilings() }
        }
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
        // The nav title was the ONE nav-bar text still drawn in the system
        // font while the rest of the page is Archivo (user report
        // 2026-07-30) — same principal-slot idiom as RoutineBuilderView.
        ToolbarItem(placement: .principal) {
            Text(routine?.name ?? "Freeform Workout")
                .font(GSFont.heading(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
        if !completed {
            // Canvas "In Progress" elapsed timer — state-driven from
            // `startedAt`, ZERO Swift Timers.
            ToolbarItem(placement: .navigationBarLeading) {
                if let startedAt = session?.startedAt {
                    // Whole-session elapsed. `.fixedSize()` + a fixed-width
                    // font: without them the system sized this to the leading
                    // slot's proportional width and truncated it to "26:…"
                    // (user screenshot 2026-08-02). Bare label — the system
                    // draws its own toolbar capsule, and painting another
                    // background inside it is the double-chrome bug the
                    // Finish button's comment records.
                    Text(startedAt, style: .timer)
                        .font(GSFont.boldFixed(14).monospacedDigit())
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .fixedSize()
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
            // Auto-return from the rest screen once the window lapses —
            // only the still-current window clears itself (the guarded-sleep
            // shape the group interlude uses). +1s grace so this clear can
            // never race the rest cue's own delivery at exactly restEndAt.
            let until = restEndAt
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 1))
                if self.restEndAt == until {
                    self.restEndAt = nil
                    // A lapsed rest window starts the next set — same stamp as
                    // the START SET shortcut, so the set clock never inherits
                    // the rest it just finished.
                    self.setStartedAt = .now
                }
            }
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
    @ViewBuilder
    private var liveSessionBody: some View {
        // Solo port (2026-07-30, user: "the solo workout should use the, if
        // not exact, a very similar page"): routine sessions get the same
        // fixed non-scrolling page as the group my-turn state. Freeform
        // keeps the scroll body — it has no planned sets to structure a
        // fixed page around — as does the completed state.
        if !isFreeform && !completed && currentExercise != nil && currentRoutineExercise != nil {
            soloFixedPage
        } else {
            soloScrollBody
        }
    }

    // MARK: - Solo fixed page (2026-07-30, final-proof geometry)
    // The group my-turn page's four-widget layout, minus rotation and voice:
    // system nav bar stays (no custom rail), chrome is the CTA alone, the
    // clock slot shows the REST countdown when one is running. All logging
    // goes through the existing log() — PR overlay, offline queue, set and
    // exercise advance, rest timer and auto-end are untouched.
    //
    // Recorded v1 deviations: entry prefill = loaded bar ?? routine target
    // (the WorkingWeight ladder's campaign/rep-goal rungs need a history
    // fetch this view doesn't hold yet — follow-up); LAST TIME card reuses
    // the cached one-line summary rather than the structured card.

    private var soloUnit: WeightUnit { sessionSettings?.weightUnit ?? .lbs }
    private var soloWeightStep: Decimal { soloUnit == .kg ? Decimal(2.5) : 5 }

    private var soloBLEBPM: Int? {
        if case .connected = BLEHeartRateService.shared.state {
            return BLEHeartRateService.shared.latestBPM
        }
        return nil
    }

    private var soloFixedPage: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 10)
            // The REST screen (user 2026-07-31: "after you log any set, you
            // go to the rest screen — watch your recovery, understand
            // what's coming up next, watch your rest timer tick down").
            // The loader keeps priority so tuning the next weight works
            // mid-rest, exactly like the group page. The warm-up page
            // (2026-08) occupies this same slot before the first set.
            if soloWarmupActive && !soloLoaderOpen {
                soloWarmupPage
            } else if soloRestActive && !soloLoaderOpen {
                soloRestPage
            } else {
                soloVitalsRow
                Color.clear.frame(height: 12)
                if soloLoaderOpen {
                    soloLoaderExpanded
                } else {
                    soloExerciseCard
                        .frame(maxHeight: .infinity)
                    Color.clear.frame(height: 12)
                    soloEntryCard
                }
            }
            Color.clear.frame(height: 8)
        }
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) { soloChrome }
        // Outside the inset: neither the page nor the chrome moves while
        // typing — the keyboard covers the bottom, nothing stacks above it
        // (user round 3: the CTA was lifting and leaving a buffer).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: "\(currentRoutineExercise?.exerciseID.uuidString ?? "")-\(currentSetIndex)") {
            soloPrefill()
        }
        .sheet(isPresented: $soloShowHRPairing) {
            NavigationStack { HeartRateMonitorView() }
        }
    }

    /// Loaded bar wins over the routine target — identical precedence to the
    /// old sheet's defaultWeight. Reps from the routine's target string.
    private func soloPrefill() {
        // Loaded bar wins (the user dialled it); then the full ladder —
        // campaign % -> routine target -> rep-goal projection -> last set.
        if let pounds = barLoaderPounds {
            soloWeight = Units.format(pounds: pounds, unit: soloUnit,
                                      rounded: false, includeUnit: false)
        } else if let last = soloCurrentExerciseSets.last(where: { !$0.isFailed && $0.weight != nil }),
                  let w = last.weight {
            // This session's own work outranks the ladder's static rungs
            // (user 2026-08-01) — RPE-aware step via SetProgression.
            //
            // Rep-scaled first (user 2026-08-02): this branch bypasses
            // `WorkingWeight.suggest` entirely, so without this it would carry
            // a heavy low-rep set's load straight into a higher-rep set — the
            // 405 × 1 → "set of 5" hazard. Scale to today's target, THEN apply
            // the RPE progression step, so the +5 lands on a weight that
            // actually fits the reps.
            let targetReps = currentRoutineExercise?.targetReps.flatMap { leadingInt($0) }
            var base = w
            if let targetReps, let lastReps = last.reps, lastReps != targetReps,
               let scaled = StatMath.projectedWeight(prWeight: w,
                                                     prReps: lastReps,
                                                     targetReps: targetReps) {
                base = Decimal(scaled)
            }
            let next = SetProgression.nextWeight(afterPounds: base, rpe: last.rpe, isFailed: last.isFailed)
            soloWeight = Units.format(pounds: next, unit: soloUnit,
                                      rounded: false, includeUnit: false)
        } else if let re = currentRoutineExercise,
                  let suggestion = WorkingWeight.suggest(
                      exerciseID: re.exerciseID,
                      targetReps: re.targetReps.flatMap { leadingInt($0) },
                      routineTargetPounds: re.targetWeight.flatMap { Decimal(string: $0) },
                      history: soloPriorSets + soloCurrentExerciseSets,
                      lastSetPounds: (soloPriorSets + soloCurrentExerciseSets)
                          .max(by: { $0.loggedAt < $1.loggedAt })?.weight,
                      enrollment: soloEnrollment) {
            soloWeight = Units.format(pounds: suggestion.pounds, unit: soloUnit,
                                      rounded: false, includeUnit: false)
        } else {
            soloWeight = ""
        }
        soloReps = currentRoutineExercise?.targetReps.flatMap { leadingInt($0).map(String.init) } ?? ""
        soloRPE = 7.0
        soloFailed = false
    }

    // MARK: - The REST screen (2026-07-31)
    //
    // The group spectate page's REST band, minus the crew: recovery, the
    // countdown hero with UP NEXT, the bar/last-time prep card, and a
    // single LOAD · % SELF line where the group has its rotation widget
    // and REST|BOARD switch — solo has nobody to toggle to.

    private var soloRestActive: Bool {
        guard let restEndAt else { return false }
        return restEndAt > .now
    }

    // MARK: - Solo warm-up page (2026-08 warm-up phase)

    private var soloWarmupActive: Bool {
        guard let until = soloWarmupEndsAt else { return false }
        return until > .now
    }

    /// The shared warm-up phase page in solo dress: just me, no vote
    /// semantics (the CTA is SKIP WARM-UP), and the − / + control adjusts
    /// the persisted duration in place.
    private var soloWarmupPage: some View {
        WarmUpPhaseView(
            mode: .solo(minutes: soloWarmupMinutes),
            countdownEndsAt: soloWarmupEndsAt ?? Date(),
            members: [WarmUpPhaseView.Member(
                id: appState.currentProfile?.id ?? UUID(),
                name: appState.currentProfile?.username ?? "You",
                avatarURL: appState.currentProfile?.avatarURL,
                isReady: false
            )],
            isOrganizer: false,
            myReady: false,
            onReady: { soloWarmupEndsAt = nil },
            onAdjustMinutes: { delta in adjustSoloWarmup(delta) }
        )
    }

    /// ± the persisted duration from the page itself (step 5, clamp 0–30,
    /// mirroring the lobby control). Re-anchors the window at `started_at
    /// + minutes`, so an increase extends the running window and a
    /// decrease past the elapsed time ends it immediately.
    private func adjustSoloWarmup(_ delta: Int) {
        let next = min(30, max(0, soloWarmupMinutes + delta))
        guard next != soloWarmupMinutes else { return }
        soloWarmupMinutes = next
        SoloWarmupStore.set(next)
        guard soloWarmupEndsAt != nil else { return }
        let anchor = session?.startedAt ?? Date()
        let ends = anchor.addingTimeInterval(TimeInterval(next * 60))
        soloWarmupEndsAt = ends > .now ? ends : nil
    }

    @ViewBuilder
    private var soloRestPage: some View {
        soloRecoveryCard
        Color.clear.frame(height: 12)
        soloRestHero
            .frame(maxHeight: .infinity)
        Color.clear.frame(height: 12)
        Group {
            if soloIsBarbell {
                soloBarCard
            } else {
                soloLastTimeCard
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 16)
        Color.clear.frame(height: 12)
        soloSelfStatsLine
    }

    /// YOUR RECOVERY — live HR falling while you rest, with the windowed
    /// peak-to-now drop and sparkline. Three-state like the vitals card:
    /// dash (never asked) / session-elapsed (asked, no strap) / live.
    private var soloRecoveryCard: some View {
        Button { if soloBLEBPM == nil { soloShowHRPairing = true } } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YOUR RECOVERY")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                    if soloBLEBPM != nil, let drop = soloRecoveryBuffer.drop, drop > 0 {
                        Text("−\(drop)")
                            .font(GSFont.bold(14, relativeTo: .subheadline).monospacedDigit())
                            .foregroundStyle(theme.text.opacity(0.78))
                    }
                }
                Spacer(minLength: 6)
                HStack(alignment: .bottom, spacing: 10) {
                    if let bpm = soloBLEBPM {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.text.opacity(0.78))
                            Text("\(bpm)")
                                .font(GSFont.boldFixed(36).monospacedDigit())
                                .foregroundStyle(theme.text)
                        }
                        Spacer()
                        soloRecoverySparkline
                    } else if HeartRatePrimeStore.hasBeenAsked, let startedAt = session?.startedAt {
                        Text(startedAt, style: .timer)
                            .font(GSFont.boldFixed(30).monospacedDigit())
                            .foregroundStyle(theme.text.opacity(0.78))
                        Spacer()
                    } else {
                        Text("—")
                            .font(GSFont.boldFixed(36))
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(soloBLEBPM != nil)
        .padding(.horizontal, 16)
    }

    /// 22-bar bpm history — the same bar language as the group page.
    @ViewBuilder
    private var soloRecoverySparkline: some View {
        let bars = soloRecoveryBuffer.sparkline(barCount: 22)
        if !bars.isEmpty {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { pair in
                    Capsule().fill(theme.text.opacity(0.45))
                        .frame(width: 3, height: max(3, CGFloat(pair.element) * 40))
                }
            }
            .frame(height: 42, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }

    /// The countdown, big, over UP NEXT — the entry page is already
    /// prefilled for exactly this set, so the readback echoes it.
    private var soloRestHero: some View {
        VStack(spacing: 0) {
            // TRANSIT (2026-08): an exercise-change window announces the
            // station move for its whole duration.
            Text(soloRestIsTransit ? "TRANSIT · SET UP YOUR STATION" : "REST")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(theme.neutral700)
            Color.clear.frame(height: 12)
            if let restEndAt {
                Text(timerInterval: .now...restEndAt, countsDown: true)
                    .font(GSFont.boldFixed(64).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 12)
            VStack(spacing: 7) {
                Text("UP NEXT")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral700)
                Text(currentExercise?.name ?? "—")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(soloUpNextReadback)
                    .font(GSFont.bold(13, relativeTo: .footnote).monospacedDigit())
                    .tracking(0.5)
                    .foregroundStyle(theme.text.opacity(0.78))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private var soloUpNextReadback: String {
        let sets = currentRoutineExercise?.targetSets.map { " OF \($0)" } ?? ""
        var parts = ["SET \(currentSetIndex)\(sets)"]
        if !soloWeight.isEmpty && !soloReps.isEmpty {
            parts.append("\(soloWeight) \(soloUnit.label.uppercased()) × \(soloReps)")
        } else if !soloWeight.isEmpty {
            parts.append("\(soloWeight) \(soloUnit.label.uppercased())")
        } else if !soloReps.isEmpty {
            parts.append("\(soloReps) REPS")
        }
        return parts.joined(separator: " · ")
    }

    /// The single-line session stats widget (user 2026-07-31: no
    /// REST|BOARD toggle solo — "just a single line widget that shows your
    /// load and percent rigor"). Same SessionScoreboard math as the group
    /// board: LOAD = Σ reps × RPE, % SELF = best set today vs your own
    /// pre-session est-1RM ceiling; dashes until there's real data.
    private var soloSelfStatsLine: some View {
        let row = appState.currentProfile.map { profile in
            SessionScoreboard.rows(
                participants: [profile.id],
                sessionSets: loggedSets,
                baselines: [profile.id: soloCeilings]
            ).first
        } ?? nil
        return HStack(spacing: 10) {
            Text("SESSION")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer()
            Text("LOAD")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral700)
            Text(row.map { $0.load > 0 ? "\($0.load)" : "—" } ?? "—")
                .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                .foregroundStyle(theme.text.opacity(0.78))
            Rectangle().fill(theme.divider)
                .frame(width: 2, height: 14)
                .padding(.horizontal, 2)
            Text("% SELF")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral700)
            Text(row?.pctSelf.map { "\($0)%" } ?? "—")
                .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                .foregroundStyle((row?.ceilingBroken ?? false) ? theme.accent : theme.text.opacity(0.78))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// Best-effort ceiling fetch per exercise lifted this session —
    /// a blocked or empty history just leaves the honest dash.
    @MainActor
    private func loadSoloCeilings() async {
        guard let userID = appState.currentProfile?.id,
              let sessionID = session?.id,
              !isLoadingSoloStats else { return }
        isLoadingSoloStats = true
        defer { isLoadingSoloStats = false }
        let exercises = Set(loggedSets.filter { !$0.isPenalty }.map(\.exerciseID))
        for exerciseID in exercises where soloCeilings[exerciseID] == nil {
            guard let history = try? await SessionRepository.exerciseHistory(
                userID: userID, exerciseID: exerciseID, limit: 200) else { continue }
            let base = SessionScoreboard.baseline(history: history,
                                                 excludingSessionID: sessionID)
            if let ceiling = base[exerciseID] {
                soloCeilings[exerciseID] = ceiling
            }
        }
    }

    // Vitals 116pt — HR three-state (shared HeartRatePrimeStore semantics:
    // dash = never asked, elapsed = asked, bpm = a strap is connected) |
    // bar strip, or LAST TIME for non-barbell.
    private var soloVitalsRow: some View {
        HStack(spacing: 10) {
            Button { if soloBLEBPM == nil { soloShowHRPairing = true } } label: {
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(soloBLEBPM != nil ? theme.text.opacity(0.78) : theme.neutral700)
                    if let bpm = soloBLEBPM {
                        Text("\(bpm)")
                            .font(GSFont.boldFixed(52).monospacedDigit())
                            .foregroundStyle(theme.text)
                    } else if HeartRatePrimeStore.hasBeenAsked, let startedAt = session?.startedAt {
                        Text(startedAt, style: .timer)
                            .font(GSFont.boldFixed(36).monospacedDigit())
                            .foregroundStyle(theme.text.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    } else {
                        Text("—")
                            .font(GSFont.boldFixed(52))
                            .foregroundStyle(theme.neutral700)
                    }
                }
                .frame(maxWidth: soloIsBarbell ? 120 : .infinity, maxHeight: .infinity)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(soloBLEBPM != nil)

            if soloIsBarbell {
                soloBarCard
            } else {
                soloLastTimeCard
            }
        }
        .frame(height: 116)
        .padding(.horizontal, 16)
    }

    private var soloIsBarbell: Bool {
        currentExercise?.equipment.lowercased() == "barbell"
    }

    private var soloBarCard: some View {
        let unit = soloUnit
        let plates: [Decimal] = {
            if let custom = ThemeStore.shared.plateInventory, !custom.isEmpty {
                return custom.sorted(by: >)
            }
            return unit.standardPlates
        }()
        let barInUnit: Decimal = {
            var value = Units.fromPounds(ThemeStore.shared.barWeightLbs, to: unit)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .plain)
            return rounded
        }()
        let targetInUnit: Decimal = Decimal.parseUserInput(soloWeight) ?? barInUnit
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { soloLoaderOpen.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOAD THE BAR")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(theme.text.opacity(0.78))
                Text(soloLoaderOpen ? "CLOSE" : "TAP HERE")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(soloLoaderOpen ? theme.accent : theme.neutral700)
                Spacer(minLength: 4)
                if targetInUnit > barInUnit {
                    // Shaft continues through the card — mirrors the full
                    // loader's silhouette (user round 3).
                    HStack(spacing: 1.5) {
                        GSBarLoaderMini(target: targetInUnit, barWeight: barInUnit,
                                        plates: plates, unit: unit)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.neutral500.opacity(0.55))
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // Collar + shaft only — the right collar is gone (user,
                    // 2026-07-30: "eliminate the far right collar").
                    HStack(spacing: 1.5) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.neutral500).frame(width: 4, height: 16)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.neutral500.opacity(0.55)).frame(height: 4)
                    }
                    .frame(height: 40)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                soloLoaderOpen ? theme.accent : theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var soloLastTimeCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAST TIME")
                .font(GSFont.bold(19, relativeTo: .body))
                .tracking(0.7)
                .foregroundStyle(theme.text.opacity(0.78))
            // Structured (queue item): weight × reps at 30pt with RPE + age
            // beneath — the group card's exact grammar, from the same fetch
            // that feeds the prefill ladder.
            if let last = soloPriorSets
                .filter({ !$0.isPenalty && $0.sessionID != session?.id })
                .max(by: { $0.loggedAt < $1.loggedAt }) {
                Text("\(last.weight.map { Units.format(pounds: $0, unit: soloUnit, rounded: false, includeUnit: false) } ?? "—") × \(last.reps.map { "\($0)" } ?? "—")")
                    .font(GSFont.boldFixed(30).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(soloLastTimeMeta(last))
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
            } else {
                Text("FIRST TIME")
                    .font(GSFont.bold(19, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(theme.neutral700)
                Spacer(minLength: 2)
                Text("NO PREVIOUS SETS")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(theme.neutral700)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var soloLoaderExpanded: some View {
        ScrollView {
            BarLoaderWidget(initialPounds: barLoaderPounds,
                            onEnteredPoundsChange: { pounds in
                                barLoaderPounds = pounds
                                guard let pounds else { return }
                                soloWeight = Units.format(pounds: pounds, unit: soloUnit,
                                                          rounded: false, includeUnit: false)
                            })
                .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    // Exercise widget — SETS | ROUTINE, flexible child.
    private var soloExerciseCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(currentExercise?.name ?? "Exercise")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.top, 12)

            if soloWidgetPage == 0 { soloSetsPage } else { soloRoutinePage }

            GSDivider().padding(.horizontal, -14)
            HStack(spacing: 0) {
                soloPagerTab("SETS", index: 0)
                soloPagerTab("ROUTINE", index: 1)
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func soloPagerTab(_ label: String, index: Int) -> some View {
        Button { soloWidgetPage = index } label: {
            Text(label)
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(1.0)
                .foregroundStyle(soloWidgetPage == index ? theme.text : theme.neutral700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if soloWidgetPage == index {
                        Capsule().fill(theme.text)
                            .frame(height: 2)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var soloCurrentExerciseSets: [SetLog] {
        guard let re = currentRoutineExercise else { return [] }
        return loggedSets
            .filter { $0.exerciseID == re.exerciseID }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var soloSetsPage: some View {
        let sets = soloCurrentExerciseSets
        let target = currentRoutineExercise?.targetSets
        let remaining = target.map { max(0, $0 - sets.count - 1) }
        return HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { pair in
                        soloSetColumn(pair.element,
                                      bright: pair.offset == sets.count - 1)
                        Rectangle().fill(theme.divider)
                            .frame(width: 1)
                            .padding(.vertical, 15)
                    }
                    soloCurrentColumn
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(theme.neutral500)
                .frame(width: 1)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)

            VStack(spacing: 8) {
                Text(remaining.map { "\($0)" } ?? "\(sets.count)")
                    .font(GSFont.boldFixed(48).monospacedDigit())
                    .foregroundStyle(theme.text)
                Text(remaining != nil
                     ? (remaining == 1 ? "SET LEFT" : "SETS LEFT")
                     : "LOGGED")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(theme.neutral700)
            }
            .frame(width: 96)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 6)
    }

    private func soloSetColumn(_ log: SetLog, bright: Bool) -> some View {
        let color: Color = bright ? theme.text.opacity(0.78) : theme.neutral700
        return VStack(spacing: 8) {
            Text(log.weight.map { Units.format(pounds: $0, unit: soloUnit, rounded: false, includeUnit: false) } ?? "—")
                .font(GSFont.boldFixed(28).monospacedDigit())
                .foregroundStyle(color)
            Text("× \(log.reps.map { "\($0)" } ?? "—")")
                .font(GSFont.boldFixed(16).monospacedDigit())
                .foregroundStyle(color)
            if log.isFailed {
                Text("FAIL")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(theme.text.opacity(0.78), lineWidth: 1))
            } else if let rpe = log.rpe {
                Text("RPE \(NSDecimalNumber(decimal: rpe).intValue)")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .frame(width: 72)
    }

    private var soloCurrentColumn: some View {
        VStack(spacing: 8) {
            Text(soloWeight.isEmpty ? "—" : soloWeight)
                .font(GSFont.boldFixed(30).monospacedDigit())
                .foregroundStyle(theme.text)
            Text("× \(leadingInt(soloReps).map { "\($0)" } ?? "—")")
                .font(GSFont.boldFixed(17).monospacedDigit())
                .foregroundStyle(theme.text)
            Text(soloFailed ? "FAIL" : "RPE \(Int(soloRPE))")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .foregroundStyle(theme.text.opacity(0.78))
        }
        .frame(width: 72)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Capsule().fill(theme.accent)
                .frame(width: 44, height: 3)
                .padding(.bottom, 2)
        }
    }

    private var soloRoutinePage: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(activeExercises.enumerated()), id: \.element.id) { index, re in
                    let isCurrent = re.exerciseID == currentRoutineExercise?.exerciseID
                    let count = loggedSets.filter { $0.exerciseID == re.exerciseID }.count
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(isCurrent ? theme.accent : theme.neutral500)
                            .frame(width: 20, alignment: .leading)
                        Text(exerciseName(for: re.exerciseID))
                            .font(isCurrent ? GSFont.bold(17, relativeTo: .body)
                                            : GSFont.body(15, relativeTo: .subheadline))
                            .foregroundStyle(isCurrent ? theme.text : theme.neutral700)
                            .lineLimit(1)
                        Spacer()
                        Text(re.targetSets.map { "\(count)/\($0)" } ?? "\(count)")
                            .font(GSFont.bold(isCurrent ? 17 : 14, relativeTo: .subheadline).monospacedDigit())
                            .foregroundStyle(isCurrent ? theme.text : theme.neutral700)
                    }
                    .frame(minHeight: isCurrent ? 30 : 22)
                    .overlay(alignment: .bottom) {
                        if isCurrent {
                            Capsule().fill(theme.accent)
                                .frame(height: 3)
                                .padding(.leading, 30)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // Entry card 220 — the clock slot shows the REST countdown while one
    // runs (solo's rest is real state, unlike group's turn clock).
    private var soloEntryCard: some View {
        let target = currentRoutineExercise?.targetSets
        let targetReps = currentRoutineExercise?.targetReps
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(currentSetIndex)")
                    .font(GSFont.boldFixed(24).monospacedDigit())
                    .foregroundStyle(theme.accent)
                if let target {
                    Text("OF \(target)")
                        .font(GSFont.bold(15, relativeTo: .subheadline))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                        .padding(.leading, 7)
                }
                Spacer()
                if let restEndAt, restEndAt > .now {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.trailing, 5)
                    Text(timerInterval: .now...restEndAt, countsDown: true)
                        .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                        .foregroundStyle(theme.text.opacity(0.78))
                } else {
                    // THIS SET's elapsed time — not the session's (user report
                    // 2026-08-02: "the timer on the set widget should be just
                    // the time elapsed for this set, not including the rest and
                    // transit times"). `setStartedAt` is re-stamped whenever a
                    // set actually begins: on log (when no rest follows), when
                    // rest is cut short via START SET, and when a rest window
                    // lapses on its own. The whole-session clock lives in the
                    // header.
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                        .padding(.trailing, 5)
                    Text(setStartedAt, style: .timer)
                        .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                        .foregroundStyle(theme.text.opacity(0.78))
                }
            }
            .frame(height: 30)

            Color.clear.frame(height: 12)
            HStack(spacing: 0) {
                Text("WEIGHT · \(soloUnit.label.uppercased())")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .frame(width: 229, alignment: .leading)
                Text(targetReps.map { "REPS · \($0)" } ?? "REPS")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
            }
            .frame(height: 14)

            Color.clear.frame(height: 6)
            // No step labels, no inner hairlines (user, 2026-07-30) — see
            // the group entry card's identical note. Row grows 56 → 64:
            // the exercise widget cedes the pixels ("the set and routine
            // widget can give some pixels to the weight logging widget").
            HStack(spacing: 0) {
                TurnAutoRepeatButton(glyph: "minus", detail: nil, theme: theme) { soloStepWeight(-1) }
                    .frame(width: 44)
                Text(soloWeight.isEmpty ? "—" : soloWeight)
                    .font(GSFont.boldFixed(38).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .frame(width: 96)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                TurnAutoRepeatButton(glyph: "plus", detail: nil, theme: theme) { soloStepWeight(1) }
                    .frame(width: 44)

                Rectangle().fill(theme.neutral500)
                    .frame(width: 1, height: 44)
                    .padding(.horizontal, 8)

                TurnAutoRepeatButton(glyph: "minus", detail: nil, theme: theme) { soloStepReps(-1) }
                    .frame(width: 44)
                Text(leadingInt(soloReps).map { "\($0)" } ?? "—")
                    .font(GSFont.boldFixed(38).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                TurnAutoRepeatButton(glyph: "plus", detail: nil, theme: theme) { soloStepReps(1) }
                    .frame(width: 44)
            }
            .frame(height: 64)

            Color.clear.frame(height: 12)
            Text("RPE")
                .font(GSFont.bold(18, relativeTo: .body))
                .tracking(1.2)
                .foregroundStyle(soloFailed ? theme.text : theme.text.opacity(0.78))
                .frame(height: 20)

            Color.clear.frame(height: 8)
            RPESwipeTrack(value: $soloRPE, isFailed: $soloFailed, theme: theme)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral700.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private var soloStepperRule: some View {
        Rectangle().fill(theme.neutral700.opacity(0.55)).frame(width: 1, height: 30)
    }

    private func soloStepWeight(_ direction: Int) {
        let current = Decimal.parseUserInput(soloWeight) ?? 0
        let next = max(0, current + soloWeightStep * Decimal(direction))
        var rounded = Decimal()
        var value = next
        NSDecimalRound(&rounded, &value, 1, .plain)
        soloWeight = rounded == 0 ? "" : "\(rounded)"
    }

    private func soloStepReps(_ direction: Int) {
        let current = leadingInt(soloReps) ?? 0
        soloReps = "\(max(0, current + direction))"
    }

    /// "RPE 8 · 6 DAYS AGO" — whichever parts are real.
    private func soloLastTimeMeta(_ log: SetLog) -> String {
        var parts: [String] = []
        if log.isFailed {
            parts.append("FAIL")
        } else if let rpe = log.rpe {
            parts.append("RPE \(NSDecimalNumber(decimal: rpe).intValue)")
        }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: log.loggedAt),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: parts.append("TODAY")
        case 1:    parts.append("YESTERDAY")
        default:   parts.append("\(days) DAYS AGO")
        }
        return parts.joined(separator: " · ")
    }

    // Chrome: the CTA alone — solo has no soundboard or PTT. During rest
    // the CTA becomes START SET (cut the rest short), mirroring the group
    // interlude's chrome.
    private var soloChrome: some View {
        VStack(spacing: 0) {
            GSDivider()
            Color.clear.frame(height: 8)
            if soloWarmupActive && !soloLoaderOpen {
                // Warm-up (2026-08): the page carries its own SKIP CTA —
                // no pinned chrome beyond the divider.
                Color.clear.frame(height: 0)
            } else if soloRestActive && !soloLoaderOpen {
                // 3D pass (2026-08): accent gs3D face, 57pt + 7pt lip =
                // the prior 64pt CTA footprint (the group interlude's idiom).
                Button {
                    // Cutting rest short IS the start of the set — stamp it so
                    // the set card's clock times this set, not the rest before it.
                    restEndAt = nil
                    setStartedAt = .now
                } label: {
                    VStack(spacing: 2) {
                        Text("START SET")
                            .font(GSFont.bold(17, relativeTo: .body))
                            .tracking(0.9)
                        if let restEndAt {
                            HStack(spacing: 4) {
                                // Short form here — the rest hero above
                                // carries the full TRANSIT k-label.
                                Text(soloRestIsTransit ? "TRANSIT" : "RESTING")
                                    .font(GSFont.bold(11, relativeTo: .caption2))
                                Text(timerInterval: .now...restEndAt, countsDown: true)
                                    .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                            }
                            .opacity(0.8)
                        }
                    }
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 57)
                }
                .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 16))
                .padding(.horizontal, 16)
            } else {
            Button {
                // Re-entrancy guard: a second tap while the first submit is
                // still in flight must not log again or advance the set.
                guard !isLoggingSet else { return }
                isLoggingSet = true
                setStartedAt = .now
                restEndAt = nil
                let weightPounds = Decimal.parseUserInput(soloWeight)
                    .map { Units.toPounds($0, from: soloUnit) }
                Task {
                    defer { isLoggingSet = false }
                    guard await log(reps: leadingInt(soloReps),
                                    weight: weightPounds,
                                    rpe: Decimal(Int(soloRPE)),
                                    isFailed: soloFailed,
                                    note: nil) else { return }
                    // A logged set visibly resets the page (user report
                    // 2026-07-30: logging over the open loader looked like
                    // nothing happened) — close the loader and keyboard so
                    // the set/rest layout is back on screen. Failure keeps
                    // everything up for a retry.
                    withAnimation(.easeInOut(duration: 0.18)) { soloLoaderOpen = false }
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            } label: {
                // 3D pass (2026-08): the gs3D style owns the fill (accent
                // face, the theme's raised face for a failed set — surface
                // was invisible as 3D) + the 7pt lip; the failed outline
                // rides the label, landing exactly on the face rect. 57pt
                // face + lip = the prior 64pt footprint.
                ZStack {
                    if soloFailed {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(theme.text, lineWidth: 1.5)
                    }
                    VStack(spacing: 2) {
                        Text(soloFailed ? "LOG FAILED SET \(currentSetIndex)" : "LOG SET \(currentSetIndex)")
                            .font(GSFont.bold(17, relativeTo: .body))
                            .tracking(0.9)
                        Text(soloCTAReadback)
                            .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                            .opacity(0.8)
                    }
                    .foregroundStyle(soloFailed ? theme.text : theme.bg)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 57)
            }
            .buttonStyle(.gs3D(face: soloFailed ? theme.raised3DFace : theme.accent,
                               lip: soloFailed ? theme.raised3DLip : nil,
                               cornerRadius: 16))
            .disabled(isLoggingSet || (leadingInt(soloReps) == nil && !soloFailed))
            .gsSpotlightTarget(.workout)
            .padding(.horizontal, 16)
            }
            Color.clear.frame(height: 10)
        }
        .background(theme.bg)
    }

    private var soloCTAReadback: String {
        if leadingInt(soloReps) == nil && !soloFailed { return "ENTER REPS TO LOG" }
        let weight = soloWeight.isEmpty ? "—" : soloWeight
        let reps = leadingInt(soloReps).map { "\($0)" } ?? "—"
        let rpe = soloFailed ? "RPE 10 · MISS" : "RPE \(Int(soloRPE))"
        return "\(weight) \(soloUnit.label) × \(reps) · \(rpe)"
    }

    private var soloScrollBody: some View {
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
                        // The primary in-workout control, pressed once per
                        // set with chalked or sweaty hands — the research
                        // argues >=64pt here. 3D pass (2026-08): the label
                        // reproduces GSPrimaryButtonStyle's left-aligned
                        // bold-16 anatomy; 57pt face + the gs3D style's
                        // 7pt lip keeps the exact 64pt footprint.
                        HStack(spacing: 0) {
                            Text("Log Set \(currentSetIndex)")
                            Spacer(minLength: 0)
                        }
                        .font(GSFont.bold(16, relativeTo: .body))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 57)
                    }
                    .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
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
                    // A failed set stores rpe = 10, so printing rpe alone
                    // renders a miss as "10" — indistinguishable from a
                    // max-effort success. isFailed is authoritative.
                    col3: Text(log.isFailed
                               ? "FAIL"
                               : (log.rpe.map { "\($0)" } ?? "—"))
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
            // Solo warm-up (2026-08): a configured duration opens the
            // warm-up page before the first set — the persisted DEFAULT of
            // 0 keeps existing solo behavior untouched. Routine sessions
            // only: freeform uses the scroll body, which has no fixed-page
            // slot for the phase.
            if !isFreeform, soloWarmupMinutes > 0 {
                soloWarmupEndsAt = (newSession.startedAt ?? Date())
                    .addingTimeInterval(TimeInterval(soloWarmupMinutes * 60))
            }
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
    /// Returns `true` once the set is durably recorded (server insert OR the
    /// offline queue) — `false` only when the attempt failed outright and the
    /// entry UI should stay up for a retry.
    @discardableResult
    private func log(reps: Int?, weight: Decimal?, rpe: Decimal?, isFailed: Bool, note: String?) async -> Bool {
        guard let session, let re = currentRoutineExercise,
              let userID = appState.currentProfile?.id else { return false }

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
            // The set is durably recorded either way (server insert or offline
            // queue) — this is the moment the success haptic fires.
            logHapticTick += 1

            // Keep the prefetched PR baseline exact without a refetch: the set
            // we just wrote is the only thing that can raise it mid-session.
            // Without this, a second PR in the same session would report the
            // pre-session best as "your previous best" instead of the PR set
            // just before it.
            if !isFailed, let weight, weight > (priorBestByExercise[re.exerciseID] ?? 0) {
                priorBestByExercise[re.exerciseID] = weight
            }

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
                // Freeform never auto-advances exercises, so its windows
                // are always same-exercise rest — never TRANSIT.
                soloRestIsTransit = false
                if restSeconds > 0 {
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
                return true
            }

            let targetSets = re.targetSets ?? 1
            let exerciseChanged: Bool
            if currentSetIndex >= targetSets {
                currentSetIndex = 1
                currentExerciseIndex += 1
                exerciseChanged = true
            } else {
                currentSetIndex += 1
                exerciseChanged = false
            }
            if currentExerciseIndex >= activeExercises.count {
                restEndAt = nil
                await endSession()
            } else {
                // Per-exercise rest wins when configured; otherwise fall back
                // to the user's default_rest_seconds (Canvas Completion Task 2)
                // rather than showing no rest timer at all.
                // TRANSIT (2026-08): an exercise boundary extends the window
                // by TransitWindow.seconds and labels the WHOLE window
                // TRANSIT — time to set up the next station. Same-exercise
                // sets are unchanged.
                let restSeconds = (re.restSeconds ?? defaultRestSeconds)
                    + (exerciseChanged ? TransitWindow.seconds : 0)
                soloRestIsTransit = exerciseChanged
                if restSeconds > 0 {
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
            }
            return true
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
            return false
        }
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
        // Ronnie for the PR moment (user 2026-08-01) — the solo path had
        // no celebration sound at all.
        Task { await SoundboardPlayer.shared.play(slug: "lightweight-baby") }
    }

    /// PR baseline for `exerciseID`, served from the prefetch when it landed.
    ///
    /// The prefetch (`.task(id: exerciseID)`) runs while the lifter is setting
    /// up, so the common path costs zero network at log time — the whole point
    /// of the 2026-08-02 latency fix. The live call is the cold fallback (the
    /// exercise just changed and the prefetch hasn't answered yet) and is now
    /// a one-row query rather than a 200-row download.
    private func priorMax(exerciseID: UUID, weight: Decimal, userID: UUID) async throws -> Decimal {
        if let cached = priorBestByExercise[exerciseID] { return cached }
        let best = try await SessionRepository.bestWeight(userID: userID, exerciseID: exerciseID)
        priorBestByExercise[exerciseID] = best
        return best
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
