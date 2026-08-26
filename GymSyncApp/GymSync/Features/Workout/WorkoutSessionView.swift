import AudioToolbox
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

    /// Resume mode (user report 2026-08-11: a swiped-down solo session was
    /// irrecoverable): a non-nil `resume` skips `startSolo` and adopts this
    /// already-running session instead — `startIfNeeded()` refetches its
    /// `set_logs` and re-derives the exercise/set cursor so the lifter lands
    /// exactly where they left off. Passed only by MainTabView's
    /// "SESSION LIVE" pill via `AppState.liveSoloSession`.
    let resumeSession: WorkoutSession?

    init(routine: Routine?, routineExercises: [RoutineExercise], allExercises: [Exercise],
         attemptOptIn: Bool? = nil, resume: WorkoutSession? = nil,
         onFinished: (() -> Void)? = nil) {
        self.routine = routine
        self.routineExercises = routineExercises
        self.allExercises = allExercises
        self.attemptOptIn = attemptOptIn
        self.resumeSession = resume
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
    // Coach note (BlockProgression, owner 2026-08-20): the block engine's
    // session-start decision for the current exercise. Advances apply to
    // the prefill and explain themselves in a compact note; a deload is
    // only a PROPOSAL until the athlete accepts it.
    @State private var soloCoachDecision: BlockProgression.Decision?
    @State private var soloCoachNoteExpanded = false
    /// Set when the return horizon left nothing to prescribe from, so the
    /// empty weight field arrives with a reason instead of reading as a
    /// bug. Deliberately NOT routed through BlockProgression.Decision:
    /// that surface is gated on `soloRoutineIsCoachProgram` plus a rep
    /// range, so a returner on their own routine — the likeliest person to
    /// come back to something familiar — would get the blank field and no
    /// explanation at all.
    @State private var soloReturnNote: String?
    /// Best substitution-graph swap for a flagged stall (5-channel corpus
    /// consensus: a stalled lift wants a variation, not another load tweak).
    @State private var soloStallSwapName: String?
    // Coach debrief chain (2026-08-21): profile loaded best-effort for the
    // headline's register + persona; per-lift history prefetched at
    // completion so the recap's trend tool narrates REAL computed trends.
    @State private var coachProfile = TrainingProfile()
    @State private var showCoachRecap = false
    @State private var recapTrendHistory: [String: [SetLog]] = [:]
    /// Drift probe (Phase 4): a found signal rides the debrief as its
    /// pending question, on the ~2-week cooldown.
    @State private var coachPendingProbe: DriftDetector.Signal?
    // Manual weight entry (field report 2026-08-21: "tap on the weight
    // recording and enter a weight manually").
    @State private var showWeightEntry = false
    @State private var weightEntryText = ""
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

    /// Per-exercise (weight, reps) history, prefetched off the critical path —
    /// the basis for rep-aware PR judgement (`PersonalRecordMath`).
    ///
    /// Held as pairs rather than a single "best weight" because a PR is now
    /// judged against the rep count it happened at, so the answer depends on
    /// the set being logged. Two columns for a whole exercise history is a few
    /// KB, which buys exact local answers for ANY rep count with no network on
    /// the log path. Appended to after each set — the only new data that can
    /// move these numbers mid-session is work we just did ourselves.
    @State private var prBasisByExercise: [UUID: [(weight: Decimal, reps: Int)]] = [:]
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
    /// log id -> when its set began (histogram fuel; session-scoped).
    @State private var soloSetStarts: [UUID: Date] = [:]
    /// Owner ruling (field #38): mid-session tweaks - prefilled load
    /// steps, deload proposals, the coach note - apply ONLY to routines
    /// Coach itself authored. A user-curated routine is never silently
    /// altered; its suggestions arrive at the END, as a debrief blurb.
    /// Trainer-prescribed routines are a human's prescription - also
    /// never touched.
    private var soloRoutineIsCoachProgram: Bool {
        routine?.name.hasPrefix("Coach · ") == true && routine?.prescribedBy == nil
    }

    /// The JUST-ENDED set's start, preserved across the log handler's
    /// `setStartedAt = .now` re-stamp (which is for the NEXT set's
    /// clock). Field bug #33: capturing after the re-stamp made every
    /// histogram set-segment ~zero.
    @State private var soloEndedSetStart: Date?
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
    /// Recovery-adaptive rest (owner 2026-08-12): when this rest window
    /// opened — with restEndAt it gives the progress fraction the verdict
    /// math needs.
    @State private var soloRestStartedAt: Date?
    /// End-of-rest HR drops from THIS session — the personal baseline
    /// (median) behind the GO EARLY / +30s pills. Captured by
    /// `captureRestDrop()` at every rest-ending path; never persisted
    /// (yesterday's recovery is a lie today).
    @State private var soloRestDrops: [Int] = []
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
    /// Exercise whose detail page (video demo + history) is open as a sheet —
    /// set by tapping the exercise name on the header card (user 2026-08-11:
    /// "click on the name of the exercise in a session and be taken to the
    /// exercise page"). A sheet, not a push, so dismissing it lands straight
    /// back in the session.
    @State private var exerciseDetailSheet: Exercise?
    /// Routine list during rest (owner 2026-08-13) — the ROUTINE pager
    /// lives on the exercise card the rest page replaces.
    @State private var showRestRoutineSheet = false
    /// Set pace (owner item 4, 2026-08-13): seconds from set start to
    /// durable record, per set this session — the no-HR recovery proxy
    /// drawn on the YOUR RECOVERY card when no strap is connected.
    @State private var soloSetDurations: [Double] = []
    /// Owner item 7: latest logged body weight (canonical lbs), stamped
    /// onto bodyweight-exercise sets. nil until fetched / never logged.
    @State private var soloLatestBodyWeightLbs: Decimal?

    @State private var freeformExercises: [RoutineExercise] = []
    @State private var showExercisePicker = false
    @State private var pickerCatalog: [Exercise] = []

    /// True for a session started with no routine (Home's "Start solo
    /// workout" without picking one). Same condition the old placeholder
    /// empty state used.
    private var isFreeform: Bool { routineExercises.isEmpty }

    /// Hot-swap (owner 2026-08-21): session-local replacements by
    /// routine-exercise id — the machine's taken, the shoulder says no.
    /// Never persisted to the routine; set logs carry the SWAPPED
    /// exercise's id, so history, PRs, and the debrief all see what was
    /// actually done. Quiet by design: shown where the exercise shows,
    /// announced nowhere.
    @State private var soloSwapOverrides: [UUID: RoutineExercise] = [:]
    @State private var showSwapSheet = false
    // Form video v1 (owner rulings 2026-08-21): record a set, attach the
    // clip to the NEXT logged set. Retention is GATED - PRO or
    // coach-linked persists; everyone else reviews immediately and the
    // file is discarded (never uploaded).
    @State private var showFormClipCapture = false
    @State private var pendingClipURL: URL? = nil
    @State private var canRetainClips: Bool? = nil
    @State private var reviewClip: ReviewClip? = nil
    struct ReviewClip: Identifiable { let url: URL; var id: URL { url } }
    // Mobility rows navigate to the exercise page (owner 2026-08-22).
    // Resolved lazily against the FULL catalog - routine sessions only
    // carry the routine's own rows in `allExercises`.
    @State private var mobilityDetail: Exercise?
    @State private var mobilityCatalog: [Exercise] = []
    // Mid-session full builder (spec 2026-08-22 §2): a session-local
    // edited list that supersedes the routine's rows; the stored
    // routine is untouched until the end-of-workout three-way.
    @State private var soloEditedList: [RoutineExercise]?
    @State private var showSessionEditor = false
    @State private var showKeepEditsDialog = false

    /// The exercise list driving the whole screen — the routine's when there
    /// is one, the lifter's running freeform picks otherwise, with any
    /// session-local hot-swaps applied on top.
    private var activeExercises: [RoutineExercise] {
        // Mid-session edits supersede the routine's rows; swap overrides
        // still layer on top (a swap made before an edit survives it).
        let base = isFreeform ? freeformExercises : (soloEditedList ?? routineExercises)
        guard !soloSwapOverrides.isEmpty else { return base }
        return base.map { soloSwapOverrides[$0.id] ?? $0 }
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
        .sheet(item: $exerciseDetailSheet) { ex in
            NavigationStack {
                ExerciseDetailView(exercise: ex)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { exerciseDetailSheet = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showRestRoutineSheet) {
            NavigationStack {
                soloRoutinePage
                    .padding(.top, 8)
                    .background(theme.bg)
                    .navigationTitle("Routine")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showRestRoutineSheet = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
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
                    userID: userID, exerciseIDs: aliasFamilyIDs(for: re.exerciseID),
                    limit: 30)) ?? []
                // PR basis, fetched HERE rather than at log time — this is the
                // latency fix: by the time the CTA is pressed the answer is
                // already in memory, so logging is one write and nothing else.
                // Best-effort; `prBasis` still has a live fallback.
                if prBasisByExercise[re.exerciseID] == nil,
                   let rows = try? await SessionRepository.prBasis(
                    userID: userID, exerciseID: re.exerciseID) {
                    prBasisByExercise[re.exerciseID] = Self.pairs(from: rows)
                }
            } else {
                soloPriorSets = []
            }
            if soloEnrollment == nil {
                soloEnrollment = try? await ProgramRepository.active()
            }
            soloPrefill()
            pushSoloWatchState(session: session, active: !completed)
            // Stall response (diagnostics pass, 5-channel consensus): a
            // stalled lift wants a VARIATION, so a flagged stall fetches
            // the graph's best swap and the note names it. Best-effort —
            // the stall note stands on its own without one.
            soloStallSwapName = nil
            if case .flagStall = soloCoachDecision,
               let slug = currentExercise?.slug, !slug.isEmpty,
               let swap = try? await ExerciseSubstitutionRepository
                   .forExercise(slug: slug).first {
                soloStallSwapName = swap.toSlug
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: " ")
            }
        }
        .onChange(of: restEndAt) { handleRestWindowChange() }
        // The existing solo pushes fire on session start, completion and
        // scene change - not when the exercise or the set count moves,
        // which is what nextSetIndex and the exercise name depend on.
        .onChange(of: currentExerciseIndex) {
            pushSoloWatchState(session: session, active: session?.completedAt == nil)
        }
        .onChange(of: soloCurrentExerciseSets.count) {
            pushSoloWatchState(session: session, active: session?.completedAt == nil)
        }
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
        // Rest buzz (owner 2026-08-14): ONE observation point covers every
        // path that opens or closes a rest window — freeform, routine,
        // superset handoff, START SET, the lapse task.
        .onChange(of: restEndAt) {
            if let end = restEndAt {
                RestNotifier.schedule(at: end)
            } else {
                RestNotifier.cancel()
            }
        }
        .sheet(item: $dropLadder, onDismiss: startPostDropRest) { ctx in
            DropLadderSheet(
                topWeightPounds: ctx.topWeightPounds,
                steps: ctx.steps,
                dropPercent: ctx.percent,
                unit: soloUnit,
                weightStep: NSDecimalNumber(decimal: soloWeightStep).doubleValue
            ) { rungs in
                // Best-effort — the parent set already logged; a failed
                // ladder write never blocks anything (the trigger picks up
                // whatever rows land).
                let segments = rungs.enumerated().map { index, rung in
                    SetLogSegment(id: UUID(), setLogID: ctx.setLogID,
                                  segmentIndex: index + 1,
                                  weight: rung.weight, reps: rung.reps)
                }
                Task { try? await SetLogSegmentRepository.log(segments) }
            }
        }
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
                        coachDebrief: coachDebrief,
                        coachName: CoachPersona.bySlug(coachProfile.persona)?.name ?? "Coach",
                        onTalkToCoach: { showCoachRecap = true },
                        onDone: { finishSession() }
                    )
                    .sheet(isPresented: $showCoachRecap) {
                        if let debrief = coachDebrief {
                            CoachRecapView(
                                applyRoutineEdit: { proposal in
                                    await applyCoachRoutineEdit(proposal)
                                },
                                debrief: debrief,
                                persona: CoachPersona.bySlug(coachProfile.persona),
                                profile: coachProfile,
                                trendLookup: { [history = recapTrendHistory] name in
                                    if let logs = history[name.lowercased()], logs.count > 1 {
                                        return DebriefBuilder.trendSentence(name: name, logs: logs)
                                    }
                                    return "\(name): not enough logged history for a trend yet — today's numbers are in the report."
                                },
                                volumeLookup: {
                                    "Per-muscle weekly volume lands in an upcoming update — ask about any lift's trend instead."
                                })
                        }
                    }
                    // The Duolingo-placement slot: fires AFTER the recap
                    // lands, never over the celebration. Dormant today;
                    // becomes the Pro upsell when the paywall flips (and is
                    // where ads would go if ever revisited).
                    .completionInterstitial(profile: appState.currentProfile)
                    .task(id: completed) {
                        await prefetchCoachContext()
                        if completed, soloEditedList != nil,
                           soloEditedList != routineExercises {
                            showKeepEditsDialog = true
                        }
                    }
                    .confirmationDialog("Keep your mid-session edits?",
                                        isPresented: $showKeepEditsDialog,
                                        titleVisibility: .visible) {
                        Button("Update this routine") {
                            Task { await persistSessionEdits(asNew: false) }
                        }
                        Button("Save as a new routine") {
                            Task { await persistSessionEdits(asNew: true) }
                        }
                        Button("Discard", role: .cancel) {}
                    } message: {
                        Text("You reshaped this workout on the fly. The stored routine hasn't changed yet — your call.")
                    }
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
                    // In-app cue (field report: "while looking at the
                    // app"): the haptic+chime fires from the timer itself,
                    // so a denied notification permission can't silence
                    // the moment that matters.
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    AudioServicesPlaySystemSound(1007)
                    self.captureRestDrop()
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

    /// Drop-ladder presentation context (set structures phase B): armed
    /// when the TOP set of a drop-prescribed exercise logs.
    struct DropLadderContext: Identifiable {
        let setLogID: UUID
        let topWeightPounds: Decimal
        let steps: Int
        let percent: Decimal
        var id: UUID { setLogID }
    }
    @State private var dropLadder: DropLadderContext?
    /// Rest deferred while the drop ladder runs — applied on sheet dismiss.
    @State private var pendingDropRestSeconds: Int?
    @State private var pendingDropRestIsTransit = false

    private var soloUnit: WeightUnit { sessionSettings?.weightUnit ?? .lbs }

    private var soloWeightStep: Decimal {
        Units.tunerStep(unit: soloUnit, equipment: currentExercise?.equipment)
    }

    /// Solo's watch session push (wearable pass): same payload shape the
    /// group flow sends, solo-shaped — always your turn, no rotation, no
    /// squad soundboard. Re-pushed on exercise change so the watch face
    /// tracks the session; an inactive push at the end returns it to idle.
    private func pushSoloWatchState(session: WorkoutSession?, active: Bool) {
        guard let session else { return }
        // Field #2: solo never activated the bridge - the push landed in
        // an inactive WCSession. Idempotent; launch also activates.
        WatchConnectivityBridge.shared.activateIfNeeded()
        let payload = WatchSessionStatePayload(
            sessionID: session.id,
            groupID: nil,
            sessionName: routine?.name ?? "Workout",
            currentExerciseName: currentExercise?.name,
            currentExerciseID: currentExercise?.id,
            currentLifterName: nil,
            isMyTurn: true,
            burpeesOwed: 0,
            isActive: active,
            shareHeartRate: ThemeStore.shared.shareHeartRate,
            // Always sample: it is the athlete's own number on their own
            // screen. Whether it is BROADCAST is still shareHeartRate's
            // decision, made phone-side.
            sampleHeartRate: true,
            // The phone is the only side that can count sets. Without this
            // the bridge hardcoded setIndex: 1, so a session logged from
            // the wrist collapsed every set onto index 1 - and
            // BlockProgression.summarize SORTS by setIndex to find the last
            // set, dropping it when a to-failure finisher is prescribed. It
            // was dropping the wrong end of the session.
            nextSetIndex: (soloCurrentExerciseSets.map(\.setIndex).max() ?? 0) + 1,
            // Dropped on the wrist path, so pull-ups logged from the watch
            // contributed no tonnage while the identical set logged on the
            // phone did.
            bodyWeightLbs: currentExercise?.equipment == "bodyweight"
                ? soloLatestBodyWeightLbs : nil)
        WatchConnectivityBridge.shared.updateSessionState(payload)
    }

    /// Live HR source ladder (wearable pass 2026-08-21): a connected BLE
    /// strap first, then a FRESH watch sample relayed through the bridge
    /// (recaps proved the data arrives; the widget just never read it).
    /// 15s freshness — a stale watch number is worse than the dash.
    private var soloBLEBPM: Int? {
        if case .connected = BLEHeartRateService.shared.state,
           let bpm = BLEHeartRateService.shared.latestBPM {
            return bpm
        }
        if let bpm = WatchConnectivityBridge.shared.latestWatchBPM,
           let at = WatchConnectivityBridge.shared.latestWatchBPMAt,
           Date().timeIntervalSince(at) < 15 {
            return bpm
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
        .sheet(isPresented: $showSwapSheet) {
            swapSheet
                .onDisappear { swapOptions = [] }
        }
        .sheet(isPresented: $showSessionEditor) {
            if let routineID = routine?.id ?? routineExercises.first?.routineID {
                SessionRoutineEditor(
                    exercises: soloEditedList ?? routineExercises,
                    nameByID: Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) }),
                    routineID: routineID,
                    onDone: { edited in
                        soloEditedList = edited
                        // The cursor may now point past the list or at a
                        // moved row - clamp and re-prefill.
                        currentExerciseIndex = min(currentExerciseIndex,
                                                   max(0, edited.count - 1))
                        soloPrefill()
                    })
            }
        }
        .sheet(isPresented: $soloShowHRPairing) {
            NavigationStack { HeartRateMonitorView() }
        }
        .fullScreenCover(isPresented: $showFormClipCapture) {
            FormClipCapture { url in
                showFormClipCapture = false
                guard let url else { return }
                if canRetainClips == true {
                    // Attaches to the next logged set - the natural flow
                    // is film the set, then log it.
                    pendingClipURL = url
                } else {
                    // No retention (owner ruling): immediate review, then
                    // the file dies with the sheet. Never uploaded. An
                    // unresolved gate lands here too - not-retained is the
                    // only safe unknown.
                    reviewClip = ReviewClip(url: url)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $reviewClip) { clip in
            FormClipReviewSheet(url: clip.url) {
                try? FileManager.default.removeItem(at: clip.url)
                reviewClip = nil
            }
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
            // Strain asymmetry (owner 2026-08-25): up-scaling always;
            // down-scaling only when the low-rep set wasn't a grind —
            // SetProgression.rescaledBase carries the full rule.
            let targetReps = currentRoutineExercise?.targetReps.flatMap { leadingInt($0) }
            let base = SetProgression.rescaledBase(lastPounds: w,
                                                   lastReps: last.reps,
                                                   lastRPE: last.rpe,
                                                   targetReps: targetReps)
            let next = SetProgression.nextWeight(afterPounds: base, rpe: last.rpe, isFailed: last.isFailed,
                                                 isLowerBody: currentExercise?.isLowerBody ?? false,
                                                 unit: soloUnit)
            soloWeight = Units.format(pounds: snapToGrid(next), unit: soloUnit,
                                      rounded: false, includeUnit: false)
        } else if let re = currentRoutineExercise,
                  let suggestion = WorkingWeight.suggest(
                      exerciseID: re.exerciseID,
                      targetReps: re.targetReps.flatMap { leadingInt($0) },
                      routineTargetPounds: re.targetWeight.flatMap { Decimal(string: $0) },
                      history: soloPriorSets + soloCurrentExerciseSets,
                      lastSetPounds: (soloPriorSets + soloCurrentExerciseSets)
                          .filter { !$0.isFailed }
                          .max(by: { $0.loggedAt < $1.loggedAt })?.weight,
                      enrollment: soloEnrollment,
                      // Getting-started anchor (owner 2026-08-12): fires
                      // only when every real-data rung above came up empty.
                      seededPounds: LiftAnchorMath.seedPounds(
                          for: currentExercise?.slug ?? "",
                          anchors: sessionSettings?.liftAnchors)) {
            soloWeight = Units.format(pounds: snapToGrid(suggestion.pounds), unit: soloUnit,
                                      rounded: false, includeUnit: false)
        } else {
            soloWeight = ""
        }
        // Explain an empty field when the reason is a layoff. Only when it
        // is ACTUALLY empty — a returner whose post-return sets already
        // support a projection gets a number and needs no note.
        soloReturnNote = (soloWeight.isEmpty
                          && TrainingHorizon.isReturning(soloPriorSets + soloCurrentExerciseSets))
            ? TrainingHorizon.emptyBarNote : nil
        soloReps = currentRoutineExercise?.targetReps.flatMap { leadingInt($0).map(String.init) } ?? ""
        // Carry diagnostics (field 2026-08-22): one Console filter
        // ("prefill rung") names which rung produced the number and what
        // it had to work with. Removable once the report is confirmed
        // fixed.
        let rung = barLoaderPounds != nil ? "bar"
            : !soloCurrentExerciseSets.isEmpty ? "carry"
            : soloWeight.isEmpty ? "empty" : "ladder"
        AppLogger.workout.info("prefill rung=\(rung, privacy: .public) weight=\(self.soloWeight, privacy: .public) cur=\(self.soloCurrentExerciseSets.count) prior=\(self.soloPriorSets.count) sess=\(self.session?.id.uuidString.prefix(8) ?? "nil", privacy: .public)")
        // BlockProgression (owner 2026-08-20): at the START of an exercise —
        // nothing logged for it this session — the block engine's decision
        // shapes the prefill. Advances apply directly (load step on a topped
        // range outranks the history ladder above, since it IS that history's
        // conclusion); a deload or stall never touches numbers here, it only
        // renders in the entry card for the athlete to act on.
        soloCoachDecision = nil
        soloCoachNoteExpanded = false
        if soloRoutineIsCoachProgram,
           soloCurrentExerciseSets.isEmpty,
           let re = currentRoutineExercise,
           let low = re.targetRepsLow, let high = re.targetRepsHigh {
            let decision = BlockProgression.decide(
                history: soloPriorSets,
                repsLow: low, repsHigh: high,
                isLowerBody: currentExercise?.isLowerBody ?? false,
                // Catalog carries no isolation flag yet; false is safe — the
                // percent step floors to one increment at isolation loads.
                isIsolation: false,
                lastSetToFailure: re.targetFailure,
                unit: soloUnit)
            soloCoachDecision = decision
            switch decision {
            case .advanceLoad(let pounds, _):
                soloWeight = Units.format(pounds: snapToGrid(pounds), unit: soloUnit,
                                          rounded: false, includeUnit: false)
                soloReps = String(low)   // load up, reps reset to the floor
            case .advanceReps(let target, _):
                soloReps = String(target)
            case .proposeDeload, .flagStall, .warnFatigue, .hold:
                break
            }
        }
        soloRPE = 7.0
        soloFailed = false
    }

    /// Hot-swap options: substitution-graph edges first (provenance-
    /// graded), then same-muscle/pattern neighbors as the fallback — the
    /// graph is the coach's answer; the neighbors are the gym's reality.
    private struct SwapOption: Identifiable {
        let id: UUID
        let name: String
        let detail: String
    }

    @State private var swapOptions: [SwapOption] = []

    private func loadSwapOptions() async {
        guard let current = currentExercise else { return }
        var options: [SwapOption] = []
        var seen: Set<UUID> = [current.id]
        if let edges = try? await ExerciseSubstitutionRepository.forExercise(slug: current.slug) {
            for edge in edges {
                guard let match = allExercises.first(where: { $0.slug == edge.toSlug }),
                      match.aliasOf == nil, !seen.contains(match.id) else { continue }
                seen.insert(match.id)
                options.append(SwapOption(id: match.id, name: match.name,
                                          detail: edge.reason))
            }
        }
        for ex in allExercises where ex.aliasOf == nil
            && ex.primaryMuscle == current.primaryMuscle
            && ex.movementPattern == current.movementPattern
            && !seen.contains(ex.id) {
            seen.insert(ex.id)
            options.append(SwapOption(id: ex.id, name: ex.name,
                                      detail: "Same muscle, same pattern"))
            if options.count >= 10 { break }
        }
        swapOptions = options
    }

    private func applySwap(_ option: SwapOption) {
        guard let re = currentRoutineExercise else { return }
        var swapped = re
        swapped = RoutineExercise(
            id: re.id, routineID: re.routineID, exerciseID: option.id,
            position: re.position, targetSets: re.targetSets,
            targetReps: re.targetReps, targetWeight: nil,
            restSeconds: re.restSeconds, notes: re.notes,
            supersetGroup: re.supersetGroup,
            targetRepsLow: re.targetRepsLow, targetRepsHigh: re.targetRepsHigh,
            cardioZone: re.cardioZone, cardioMinutes: re.cardioMinutes)
        soloSwapOverrides[re.id] = swapped
        showSwapSheet = false
        soloPrefill()
    }

    private var swapSheet: some View {
        NavigationStack {
            List {
                if swapOptions.isEmpty {
                    Text("Looking for swaps…")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                }
                ForEach(swapOptions) { option in
                    Button { applySwap(option) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.name)
                                .font(GSFont.bold(15, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Text(option.detail)
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Swap \(currentExercise?.name ?? "exercise")")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadSwapOptions() }
        }
    }

    /// The engine's note for the current decision — every case explains
    /// itself except a data-starved hold.
    private func coachNote(for decision: BlockProgression.Decision) -> BlockProgression.CoachNote? {
        switch decision {
        case .advanceLoad(_, let note), .advanceReps(_, let note),
             .proposeDeload(_, let note), .flagStall(let note),
             .warnFatigue(let note):
            return note
        case .hold(let note):
            return note
        }
    }

    private var soloCoachDeloadPounds: Decimal? {
        if case .proposeDeload(let pounds, _) = soloCoachDecision { return pounds }
        return nil
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
            onReady: { soloWarmupEndsAt = nil; setStartedAt = .now },
            onAdjustMinutes: { delta in adjustSoloWarmup(delta) },
            // Owner 2026-08-22: the warm-up window doubles as the
            // mobility slot - the day's muscles pick the circuit.
            mobilityCircuit: WarmupMobility.circuit(for: soloSessionMuscles),
            onTapMove: { move in Task { await openMobilityDetail(move) } }
        )
        .sheet(item: $mobilityDetail) { ex in
            NavigationStack {
                ExerciseDetailView(exercise: ex)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { mobilityDetail = nil }
                        }
                    }
            }
        }
    }

    /// Resolve a circuit move against the full catalog (fetched once,
    /// lazily) and open its exercise page - video and description like
    /// everything else. No match = quiet no-op.
    @MainActor
    private func openMobilityDetail(_ move: WarmupMobility.Move) async {
        guard !move.catalogQuery.isEmpty else { return }
        if mobilityCatalog.isEmpty {
            mobilityCatalog = (try? await ExerciseRepository.fetchAll()) ?? []
        }
        let q = move.catalogQuery.lowercased()
        mobilityDetail = mobilityCatalog.first {
            $0.aliasOf == nil && $0.name.lowercased().contains(q)
        }
    }

    /// Lowercased primary muscles of the day's work - the mobility
    /// circuit's selector.
    private var soloSessionMuscles: [String] {
        let ids = Set(routineExercises.map(\.exerciseID))
        return allExercises.filter { ids.contains($0.id) }
            .map { $0.primaryMuscle.lowercased() }
    }

    /// Whether the day's routine already carries mobility work - if it
    /// does, the routine IS the mobility slot and the warm-up stays at
    /// its configured length.
    private var soloRoutineHasMobility: Bool {
        let ids = Set(routineExercises.map(\.exerciseID))
        return allExercises.contains { ids.contains($0.id) && $0.category == "mobility" }
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
        // Field report #23: the stats line sat flush on the swipe-up
        // region and its text rode the border - give it clear air.
        Color.clear.frame(height: 14)
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
                    } else if !soloRestSetPairs.isEmpty {
                        // Owner item 4: no strap — set pace is the honest
                        // recovery proxy (how long each set took, last one
                        // emphasized).
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paceText(soloRestSetPairs.last?.set ?? 0))
                                .font(GSFont.boldFixed(30).monospacedDigit())
                                .foregroundStyle(theme.text)
                            Text("LAST SET")
                                .font(GSFont.bold(9, relativeTo: .caption2))
                                .tracking(1.2)
                                .foregroundStyle(theme.neutral700)
                        }
                        Spacer()
                        soloStackedHistogram
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

    /// Set-pace bars (owner item 4) — one capsule per completed set,
    /// normalized against the session's own min/max duration, latest
    /// emphasized. Same bar language as the HR sparkline beside it.
    /// (rest-before, set-duration) per non-penalty logged set, oldest
    /// first — the stacked histogram's fuel (owner design 2026-08-21).
    /// Set duration reads the per-set start stamp; rest is the gap between
    /// the previous log and this set's start. First set has no rest bar.
    private var soloRestSetPairs: [(rest: Double, set: Double)] {
        let logs = loggedSets.filter { !$0.isPenalty }
            .sorted { $0.loggedAt < $1.loggedAt }
        var pairs: [(Double, Double)] = []
        var previousEnd: Date?
        for log in logs {
            let start = soloSetStarts[log.id] ?? previousEnd ?? log.loggedAt
            let setDuration = max(0, log.loggedAt.timeIntervalSince(start))
            let rest = previousEnd.map { max(0, start.timeIntervalSince($0)) } ?? 0
            pairs.append((rest, min(setDuration, 600)))
            previousEnd = log.loggedAt
        }
        return pairs
    }

    /// The owner's stacked histogram: per set, REST on the bottom
    /// (neutral) and SET DURATION on top (accent) — recovery and work as
    /// one picture, no strap required.
    private var soloStackedHistogram: some View {
        let pairs = Array(soloRestSetPairs.suffix(10))
        let maxTotal = max(pairs.map { $0.rest + $0.set }.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.accent)
                        .frame(width: 7, height: max(2, 34 * pair.set / maxTotal))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.neutral500.opacity(0.55))
                        .frame(width: 7, height: max(pair.rest > 0 ? 2 : 0,
                                                     34 * pair.rest / maxTotal))
                }
            }
        }
        .frame(height: 38, alignment: .bottom)
        .accessibilityLabel("Set and rest durations, most recent sets")
    }

    private var soloSetPaceSparkline: some View {
        let ds = Array(soloSetDurations.suffix(12))
        let hi = ds.max() ?? 1
        let lo = ds.min() ?? 0
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(ds.enumerated()), id: \.offset) { pair in
                let norm = hi == lo ? 0.5 : (pair.element - lo) / (hi - lo)
                Capsule()
                    .fill(theme.text.opacity(pair.offset == ds.count - 1 ? 0.9 : 0.45))
                    .frame(width: 4, height: max(4, CGFloat(norm) * 40))
            }
        }
        .frame(height: 42, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// "1:23" — a set duration in m:ss.
    private func paceText(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Live HR as an accent line over the 90s window (field #34).
    @ViewBuilder
    private var soloRecoverySparkline: some View {
        // Field #34: the faint bars read as invisible — live HR draws as
        // a real accent LINE over the 90s window, endpoint emphasized.
        let samples = soloRecoveryBuffer.samples
        if samples.count >= 2 {
            let bpms = samples.map(\.bpm)
            let lo = bpms.min() ?? 0
            let span = max(1, (bpms.max() ?? 1) - lo)
            Canvas { ctx, size in
                var path = Path()
                for (i, sample) in samples.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(samples.count - 1)
                    let y = size.height - size.height * CGFloat(sample.bpm - lo) / CGFloat(span)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(theme.accent),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = samples.last {
                    let y = size.height - size.height * CGFloat(last.bpm - lo) / CGFloat(span)
                    ctx.fill(Path(ellipseIn: CGRect(x: size.width - 3, y: y - 3, width: 6, height: 6)),
                             with: .color(theme.accent))
                }
            }
            .frame(width: 96, height: 42)
            .accessibilityHidden(true)
        }
    }

    /// End-of-rest recovery capture (owner 2026-08-12): the drop achieved
    /// by the time a rest window closes — RecoveryBuffer's 90s window still
    /// spans set-peak → rest-trough at that moment. Called immediately
    /// BEFORE every `restEndAt = nil` (lapse task, START SET, both log
    /// paths); a no-op outside a rest window or without HR samples.
    private func captureRestDrop() {
        guard restEndAt != nil, let drop = soloRecoveryBuffer.drop, drop > 0 else { return }
        soloRestDrops.append(drop)
    }

    /// The GO EARLY / +30s suggestion pill. Actions follow the house rules:
    /// GO EARLY is the accent action (starting the set IS the primary
    /// action, same stamp as the START SET shortcut); +30s is a quiet
    /// raised-face button. Default-colored labels per the room's text law.
    @ViewBuilder
    private func restRecoveryPill(now: Date, start: Date, end: Date) -> some View {
        let total = end.timeIntervalSince(start)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(start) / total)) : 0
        let verdict = RestRecoveryMath.verdict(
            currentDrop: soloRecoveryBuffer.drop,
            baseline: RestRecoveryMath.baseline(priorDrops: soloRestDrops),
            progress: progress)
        switch verdict {
        case .ready:
            Button {
                captureRestDrop()
                restEndAt = nil
                setStartedAt = .now
            } label: {
                Text("RECOVERED — GO EARLY")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(0.8)
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 10, lipHeight: 4))
            .padding(.top, 10)
            .accessibilityHint("Heart-rate recovery hit your session's usual mark early.")
        case .lagging:
            Button {
                restEndAt = end.addingTimeInterval(30)
            } label: {
                Text("SLOW RECOVERY — +30s")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(0.8)
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 10, lipHeight: 4))
            .padding(.top, 10)
            .accessibilityHint("Heart-rate recovery is behind your session's usual mark.")
        case nil:
            EmptyView()
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
            // Recovery-adaptive pills (owner 2026-08-12) — suggestions only,
            // judged against THIS session's own median end-of-rest drop.
            // Silent without an HR source or a 2-rest baseline; the 5s
            // periodic tick is the verdict's clock (the countdown Text
            // renders itself and needs no external ticks).
            if let restEndAt, let restStart = soloRestStartedAt {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    restRecoveryPill(now: context.date, start: restStart, end: restEndAt)
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 7) {
                Text("UP NEXT")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral700)
                // Owner 2026-08-13: tappable during rest too — same
                // extruded chip → exercise page as the live set card.
                if let ex = currentExercise {
                    Button {
                        exerciseDetailSheet = ex
                    } label: {
                        HStack(spacing: 6) {
                            Text(ex.name)
                                .font(GSFont.bold(20, relativeTo: .title3))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 10, lipHeight: 3))
                } else {
                    Text("—")
                        .font(GSFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                // Field 2026-08-24: "can't load weight on a machine
                // during rest" — the readback gains the entry card's
                // − / + steps so the station gets set to the RIGHT number
                // while resting, not after. Writes the same soloWeight
                // the entry card is prefilled with.
                HStack(spacing: 10) {
                    Button { soloStepWeight(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.text)
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 8, lipHeight: 3))
                    Text(soloUpNextReadback)
                        .font(GSFont.bold(13, relativeTo: .footnote).monospacedDigit())
                        .tracking(0.5)
                        .foregroundStyle(theme.text.opacity(0.78))
                    Button { soloStepWeight(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.text)
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 8, lipHeight: 3))
                }
                // Owner 2026-08-13: "can't see routine during rest" — the
                // ROUTINE pager lives on the exercise card the rest page
                // replaces, so the rest page gets its own door to the same
                // list (sheet reuses soloRoutinePage verbatim).
                Button {
                    showRestRoutineSheet = true
                } label: {
                    Text("VIEW ROUTINE")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.text.opacity(0.78))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                }
                .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                   cornerRadius: 10, lipHeight: 5))
                .padding(.top, 4)
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
            // EZ-bar lifts load against the lighter bar (field report
            // 2026-08-21) — the setting when loaded, the standard 15 lb
            // otherwise.
            let barLbs = currentExercise?.equipment == "ez-bar"
                ? (sessionSettings?.ezBarWeightLbs ?? 15)
                : (sessionSettings?.barWeightLbs ?? ThemeStore.shared.barWeightLbs)
            var value = Units.fromPounds(barLbs, to: unit)
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
                .filter({ !$0.isFailed && !$0.isPenalty && $0.sessionID != session?.id })
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
                // Owner 2026-08-12: the name is an extruded button — tap
                // opens the exercise page (video + history) as a sheet.
                // (Round-1 wiring landed on exerciseHeaderCard, which only
                // the freeform scroll body renders — THIS is the routine
                // fixed page's card.)
                if let ex = currentExercise {
                    Button {
                        exerciseDetailSheet = ex
                    } label: {
                        HStack(spacing: 6) {
                            Text(ex.name)
                                .font(GSFont.bold(20, relativeTo: .title3))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                                       cornerRadius: 10, lipHeight: 3))
                } else {
                    Text("Exercise")
                        .font(GSFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
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
                if remaining == 0 {
                    // Owner 2026-08-13: the last set is a moment, not a
                    // zero — "0 SETS LEFT" read like a bug.
                    Text("LAST SET")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                    Text("GO TO FAILURE!")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                        .multilineTextAlignment(.center)
                } else {
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
                Text("RPE \((rpe).displayInt)")
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
    /// The rep-target column label. Set structures (20260814000003): on
    /// the FINAL prescribed set, a burnout shows MAX and a to-failure
    /// prescription shows TO FAILURE — the number disappears because the
    /// number isn't the assignment anymore.
    private var repTargetLabel: String {
        guard let re = currentRoutineExercise else { return "REPS" }
        // Cardio prescriptions (generator): zone + MINUTES, not reps.
        if let zone = re.cardioZone, let minutes = re.cardioMinutes {
            return "ZONE \(zone) · \(minutes) MIN"
        }
        let isFinalSet = currentSetIndex >= (re.targetSets ?? 1)
        if re.setType == "drop" {
            // Owner 2026-08-14 (corrected): a drop prescription fires on
            // EVERY set — each set is a top bell plus its ladder.
            let pct = (re.dropPercent ?? 20).displayInt
            return "REPS · TOP + DROP \(re.dropSteps ?? 2)×\(pct)%"
        }
        if isFinalSet, re.setType == "burnout" { return "REPS · MAX" }
        if isFinalSet, re.targetFailure { return "REPS · TO FAILURE" }
        return re.targetReps.map { "REPS · \($0)" } ?? "REPS"
    }

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
                Button {
                    showSwapSheet = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap this exercise")
                Button {
                    showSessionEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(soloEditedList == nil ? theme.neutral500 : theme.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit this session's routine")
                Button {
                    if canRetainClips == nil {
                        Task {
                            let coached = await SetLogClipRepository.hasActiveCoach()
                            canRetainClips = Entitlements.hasPro || coached
                        }
                    }
                    showFormClipCapture = true
                } label: {
                    Image(systemName: pendingClipURL == nil ? "video" : "video.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pendingClipURL == nil ? theme.neutral500 : theme.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record form clip")
            }
            .frame(height: 30)

            // Return note. Above the coach note and ungated — see
            // soloReturnNote.
            if let returnNote = soloReturnNote {
                Color.clear.frame(height: 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(returnNote)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Coach note (owner 2026-08-20: "compact note + reason"). One
            // line, expandable why; a deload proposal adds accept/dismiss
            // and changes NOTHING until accepted.
            if let decision = soloCoachDecision, let note = coachNote(for: decision) {
                Color.clear.frame(height: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Button { soloCoachNoteExpanded.toggle() } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text("COACH · \(note.summary.uppercased())")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .tracking(0.6)
                                .foregroundStyle(theme.text.opacity(0.82))
                                .lineLimit(soloCoachNoteExpanded ? 3 : 1)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: soloCoachNoteExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .buttonStyle(.plain)
                    if soloCoachNoteExpanded {
                        Text(note.reason)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                        if let swapName = soloStallSwapName {
                            Text("SWAP OPTION · \(swapName.uppercased())")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .tracking(0.6)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    if let deloadPounds = soloCoachDeloadPounds {
                        HStack(spacing: 10) {
                            Button {
                                soloWeight = Units.format(pounds: deloadPounds, unit: soloUnit,
                                                          rounded: false, includeUnit: false)
                                if let low = currentRoutineExercise?.targetRepsLow {
                                    soloReps = String(low)
                                }
                                soloCoachDecision = nil   // proposal consumed
                            } label: {
                                Text("DELOAD")
                                    .font(GSFont.bold(12, relativeTo: .caption))
                                    .tracking(0.8)
                                    .foregroundStyle(theme.bg)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(theme.accent))
                            }
                            .buttonStyle(.plain)
                            Button { soloCoachDecision = nil } label: {
                                Text("NOT TODAY")
                                    .font(GSFont.bold(12, relativeTo: .caption))
                                    .tracking(0.8)
                                    .foregroundStyle(theme.neutral700)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().stroke(theme.neutral500, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Color.clear.frame(height: 12)
            HStack(spacing: 0) {
                Text("WEIGHT · \(soloUnit.label.uppercased())")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .frame(width: 229, alignment: .leading)
                Text(repTargetLabel)
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        weightEntryText = soloWeight
                        showWeightEntry = true
                    }
                    .alert("Enter weight (\(soloUnit.label))", isPresented: $showWeightEntry) {
                        TextField("Weight", text: $weightEntryText)
                            .keyboardType(.decimalPad)
                        Button("Set") {
                            if let value = Decimal.parseUserInput(weightEntryText), value > 0 {
                                soloWeight = "\(value)"
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
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

    /// Suggestions land on the equipment's honest loading grid (owner
    /// field report 2026-08-21: machines and stacks have no bar — a
    /// suggestion ending in 5 can't be loaded there).
    /// The alias FAMILY for an exercise: itself, its canonical, and every
    /// duplicate aliasing the same canonical (catalog dedup 20260821) —
    /// so history split across duplicate names reads as one lift.
    private func aliasFamilyIDs(for id: UUID) -> [UUID] {
        let canonical = allExercises.first(where: { $0.id == id })?.aliasOf ?? id
        var ids: Set<UUID> = [id, canonical]
        for ex in allExercises where ex.aliasOf == canonical {
            ids.insert(ex.id)
        }
        return Array(ids)
    }

    private func snapToGrid(_ pounds: Decimal) -> Decimal {
        let step = Units.loadIncrement(forEquipment: currentExercise?.equipment,
                                       unit: soloUnit)
        let unitValue = Units.fromPounds(pounds, to: soloUnit)
        return Units.toPounds(Units.roundToIncrement(unitValue, step: step),
                              from: soloUnit)
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
            parts.append("RPE \((rpe).displayInt)")
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
                    captureRestDrop()
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
                soloEndedSetStart = setStartedAt
                setStartedAt = .now
                captureRestDrop()
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
                        captureRestDrop()
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
        // Clean sets only: history now ARRIVES with failed rows (doctrine
        // 2026-08-13) — this display card keeps its pre-doctrine content
        // (a "225×7" whose 7th missed would misread as seven completed).
        let prior = logs.filter { $0.sessionID != sessionID && !$0.isFailed }
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
            // Owner field report 2026-08-21: cues fired for nobody who
            // declined the PUSH priming — local notifications need their
            // own authorization, requested lazily at first rest so the
            // prompt lands in context ("may I tell you when rest is
            // over?"), not at onboarding.
            let center = UNUserNotificationCenter.current()
            Task {
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound])
                }
                let content = UNMutableNotificationContent()
                content.title = "Rest over"
                content.body = "Up next: set \(setNumber) — \(exerciseName)"
                content.sound = .default
                // Field #35: a Focus mode swallows .active delivery -
                // a rest cue mid-workout is the textbook time-sensitive
                // case (entitlement in project.yml).
                content.interruptionLevel = .timeSensitive
                let seconds = max(1, date.timeIntervalSinceNow)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
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
        var barConverted = Units.fromPounds(sessionSettings?.barWeight(forEquipment: currentExercise?.equipment) ?? 45, to: unit)
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
            Button {
                exerciseDetailSheet = ex
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ex.name)
                        .font(GSFont.heading(28, relativeTo: .title))
                        .foregroundStyle(theme.bg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.bg.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

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

    // MARK: Coach debrief assembly (2026-08-21)
    //
    // The deterministic payload both tiers share — built from what this
    // view already holds: prescriptions (routineExercises), the session's
    // logs, and the PRs the celebration already computed (reused, never
    // re-derived).
    private var coachDebrief: WorkoutDebrief? {
        guard completed, !routineExercises.isEmpty else { return nil }
        let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        let logsByExercise = Dictionary(grouping: loggedSets.filter { !$0.isPenalty },
                                        by: \.exerciseID)
        let reports = routineExercises
            .filter { $0.cardioZone == nil }
            .map { re in
                DebriefBuilder.ExerciseReport(
                    name: nameByID[re.exerciseID] ?? "Exercise",
                    prescribedSets: re.targetSets ?? 3,
                    repsLow: re.targetRepsLow,
                    repsHigh: re.targetRepsHigh,
                    sets: (logsByExercise[re.exerciseID] ?? [])
                        .sorted { $0.setIndex < $1.setIndex },
                    // Owner ruling (field #38): custom routines get their
                    // progression counsel HERE, at the end, as a blurb -
                    // never as a mid-session prefill. Coach programs got
                    // theirs live, so nil avoids double-speaking.
                    decision: soloRoutineIsCoachProgram ? nil
                        : endOfSessionDecision(for: re))
            }
        var context = DebriefBuilder.Context()
        context.profile = coachProfile
        context.personalRecords = sessionPRs.map { pr in
            let name = nameByID[pr.exerciseID] ?? "Lift"
            let weight = Units.format(pounds: pr.weight,
                                      unit: sessionSettings?.weightUnit ?? .lbs,
                                      rounded: false, includeUnit: true)
            return "\(name) \(weight)×\(pr.reps) — new best"
        }
        if let session = completedSession, let end = session.completedAt,
           let start = session.startedAt {
            context.sessionMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        }
        context.pendingProbe = coachPendingProbe
        return DebriefBuilder.build(reports: reports, context: context)
    }

    /// The end-of-workout three-way's write half (spec 2026-08-22 §2):
    /// update-in-place rewrites the stored rows; save-as-new clones the
    /// routine with fresh ids. Best effort - a failed write leaves the
    /// stored routine exactly as it was.
    @MainActor
    private func persistSessionEdits(asNew: Bool) async {
        guard let edited = soloEditedList, let routine else { return }
        if asNew {
            let newRoutineID = UUID()
            let clone = Routine(
                id: newRoutineID, ownerID: routine.ownerID,
                name: "\(routine.name) (edited)",
                description: routine.description,
                visibility: "private",
                createdAt: Date(), updatedAt: Date())
            let rows = edited.enumerated().map { index, re in
                RoutineExercise(
                    id: UUID(), routineID: newRoutineID, exerciseID: re.exerciseID,
                    position: index + 1, targetSets: re.targetSets,
                    targetReps: re.targetReps, targetWeight: re.targetWeight,
                    restSeconds: re.restSeconds, notes: re.notes,
                    supersetGroup: re.supersetGroup,
                    targetRepsLow: re.targetRepsLow, targetRepsHigh: re.targetRepsHigh,
                    cardioZone: re.cardioZone, cardioMinutes: re.cardioMinutes)
            }
            try? await RoutineRepository.save(clone, exercises: rows)
        } else {
            let rows = edited.enumerated().map { index, re in
                var r = re
                r.position = index + 1
                return r
            }
            try? await RoutineRepository.save(routine, exercises: rows)
        }
    }

    /// The Apply card's writer (owner 2026-08-22: "want me to edit your
    /// routine to reflect this?" - and then it actually does). Fuzzy
    /// name match, display-unit -> pounds conversion, full-list save.
    /// Trainer prescriptions are never edited - a human wrote those.
    @MainActor
    private func applyCoachRoutineEdit(_ proposal: RoutineEditProposal) async -> String? {
        guard let routine, routine.prescribedBy == nil else { return nil }
        let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name.lowercased()) })
        let target = proposal.exerciseName.lowercased()
        guard let index = routineExercises.firstIndex(where: { re in
            guard let name = nameByID[re.exerciseID] else { return false }
            return name == target || name.contains(target) || target.contains(name)
        }) else { return nil }
        var rows = routineExercises
        var summary: [String] = []
        if let weight = proposal.weight {
            let pounds = Units.toPounds(Decimal(weight), from: sessionSettings?.weightUnit ?? .lbs)
            rows[index].targetWeight = "\(pounds)"
            summary.append(Units.format(pounds: pounds,
                                        unit: sessionSettings?.weightUnit ?? .lbs,
                                        rounded: false, includeUnit: true))
        }
        if let lo = proposal.repsLow {
            rows[index].targetRepsLow = lo
            rows[index].targetRepsHigh = proposal.repsHigh ?? max(lo, rows[index].targetRepsHigh ?? lo)
            rows[index].targetReps = "\(lo)"
            summary.append("\(lo)–\(rows[index].targetRepsHigh ?? lo) reps")
        } else if let hi = proposal.repsHigh {
            rows[index].targetRepsHigh = hi
            summary.append("up to \(hi) reps")
        }
        guard !summary.isEmpty else { return nil }
        do {
            try await RoutineRepository.save(routine, exercises: rows)
        } catch { return nil }
        // routineExercises is an immutable init param - the session-local
        // overlay (the mid-session editor's own channel) carries the
        // update for the rest of this view's lifetime.
        soloEditedList = rows
        let name = allExercises.first(where: { $0.id == rows[index].exerciseID })?.name
            ?? proposal.exerciseName
        return "Done — \(name) is now \(summary.joined(separator: " × ")). It'll load that way next session."
    }

    /// The suppressed-mid-session counsel for a CUSTOM routine, computed
    /// at recap time from the prefetched history (field #38).
    private func endOfSessionDecision(for re: RoutineExercise) -> BlockProgression.Decision? {
        guard let low = re.targetRepsLow, let high = re.targetRepsHigh,
              let name = allExercises.first(where: { $0.id == re.exerciseID })?.name,
              let history = recapTrendHistory[name.lowercased()], !history.isEmpty
        else { return nil }
        return BlockProgression.decide(
            history: history,
            repsLow: low, repsHigh: high,
            isLowerBody: allExercises.first(where: { $0.id == re.exerciseID })?.isLowerBody ?? false,
            isIsolation: false,
            lastSetToFailure: re.targetFailure,
            unit: soloUnit)
    }

    /// Best-effort context for the recap: the athlete's profile (headline
    /// register + persona voice) and per-lift history so the trend tool
    /// narrates real computed trends. Fires once when the session
    /// completes; failures degrade to defaults, never block the recap.
    private func prefetchCoachContext() async {
        guard completed else { return }
        if let profile = try? await TrainingProfileRepository.load() {
            coachProfile = profile
        }
        guard let userID = appState.currentProfile?.id else { return }
        let nameByID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        for re in routineExercises.prefix(10) where re.cardioZone == nil {
            guard let name = nameByID[re.exerciseID] else { continue }
            if let history = try? await SessionRepository.exerciseHistory(
                userID: userID, exerciseID: re.exerciseID, limit: 60) {
                recapTrendHistory[name.lowercased()] = history
            }
        }
        // Drift detection (Phase 4): the logbook vs the stated profile.
        // A found signal becomes the debrief's pending question and
        // stamps the cooldown ledger, so Coach asks like a coach — once,
        // in conversation — never like a calendar.
        if let logs = try? await SessionRepository.recentSetLogs(
            userID: userID, since: Date(timeIntervalSinceNow: -28 * 86_400)) {
            let signals = DriftDetector.detect(profile: coachProfile,
                                               logs: logs,
                                               windowWeeks: 4,
                                               lastProbeDate: coachProfile.lastProbeAt)
            if let first = signals.first {
                coachPendingProbe = first
                coachProfile.lastProbeAt = .now
                try? await TrainingProfileRepository.save(coachProfile, userID: userID)
            }
        }
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
        if let resumeSession {
            // Re-entry after a sheet dismissal: adopt the running session and
            // rebuild local state from the durable record. Leaderboard-
            // attempt startup stays new-session-only; the WARM-UP window
            // is not (field #32: swiping down mid-warmup landed the
            // resume in logging) — recompute it from the durable
            // startedAt, and re-enter the phase when it's still open and
            // nothing has been logged yet.
            session = resumeSession
            await restoreLoggedProgress(sessionID: resumeSession.id)
            if !isFreeform, soloWarmupMinutes > 0, loggedSets.isEmpty {
                let ends = (resumeSession.startedAt ?? Date())
                    .addingTimeInterval(TimeInterval(soloWarmupMinutes * 60))
                if ends > .now { soloWarmupEndsAt = ends }
            }
            return
        }
        // Field regression 2026-08-22 ("weight not carrying forward"):
        // Start Workout became a dismissible SHEET in the third-load
        // build, so swipe-down + Start-again minted a BRAND-NEW session
        // - empty carry, fragmented history, the exact report. Any entry
        // point now ADOPTS the live session for the same routine; the
        // pill and this button converge on one session.
        if let live = appState.liveSoloSession,
           live.session.completedAt == nil,
           live.routine?.id == routine?.id {
            session = live.session
            await restoreLoggedProgress(sessionID: live.session.id)
            if !isFreeform, soloWarmupMinutes > 0, loggedSets.isEmpty {
                let ends = (live.session.startedAt ?? Date())
                    .addingTimeInterval(TimeInterval(soloWarmupMinutes * 60))
                if ends > .now { soloWarmupEndsAt = ends }
            }
            return
        }
        do {
            let newSession = try await SessionRepository.startSolo(routineID: routine?.id)
            session = newSession
            appState.liveSoloSession = AppState.LiveSoloSession(
                session: newSession, routine: routine,
                routineExercises: routineExercises, allExercises: allExercises)
            // Solo warm-up (2026-08): a configured duration opens the
            // warm-up page before the first set — the persisted DEFAULT of
            // 0 keeps existing solo behavior untouched. Routine sessions
            // only: freeform uses the scroll body, which has no fixed-page
            // slot for the phase.
            if !isFreeform, soloWarmupMinutes > 0 {
                // Owner 2026-08-22: no mobility in the routine and the
                // duration never configured -> the default warm-up grows
                // 5 -> 10 so the guided circuit actually fits. An
                // explicit choice is always respected.
                if !SoloWarmupStore.isConfigured, !soloRoutineHasMobility,
                   soloWarmupMinutes == 5 {
                    soloWarmupMinutes = 10
                }
                soloWarmupEndsAt = (newSession.startedAt ?? Date())
                    .addingTimeInterval(TimeInterval(soloWarmupMinutes * 60))
            }
            // Wearable pass (2026-08-21): SOLO sessions now reach the
            // watch. Without this push the bridge rejected every watch HR
            // sample with "No active session" and the watch app never
            // left idle — the owner's exact field report. A remembered
            // BLE strap also reconnects itself; no pairing sheet needed.
            BLEHeartRateService.shared.connectRememberedIfAny()
            pushSoloWatchState(session: newSession, active: true)
            // Recovery-accounting fix (field report: exercise one counted
            // from SCREEN OPEN): the set clock starts when the session
            // actually exists, and restarts again when the warm-up ends.
            setStartedAt = newSession.startedAt ?? .now
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

    /// Rebuild `loggedSets` + the exercise/set cursor from the session's
    /// durable `set_logs` record — the resume-mode half of `startIfNeeded()`.
    /// Best-effort on the fetch: an empty result just lands the lifter at
    /// the top of the routine, which is the honest floor.
    @MainActor
    private func restoreLoggedProgress(sessionID: UUID) async {
        let logs = (try? await SessionRepository.setLogs(sessionID: sessionID)) ?? []
        loggedSets = logs
        let workSets = logs.filter { !$0.isPenalty }
        if isFreeform {
            // The synthesized picks never persisted (only set_logs rows did) —
            // rebuild them from the log record: distinct exercises in
            // first-logged order, same synthesis as `addFreeformExercise`.
            var seen: [UUID] = []
            for log in workSets.sorted(by: { $0.loggedAt < $1.loggedAt })
            where !seen.contains(log.exerciseID) {
                seen.append(log.exerciseID)
            }
            freeformExercises = seen.enumerated().map { i, exID in
                RoutineExercise(id: UUID(), routineID: UUID(), exerciseID: exID,
                                position: i + 1, targetSets: nil, targetReps: nil,
                                targetWeight: nil, restSeconds: nil, notes: nil)
            }
            currentExerciseIndex = max(freeformExercises.count - 1, 0)
            currentSetIndex = workSets.filter { $0.exerciseID == seen.last }.count + 1
        } else {
            // Walk the plan in order, attributing logged sets to slots
            // greedily (handles the same exercise appearing twice); land on
            // the first slot still short of its target. A fully-logged
            // routine lands on the last slot, one past its target — the
            // lifter finishes from there.
            var remaining = workSets
            for (i, re) in activeExercises.enumerated() {
                let target = max(re.targetSets ?? 1, 1)
                var consumed = 0
                remaining.removeAll { log in
                    if consumed < target && log.exerciseID == re.exerciseID {
                        consumed += 1
                        return true
                    }
                    return false
                }
                currentExerciseIndex = i
                currentSetIndex = consumed + 1
                if consumed < target { break }
            }
        }
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
        // Owner item 7: the latest logged body weight (canonical lbs) —
        // stamped onto bodyweight-exercise sets at log time. Best-effort;
        // no log means bodyweight sets contribute no volume (honest zero).
        if let userID = appState.currentProfile?.id,
           let latest = try? await BodyWeightLogRepository.recent(userID: userID).first {
            soloLatestBodyWeightLbs = latest.weight
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
            note: note, loggedAt: Date(),
            // Owner item 7: bodyweight sets carry the load they actually
            // moved — the latest logged body weight, stamped at log time.
            bodyWeightLbs: currentExercise?.equipment == "bodyweight" ? soloLatestBodyWeightLbs : nil
        )
        do {
            // Prior max MUST be captured BEFORE the insert below — querying it after
            // logSet() would fold the just-inserted set's own weight into the max
            // (self-comparison), making `weight > priorBest` always false for a
            // genuine new max and silently suppressing the PR celebration. Mirrors
            // GroupSessionLiveView.logSetAndAdvance's identical ordering.
            var isPR = false
            var priorBest: Decimal = 0
            // Failure doctrine (owner 2026-08-13): failed sets are judged on
            // their COMPLETED reps ("7 + FAIL" = 6 completed at true RIR 0 —
            // a real achievement AND a calibration point). Only the failed
            // single carries nothing — `completedReps` encodes the rule.
            let completedReps = log.completedReps
            if let weight, weight > 0, let completedReps {
                // Phase O Task 3 (offline set logging, master spec §6.4): this is a
                // READ that requires connectivity. Without this catch, an offline
                // attempt throws HERE — before the actual set-log write below is ever
                // reached — meaning an offline lifter could never log a single
                // non-failed, weighted set (the common case). Only `.network` gets
                // this tolerant treatment; every other error (validation,
                // unauthorized, …) still aborts exactly as before.
                do {
                    // Rep-aware (owner 2026-08-02: "PRs should just be what
                    // you've accomplished"): judged against the best weight
                    // already done for AT LEAST this many reps, so a heavy
                    // single and a hard set of ten are separate achievements.
                    let basis = try await prBasis(exerciseID: re.exerciseID, userID: userID)
                    priorBest = PersonalRecordMath.bestWeight(atLeastReps: completedReps, in: basis)
                    isPR = PersonalRecordMath.isPR(weight: weight, reps: completedReps, basis: basis)
                } catch let error as GymSyncError {
                    guard case .network = error else { throw error }
                    // Offline — PR check skipped (best-effort, never blocks logging;
                    // mirrors the PersonalRecordRepository.record fallback below,
                    // which already tolerates a failed PR-record insert the same way).
                }
            }

            // Rep-PR for pure-bodyweight sets (owner item 6): no added
            // weight means the record IS the rep count. Judged locally
            // against this exercise's known unloaded sets (prior history +
            // this session) — stored as weight 0 with previousBest carrying
            // the prior REP count.
            var isRepPR = false
            var priorBestReps = 0
            if (weight ?? 0) == 0,
               currentExercise?.equipment == "bodyweight",
               let completedReps {
                priorBestReps = (soloPriorSets + soloCurrentExerciseSets)
                    .filter { $0.exerciseID == re.exerciseID && !$0.isPenalty && ($0.weight ?? 0) == 0 }
                    .compactMap(\.completedReps).max() ?? 0
                isRepPR = completedReps > priorBestReps
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
            // Stacked-histogram fuel (owner design 2026-08-21): stamp
            // when THIS set started so the recovery card can stack rest
            // (bottom) under set duration (top), per set.
            soloSetStarts[log.id] = soloEndedSetStart ?? setStartedAt
            soloEndedSetStart = nil
            loggedSets.append(log)
            // Form clip attach (video v1): the pending recording belongs
            // to the set just logged. Fire-and-forget - a failed upload
            // never blocks the set; the retention gate was checked before
            // the file was ever held.
            if let clipURL = pendingClipURL {
                pendingClipURL = nil
                let logID = log.id
                Task {
                    // Medium-preset re-encode first: about half the bytes
                    // at form-check quality (storage v1.5).
                    let uploadURL = await FormClipMath.compressed(clipURL)
                    defer { try? FileManager.default.removeItem(at: uploadURL) }
                    guard let userID = appState.currentProfile?.id,
                          let data = try? Data(contentsOf: uploadURL) else { return }
                    _ = try? await SetLogClipRepository.attach(
                        clipID: UUID(), setLogID: logID, userID: userID,
                        data: data, durationSeconds: FormClipMath.duration(of: uploadURL))
                }
            }
            // The set is durably recorded either way (server insert or offline
            // queue) — this is the moment the success haptic fires.
            logHapticTick += 1

            // Keep the prefetched basis exact without a refetch: the set we
            // just wrote is the only thing that can change it mid-session.
            // Without this, a second PR in the same session would report the
            // pre-session best as "your previous best" instead of the PR set
            // just before it.
            if let weight, weight > 0, let completedReps {
                prBasisByExercise[re.exerciseID, default: []].append((weight, completedReps))
            }

            if isRepPR, let completedReps {
                // Bodyweight rep record (owner item 6): weight 0 signals the
                // rep-PR form to the overlay and every display site;
                // previousBest carries the prior REP count (completed reps —
                // a failed 12th attempt celebrates the 11 that happened).
                showPROverlay(exerciseName: exerciseName(for: re.exerciseID), weight: 0,
                              reps: completedReps, priorBest: Decimal(priorBestReps))
                if let record = try? await PersonalRecordRepository.record(
                    exerciseID: re.exerciseID,
                    weight: 0,
                    reps: completedReps,
                    previousBest: Decimal(priorBestReps),
                    sessionID: session.id
                ) {
                    sessionPRs.append(record)
                } else {
                    sessionPRs.append(PersonalRecord(
                        id: UUID(), userID: userID, exerciseID: re.exerciseID,
                        weight: 0, reps: completedReps, previousBest: Decimal(priorBestReps),
                        sessionID: session.id, achievedAt: Date()
                    ))
                }
            }

            if isPR, let weight {
                let repsForOverlay = completedReps ?? 0
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
            // Set pace (owner item 4): stamp the completed set's duration —
            // clamped to a sane range so a backgrounded app can't record a
            // 40-minute "set".
            let setDuration = Date().timeIntervalSince(setStartedAt)
            if setDuration >= 5, setDuration <= 900 {
                soloSetDurations.append(setDuration)
            }
            if isFreeform {
                currentSetIndex += 1
                let restSeconds = defaultRestSeconds
                // Freeform never auto-advances exercises, so its windows
                // are always same-exercise rest — never TRANSIT.
                soloRestIsTransit = false
                if restSeconds > 0 {
                    soloRestStartedAt = Date()
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
                return true
            }

            let targetSets = re.targetSets ?? 1
            // Drop ladder (owner corrected 2026-08-14): EVERY set of a
            // drop-prescribed exercise is a top bell + its ladder — capture
            // before the advance mutates counters; the sheet arms after.
            let wasFinalDropSet = re.setType == "drop"
                && (weight ?? 0) > 0
            // Superset alternation (Phase B, owner design): an adjacent
            // pair runs A→B with NO rest, one shared rest after B, then
            // back to A for the next round; the pair exits together after
            // B's final set. Non-paired exercises are unchanged below.
            let partner = supersetPartnerIndex(of: currentExerciseIndex)
            let exerciseChanged: Bool
            var supersetHandoff = false
            if let partner, partner == currentExerciseIndex + 1 {
                // A side: hand the bar straight to B, same round.
                currentExerciseIndex = partner
                exerciseChanged = false   // same station cluster — no TRANSIT
                supersetHandoff = true
            } else if let partner, partner == currentExerciseIndex - 1,
                      currentSetIndex < targetSets {
                // B side, round complete: shared rest, back to A.
                currentSetIndex += 1
                currentExerciseIndex = partner
                exerciseChanged = false
            } else if currentSetIndex >= targetSets {
                currentSetIndex = 1
                currentExerciseIndex += 1
                exerciseChanged = true
            } else {
                currentSetIndex += 1
                exerciseChanged = false
            }
            if currentExerciseIndex >= activeExercises.count {
                captureRestDrop()
                restEndAt = nil
                await endSession()
            } else if supersetHandoff {
                // No rest between the pair — the whole point. Capture
                // first: the lifter may have logged mid-window.
                captureRestDrop()
                restEndAt = nil
                soloRestIsTransit = false
            } else if wasFinalDropSet {
                // Drop ladder (owner 2026-08-14): no rest DURING the
                // ladder — rungs are back-to-back by definition. The rest
                // (with any TRANSIT extension) starts when the ladder
                // sheet closes, via its onDismiss.
                pendingDropRestSeconds = (re.restSeconds ?? defaultRestSeconds)
                    + (exerciseChanged ? TransitWindow.seconds : 0)
                pendingDropRestIsTransit = exerciseChanged
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
                    soloRestStartedAt = Date()
                    restEndAt = Date().addingTimeInterval(TimeInterval(restSeconds))
                }
            }
            if wasFinalDropSet, let weight {
                dropLadder = DropLadderContext(setLogID: log.id,
                                               topWeightPounds: weight,
                                               steps: re.dropSteps ?? 2,
                                               percent: re.dropPercent ?? 20)
            }
            return true
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
            return false
        }
    }

    /// The rest deferred by a drop ladder starts the moment the sheet
    /// closes — logged or skipped, the recovery clock is honest either way.
    private func startPostDropRest() {
        guard let seconds = pendingDropRestSeconds else { return }
        pendingDropRestSeconds = nil
        soloRestIsTransit = pendingDropRestIsTransit
        pendingDropRestIsTransit = false
        if seconds > 0 {
            soloRestStartedAt = Date()
            restEndAt = Date().addingTimeInterval(TimeInterval(seconds))
        }
    }

    /// The adjacent index this exercise is superset-paired with, if any.
    /// Pairs are adjacency-guaranteed by the builder's save normalization,
    /// so one next/prev probe is the whole lookup.
    private func supersetPartnerIndex(of index: Int) -> Int? {
        guard index >= 0, index < activeExercises.count,
              let group = activeExercises[index].supersetGroup else { return nil }
        if index + 1 < activeExercises.count,
           activeExercises[index + 1].supersetGroup == group {
            return index + 1
        }
        if index > 0, activeExercises[index - 1].supersetGroup == group {
            return index - 1
        }
        return nil
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

    /// The PR basis for `exerciseID`, served from the prefetch when it landed.
    ///
    /// The prefetch (`.task(id: exerciseID)`) runs while the lifter is setting
    /// up, so the common path costs zero network at log time — the point of
    /// the 2026-08-02 latency fix. The live call is the cold fallback for when
    /// the exercise just changed and the prefetch hasn't answered yet.
    private func prBasis(exerciseID: UUID, userID: UUID) async throws -> [(weight: Decimal, reps: Int)] {
        if let cached = prBasisByExercise[exerciseID] { return cached }
        let rows = try await SessionRepository.prBasis(userID: userID, exerciseID: exerciseID)
        let basis = Self.pairs(from: rows)
        prBasisByExercise[exerciseID] = basis
        return basis
    }

    /// Drop rows missing either half — a set without both numbers can neither
    /// set a record nor be compared against one. Failed rows enter at their
    /// COMPLETED reps (doctrine: n logged − 1; failed singles drop out).
    private static func pairs(from rows: [SessionRepository.SetBasis]) -> [(weight: Decimal, reps: Int)] {
        rows.compactMap { row in
            guard let weight = row.weight, weight > 0,
                  let reps = row.completedReps else { return nil }
            return (weight, reps)
        }
    }

    @MainActor
    private func endSession() async {
        guard let session else { return }
        do {
            let completedResult = try await SessionRepository.complete(sessionID: session.id)
            let logs = try await SessionRepository.setLogs(sessionID: completedResult.id)
            completedSession = completedResult
            // The session is durably over — retire the recovery pill.
            if appState.liveSoloSession?.id == session.id {
                appState.liveSoloSession = nil
            }

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
            // Watch returns to idle — and stops accepting HR samples for
            // a session that no longer exists.
            pushSoloWatchState(session: session, active: false)
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
