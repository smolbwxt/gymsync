import Foundation
import Supabase

// MARK: - LiveBlockGoalRepository
//
// Plan: Stream A task A11. The Supabase implementation of the Task 0
// `BlockGoalRepository` protocol.
//
// ITS OWN FILE, for the reason `WeeklyGoalLiveRepository.swift:9-13` gives:
// `Models/BlockGoal.swift` and `Models/BlockGoalRepository.swift` are the
// FROZEN interface three other streams read, and keeping the persistence here
// keeps those files untouched for the whole of the parallel build.
//
// THE DEFAULT BINDING IS STILL THE STUB. Integration task I1 swaps it.

/// One row of `public.block_goals`.
///
/// `createdAt` / `updatedAt` are optional ONLY so a write can omit them:
/// Swift's synthesized encoder uses `encodeIfPresent`, so an upsert built with
/// both nil sends neither and the column defaults plus the
/// `block_goals_touch_updated_at` trigger do their jobs. Both are `NOT NULL` in
/// the table, so on a READ they are always present.
private struct BlockGoalRow: Codable {
    let id: UUID
    let userID: UUID
    let enrollmentID: UUID
    let metric: String
    let target: GoalTarget
    /// **THE RAW DATE STRING, NEVER A `Date`.** `block_goals.by_date` is a
    /// `date` column, and a DATE must not go through the SDK's timestamp
    /// decoder — the `SessionSeries` idiom documented at
    /// `Models/ProgramEnrollment.swift:34-38`. This is the single most likely
    /// defect in the whole stream, which is why it is a `String?` here and
    /// converted at exactly two places: `init(_:calendar:)` and `model`.
    let byDate: String?
    let preset: String?
    let source: String
    let outcome: String?
    let outcomeValue: GoalTarget?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case enrollmentID = "enrollment_id"
        case metric
        case target
        case byDate = "by_date"
        case preset
        case source
        case outcome
        case outcomeValue = "outcome_value"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(_ goal: BlockGoal, calendar: Calendar) {
        id = goal.id
        userID = goal.userID
        enrollmentID = goal.enrollmentID
        metric = goal.metric.rawValue
        target = goal.target
        byDate = goal.byDate.map {
            SessionSeries.dayString(for: $0, in: calendar.timeZone)
        }
        preset = goal.preset?.rawValue
        source = goal.source.rawValue
        outcome = goal.outcome?.rawValue
        outcomeValue = goal.outcomeValue
        createdAt = nil
        updatedAt = nil
    }

    /// nil when the row carries a `metric`, `preset` or `source` this build
    /// does not know — the forward-compatibility guard `WeeklyGoalRow.model`
    /// sets, and the reason A1's header can leave `metric` un-CHECKed. The page
    /// then renders empty, which is the honest state for "there is a goal here
    /// that this version cannot read".
    func model(calendar: Calendar) -> BlockGoal? {
        guard let metric = GoalMetric(rawValue: metric),
              let source = WeeklyGoalSource(rawValue: source) else { return nil }
        // `preset` is nullable and nil is MEANINGFUL ("Coach-guided or custom",
        // `BlockGoal.preset`), so absent is fine — but a present string this
        // build cannot spell is a row from a future version, and it gates.
        var resolvedPreset: GoalPreset?
        if let preset {
            guard let known = GoalPreset(rawValue: preset) else { return nil }
            resolvedPreset = known
        }
        var resolvedOutcome: GoalOutcome?
        if let outcome {
            guard let known = GoalOutcome(rawValue: outcome) else { return nil }
            resolvedOutcome = known
        }
        return BlockGoal(
            id: id, userID: userID, enrollmentID: enrollmentID,
            metric: metric, target: target,
            byDate: byDate.flatMap {
                WeekMath.date(fromWeekStartString: $0, calendar: calendar)
            },
            preset: resolvedPreset, source: source,
            outcome: resolvedOutcome, outcomeValue: outcomeValue,
            // Both columns are NOT NULL, so the fallbacks are unreachable.
            createdAt: createdAt ?? .distantPast,
            updatedAt: updatedAt ?? createdAt ?? .distantPast)
    }
}

/// One row of `public.block_goal_rungs`. `week_start` is a DATE column and is
/// therefore a raw String here, for the same reason `by_date` is.
private struct RungRow: Codable {
    let goalID: UUID
    let weekIndex: Int
    let weekStart: String
    let target: GoalTarget
    let status: String
    let derivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case weekIndex = "week_index"
        case weekStart = "week_start"
        case target
        case status
        case derivedAt = "derived_at"
    }

    init(_ rung: LadderRung, goalID: UUID) {
        self.goalID = goalID
        weekIndex = rung.weekIndex
        weekStart = rung.weekStartString
        target = rung.target
        status = rung.status.rawValue
        derivedAt = nil
    }

    var model: LadderRung? {
        guard let status = RungStatus(rawValue: status) else { return nil }
        return LadderRung(weekIndex: weekIndex, weekStartString: weekStart,
                          target: target, status: status)
    }
}

/// Reads and writes the block's goal and its ladder against `block_goals` and
/// `block_goal_rungs`.
///
/// Best-effort throughout, matching the protocol's own contract: `async` with
/// no `throws`, because a network blip must render the page's empty state
/// rather than an error dialog.
struct LiveBlockGoalRepository: BlockGoalRepository {

    private var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Read

    func activeGoal() async -> BlockGoal? {
        guard let enrollment = try? await ProgramRepository.active() else { return nil }
        return await goal(enrollmentID: enrollment.id)
    }

    /// The goal driving one block. `UNIQUE (enrollment_id)` is why `limit(1)`
    /// is not a truncation: there cannot be a second row (owner decision 2).
    func goal(enrollmentID: UUID) async -> BlockGoal? {
        await first(column: "enrollment_id", value: enrollmentID)
    }

    /// **INTERNAL ONLY BECAUSE `BlockGoalLiveRepositoryTests` NEEDS IT** to read
    /// back what it just wrote — the posture `LiveWeeklyGoalRepository.deleteRow`
    /// states at :149-157. Production reads a goal through `activeGoal()`.
    func goal(id: UUID) async -> BlockGoal? {
        await first(column: "id", value: id)
    }

    private func first(column: String, value: UUID) async -> BlockGoal? {
        let calendar = Calendar.current
        do {
            let rows: [BlockGoalRow] = try await client
                .from("block_goals")
                .select()
                .eq(column, value: value)
                .limit(1)
                .execute().value
            return rows.first?.model(calendar: calendar)
        } catch {
            AppLogger.db.error("block_goals read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func ladder(goalID: UUID) async -> Ladder? {
        do {
            let rows: [RungRow] = try await client
                .from("block_goal_rungs")
                .select()
                .eq("goal_id", value: goalID)
                .order("week_index", ascending: true)
                .execute().value
            let rungs = rows.compactMap(\.model)
            guard !rungs.isEmpty else { return nil }
            let derivedAt = rows.compactMap(\.derivedAt).max() ?? .distantPast
            return Ladder(goalID: goalID, rungs: rungs, derivedAt: derivedAt)
        } catch {
            AppLogger.db.error("block_goal_rungs read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Write

    /// The athlete editing their own milestone or date. ALWAYS `source = .user`
    /// on this path, for the same reason `LiveWeeklyGoalRepository.save` stamps
    /// it: the milestone belongs to the athlete (owner decision 8), and Coach
    /// may only propose against a `user` row.
    @discardableResult
    func save(_ goal: BlockGoal) async -> Bool {
        var owned = goal
        owned.source = .user
        return await upsert(owned)
    }

    /// A Coach-derived goal (task A13). Kept apart from `save` precisely
    /// BECAUSE `save` stamps `.user` unconditionally — one function that
    /// sometimes stamps and sometimes does not is how a detection would come to
    /// masquerade as the athlete's own milestone.
    @discardableResult
    func saveDetected(_ goal: BlockGoal) async -> Bool {
        var coached = goal
        coached.source = .coach
        return await upsert(coached)
    }

    @discardableResult
    private func upsert(_ goal: BlockGoal) async -> Bool {
        let calendar = Calendar.current
        do {
            try await client
                .from("block_goals")
                .upsert(BlockGoalRow(goal, calendar: calendar), onConflict: "id")
                .execute()
            return true
        } catch {
            AppLogger.db.error("block_goals upsert failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// **INTERNAL ONLY BECAUSE THE TESTS NEED IT** — every live-DB test
    /// registers this with `addTeardownBlock` BEFORE it writes, and the rungs
    /// cascade with the goal so one delete cleans both.
    func deleteGoal(id: UUID) async {
        do {
            try await client.from("block_goals").delete().eq("id", value: id).execute()
        } catch {
            AppLogger.db.error("block_goals delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persist a whole ladder. Upserts on `(goal_id, week_index)` — the primary
    /// key — so re-deriving a week edits its row rather than colliding.
    @discardableResult
    func saveLadder(_ ladder: Ladder) async -> Bool {
        await upsertRungs(ladder.rungs, goalID: ladder.goalID)
    }

    @discardableResult
    private func upsertRungs(_ rungs: [LadderRung], goalID: UUID) async -> Bool {
        guard !rungs.isEmpty else { return true }
        do {
            try await client
                .from("block_goal_rungs")
                .upsert(rungs.map { RungRow($0, goalID: goalID) },
                        onConflict: "goal_id,week_index")
                .execute()
            return true
        } catch {
            AppLogger.db.error("block_goal_rungs upsert failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Re-laddering

    /// LET COACH RE-LADDER: re-derive the remaining rungs from ACTUALS and
    /// persist them.
    ///
    /// `LadderMath` decides; this only fetches and writes. Only the rungs that
    /// actually changed are written back, so a refresh that moves nothing costs
    /// no round trip — and the ones that did not change are, by
    /// `LadderMath.reLadder`'s own law, every rung already met, missed or
    /// overridden.
    func reLadder(goalID: UUID) async -> Ladder? {
        guard let userID = await SupabaseService.shared.currentUserID(),
              let goal = await goal(id: goalID),
              let existing = await ladder(goalID: goalID) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }
        let currentWeekStart = WeekMath.weekStartString(now, calendar: calendar)

        let measured = await measuredByWeek(goal: goal, rungs: existing.rungs,
                                            userID: userID, calendar: calendar)
        let overridden = await overriddenWeeks(goalID: goalID)

        var stamped = existing
        stamped.rungs = LadderMath.statuses(rungs: existing.rungs, metric: goal.metric,
                                            measuredByWeek: measured,
                                            currentWeekStart: currentWeekStart,
                                            overriddenWeeks: overridden)

        let template = (try? await ProgramRepository.active())?.template
        let fresh = LadderMath.reLadder(
            existing: stamped, metric: goal.metric,
            current: measured[currentWeekStart] ?? GoalTarget(),
            milestone: goal.target,
            constraints: LadderReadout.constraints(template: template, unit: unit),
            rule: LadderRules.rule(for: goal.metric),
            derivedAt: now)

        let changed = zip(existing.rungs, fresh.rungs)
            .filter { $0 != $1 }
            .map(\.1)
        await upsertRungs(changed, goalID: goalID)
        return fresh
    }

    /// The weeks the athlete took back. An override is not a flag of its own:
    /// it IS a `weekly_goals` row for this ladder whose `source` is `user`,
    /// which is exactly what spec §4 means by "an athlete's edit of this week's
    /// row is an override of the rung".
    private func overriddenWeeks(goalID: UUID) async -> Set<String> {
        struct WeekKeyRow: Decodable {
            let weekStart: String
            enum CodingKeys: String, CodingKey { case weekStart = "week_start" }
        }
        do {
            let rows: [WeekKeyRow] = try await client
                .from("weekly_goals")
                .select("week_start")
                .eq("goal_id", value: goalID)
                .eq("source", value: "user")
                .execute().value
            return Set(rows.map(\.weekStart))
        } catch {
            AppLogger.db.error("weekly_goals override read failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Materialisation

    /// Write this week's rung into `weekly_goals` (spec §4).
    ///
    /// Returns the row NOW IN EFFECT — which may be the athlete's own, because
    /// this consults `WeeklyGoalWriteRule.shouldOverwrite` exactly as every
    /// other Coach write does. It does not open a second write path into
    /// `weekly_goals`: `LiveWeeklyGoalRepository.upsert` is private on purpose,
    /// and `writeMaterialisedRung` is the one door added for this.
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? {
        guard let userID = await SupabaseService.shared.currentUserID(),
              let goal = await goal(id: goalID),
              let ladder = await ladder(goalID: goalID),
              let rung = LadderMath.rung(in: ladder, weekStart: weekStart),
              let derived = LadderMath.weeklyGoal(from: rung, goal: goal,
                                                  userID: userID, now: Date())
        else { return nil }

        let weekly = LiveWeeklyGoalRepository()
        let existing = await weekly.goal(weekStart: weekStart)
        guard WeeklyGoalWriteRule.shouldOverwrite(existing: existing,
                                                  detected: derived) else {
            AppLogger.db.info("rung left alone for \(weekStart, privacy: .public) — the athlete set that week")
            return existing
        }
        return await weekly.writeMaterialisedRung(derived) ? derived : existing
    }

    // MARK: - Derivation at build time (task B4's step 7b, implemented here)

    /// Derive this goal's whole ladder from the block that was just generated,
    /// and persist it.
    ///
    /// **DECLARED BY STREAM B ON `BlockGoalRepository`, IMPLEMENTED HERE.** B's
    /// default returns nil so every existing conformer keeps compiling; this is
    /// the one that actually writes rungs.
    ///
    /// THE LADDER IS A READ-OUT OF THE BLOCK (spec §3.1), so the three metrics
    /// the generator PRESCRIBES are read off `program` through `LadderReadout`,
    /// and the eight it ramps go through `LadderRules.rule(for:)`.
    ///
    /// THE RAMPS GET NO MEASURED CURRENT STATE, and that is correct rather than
    /// a gap: the block starts today, so there is nothing measured yet, and
    /// every ramp's documented answer to that is to hold the milestone flat.
    /// The first `reLadder(goalID:)` — which A13 runs on the next Home load —
    /// replaces every one of those rungs from actuals, because at derivation
    /// they are all `ahead` and `ahead` is exactly what re-laddering rewrites.
    @discardableResult
    func saveDerivedLadder(goal: BlockGoal,
                           program: ProgramGenerator.Program,
                           catalog: [Exercise],
                           startedOn: Date,
                           unit: WeightUnit) async -> Ladder? {
        let calendar = Calendar.current
        let weekKeys = LadderMath.weekStartStrings(from: startedOn,
                                                   count: program.weeks.count,
                                                   calendar: calendar)
        guard !weekKeys.isEmpty else { return nil }
        let byID = Dictionary(catalog.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        let constraints = LadderReadout.constraints(program: program, unit: unit)

        let targets = await derivedTargets(goal: goal, program: program,
                                           catalog: byID, weeks: weekKeys.count,
                                           constraints: constraints, unit: unit)
        guard targets.count == weekKeys.count else { return nil }

        let raw = zip(weekKeys.enumerated(), targets).map { pair, target in
            LadderRung(weekIndex: pair.offset, weekStartString: pair.element,
                       target: target, status: .ahead)
        }
        // The week the block starts in is `current`, everything after it
        // `ahead` — decided by the same law that decides it on every later
        // refresh, rather than by a second rule that only runs at build time.
        let rungs = LadderMath.statuses(
            rungs: raw, metric: goal.metric, measuredByWeek: [:],
            currentWeekStart: WeekMath.weekStartString(startedOn, calendar: calendar))

        let ladder = Ladder(goalID: goal.id, rungs: rungs, derivedAt: Date())
        guard await upsertRungs(ladder.rungs, goalID: goal.id) else { return nil }
        return ladder
    }

    /// One target per week, from whichever door this metric belongs to.
    private func derivedTargets(goal: BlockGoal,
                                program: ProgramGenerator.Program,
                                catalog: [UUID: Exercise], weeks: Int,
                                constraints: LadderConstraints,
                                unit: WeightUnit) async -> [GoalTarget] {
        func ramped() -> [GoalTarget] {
            LadderRules.rule(for: goal.metric).rungs(
                current: GoalTarget(), target: goal.target,
                weeks: weeks, constraints: constraints)
        }

        switch goal.metric {
        case .liftOneRepMax:
            // The baseline is the ENROLLMENT'S frozen one, not the milestone:
            // a ladder built from where the athlete is going rather than from
            // where they are would prescribe week 1 at the goal.
            guard let exerciseID = goal.target.exerciseID,
                  let enrollment = try? await ProgramRepository.active(),
                  let baseline = enrollment.baselineValue(for: exerciseID),
                  let rungs = LadderReadout.strengthRungs(
                    program: program, exerciseID: exerciseID,
                    baselineE1RMLbs: baseline, unit: unit)
            else { return ramped() }
            return rungs

        case .liftRepsAtLoad:
            // The block's own prescription for the lift IS "where the athlete
            // is" at build time — there is no logged history for a block that
            // has not happened, and reading the rep target back out of the
            // milestone would make every week the last one.
            guard let exerciseID = goal.target.exerciseID,
                  let slot = LadderReadout.mainSlot(program: program,
                                                    exerciseID: exerciseID),
                  let targetReps = goal.target.targetReps,
                  let rungs = LadderReadout.repStrengthRungs(
                    program: program, exerciseID: exerciseID,
                    loadLbs: goal.target.loadLbs ?? goal.target.targetWeightLbs ?? 0,
                    currentReps: slot.repsLow, targetReps: targetReps)
            else { return ramped() }
            return rungs

        case .weeklyMuscleSets:
            let groups = (goal.target.muscleTargets ?? [:]).keys
                .compactMap { MuscleGroup(rawValue: $0) }
            return LadderReadout.muscleRungs(program: program, catalog: catalog,
                                             groups: groups)

        case .weeklyDistance, .trainingDaysPerWeek, .sessionsOfTypePerWeek,
             .lissMinutesPerWeek, .stretchingExercisesPerWeek, .bodyWeight,
             .cumulativeVolume, .benchmarkTime:
            return ramped()
        }
    }

    // MARK: - The actuals read
    //
    // ONLY WHAT THIS METRIC NEEDS IS FETCHED — the same discipline
    // `LiveWeeklyGoalRepository.progress(for:)` documents at :339-341. A `days`
    // goal has no business paging the 1,300-row exercise catalog, and this runs
    // on Home's refresh budget.

    private func measuredByWeek(goal: BlockGoal, rungs: [LadderRung],
                                userID: UUID,
                                calendar: Calendar) async -> [String: GoalTarget] {
        let weeks: [(key: String, start: Date, end: Date)] = rungs.compactMap { rung in
            guard let start = WeekMath.date(fromWeekStartString: rung.weekStartString,
                                            calendar: calendar),
                  let end = calendar.date(byAdding: .day, value: 7, to: start)
            else { return nil }
            return (rung.weekStartString, start, end)
        }
        guard let first = weeks.first, let last = weeks.last else { return [:] }
        var out: [String: GoalTarget] = [:]

        switch goal.metric {
        case .liftOneRepMax, .liftRepsAtLoad:
            guard let exerciseID = goal.target.exerciseID else { return [:] }
            let logs = (try? await SessionRepository.exerciseHistory(
                userID: userID, exerciseID: exerciseID, limit: 500)) ?? []
            for week in weeks {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                var target = GoalTarget()
                if goal.metric == .liftOneRepMax {
                    target.targetWeightLbs = WeeklyGoalProgressMath.bestE1RMPounds(
                        logs: inWeek, exerciseID: exerciseID)
                } else {
                    target.targetReps = BlockGoalMetricMath.bestRepsAtLoad(
                        logs: inWeek, exerciseID: exerciseID,
                        loadLbs: goal.target.loadLbs ?? 0)
                }
                out[week.key] = target
            }

        case .weeklyMuscleSets:
            let logs = await setLogs(userID: userID, since: first.start, until: last.end)
            let catalog = await catalogByID()
            for week in weeks {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                let credit = WeeklyGoalProgressMath.muscleSetCredit(logs: inWeek,
                                                                    catalog: catalog)
                var targets: [String: Int] = [:]
                for (group, value) in credit { targets[group.rawValue] = Int(value.rounded()) }
                out[week.key] = GoalTarget(muscleTargets: targets)
            }

        case .cumulativeVolume:
            let logs = await setLogs(userID: userID, since: first.start, until: last.end)
            for week in weeks {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                var target = GoalTarget()
                target.volumeLbs = BlockGoalMetricMath.volumePounds(logs: inWeek)
                out[week.key] = target
            }

        case .trainingDaysPerWeek:
            let sessions = await blockSessions(userID: userID)
            for week in weeks {
                var target = GoalTarget()
                target.days = WeeklyGoalProgressMath.distinctTrainingDays(
                    sessions: sessions, now: week.start, calendar: calendar)
                out[week.key] = target
            }

        case .sessionsOfTypePerWeek:
            let type = goal.target.sessionType ?? ""
            let sessions = await blockSessions(userID: userID)
            let routines = await routinesByID(userID: userID)
            let rows = (try? await RoutineRepository.exercisesForRoutines(
                ids: Array(routines.keys))) ?? []
            let byRoutine = Dictionary(grouping: rows, by: \.routineID)
            let catalog = await catalogByID()
            for week in weeks {
                let tags = await HealthKitBridge.workoutTags(from: week.start, to: week.end)
                let counted = sessions.filter { session in
                    guard let completed = session.completedAt,
                          completed >= week.start, completed < week.end else { return false }
                    return WeeklyGoalProgressMath.sessionCounts(
                        towardType: type, session: session, routines: routines,
                        routineExercises: byRoutine, catalog: catalog,
                        healthWorkouts: tags, calendar: calendar)
                }
                var target = GoalTarget()
                target.sessionType = type
                target.sessions = counted.count
                out[week.key] = target
            }

        case .weeklyDistance:
            let unit = await MainActor.run { ThemeStore.shared.weightUnit }
            let activity = goal.target.activity ?? ""
            for week in weeks {
                let metres = await HealthKitBridge.distanceMeters(
                    activity: activity, from: week.start, to: week.end)
                var target = GoalTarget()
                target.activity = activity
                target.distance = WeeklyGoalProgressMath.distanceValue(metres: metres,
                                                                       unit: unit)
                out[week.key] = target
            }

        case .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            let logs = await setLogs(userID: userID, since: first.start, until: last.end)
            let catalog = await catalogByID()
            let sessions = await blockSessions(userID: userID)
            let routines = await routinesByID(userID: userID)
            let rows = (try? await RoutineRepository.exercisesForRoutines(
                ids: Array(routines.keys))) ?? []
            let byRoutine = Dictionary(grouping: rows, by: \.routineID)
            for week in weeks {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                let weekSessions = sessions.filter { session in
                    guard let completed = session.completedAt else { return false }
                    return completed >= week.start && completed < week.end
                }
                let healthMinutes = await HealthKitBridge.lissMinutes(from: week.start,
                                                                      to: week.end)
                let tags = await HealthKitBridge.workoutTags(from: week.start, to: week.end)
                var target = GoalTarget()
                target.lissMinutes = BlockGoalMetricMath.lissMinutes(
                    healthMinutes: healthMinutes, sessions: weekSessions,
                    routines: routines, routineExercises: byRoutine,
                    catalog: catalog, healthWorkouts: tags)
                target.stretchingExercises = BlockGoalMetricMath.stretchingExerciseCount(
                    logs: inWeek, catalog: catalog)
                out[week.key] = target
            }

        case .bodyWeight:
            let logs = (try? await BodyWeightLogRepository.recent(userID: userID)) ?? []
            for week in weeks {
                // The scale reading AS OF the end of that week — a body-weight
                // rung is a level reached, not a thing done inside seven days,
                // so a week with no weigh-in reads the last one before it
                // rather than nothing.
                let upTo = logs.filter { $0.loggedAt < week.end }
                var target = GoalTarget()
                target.bodyWeightLbs = BlockGoalMetricMath.currentBodyWeightPounds(logs: upTo)
                target.bodyWeightRatePercent = goal.target.bodyWeightRatePercent
                out[week.key] = target
            }

        case .benchmarkTime:
            guard let routineID = goal.target.routineID else { return [:] }
            let sessions = await blockSessions(userID: userID)
            for week in weeks {
                let weekSessions = sessions.filter { session in
                    guard let completed = session.completedAt else { return false }
                    return completed >= week.start && completed < week.end
                }
                var target = GoalTarget()
                target.routineID = routineID
                target.targetSeconds = BlockGoalMetricMath.bestBenchmarkSeconds(
                    sessions: weekSessions, routineID: routineID)
                out[week.key] = target
            }
        }
        return out
    }

    // MARK: - The fetches

    /// The block's set logs, PENALTY EXCLUDED AND FAILED KEPT.
    ///
    /// Deliberately not `SessionRepository.recentSetLogs(userID:since:)`, which
    /// filters `is_failed = false` at the query: a failed triple completed two
    /// reps and credits a full set (`SetLog.completedReps`), so filtering it
    /// server-side would silently undercount every week that contained one.
    /// `LiveWeeklyGoalRepository.weekSetLogs` takes the identical position and
    /// says so; it is `private` to that type, and widening it would open a
    /// second door into a file whose write path is deliberately sealed.
    ///
    /// Bounded at both ends and explicitly limited, for the reason that one
    /// records: `gte` alone leans on "no future logs exist" for its ceiling and
    /// on PostgREST's default max-rows for its size.
    private func setLogs(userID: UUID, since: Date, until: Date) async -> [SetLog] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .gte("logged_at", value: formatter.string(from: since))
                .lt("logged_at", value: formatter.string(from: until))
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: true)
                .limit(5000)
                .execute().value
            return rows
        } catch {
            AppLogger.db.error("block goal set_logs read failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func blockSessions(userID: UUID) async -> [WorkoutSession] {
        (try? await SessionRepository.history(userID: userID, limit: 200)) ?? []
    }

    private func catalogByID() async -> [UUID: Exercise] {
        let all = (try? await ExerciseRepository.fetchAll()) ?? []
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func routinesByID(userID: UUID) async -> [UUID: Routine] {
        let all = (try? await RoutineRepository.fetchAll(ownerID: userID)) ?? []
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
