import Foundation
import Supabase

// MARK: - LiveWeeklyGoalRepository
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, Stream
// A task A12. The Supabase implementation of the Task 0 protocol.
//
// ITS OWN FILE, and that is a ruling rather than a preference (Task 0
// review, finding 2): `Models/WeeklyGoal.swift` is the frozen interface
// three other streams read, and `WeeklyGoal` is deliberately not `Codable` —
// `setAt` has no column of its own. Putting the persistence here keeps that
// file untouched for the whole of the parallel build.
//
// THE DEFAULT BINDING IS STILL THE STUB. Integration task I1 swaps it.

/// One row of `public.weekly_goals`.
///
/// `created_at` and `updated_at` are optionals ONLY so that a write can omit
/// them: Swift's synthesized encoder uses `encodeIfPresent` for optionals, so
/// an upsert built with both nil sends neither, and the column default and
/// the `weekly_goals_touch_updated_at` trigger do their jobs. Both columns
/// are `NOT NULL` in the table, so on a READ they are always present.
private struct WeeklyGoalRow: Codable {
    let userID: UUID
    /// The raw DATE string. Never a `Date` — DATE columns must not go
    /// through the SDK's timestamp decoder (`ProgramEnrollment.swift:34-36`).
    let weekStart: String
    let kind: String
    let params: WeeklyGoalParams
    let source: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case weekStart = "week_start"
        case kind
        case params
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(_ goal: WeeklyGoal) {
        userID = goal.userID
        weekStart = goal.weekStartString
        kind = goal.kind.rawValue
        params = goal.params
        source = goal.source.rawValue
        createdAt = nil
        updatedAt = nil
    }

    /// nil when the row carries a `kind` or `source` this build does not
    /// know — a forward-compatibility guard rather than a crash. The strip
    /// then renders the invitation, which is the honest state for "there is
    /// a goal here that this version cannot read".
    var model: WeeklyGoal? {
        guard let kind = WeeklyGoalKind(rawValue: kind),
              let source = WeeklyGoalSource(rawValue: source) else { return nil }
        return WeeklyGoal(userID: userID,
                          weekStartString: weekStart,
                          kind: kind,
                          params: params,
                          source: source,
                          // `updated_at` IS `setAt`: the goal's own trigger
                          // bumps it on every edit (A1). The fallbacks are
                          // unreachable — both columns are NOT NULL.
                          setAt: updatedAt ?? createdAt ?? .distantPast)
    }
}

/// Reads and writes this week's goal against `weekly_goals`, and computes
/// its progress through `WeeklyGoalProgressMath`.
///
/// Best-effort throughout, matching the protocol's own contract: `async`
/// with no `throws`, because a network blip on Home must render the
/// invitation rather than an error on a strip.
struct LiveWeeklyGoalRepository: WeeklyGoalRepository, WeeklyGoalCoachWriter {

    private var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Read

    func goal(weekStart: String) async -> WeeklyGoal? {
        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        do {
            let rows: [WeeklyGoalRow] = try await client
                .from("weekly_goals")
                .select()
                .eq("user_id", value: userID)
                .eq("week_start", value: weekStart)
                .limit(1)
                .execute().value
            return rows.first?.model
        } catch {
            AppLogger.db.error("weekly_goals read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Write

    /// The athlete's own goal. Always `source = 'user'` on this path — this
    /// is the editor's Save, and owner answer 3 turns on that column: once
    /// it says `user`, Coach may only propose (task A11).
    ///
    /// Upserts on the primary key `(user_id, week_start)`, so saving twice
    /// in a week edits one row rather than failing on the second.
    /// SAVE IS ALSO WHERE HEALTH IS ASKED FOR (controller ruling,
    /// 2026-09-06). The editor's primary and its ACCEPT both land here, so a
    /// `distance` or `sessionsOfType` save is a real user gesture and the
    /// system sheet has an answer in it. Deliberately NOT from
    /// `progress(for:)` or from Home's refresh, which would put a
    /// permission sheet in front of someone who only opened the app.
    ///
    /// Best-effort and non-blocking: iOS does not re-prompt once answered,
    /// so calling it on every save of these kinds is cheap and idempotent,
    /// and a throw here must never cost the athlete their goal.
    @discardableResult
    func save(_ goal: WeeklyGoal) async -> Bool {
        var userGoal = goal
        userGoal.source = .user
        if goal.kind == .distance || goal.kind == .sessionsOfType {
            try? await HealthKitBridge.requestWorkoutAndDistancePermission()
        }
        return await upsert(userGoal)
    }

    /// LET COACH SET IT: delete the row, then hand back what detection says
    /// this week should be — and persist that, so the next read agrees with
    /// what the editor just showed.
    ///
    /// The delete comes first on purpose. If detection fails, the athlete is
    /// left with no row, which is the state the detector is guaranteed to
    /// fill on the next Home refresh; leaving the old `user` row in place
    /// would silently contradict the button they just pressed.
    func clearToCoach(weekStart: String) async -> WeeklyGoal? {
        await deleteRow(weekStart: weekStart)
        guard let detected = await detect(weekStart: weekStart) else { return nil }
        await upsert(detected)
        return detected
    }

    /// Removes this week's row and writes nothing back. `clearToCoach`'s
    /// first half, and the only way a test can undo what it wrote.
    func deleteRow(weekStart: String) async {
        guard let userID = await SupabaseService.shared.currentUserID() else { return }
        do {
            try await client
                .from("weekly_goals")
                .delete()
                .eq("user_id", value: userID)
                .eq("week_start", value: weekStart)
                .execute()
        } catch {
            AppLogger.db.error("weekly_goals delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes a row exactly as given. Shared by `save` and by A11's Coach
    /// write path, which has already decided it is allowed to write.
    @discardableResult
    func upsert(_ goal: WeeklyGoal) async -> Bool {
        do {
            try await client
                .from("weekly_goals")
                .upsert(WeeklyGoalRow(goal), onConflict: "user_id,week_start")
                .execute()
            return true
        } catch {
            AppLogger.db.error("weekly_goals upsert failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Detection

    /// What Coach would set for `weekStart`, fetching the detector's inputs.
    /// Writes NOTHING — the propose-only path (A11) and `clearToCoach` both
    /// build on this.
    func detect(weekStart: String) async -> WeeklyGoal? {
        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }
        let calendar = Calendar.current
        let now = Date()

        async let enrollment = try? await ProgramRepository.active()
        async let trainingProfile = try? await TrainingProfileRepository.load()
        async let volumeTargets = (try? await VolumeTargetRepository.all()) ?? []
        async let library = routineLibrary(userID: userID)
        async let sessions = weekSessions(userID: userID)
        async let weeklyGoal = effectiveWeeklyGoal(userID: userID)

        // THE WEEK'S ROUTINES, not the athlete's whole library. Feeding the
        // detector everything they own summed `muscleTargets` across five
        // saved routines when the week prescribes one, and let the
        // conditioning test judge the library rather than the week.
        let weekRoutines = WeeklyGoalDetector.routinesForWeek(
            library: await library, sessions: await sessions,
            now: now, calendar: calendar)
        let rows = (try? await RoutineRepository
            .exercisesForRoutines(ids: weekRoutines.map(\.id))) ?? []
        let byRoutine = Dictionary(grouping: rows, by: \.routineID)

        // THE CATALOG IS FETCHED ONLY WHEN IT WILL BE READ. It is ~1,300
        // paged rows on every book() and every build(), and it is looked up
        // only through `routineExercises` — so with no routines this week,
        // neither consumer has anything to resolve and the fetch is pure
        // waste. That covers the case the review named: rule 3 answering
        // `days` for an athlete with an unbooked week.
        //
        // NOT skipped merely because the titration has rows, which was the
        // other option offered: `muscleSetParams`' routines fallback is not
        // the only consumer — `isMostlyCardio` reads the catalog too, and
        // skipping on a non-empty `volume_targets` would silently stop a
        // cardio-flavoured week from being detected as one.
        let targets = await volumeTargets
        let catalog = weekRoutines.isEmpty ? [:] : await catalogByID()

        return WeeklyGoalDetector.detect(
            userID: userID,
            enrollment: await enrollment,
            weekRoutines: weekRoutines,
            routineExercises: byRoutine,
            catalog: catalog,
            trainingProfile: await trainingProfile,
            volumeTargets: targets,
            effectiveWeeklyGoal: await weeklyGoal,
            weekStart: weekStart,
            unit: unit,
            now: now,
            calendar: calendar)
    }

    /// What Coach WOULD set, for the Coach tile's line. Writes nothing, ever
    /// — this is the whole of owner answer 3's "propose" half: when the
    /// athlete has set this week's goal themselves, Coach's only recourse is
    /// a sentence they can accept in the editor.
    ///
    /// A named path rather than a call to `detect` at the tile, so that
    /// "Coach proposes" is greppable and a future write can never be added
    /// to it by accident.
    func propose(weekStart: String) async -> WeeklyGoal? {
        await detect(weekStart: weekStart)
    }

    /// COACH'S WRITE PATH (task A11). Detects this week's goal and persists
    /// it only when `WeeklyGoalWriteRule` allows — no row, or a row Coach
    /// itself wrote. A `source = user` row is left exactly as it is.
    ///
    /// Returns the goal now in effect for the week (the athlete's, if theirs
    /// stood), or nil when nothing could be read or derived. Best-effort
    /// like every other Coach write: it never throws and never blocks the
    /// booking or the build that called it.
    @discardableResult
    func writeDetectedGoal(weekStart: String) async -> WeeklyGoal? {
        let existing = await goal(weekStart: weekStart)
        guard let detected = await detect(weekStart: weekStart) else { return existing }
        guard WeeklyGoalWriteRule.shouldOverwrite(existing: existing,
                                                  detected: detected) else {
            AppLogger.db.info("weekly goal left alone for \(weekStart, privacy: .public) — the athlete set it")
            return existing
        }
        await upsert(detected)
        return detected
    }

    // MARK: - Progress

    /// Only what THIS kind needs is fetched. A `days` goal has no business
    /// paging the 1,300-row exercise catalog, and Home's refresh is a budget
    /// the strip shares with eight other reads.
    func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            return WeeklyGoalProgress()
        }
        let calendar = Calendar.current
        let now = Date()
        let weekStart = WeekMath.startOfWeek(now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }

        switch goal.kind {
        case .muscleSets:
            async let logs = weekSetLogs(userID: userID, since: weekStart,
                                         until: weekEnd)
            async let catalog = catalogByID()
            return WeeklyGoalProgressMath.muscleSetsProgress(
                goal: goal, logs: await logs, catalog: await catalog,
                now: now, calendar: calendar)

        case .days:
            async let sessions = weekSessions(userID: userID)
            async let weeklyGoal = effectiveWeeklyGoal(userID: userID)
            return WeeklyGoalProgressMath.daysProgress(
                goal: goal, sessions: await sessions,
                effectiveWeeklyGoal: await weeklyGoal,
                now: now, calendar: calendar)

        case .lift:
            guard let exerciseID = goal.params.exerciseID else {
                return WeeklyGoalProgressMath.liftProgress(
                    goal: goal, blockLogs: [], blockStartLbs: nil, unit: unit,
                    now: now, calendar: calendar)
            }
            async let enrollment = try? await ProgramRepository.active()
            async let history = (try? await SessionRepository.exerciseHistory(
                userID: userID, exerciseID: exerciseID, limit: 500)) ?? []
            async let exercise = try? await ExerciseRepository.fetch(id: exerciseID)

            let block = await enrollment
            let allLogs = await history
            let liftName = await exercise
            // The BLOCK's logs, not the week's: an e1RM is a block-long fact.
            // With no active block the whole history is the window, which is
            // the honest reading of "since you started chasing this".
            let blockLogs = allLogs.filter { log in
                guard let block else { return true }
                return log.loggedAt >= block.startedOn
            }
            return WeeklyGoalProgressMath.liftProgress(
                goal: goal, blockLogs: blockLogs,
                blockStartLbs: block?.baselineValue(for: exerciseID),
                unit: unit,
                exerciseName: liftName?.name ?? "",
                now: now, calendar: calendar)

        case .sessionsOfType:
            async let sessions = weekSessions(userID: userID)
            async let catalog = catalogByID()
            async let tags = HealthKitBridge.workoutTags(from: weekStart, to: weekEnd)
            async let needsConnecting = HealthKitBridge.weeklyGoalHealthNeedsConnecting()
            let loaded = await sessions
            let routineIDs = Array(Set(loaded.compactMap(\.routineID)))
            async let routines = routinesByID(userID: userID)
            let rows = (try? await RoutineRepository
                .exercisesForRoutines(ids: routineIDs)) ?? []
            return WeeklyGoalProgressMath.sessionsOfTypeProgress(
                goal: goal, sessions: loaded, routines: await routines,
                routineExercises: Dictionary(grouping: rows, by: \.routineID),
                catalog: await catalog,
                healthWorkouts: await tags,
                healthNeedsConnecting: await needsConnecting,
                now: now, calendar: calendar)

        case .distance:
            // The read AND the "have we ever asked" check, together: a
            // permission never requested returns 0 metres, and 0 mi must not
            // be how the strip says "Health is not connected".
            async let metres = HealthKitBridge.distanceMeters(
                activity: goal.params.activity ?? "", from: weekStart, to: weekEnd)
            async let needsConnecting = HealthKitBridge.weeklyGoalHealthNeedsConnecting()
            return WeeklyGoalProgressMath.distanceProgress(
                goal: goal, metres: await metres, unit: unit,
                healthNeedsConnecting: await needsConnecting,
                now: now, calendar: calendar)
        }
    }

    // MARK: - The fetches

    /// This week's set logs, PENALTY EXCLUDED AND FAILED KEPT.
    ///
    /// Deliberately not `SessionRepository.recentSetLogs(userID:since:)`,
    /// which filters `is_failed = false` at the query. That is right for the
    /// volume chart it backs and wrong here: a failed triple completed two
    /// reps and credits a full set (`SetLog.completedReps`), so filtering it
    /// server-side would silently undercount every week that contained one.
    /// `exerciseHistory` above takes the same position and says so in its own
    /// comment.
    ///
    /// BOUNDED AT BOTH ENDS AND EXPLICITLY LIMITED. `gte` alone leaned on
    /// "no future logs exist" for its ceiling and on PostgREST's default
    /// max-rows for its size — so a heavy week could silently truncate and
    /// undercount the tally with no signal at all. 2,000 is far above any
    /// real week (a 3-hour session logs perhaps 40 sets) and low enough to
    /// stay one page.
    private func weekSetLogs(userID: UUID, since: Date, until: Date) async -> [SetLog] {
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
                .limit(2000)
                .execute().value
            return rows
        } catch {
            AppLogger.db.error("weekly goal set_logs read failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Completed AND scheduled sessions — `daysProgress` needs both: the
    /// completed ones fill a chip, the scheduled ones mark it booked.
    private func weekSessions(userID: UUID) async -> [WorkoutSession] {
        async let history = (try? await SessionRepository.history(userID: userID,
                                                                  limit: 50)) ?? []
        async let upcoming = (try? await SessionRepository.upcoming(limit: 50)) ?? []
        let completed = await history
        let booked = await upcoming
        return completed + booked
    }

    private func catalogByID() async -> [UUID: Exercise] {
        let all = (try? await ExerciseRepository.fetchAll()) ?? []
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// EVERY routine the athlete owns — the library, and named as such.
    ///
    /// It used to be called `weekRoutines` and handed straight to the
    /// detector, which is how a five-routine library became a week's targets.
    /// `WeeklyGoalDetector.routinesForWeek(library:sessions:)` is what
    /// narrows it now; this function's only job is the fetch.
    private func routineLibrary(userID: UUID) async -> [Routine] {
        (try? await RoutineRepository.fetchAll(ownerID: userID)) ?? []
    }

    /// The library keyed by id, for looking a session's routine name up.
    /// `sessionsOfType` wants the NAME of whatever routine a session ran,
    /// including one no longer scheduled, so this one is deliberately not
    /// narrowed to the week.
    private func routinesByID(userID: UUID) async -> [UUID: Routine] {
        let all = await routineLibrary(userID: userID)
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The anti-goalpost weekly days number, with the app's own default when
    /// there is no profile to read (`HomeView.weeklyGoalWidget` uses the same
    /// 3).
    private func effectiveWeeklyGoal(userID: UUID) async -> Int {
        let profile = try? await ProfileRepository.fetch(userID: userID)
        return profile?.effectiveWeeklyGoal ?? 3
    }
}
