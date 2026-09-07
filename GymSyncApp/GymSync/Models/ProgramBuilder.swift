import Foundation

// MARK: - ProgramBuilder
//
// Build a block from the PROFILE, with no screen in between. Owner
// 2026-08-27: "eliminate the 5 door page all together, and land on the
// built program page."
//
// Everything here was CoachWizardView.create() — the one function in the
// app that writes a program — lifted out of the view so the consult's
// BUILD IT can call it directly. The wizard's dials were a second copy of
// the consult's answers (goal, days, duration, experience, session
// length, equipment, no-gos): the athlete answered Coach and then
// re-answered a form. The profile the consult tunes IS the input now.
//
// Order of writes is preserved from the wizard, and it is load-bearing:
//   1. evidence reads (rules, titration, targets, history, starred)
//   2. generate — refuse BEFORE anything is written
//   3. profile (carryover + lastBuild)
//   4. snapshot the routines this build replaces
//   5. write the new day routines (throws — the deliverable)
//   6. delete the superseded routines
//   7. template row → enroll (retires the old enrollment FIRST) → plan
//   8. stamp the rules whose levers actually fired
// Booking is NOT here any more: the program page owns scheduling (owner
// 2026-08-27: "weeks are extruded buttons... schedule your weeks here").
enum ProgramBuilder {

    enum Failure: LocalizedError {
        case emptyWeek
        var errorDescription: String? {
            switch self {
            case .emptyWeek:
                return "I could not put any lifts in that week. "
                     + "Give the exercise library a moment and try again."
            }
        }
    }

    struct Outcome {
        let program: ProgramGenerator.Program
        let durationWeeks: Int
    }

    /// Generate and commit a block for `profile`. `answers` is the consult
    /// that just ran (nil when building from a stored profile alone) — it
    /// supplies the block length; the profile supplies everything else.
    @MainActor
    static func build(profile loaded: TrainingProfile,
                      answers: ConsultAnswers?,
                      catalog all: [Exercise],
                      userID: UUID,
                      goalWriter: WeeklyGoalCoachWriter = LiveWeeklyGoalRepository()) async throws -> Outcome {

        // ── 1. Evidence ──────────────────────────────────────────────
        let standingRules = (try? await TrainingRulesRepository.active()) ?? []
        // THE TITRATION runs before the targets read, so any move it
        // makes is what this build prescribes (owner policy 2026-08-26).
        await VolumeTitrationRunner.run(userID: userID, catalog: all)
        let volumeTargets = Dictionary(
            uniqueKeysWithValues: ((try? await VolumeTargetRepository.all()) ?? [])
                .map { ($0.muscle, $0.weeklySets) })

        var daysSinceLastSession: Int?
        var daysSinceReturn: Int?
        if let sessions = try? await SessionRepository.history(userID: userID, limit: 200) {
            let dates = sessions.compactMap(\.completedAt)
            if let latest = dates.max() {
                daysSinceLastSession = Calendar.current
                    .dateComponents([.day], from: latest, to: .now).day
                daysSinceReturn = GeneratorScience.daysSinceReturn(sessionDates: dates)
            }
        }

        var starred: Set<UUID> = []
        if let starredRoutines = try? await PublicWorkoutRepository.myStarredRoutineIDs(),
           !starredRoutines.isEmpty,
           let rows = try? await RoutineRepository.exercisesForRoutines(ids: starredRoutines) {
            let canonical = Dictionary(uniqueKeysWithValues: all.map {
                ($0.id, $0.aliasOf ?? $0.id)
            })
            starred = Set(rows.map { canonical[$0.exerciseID] ?? $0.exerciseID })
        }

        // ── 2. Generate ──────────────────────────────────────────────
        // The block length: the consult's date probe when it was
        // answered, else the same eight weeks the wizard defaulted to.
        let duration = answers?.durationWeeks ?? 8
        // Alias rows never enter selection — the same movement can't be
        // "varied" into itself under a second name.
        let selectable = all.filter { $0.aliasOf == nil }
        let generatorCatalog = selectable.enumerated().map { index, ex in
            ProgramGenerator.CatalogExercise(
                id: ex.id, name: ex.name,
                primaryMuscle: ex.primaryMuscle,
                secondaryMuscles: ex.secondaryMuscles,
                category: ex.category, equipment: ex.equipment,
                movementPattern: ex.movementPattern ?? "other",
                rank: index,
                focusScores: ex.focusScores ?? [:],
                complexity: ex.complexity ?? 3,
                fatigueCost: ex.fatigueCost ?? 3,
                spinalLoad: ex.spinalLoad ?? 0,
                repMin: ex.repMin,
                repMax: ex.repMax,
                lengthenedBias: ex.lengthenedBias ?? false,
                unilateral: ex.unilateral ?? false,
                impact: ex.impact ?? "none",
                legInterference: ex.legInterference ?? false,
                explosive: ex.explosive ?? false,
                jointStress: ex.jointStress ?? [])
        }
        // Youth ceilings read the ACCOUNT profile's birth year (the
        // training profile never carried it; the wizard's own text field
        // was the only source until the 2026-08-28 audit).
        let accountBirthYear = ((try? await ProfileRepository.fetch(userID: userID)) ?? nil)?.birthYear
        var inputs = loaded.generatorInputs(
            durationWeeks: duration,
            birthYear: accountBirthYear,
            daysSinceLastSession: daysSinceLastSession,
            daysSinceReturn: daysSinceReturn,
            standingRules: standingRules,
            volumeTargets: volumeTargets)
        inputs.sessionMinutes = loaded.sessionMinutes
        // UNION: RuleIntent.swap stars the lift the athlete asked to
        // switch TO; an assignment here would erase it.
        inputs.starredExerciseIDs.formUnion(starred)

        let program = ProgramGenerator.generate(inputs: inputs, catalog: generatorCatalog)
        // With an empty catalog the generator still emits days, just with
        // no exercises in them. Refuse before anything is written.
        guard program.days.contains(where: { !$0.exercises.isEmpty }) else {
            throw Failure.emptyWeek
        }

        // ── 3. Profile ───────────────────────────────────────────────
        var profile = loaded
        let focus = profile.generatorFocus
        let days = profile.daysPerWeek
        var carryover = profile.carryover ?? TrainingProfile.Carryover()
        carryover.blockGoalHistory.append(profile.blockGoal)
        carryover.pendingGraduation = false
        profile.carryover = carryover
        profile.lastBuild = TrainingProfile.BuiltBlock(
            notes: program.notes,
            unhonoredRules: program.unhonoredRules,
            builtAt: .now)
        try? await TrainingProfileRepository.save(profile, userID: userID)

        // ── 4. Snapshot what this build replaces ─────────────────────
        // Snapshot first, write second, delete third. A failure midway
        // leaves duplicates the athlete can see, not nothing.
        let supersededRoutineIDs: [UUID] = ((try? await RoutineRepository
            .fetchAll(ownerID: userID)) ?? [])
            .filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
            .map(\.id)

        // ── 5. Write the day routines ────────────────────────────────
        let now = Date()
        for day in program.days {
            let routineID = UUID()
            let routine = Routine(
                id: routineID, ownerID: userID,
                name: "Coach · \(day.name)",
                description: "Generated by Coach — \(label(for: focus.rawValue)), \(days)×/week.",
                visibility: "private", createdAt: now, updatedAt: now)
            let exercises = day.exercises.enumerated().map { index, ex in
                RoutineExercise(
                    id: UUID(), routineID: routineID, exerciseID: ex.exerciseID,
                    position: index + 1,
                    targetSets: ex.sets,
                    targetReps: ex.cardioZone != nil ? nil : "\(ex.repsLow)-\(ex.repsHigh)",
                    targetWeight: nil,
                    restSeconds: ex.restSeconds,
                    notes: nil,
                    setType: ex.setType,
                    supersetGroup: ex.supersetGroup,
                    dropSteps: ex.dropSteps,
                    dropPercent: ex.dropPercent,
                    targetFailure: ex.targetFailure,
                    targetRepsLow: ex.cardioZone != nil ? nil : ex.repsLow,
                    targetRepsHigh: ex.cardioZone != nil ? nil : ex.repsHigh,
                    cardioZone: ex.cardioZone,
                    cardioMinutes: ex.cardioMinutes)
            }
            try await RoutineRepository.save(routine, exercises: exercises)
        }

        // ── 6. The week it replaces can go ───────────────────────────
        // sessions.routine_id is ON DELETE SET NULL, so past workouts
        // keep their sets and lose only the pointer.
        for id in supersededRoutineIDs {
            try? await RoutineRepository.delete(id: id)
        }

        // ── 7. Template row → enroll → plan ──────────────────────────
        let focusKind = focus == .weightLoss ? "weight_loss" : focus.rawValue
        let weekPlan = ProgramGenerator.weekSummaries(program)
        let savedRow = try? await ProgramTemplateRepository.saveGenerated(
            name: "Coach · \(label(for: focus.rawValue)) · \(days)-day",
            summary: "Generated \(duration)-week \(label(for: focus.rawValue).lowercased()) block — \(days) lifting days a week.",
            focusKind: focusKind,
            sessionsPerWeek: days,
            durationWeeks: duration,
            weeks: weekPlan)
        if let savedRow, !weekPlan.isEmpty {
            await enroll(row: savedRow, weeks: weekPlan, program: program,
                         userID: userID,
                         config: configSnapshot(profile: profile,
                                                duration: duration,
                                                standingRules: standingRules,
                                                catalog: all))
            _ = try? await TrainingPlanRepository.add(templateID: savedRow.id)
        }

        // ── 8. Receipts ──────────────────────────────────────────────
        // Only the rules whose levers ACTUALLY fired while these inputs
        // were assembled — never the merely eligible.
        await TrainingRulesRepository.markApplied(inputs.appliedRuleIDs)

        // ── 9. This week's goal (Stream A task A11) ──────────────────
        // A block always arrives with its goal, so Home is never a fresh
        // block over an empty strip.
        //
        // LAST, and that placement is the point: this file's header calls
        // the order of writes load-bearing, and detection reads the
        // enrollment and the day routines that steps 5 and 7 just wrote.
        // Run any earlier and it would derive a goal from the block being
        // replaced.
        //
        // PROPOSE ONLY: `writeDetectedGoal` leaves a `source = user` row
        // alone (WeeklyGoalWriteRule) — building a block must not silently
        // replace a goal the athlete set for this week. Best-effort, like
        // every other write after step 5's deliverable.
        //
        // INJECTED, not constructed inline, so a unit test of build(...)
        // does not perform six network fetches and a write.
        await goalWriter.writeDetectedGoal(weekStart: WeekMath.weekStartString())

        return Outcome(program: program, durationWeeks: duration)
    }

    // MARK: Enrollment (lifted from CoachWizardView.enrollGenerated)

    /// Enroll the lifter in the block just generated, so the weekly wave
    /// reaches their prescriptions. Best-effort throughout.
    private static func enroll(row: ProgramTemplateRow,
                               weeks: [ProgramWeek],
                               program: ProgramGenerator.Program,
                               userID: UUID,
                               config: [String: String]) async {
        // RETIRE FIRST: building a program ends the one before it,
        // whether or not the new one enrolls.
        if let active = try? await ProgramRepository.active(), active.endedAt == nil {
            try? await ProgramRepository.end(enrollmentID: active.id, reason: "abandoned")
        }

        let mainLiftIDs = Array(Set(program.days
            .flatMap(\.exercises)
            .filter { $0.isMain && $0.cardioZone == nil }
            .map(\.exerciseID)))
        guard !mainLiftIDs.isEmpty else { return }

        var baselines: [String: Double] = [:]
        if let since = Calendar.current.date(byAdding: .day, value: -180, to: .now),
           let logs = try? await SessionRepository.recentSetLogs(userID: userID, since: since) {
            let byExercise = Dictionary(grouping: logs, by: \.exerciseID)
            for id in mainLiftIDs {
                // The CURRENT training era only — a layoff inside the
                // window must not freeze a pre-layoff max in.
                guard let history = byExercise[id],
                      let best = WorkingWeight.bestQualifyingSet(
                                  in: TrainingHorizon.sinceReturn(history)) else { continue }
                let oneRM = StatMath.estimatedOneRepMax(weight: best.weight, reps: best.reps)
                baselines[id.uuidString.lowercased()] = NSDecimalNumber(decimal: oneRM).doubleValue
            }
        }

        let template = ProgramTemplate(row: row, weeks: weeks)
        ProgramTemplateStore.shared.register([template])

        _ = try? await ProgramRepository.enroll(
            template: template,
            focus: ProgramFocus(exerciseIDs: mainLiftIDs),
            baseline: baselines,
            config: config)
    }

    /// The profile's state at the moment of the build, frozen onto the
    /// enrollment. Human-readable on purpose — the provenance drawer and
    /// the AAR payload render these lines verbatim.
    private static func configSnapshot(profile: TrainingProfile,
                                       duration: Int,
                                       standingRules: [TrainingRule],
                                       catalog: [Exercise]) -> [String: String] {
        var config: [String: String] = [:]
        config["goal"] = label(for: profile.generatorFocus.rawValue)
        if let ids = profile.focusExerciseIDs, !ids.isEmpty {
            let names = ids.compactMap { id in catalog.first { $0.id == id }?.name }
            if !names.isEmpty { config["focus lifts"] = names.joined(separator: ", ") }
        }
        config["days per week"] = "\(profile.daysPerWeek)"
        config["duration"] = "\(duration) weeks"
        config["experience"] = profile.trainingAge.rawValue.capitalized
        config["session length"] = profile.sessionMinutes.map { "\($0) min" } ?? "uncapped"
        config["structure"] = String(describing: profile.sessionStructure)
        config["intensity appetite"] = profile.intensityAppetite
        if let equipment = profile.equipment,
           equipment != Set(Venue.equipmentClasses), !equipment.isEmpty {
            config["equipment"] = equipment.sorted().joined(separator: ", ")
        }
        if !profile.excludedPatterns.isEmpty {
            config["won't do"] = profile.excludedPatterns.sorted().joined(separator: ", ")
        }
        if !profile.cautionJoints.isEmpty {
            config["working around"] = profile.cautionJoints.sorted().joined(separator: ", ")
        }
        if !profile.injuredJoints.isEmpty {
            config["injured, kept out"] = profile.injuredJoints.sorted().joined(separator: ", ")
        }
        if let cap = profile.derivedComplexityCap {
            config["movement complexity"] = "up to level \(cap) of 5"
        }
        if !standingRules.isEmpty {
            config["standing rules"] = "\(standingRules.count) held"
        }
        config["scheduled"] = "set week by week on the program page"
        return config
    }

    private static func label(for option: String) -> String {
        switch option {
        case "weightLoss": return "Weight Loss"
        case "new": return "New"
        case "intermediate": return "Intermediate"
        case "advanced": return "Advanced"
        default: return option.capitalized
        }
    }
}

// MARK: - VolumeTitrationRunner
//
// One titration step per probed muscle (lifted verbatim from
// CoachWizardView.runVolumeTitration so the builder can run it without
// the wizard). Deliberately conservative at every gate, because each gate
// is one of the titration's own rules: no probe answers → no move; fewer
// than two readable sessions → hold; a muscle with no prescription
// history seeds from the middle of the owner's 12–25 band.
enum VolumeTitrationRunner {

    static func run(userID: UUID, catalog: [Exercise]) async {
        let probes = (try? await RecoveryProbeRepository.recentAnswered()) ?? []
        guard !probes.isEmpty else { return }
        let recoveryByMuscle = Dictionary(grouping: probes, by: \.muscle)

        guard let sessions = try? await SessionRepository.history(userID: userID, limit: 30)
        else { return }
        let scored = sessions.filter { $0.routineID != nil && $0.completedAt != nil }
            .prefix(12)
        guard scored.count >= 2 else { return }

        let routineIDs = Array(Set(scored.compactMap(\.routineID)))
        let rows = (try? await RoutineRepository.exercisesForRoutines(ids: routineIDs)) ?? []
        let prescriptionByRoutine = Dictionary(grouping: rows, by: \.routineID)

        guard let oldest = scored.compactMap(\.completedAt).min(),
              let logs = try? await SessionRepository.recentSetLogs(
                  userID: userID,
                  since: oldest.addingTimeInterval(-86_400))
        else { return }
        let logsBySession = Dictionary(grouping: logs, by: \.sessionID)

        let muscleByExercise = Dictionary(uniqueKeysWithValues:
            catalog.map { ($0.id, $0.primaryMuscle.lowercased()) })

        var outcomesByMuscle: [String: [VolumeTitration.SessionOutcome]] = [:]
        for session in scored {
            guard let routineID = session.routineID,
                  let date = session.completedAt,
                  let prescription = prescriptionByRoutine[routineID]
            else { continue }
            let sessionLogs = logsBySession[session.id] ?? []
            var prescribed: [String: Int] = [:]
            var completed: [String: Int] = [:]
            var failed: Set<String> = []
            for ex in prescription {
                guard let muscle = muscleByExercise[ex.exerciseID],
                      let sets = ex.targetSets, sets > 0,
                      let repsLow = ex.targetRepsLow, repsLow > 0
                else { continue }
                prescribed[muscle, default: 0] += sets * repsLow
                for log in sessionLogs where log.exerciseID == ex.exerciseID {
                    completed[muscle, default: 0] += log.completedReps ?? 0
                    if log.isFailed { failed.insert(muscle) }
                }
            }
            for (muscle, target) in prescribed where target > 0 {
                outcomesByMuscle[muscle, default: []].append(
                    .init(date: date,
                          repCompletion: min(1.0, Double(completed[muscle] ?? 0) / Double(target)),
                          bestE1RM: nil,
                          anyFailure: failed.contains(muscle)))
            }
        }

        let existing = Dictionary(uniqueKeysWithValues:
            ((try? await VolumeTargetRepository.all()) ?? [])
                .map { ($0.muscle, $0.weeklySets) })

        for (muscle, recoveryProbes) in recoveryByMuscle {
            guard let outcomes = outcomesByMuscle[muscle], outcomes.count >= 2
            else { continue }
            let dates = outcomes.map(\.date).sorted()
            let gaps = zip(dates.dropFirst(), dates).map {
                Calendar.current.dateComponents([.day], from: $1, to: $0).day ?? 3
            }
            let gapDays = max(1, gaps.sorted()[gaps.count / 2])

            let current = existing[muscle]
                ?? VolumeTitration.startingPoint(
                    low: VolumeTitration.floorWeeklySets,
                    high: VolumeTitration.ceilingWeeklySets)
            let move = VolumeTitration.decide(
                muscle: muscle,
                current: current,
                outcomes: outcomes,
                recovery: recoveryProbes.map(\.observation),
                sessionGapDays: gapDays)
            let next = VolumeTitration.apply(move, to: current)
            if next != current || existing[muscle] == nil {
                try? await VolumeTargetRepository.set(
                    muscle: muscle, weeklySets: next, reason: move.reason,
                    userID: userID)
            }
        }
    }
}
