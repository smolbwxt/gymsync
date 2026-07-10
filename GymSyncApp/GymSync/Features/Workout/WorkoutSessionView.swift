import SwiftUI

struct WorkoutSessionView: View {
    let routine: Routine
    let routineExercises: [RoutineExercise]
    let allExercises: [Exercise]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var session: WorkoutSession?
    @State private var loggedSets: [SetLog] = []
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 1
    @State private var showLogSheet = false
    @State private var errorText: String?
    @State private var completed = false
    @State private var isPRToast: Bool = false
    @State private var setStartedAt: Date = .now

    private var currentRoutineExercise: RoutineExercise? {
        guard currentExerciseIndex < routineExercises.count else { return nil }
        return routineExercises[currentExerciseIndex]
    }

    private var currentExercise: Exercise? {
        guard let re = currentRoutineExercise else { return nil }
        return allExercises.first { $0.id == re.exerciseID }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let ex = currentExercise, let re = currentRoutineExercise {
                headerCard(ex: ex, re: re)
                Spacer()
                Button {
                    setStartedAt = .now
                    showLogSheet = true
                } label: {
                    Text("Log set")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                loggedSetsList
            } else if completed {
                completionCard
            } else {
                ProgressView()
            }
            if isPRToast {
                Text("🔥 NEW PR!")
                    .font(.headline)
                    .padding()
                    .background(Color.yellow.opacity(0.9), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle(routine.name)
        .navigationBarBackButtonHidden(!completed)
        .toolbar {
            if !completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End") { Task { await endSession() } }
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
                    Task { await log(reps: reps, weight: weight, rpe: rpe, isFailed: isFailed, note: note) }
                }
            }
        }
    }

    private func headerCard(ex: Exercise, re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise \(currentExerciseIndex + 1) of \(routineExercises.count)")
                .font(.caption).foregroundStyle(.secondary)
            Text(ex.name).font(.title.bold())
            HStack(spacing: 16) {
                LabeledPill("Set", "\(currentSetIndex) / \(re.targetSets ?? 1)")
                if let reps = re.targetReps { LabeledPill("Reps", reps) }
                if let w = re.targetWeight { LabeledPill("Weight", w) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var loggedSetsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(loggedSets) { log in
                    let ex = allExercises.first { $0.id == log.exerciseID }
                    HStack {
                        Text("\(ex?.name ?? "?")").font(.caption)
                        Spacer()
                        Text("\(log.reps ?? 0) × \(log.weight?.description ?? "-") @ RPE \(log.rpe?.description ?? "-")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: 120)
    }

    private var completionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .resizable().frame(width: 60, height: 60).foregroundStyle(.green)
            Text("Workout complete!").font(.title2.bold())
            Text("\(loggedSets.count) sets logged")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
    }

    @MainActor
    private func startIfNeeded() async {
        guard session == nil else { return }
        do { session = try await SessionRepository.startSolo(routineID: routine.id) }
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

            // PR check (Phase 1: client-side after insert, via RPC-ish helper)
            if !isFailed, let weight, weight > 0 {
                let priorMax = try await priorMax(exerciseID: re.exerciseID, weight: weight, userID: userID)
                if weight > priorMax {
                    withAnimation { isPRToast = true }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { isPRToast = false }
                }
            }

            // Advance to next set / exercise
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
        // Fetch prior best (excluding this newly-inserted set)
        let history = try await SessionRepository.exerciseHistory(userID: userID, exerciseID: exerciseID, limit: 200)
        let priorBest = history
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { $0.weight }
            .max() ?? 0
        return priorBest
    }

    @MainActor
    private func endSession() async {
        guard let session else { return }
        do {
            let completed = try await SessionRepository.complete(sessionID: session.id)
            let logs = try await SessionRepository.setLogs(sessionID: completed.id)
            try? await HealthKitBridge.requestPermission()
            try? await HealthKitBridge.exportWorkout(session: completed, setLogs: logs)
            self.completed = true
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

private struct LabeledPill: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 8))
    }
}
