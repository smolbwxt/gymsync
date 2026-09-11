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
// THIS IS THE DEFAULT BINDING (I1's swap). `StubWeeklyGoalRepository` stays
// for the catalog, which constructs it explicitly.

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
    /// `weekly_goals.goal_id` (task A2) — the COLUMN half of the ladder link.
    /// `params.goalID` is the other half; see `model` for why the column is the
    /// authority on READ.
    let goalID: UUID?
    /// `weekly_goals.rung_index`. Column-only: `WeeklyGoalParams` has no mirror
    /// for it, so nothing in `WeeklyGoal` carries it and only the writer sets it.
    let rungIndex: Int?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case weekStart = "week_start"
        case kind
        case params
        case source
        case goalID = "goal_id"
        case rungIndex = "rung_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// `rungIndex` is a WRITE-SIDE argument because `WeeklyGoal` cannot carry it
    /// — that struct is the frozen Task 0 shape and has no field per column.
    /// `goal_id` needs no such argument: `params.goalID` already holds it, and
    /// writing the column FROM the param here is what makes the two halves one
    /// value written twice, exactly as A2's own COMMENT promises.
    ///
    /// Both are optional and both encode only when set, so `save`'s ordinary
    /// upsert — which passes no rung index and may carry no goal id — omits them
    /// and leaves whatever the row already had.
    init(_ goal: WeeklyGoal, rungIndex: Int? = nil) {
        userID = goal.userID
        weekStart = goal.weekStartString
        kind = goal.kind.rawValue
        params = goal.params
        source = goal.source.rawValue
        goalID = goal.params.goalID
        self.rungIndex = rungIndex
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
                          params: LiveWeeklyGoalRepository.reconcileLadderLink(
                              params: params, goalIDColumn: goalID),
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

    /// The BLOCK's answer for a week, asked before this repository detects one
    /// of its own (plan item 6; final review F1).
    ///
    /// `LiveBlockGoalRepository` in production — the default is the wiring, and
    /// `LadderDetectionSeamTests` pins it, because a default that silently
    /// resolved to something inert is precisely how item 6 came to be ruled and
    /// then not built.
    var ladderSource: any LadderWeekSource = LiveBlockGoalRepository()

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
    ///
    /// **INTERNAL ONLY BECAUSE `WeeklyGoalLiveRepositoryTests` NEEDS IT** for
    /// teardown (final review finding 10; `upsert` went `private` in the same
    /// pass, having no such caller). It is NOT a production door: nothing
    /// outside this file may write or delete a `weekly_goals` row except
    /// through `save` (the athlete's own, always `source = user`),
    /// `clearToCoach`, `writeDetectedGoal` or `detectIfMissing` — and the
    /// last two consult `WeeklyGoalWriteRule` first, which is the whole of
    /// owner answer 3. A future caller that deletes a row here to write over
    /// it would route around that rule without ever mentioning it.
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

    /// THE LADDER'S ONE DOOR INTO `weekly_goals` (task A11).
    ///
    /// `LiveBlockGoalRepository.materialiseRung` has ALREADY consulted
    /// `WeeklyGoalWriteRule.shouldOverwrite` against the existing row before
    /// calling this — that check belongs to the caller because the caller is the
    /// one that knows what it derived, and this method deliberately does not
    /// repeat it. Nothing else may call it.
    ///
    /// It exists at all because `upsert` below is `private` on purpose: the
    /// write rule's whole premise is that one function consults `source` before
    /// any Coach write, and an internal `upsert` would let a future caller put a
    /// `coach` row over a `user` one without ever passing through it. One named
    /// door, with the rule named in its own doc comment, is the seam that keeps
    /// that true while still letting the ladder materialise.
    @discardableResult
    func writeMaterialisedRung(_ goal: WeeklyGoal, rungIndex: Int? = nil) async -> Bool {
        await upsert(goal, rungIndex: rungIndex)
    }

    /// **THE COLUMN IS THE AUTHORITY ON READ** (Stream B review, cross-stream
    /// requirement).
    ///
    /// The ladder link lives in two places: `weekly_goals.goal_id`, which the
    /// foreign key and its `ON DELETE SET NULL` need, and `params.goalID`, which
    /// is what survives into `WeeklyGoal` — a struct with no field per column.
    /// The client asks `params.goalID` whether a week belongs to a ladder
    /// (`isLadderWeek`), and JSON does not participate in `ON DELETE SET NULL`.
    ///
    /// So when the goal is deleted the column goes NULL and the param does not,
    /// and without this the week would stay frozen as a ladder week forever —
    /// pointing at a goal that no longer exists. Clearing the param when the
    /// column is null makes it a plain weekly goal again, which is exactly what
    /// spec §4 says a `goal_id = null` row IS.
    ///
    /// ONE DIRECTION ONLY. A non-null column does NOT write the param back: an
    /// athlete who saves a standalone goal over a ladder week has dropped the
    /// link on purpose, and resurrecting it from a column they never touched
    /// would undo their own edit.
    static func reconcileLadderLink(params: WeeklyGoalParams,
                                    goalIDColumn: UUID?) -> WeeklyGoalParams {
        guard goalIDColumn == nil else { return params }
        var cleared = params
        cleared.goalID = nil
        return cleared
    }

    /// Writes a row exactly as given. Shared by `save` and by A11's Coach
    /// write path, which has already decided it is allowed to write.
    ///
    /// **PRIVATE** (final review finding 10). `WeeklyGoalWriteRule`'s whole
    /// premise is that one function consults `source` before any Coach write;
    /// an internal `upsert` let a future caller put a `coach` row over a
    /// `user` one without ever passing through it. No test calls it, so the
    /// seam costs nothing.
    @discardableResult
    private func upsert(_ goal: WeeklyGoal, rungIndex: Int? = nil) async -> Bool {
        do {
            try await client
                .from("weekly_goals")
                .upsert(WeeklyGoalRow(goal, rungIndex: rungIndex),
                        onConflict: "user_id,week_start")
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
    ///
    /// **`now` IS THE WEEK BEING DETECTED, NOT TODAY** (final review finding
    /// 3). `weekStart` used to be only the row key: everything that decides
    /// what the goal IS — `routinesForWeek`, the detector's own `now:` — read
    /// `Date()`. `WeekBooker.book` calls `writeDetectedGoal` with a FUTURE
    /// week (`BlockCalendarView` books forward), so week N+1's row was
    /// stamped with week N's routines and week N's cardio judgment, and
    /// nothing ever re-derived it. Parsing the week back out of its own key
    /// is what makes the row about the week it belongs to.
    ///
    /// The FETCHES are not week-scoped and do not need to be:
    /// `SessionRepository.upcoming()` is ordered soonest-first with no
    /// horizon, so a week booked three weeks out is in the same page as this
    /// one, and `weekRoutineIDs` is what narrows either to the right seven
    /// days. `Date()` remains the fallback for a `weekStart` that will not
    /// parse — a value this app never writes.
    func detect(weekStart: String) async -> WeeklyGoal? {
        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }
        let calendar = Calendar.current
        let now = WeekMath.date(fromWeekStartString: weekStart, calendar: calendar) ?? Date()

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
        return await writeDetected(weekStart: weekStart, existing: existing)
    }

    /// DETECT ON READ (final review finding 1). Home's fetch calls this when
    /// `goal(weekStart:)` came back nil, and it is the reason a lifter with
    /// no block and no booked week now sees a goal at all: before it,
    /// `writeDetectedGoal`'s only callers were `WeekBooker.book` and
    /// `ProgramBuilder.build`, so the design's rule 3 ("never empty") had no
    /// production trigger and the strip's invitation was the permanent state
    /// for most accounts.
    ///
    /// THE ROW IS RE-READ HERE rather than taken from the caller's nil, and
    /// that read is the point: between Home's fetch and this call a booking
    /// or a build may have written the very row this is about to derive, and
    /// `WeeklyGoalWriteRule` can only protect a `user` row it has been shown.
    /// It costs one extra round trip on a week with no goal, and exactly
    /// nothing on every week that has one — which, after the first successful
    /// write, is every week.
    ///
    /// Detection runs at most once per fetch: this makes one attempt and
    /// returns, so a week that cannot be written (offline) renders the
    /// invitation and is retried on the next refresh rather than looped on.
    /// **AND THE LADDER IS ASKED FIRST** (plan item 6's controller ruling;
    /// final review F1). See `weekInEffect` below for the whole of the rule
    /// and why it is stated there rather than here.
    func detectIfMissing(weekStart: String) async -> WeeklyGoal? {
        let existing = await goal(weekStart: weekStart)
        return await Self.weekInEffect(
            existing: existing,
            weekStart: weekStart,
            currentWeekStart: WeekMath.weekStartString(),
            ladder: { await ladderSource.ladderWeek(weekStart: weekStart) },
            detect: { await writeDetected(weekStart: weekStart, existing: existing) })
    }

    /// PLAN ITEM 6, THE WHOLE OF IT, with no Supabase in it — so the ruling's
    /// own week-2 world is a unit test (`LadderDetectionSeamTests`).
    ///
    /// > "when `detectIfMissing` runs for a user with an active `BlockGoal`, it
    /// > calls `reLadder` from actuals and then `materialiseRung` for the
    /// > current week, and returns that row — so a new week re-ladders itself
    /// > on its first Home load"
    ///
    /// THE LADDER IS ASKED BEFORE DETECTION, not after, and that ordering is
    /// the fix rather than a preference. Detection writes a goal with **no
    /// `goalID`** (`detect` has no idea a block exists), and a row with no
    /// `goalID` is a standalone weekly goal by spec §4 — so from week 2 of
    /// every block the strip lost its `WEEK 3 OF 8` kicker and the strip's tap
    /// went to the editor instead of the ladder. Asking second would have
    /// written that row first and then had to overwrite it.
    ///
    /// `shouldDetectOnRead` STILL GATES BOTH. A week that already has a row is
    /// not the ladder's to fill any more than it is detection's — the rung for
    /// a week the athlete has spoken for is `materialiseRung`'s to decline, and
    /// it does, through `WeeklyGoalWriteRule` — and a week that is not the
    /// current one is never written from a read at all.
    static func weekInEffect(existing: WeeklyGoal?,
                             weekStart: String,
                             currentWeekStart: String,
                             ladder: () async -> WeeklyGoal?,
                             detect: () async -> WeeklyGoal?) async -> WeeklyGoal? {
        guard WeeklyGoalWriteRule.shouldDetectOnRead(
                existing: existing,
                weekStart: weekStart,
                currentWeekStart: currentWeekStart) else { return existing }
        if let rung = await ladder() { return rung }
        return await detect()
    }

    /// The gated write both paths share, so "Coach may not overwrite you"
    /// has one implementation rather than two that can drift.
    private func writeDetected(weekStart: String,
                               existing: WeeklyGoal?) async -> WeeklyGoal? {
        // A LADDER WEEK IS NOT DETECTION'S TO FILL (task B6). Asked FIRST, and
        // before the derivation, so a booking inside an active block costs
        // neither a wrong write nor the six reads `detect` would have made to
        // arrive at one.
        guard !WeeklyGoalWriteRule.isLadderWeek(existing) else { return existing }
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

    /// The kind's own progress, plus the BLOCK CONTEXT when this row belongs to
    /// a ladder (task A14, spec §6).
    ///
    /// ONE EXTRA READ, and only for a row that HAS a `goalID`: a standalone
    /// weekly goal — every row written before goal-first programming, and every
    /// row an athlete sets themselves outside a block — pays exactly nothing.
    ///
    /// The frozen Home frames are unaffected (global constraint 8): they build
    /// their `WeeklyGoalProgress` from a literal fixture and never reach this
    /// type at all.
    func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress {
        var progress = await rawProgress(for: goal)
        guard let goalID = goal.params.goalID,
              let context = await blockContext(goalID: goalID,
                                               weekStart: goal.weekStartString)
        else { return progress }
        let now = Date()
        progress.kicker = WeeklyGoalProgressMath.blockKicker(
            source: goal.source, met: progress.met,
            daysLeft: WeekMath.daysRemaining(in: now, from: now, calendar: .current),
            weekNumber: context.weekNumber, weekCount: context.weekCount)
        return progress
    }

    /// Which rung of which ladder this week is — the two numbers `WEEK 3 OF 8`
    /// needs, in one query.
    ///
    /// nil when the ladder has no rung for this week, which is the honest answer
    /// for a row whose block was re-laddered shorter: the kicker then falls back
    /// to `THIS WEEK` rather than naming a week the ladder does not have.
    private func blockContext(goalID: UUID,
                              weekStart: String) async -> (weekNumber: Int,
                                                           weekCount: Int)? {
        struct RungKeyRow: Decodable {
            let weekIndex: Int
            /// A DATE column, so a raw String — never through the timestamp
            /// decoder (`ProgramEnrollment.swift:34-38`).
            let weekStart: String
            enum CodingKeys: String, CodingKey {
                case weekIndex = "week_index"
                case weekStart = "week_start"
            }
        }
        do {
            let rows: [RungKeyRow] = try await client
                .from("block_goal_rungs")
                .select("week_index, week_start")
                .eq("goal_id", value: goalID)
                .order("week_index", ascending: true)
                .execute().value
            guard !rows.isEmpty,
                  let match = rows.first(where: { $0.weekStart == weekStart })
            else { return nil }
            return (match.weekIndex + 1, rows.count)
        } catch {
            AppLogger.db.error("block_goal_rungs context read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Only what THIS kind needs is fetched. A `days` goal has no business
    /// paging the 1,300-row exercise catalog, and Home's refresh is a budget
    /// the strip shares with eight other reads.
    private func rawProgress(for goal: WeeklyGoal) async -> WeeklyGoalProgress {
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

        // ── goal-first programming phase 1 ────────────────────────────────
        //
        // WIRED IN TASK A11, exactly as Task 0's own comment said they would
        // be: "each arm still routes through the kind's own pure function, so
        // A5 fills in an argument rather than inventing an arm." A5 and A6
        // shipped those functions, and A2 widened `weekly_goals.kind` so a row
        // of one of these kinds is now reachable — at which point leaving the
        // stubbed zeros would print `0 / 6 stretches` at an athlete who had
        // stretched, which is worse than the empty state it replaced.
        //
        // ONLY WHAT THE KIND NEEDS IS FETCHED, the same discipline the five
        // arms above follow.
        case .recovery:
            async let recoveryLogs = weekSetLogs(userID: userID, since: weekStart,
                                                 until: weekEnd)
            async let recoveryCatalog = catalogByID()
            async let recoverySessions = weekSessions(userID: userID)
            async let recoveryRoutines = routinesByID(userID: userID)
            async let recoveryHealthMinutes = HealthKitBridge.lissMinutes(from: weekStart,
                                                                          to: weekEnd)
            async let recoveryTags = HealthKitBridge.workoutTags(from: weekStart,
                                                                 to: weekEnd)
            async let recoveryNeedsConnecting =
                HealthKitBridge.weeklyGoalHealthNeedsConnecting()

            let recoveryLibrary = await recoveryRoutines
            let recoveryRows = (try? await RoutineRepository
                .exercisesForRoutines(ids: Array(recoveryLibrary.keys))) ?? []
            let recoveryCatalogByID = await recoveryCatalog
            // The week's COMPLETED sessions only: `weekSessions` deliberately
            // also returns booked ones for `daysProgress`, and a session that
            // has not happened has moved nobody's minutes.
            let recoveryCompleted = (await recoverySessions).filter { session in
                guard let done = session.completedAt else { return false }
                return done >= weekStart && done < weekEnd
            }
            return WeeklyGoalProgressMath.recoveryProgress(
                goal: goal,
                stretchingExercisesDone: BlockGoalMetricMath.stretchingExerciseCount(
                    logs: await recoveryLogs, catalog: recoveryCatalogByID),
                lissMinutesDone: BlockGoalMetricMath.lissMinutes(
                    healthMinutes: await recoveryHealthMinutes,
                    sessions: recoveryCompleted, routines: recoveryLibrary,
                    routineExercises: Dictionary(grouping: recoveryRows, by: \.routineID),
                    catalog: recoveryCatalogByID, healthWorkouts: await recoveryTags),
                healthNeedsConnecting: await recoveryNeedsConnecting,
                now: now, calendar: calendar)

        case .bodyWeight:
            async let bodyWeightBlock = try? await ProgramRepository.active()
            let bodyWeightLogs = (try? await BodyWeightLogRepository
                .recent(userID: userID)) ?? []
            // The reading AT THE BLOCK'S START is the "from" of the strip's
            // "185 → 178", and it is the last weigh-in on or before that day —
            // not the oldest row in the table, which could be years old.
            let bodyWeightStart = (await bodyWeightBlock)?.startedOn
            let atBlockStart = bodyWeightStart.map { start in
                bodyWeightLogs.filter { $0.loggedAt <= start }
            } ?? []
            return WeeklyGoalProgressMath.bodyWeightProgress(
                goal: goal,
                currentLbs: BlockGoalMetricMath.currentBodyWeightPounds(logs: bodyWeightLogs),
                blockStartLbs: BlockGoalMetricMath.currentBodyWeightPounds(logs: atBlockStart),
                unit: unit, now: now, calendar: calendar)

        case .volume:
            let volumeLogs = await weekSetLogs(userID: userID, since: weekStart,
                                               until: weekEnd)
            return WeeklyGoalProgressMath.volumeProgress(
                goal: goal,
                volumeLbs: BlockGoalMetricMath.volumePounds(logs: volumeLogs),
                unit: unit, now: now, calendar: calendar)

        case .benchmark:
            // The routine's NAME is the benchmark's subject chip, and it is
            // readable now — the library is already keyed by id for
            // `sessionsOfType`, so this costs the fetch that arm costs and
            // nothing new.
            guard let benchmarkRoutineID = goal.params.routineID else {
                return WeeklyGoalProgressMath.benchmarkProgress(
                    goal: goal, bestSeconds: nil, startSeconds: nil,
                    routineName: "", now: now, calendar: calendar)
            }
            async let benchmarkLibrary = routinesByID(userID: userID)
            async let benchmarkHistory = (try? await SessionRepository
                .history(userID: userID, limit: 200)) ?? []
            let benchmarkName = (await benchmarkLibrary)[benchmarkRoutineID]?.name ?? ""
            let benchmarkSessions = await benchmarkHistory
            // THE WHOLE HISTORY, not the week: a benchmark is a record, and
            // "your best" does not reset on Sunday. `startSeconds` is the
            // EARLIEST finished run, so the strip can show the gap closed.
            let firstRun = benchmarkSessions
                .filter { $0.routineID == benchmarkRoutineID }
                .compactMap { session -> (Date, Int)? in
                    guard let started = session.startedAt,
                          let completed = session.completedAt,
                          completed > started else { return nil }
                    return (completed, Int(completed.timeIntervalSince(started).rounded()))
                }
                .min { $0.0 < $1.0 }?.1
            return WeeklyGoalProgressMath.benchmarkProgress(
                goal: goal,
                bestSeconds: BlockGoalMetricMath.bestBenchmarkSeconds(
                    sessions: benchmarkSessions, routineID: benchmarkRoutineID),
                startSeconds: firstRun,
                routineName: benchmarkName, now: now, calendar: calendar)
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
