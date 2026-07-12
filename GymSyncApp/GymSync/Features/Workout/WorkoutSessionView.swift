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
    @State private var isPRToast: Bool = false
    @State private var setStartedAt: Date = .now
    /// PRs achieved this session — consumed by the recap view (Task 9).
    @State private var sessionPRs: [PersonalRecord] = []
    /// The completed session record (has `completedAt`) — captured by `endSession()`
    /// so the recap's duration hero can compute `completedAt - startedAt`.
    @State private var completedSession: WorkoutSession?
    /// True only when `HealthKitBridge.exportWorkout` succeeded — surfaces sync
    /// state to the recap's Apple Health card (never blocks completion on failure).
    @State private var healthSynced: Bool = false

    private var currentRoutineExercise: RoutineExercise? {
        guard currentExerciseIndex < routineExercises.count else { return nil }
        return routineExercises[currentExerciseIndex]
    }

    private var currentExercise: Exercise? {
        guard let re = currentRoutineExercise else { return nil }
        return allExercises.first { $0.id == re.exerciseID }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let ex = currentExercise, let re = currentRoutineExercise {
                        // Canvas: accent-filled exercise header card
                        exerciseHeaderCard(ex: ex, re: re)

                        // Canvas: logged sets table
                        loggedSetsTable

                    } else if completed {
                        recapHeader
                        recapBody
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
            if !completed, currentExercise != nil {
                VStack(spacing: 0) {
                    GSDivider()
                    Button {
                        setStartedAt = .now
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

            // Canvas: recap sticky footer — single centered "Done" CTA (Dossier §A.4).
            if completed {
                VStack(spacing: 0) {
                    GSDivider()
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                }
                .background(theme.bg)
            }

            // Canvas: PR toast — accent pill
            if isPRToast {
                Text("NEW PR")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.accent)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.bottom, 100)
            }
        }
        .background(theme.bg)
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
                // Compact bordered-secondary treatment (not the full-size
                // GSSecondaryButtonStyle, which is sized for block CTAs).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await endSession() }
                    } label: {
                        Text("End")
                            .font(GSFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await startIfNeeded() }
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
                    col0: Image(systemName: "checkmark")
                              .font(.system(size: 13, weight: .bold))
                              .foregroundStyle(theme.accent700),
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

    // MARK: - Recap (Dossier §A.4) — replaces the old completionCard.
    // All data below is already in view state (§B.10): no new queries.

    // Canvas: recap header bar — "Workout Complete" title + share button, border-bottom divider.
    private var recapHeader: some View {
        HStack {
            Text("Workout Complete")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer()
            ShareLink(item: recapShareSummary) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 2)
        }
    }

    // Canvas: recap body — accent hero, PR card, by-exercise breakdown, Apple Health card.
    private var recapBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            recapHero

            if let pr = heaviestSessionPR {
                prCelebrationCard(pr)
            }

            if !exerciseSummaries.isEmpty {
                exerciseBreakdown
            }

            if healthSynced {
                appleHealthCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // Canvas: accent hero block — routine kicker, duration hero (52pt), subline, 3-cell stat row.
    private var recapHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recapKicker)
                .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(recapDurationText)
                .font(GSFont.heading(52, relativeTo: .largeTitle))
                .tracking(-0.4)
                .foregroundStyle(theme.bg)

            Text(recapSubline)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.bg.opacity(0.9))

            HStack(spacing: 8) {
                heroStatCell(value: recapTotalLbsText, label: "TOTAL LBS")
                heroStatCell(value: "\(recapNonPenaltySets.count)", label: "SETS")
                heroStatCell(value: "\(sessionPRs.count)", label: "PR")
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    private func heroStatCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.bold(20, relativeTo: .title3))
                .foregroundStyle(theme.bg)
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.bg.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Canvas: PR celebration card — accent100 fill, shown for the heaviest PR this session.
    private func prCelebrationCard(_ pr: PersonalRecord) -> some View {
        let exerciseName = allExercises.first { $0.id == pr.exerciseID }?.name ?? "Exercise"
        let delta = pr.weight - pr.previousBest
        return GSCard(backgroundColor: theme.accent100) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🔥 New personal record")
                    .font(GSFont.bodyMedium(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent)
                Text("\(exerciseName) — \(decimalString(pr.weight)) lbs × \(pr.reps)")
                    .font(GSFont.bold(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text("▲ Beat previous best by \(decimalString(delta)) lbs")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Canvas: "By exercise" breakdown — grouped by first-logged order, 1px dividers, PR tags.
    private var exerciseBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By exercise")
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .padding(.bottom, 8)

            ForEach(Array(exerciseSummaries.enumerated()), id: \.element.id) { index, summary in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.name)
                            .font(GSFont.bold(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text(summary.metaText)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    }
                    Spacer()
                    if summary.isPR {
                        GSTag(text: "PR", style: .accent)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                if index < exerciseSummaries.count - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    // Canvas: Apple Health sync card — only rendered when export actually succeeded.
    private var appleHealthCard: some View {
        GSCard {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synced to Apple Health")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text(appleHealthMetaText)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                Spacer()
            }
            .padding(12)
        }
    }

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

    /// One row of the "By exercise" breakdown: name, set count, top set, PR flag.
    private struct ExerciseSummary: Identifiable {
        let id: UUID
        let name: String
        let setCount: Int
        let topWeight: Decimal?
        let topReps: Int?
        let isPR: Bool

        var metaText: String {
            if let topWeight, let topReps {
                return "\(setCount) sets · top \(topWeight) × \(topReps)"
            }
            return "\(setCount) sets"
        }
    }

    /// Non-penalty sets logged this session — backs the hero SETS stat and Apple Health meta.
    private var recapNonPenaltySets: [SetLog] {
        loggedSets.filter { !$0.isPenalty }
    }

    /// `loggedSets` grouped by exercise (excluding penalty), preserving first-logged order.
    private var exerciseSummaries: [ExerciseSummary] {
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
            let topSet = sets.max { ($0.weight ?? 0) < ($1.weight ?? 0) }
            return ExerciseSummary(
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

    private var appleHealthMetaText: String {
        let minutes = Int((recapDurationInterval / 60).rounded())
        return "\(minutes) min · \(recapNonPenaltySets.count) sets"
    }

    private var recapShareSummary: String {
        let title = routine?.name ?? "Solo Workout"
        return "\(title) — \(recapDurationText), \(recapTotalLbsText) lbs, \(recapNonPenaltySets.count) sets"
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

    /// Trims a trailing ".0"/zero fraction so whole-number weights read as "190" not "190.0".
    private func decimalString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    @MainActor
    private func startIfNeeded() async {
        guard session == nil else { return }
        do { session = try await SessionRepository.startSolo(routineID: routine?.id) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
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
            try await SessionRepository.logSet(log)
            loggedSets.append(log)

            if !isFailed, let weight, weight > 0 {
                let priorMax = try await priorMax(exerciseID: re.exerciseID,
                                                  weight: weight, userID: userID)
                if weight > priorMax {
                    withAnimation { isPRToast = true }
                    // Best-effort PR record — a failed insert must never block or delay
                    // set logging (which already happened above). Fall back to a local
                    // record so the recap (Task 9) still has the PR if the write failed.
                    if let record = try? await PersonalRecordRepository.record(
                        exerciseID: re.exerciseID,
                        weight: weight,
                        reps: reps ?? 0,
                        previousBest: priorMax,
                        sessionID: session.id
                    ) {
                        sessionPRs.append(record)
                    } else {
                        sessionPRs.append(PersonalRecord(
                            id: UUID(),
                            userID: userID,
                            exerciseID: re.exerciseID,
                            weight: weight,
                            reps: reps ?? 0,
                            previousBest: priorMax,
                            sessionID: session.id,
                            achievedAt: Date()
                        ))
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { isPRToast = false }
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
                await endSession()
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
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

            // Export result IS surfaced (recap's Apple Health card needs to know),
            // but a failure still must not block completion — do/catch, not `throw`.
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
