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

    /// `derivedAt` IS WRITTEN, not defaulted (fix round 1, finding F7).
    ///
    /// The column is `NOT NULL DEFAULT now()` with no touch trigger, so an
    /// omitted value means `ON CONFLICT DO UPDATE` leaves the original insert
    /// time in place forever — while `LadderMath.reLadder` correctly stamps the
    /// new time on the value it returns. The two disagreed the moment the
    /// returned ladder was dropped and re-read, which makes "when was this
    /// ladder last derived" unanswerable on the read side.
    init(_ rung: LadderRung, goalID: UUID, derivedAt: Date) {
        self.goalID = goalID
        weekIndex = rung.weekIndex
        weekStart = rung.weekStartString
        target = rung.target
        status = rung.status.rawValue
        self.derivedAt = derivedAt
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

    /// The goals driving a set of blocks — **the ledger's read** (final review
    /// F3), and the one the plan describes: `.in("enrollment_id", …)`.
    ///
    /// ONE ROUND TRIP for every row on screen, and it answers for blocks that
    /// have ENDED, which `activeGoal()` cannot by definition. `UNIQUE
    /// (enrollment_id)` means one goal per key, so the dictionary cannot lose a
    /// row to a collision.
    ///
    /// An empty `enrollmentIDs` short-circuits rather than sending
    /// `in.()`, which PostgREST reads as a one-element list containing the
    /// empty string and answers with a 400 on a uuid column.
    func goals(enrollmentIDs: [UUID]) async -> [UUID: BlockGoal] {
        guard !enrollmentIDs.isEmpty else { return [:] }
        let calendar = Calendar.current
        do {
            let rows: [BlockGoalRow] = try await client
                .from("block_goals")
                .select()
                .in("enrollment_id", values: enrollmentIDs.map(\.uuidString))
                .execute().value
            return Dictionary(rows.compactMap { $0.model(calendar: calendar) }
                                  .map { ($0.enrollmentID, $0) },
                              uniquingKeysWith: { first, _ in first })
        } catch {
            AppLogger.db.error("block_goals batch read failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
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

    /// The enrollment a goal actually drives.
    ///
    /// `BlockGoal.enrollmentID` names it; `ProgramRepository.active()` names
    /// whatever the athlete is training NOW, and the two are the same block only
    /// while the block is current. Every read keyed on a goal id has to use this
    /// one — the ladder page for a finished block is a shipped surface
    /// (spec §7, Stream D's ledger).
    ///
    /// Fetched by id rather than through `ProgramRepository.history()`, which
    /// pages every enrollment the athlete has ever had to find one row.
    private func enrollment(id: UUID) async -> ProgramEnrollment? {
        do {
            let rows: [ProgramEnrollment] = try await client
                .from("program_enrollments")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute().value
            return rows.first
        } catch {
            AppLogger.db.error("program_enrollments read failed: \(error.localizedDescription, privacy: .public)")
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

    /// Everything the ladder page renders, already worded (task A12).
    ///
    /// The wording is `LadderMath.page`'s, never this file's: one place chooses
    /// the ladder's words, so the page, the schedule card and Coach's line
    /// cannot spell one rung three ways.
    ///
    /// The block's own facts come from the ENROLLMENT'S TEMPLATE — its deload
    /// weeks and its per-week notes — rather than from a re-run of the
    /// generator, for the reason `LadderReadout`'s template door states in full.
    func page(goalID: UUID) async -> LadderPageModel? {
        guard let goal = await goal(id: goalID),
              let ladder = await ladder(goalID: goalID) else { return nil }
        let calendar = Calendar.current
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }
        // THE GOAL'S OWN BLOCK, never "the active block". `page(goalID:)` is
        // keyed on a GOAL, and spec §7 renders finished blocks' ladders in the
        // ledger — so reading the active enrollment attached another block's
        // deloads and notes, and attached NOTHING at all once the athlete had
        // no active block.
        let template = await enrollment(id: goal.enrollmentID)?.template

        var liftName = ""
        if let exerciseID = goal.target.exerciseID {
            liftName = (try? await ExerciseRepository.fetch(id: exerciseID))?.name ?? ""
        }

        // ONE `rungSets` FOR THE WHOLE LADDER, because that is the signature the
        // plan fixes. The block's weeks can each prescribe their own set count
        // (`march-to-1rm` runs 3 × 5 down to 2 × 1), so this passes the first
        // week's and a per-week spelling is an I1 question, not a silent
        // approximation: recorded rather than papered over.
        //
        // A HELD GOAL NEVER NEEDS A CEILING (r2 open item 2): `LadderMath.page`
        // returns "Held for the block." on its own held-preset guard before
        // `rampCeiling` is ever read, so asking for one here was a wasted
        // `measuredByWeek` read (a `blockSessions` fetch for a Consistency
        // goal) on every held ladder's page load.
        //
        // KEYED ON THE PRESET, NOT ON `byDate != nil` (I1 audit, ruling 14):
        // Consistency's `byDate` now carries the derived block length
        // (Stream C round 2), not a deadline, so a non-nil `byDate` no
        // longer means the ceiling is worth asking for — reading it that way
        // would pay the wasted read on every Consistency ladder again. A nil
        // `preset` (Coach-guided, phase 2) falls back to the plain nil check.
        let held = goal.preset?.asksForDate == false
        let ceiling = held
            ? nil
            : await rampCeiling(goal: goal, ladder: ladder, calendar: calendar)
        return LadderMath.page(
            goal: goal, ladder: ladder, liftName: liftName,
            rungSets: template?.weeks.first?.sets ?? 3,
            notesByWeek: LadderReadout.notesByWeek(template: template),
            deloadWeeks: LadderReadout.constraints(template: template,
                                                   unit: unit).deloadWeeks,
            unit: unit,
            rampCeiling: ceiling,
            now: Date(), calendar: calendar)
    }

    /// Where a forced ramp actually arrives, or nil when it reaches (finding F4).
    ///
    /// `LadderMath.rampCeiling` decides; this only fetches what it decides from.
    /// The question is about the weeks that REMAIN — Coach proposes a date move
    /// on the ladder as it stands now, not as it stood when the block began — so
    /// the span is the `ahead` and `current` rungs and the starting point is
    /// today's measured reading, the same pair `reLadder` works from.
    private func rampCeiling(goal: BlockGoal, ladder: Ladder,
                             calendar: Calendar) async -> GoalTarget? {
        // Only four metrics can be forced short; the rest answer from their last
        // rung and this whole read is waste for them.
        switch goal.metric {
        case .weeklyDistance, .trainingDaysPerWeek, .sessionsOfTypePerWeek,
             .cumulativeVolume:
            break
        case .liftOneRepMax, .liftRepsAtLoad, .weeklyMuscleSets, .bodyWeight,
             .benchmarkTime, .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            return nil
        }
        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }

        let remaining = ladder.rungs.filter {
            $0.status == .ahead || $0.status == .current
        }.count
        guard remaining > 0 else { return nil }

        let currentWeek = WeekMath.weekStartString(Date(), calendar: calendar)
        let measured = await measuredByWeek(goal: goal, rungs: ladder.rungs,
                                            userID: userID, calendar: calendar)
        let best = goal.metric == .cumulativeVolume
            ? await bestRecentWeekVolumeLbs(userID: userID, calendar: calendar)
            : nil

        return LadderMath.rampCeiling(
            metric: goal.metric,
            current: measured[currentWeek] ?? GoalTarget(),
            milestone: goal.target, weeks: remaining,
            bestRecentWeekVolumeLbs: best)
    }

    /// The heaviest single week the athlete has actually put in lately — the
    /// last NINE weeks of set logs, bucketed by week and maxed: the eight
    /// prior weeks plus the partial current week (r2 open item 4 — the code
    /// and this comment used to disagree on the count).
    ///
    /// Eight PRIOR weeks because that is a block's own length: a ceiling
    /// drawn from a longer window would let a peak from two blocks ago vouch
    /// for a plan the athlete is nowhere near today, and a shorter one would
    /// let a single deload week declare a reasonable milestone unreachable.
    /// The partial ninth (this week, still in progress) can only LOWER the
    /// max it is bucketed alongside, never raise it, so including it is safe
    /// rather than a second window to reason about.
    ///
    /// nil when there is no history, which `rampCeiling` reads as "nothing to
    /// judge against" and gives the ladder the benefit of the doubt.
    private func bestRecentWeekVolumeLbs(userID: UUID,
                                         calendar: Calendar) async -> Double? {
        let now = Date()
        let thisWeek = WeekMath.startOfWeek(now, calendar: calendar)
        guard let since = calendar.date(byAdding: .day, value: -56, to: thisWeek),
              let until = calendar.date(byAdding: .day, value: 7, to: thisWeek)
        else { return nil }

        let logs = await setLogs(userID: userID, since: since, until: until)
        guard !logs.isEmpty else { return nil }

        var byWeek: [String: [SetLog]] = [:]
        for log in logs {
            byWeek[WeekMath.weekStartString(log.loggedAt, calendar: calendar),
                   default: []].append(log)
        }
        let best = byWeek.values
            .map { BlockGoalMetricMath.volumePounds(logs: $0) }
            .max() ?? 0
        return best > 0 ? best : nil
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
        await upsertRungs(ladder.rungs, goalID: ladder.goalID,
                          derivedAt: ladder.derivedAt)
    }

    @discardableResult
    private func upsertRungs(_ rungs: [LadderRung], goalID: UUID,
                             derivedAt: Date) async -> Bool {
        guard !rungs.isEmpty else { return true }
        do {
            try await client
                .from("block_goal_rungs")
                .upsert(rungs.map { RungRow($0, goalID: goalID, derivedAt: derivedAt) },
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

        // The goal's own block, for the reason `page(goalID:)` gives.
        let template = await enrollment(id: goal.enrollmentID)?.template
        // `LadderMath` decides, this only fetches and writes — including the
        // choice of WHICH DOOR a metric re-ladders through (final review F1).
        let fresh = LadderMath.reLaddered(goal: goal, existing: stamped,
                                          template: template, measured: measured,
                                          unit: unit, now: now, calendar: calendar)

        let changed = zip(existing.rungs, fresh.rungs)
            // `$0.0` / `$0.1`, not `$0` / `$1`: `filter`'s closure takes ONE
            // element and that element is the pair.
            .filter { $0.0 != $0.1 }
            .map(\.1)
        await upsertRungs(changed, goalID: goalID, derivedAt: now)
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
        guard let goal = await goal(id: goalID),
              let ladder = await ladder(goalID: goalID) else { return nil }
        return await materialiseRung(goal: goal, ladder: ladder, weekStart: weekStart)
    }

    /// The same write, for a caller that ALREADY holds the goal and the ladder
    /// (fix round 1, finding F5).
    ///
    /// `detectGoalIfMissing` re-laddered — reading both — and then called the
    /// id-keyed door, which read both again. Two round trips for rows already in
    /// hand, on Home's first load.
    @discardableResult
    func materialiseRung(goal: BlockGoal, ladder: Ladder,
                         weekStart: String) async -> WeeklyGoal? {
        guard let userID = await SupabaseService.shared.currentUserID(),
              let rung = LadderMath.rung(in: ladder, weekStart: weekStart),
              let derived = LadderMath.weeklyGoal(
                  from: rung, goal: goal, userID: userID, now: Date(),
                  // The week before this one, so a cumulative-volume rung
                  // materialises as the WEEK's share rather than the block's
                  // running total. nil for week one, and ignored by every other
                  // metric.
                  previousRung: ladder.rungs.first(where: { $0.weekIndex == rung.weekIndex - 1 }))
        else { return nil }

        let weekly = LiveWeeklyGoalRepository()
        let existing = await weekly.goal(weekStart: weekStart)
        guard WeeklyGoalWriteRule.shouldOverwrite(existing: existing,
                                                  detected: derived) else {
            AppLogger.db.info("rung left alone for \(weekStart, privacy: .public) — the athlete set that week")
            return existing
        }
        // The rung index goes to the COLUMN — `WeeklyGoalParams` has no mirror
        // for it, so this is the only place it is written.
        let written = await weekly.writeMaterialisedRung(derived,
                                                         rungIndex: rung.weekIndex)
        return written ? derived : existing
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
        guard await upsertRungs(ladder.rungs, goalID: goal.id,
                                derivedAt: ladder.derivedAt) else { return nil }
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
            // THE GOAL'S OWN BLOCK here too. At build time it happens to be the
            // active one, but keying the baseline read on anything other than
            // `goal.enrollmentID` is the same defect F3 names, waiting for the
            // first caller that derives a ladder for a block that is not current.
            guard let exerciseID = goal.target.exerciseID,
                  let block = await enrollment(id: goal.enrollmentID),
                  let baseline = block.baselineValue(for: exerciseID),
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
        // The closure's return type and the tuple's labels are BOTH spelled out.
        // A bare `(rung.weekStartString, start, end)` leans on Swift adding the
        // labels for you, which it does not reliably do inside a `compactMap`.
        let weeks: [(key: String, start: Date, end: Date)] = rungs.compactMap {
            rung -> (key: String, start: Date, end: Date)? in
            guard let start = WeekMath.date(fromWeekStartString: rung.weekStartString,
                                            calendar: calendar),
                  let end = calendar.date(byAdding: .day, value: 7, to: start)
            else { return nil }
            return (key: rung.weekStartString, start: start, end: end)
        }
        guard let first = weeks.first, let last = weeks.last else { return [:] }
        var out: [String: GoalTarget] = [:]

        switch goal.metric {
        case .liftOneRepMax, .liftRepsAtLoad:
            guard let exerciseID = goal.target.exerciseID else { return [:] }
            // BOUNDED BY THE BLOCK, not by a row count (fix round 1, finding
            // F8). `SessionRepository.exerciseHistory` takes the most recent 500
            // logs across all time; for a frequently-trained main on a long
            // block those 500 need not reach the block's start, and a rung with
            // no reading is one `statuses` marks `missed`. Every other arm here
            // already bounds its read by `first.start`/`last.end`.
            let logs = await exerciseLogs(userID: userID, exerciseID: exerciseID,
                                          since: first.start, until: last.end)
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
            // TONNAGE-TO-DATE, NOT THE WEEK'S. The rungs this is compared
            // against are cumulative (`CumulativeLadderRule`), so the reading
            // has to be on the same scale or `statuses` marks a perfectly good
            // week `missed`. The fetch already starts at the block's first
            // week, so the running total is tonnage since the block began.
            let logs = await setLogs(userID: userID, since: first.start, until: last.end)
            var running = 0.0
            for week in weeks {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                running += BlockGoalMetricMath.volumePounds(logs: inWeek)
                var target = GoalTarget()
                target.volumeLbs = running
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
            // ONE query for the block, not one per rung (finding F5). The tags
            // carry their own windows and `sessionCounts` overlap-matches them,
            // so handing every week the whole span is correct as well as cheaper.
            let tags = await HealthKitBridge.workoutTags(windows: windows(weeks))
            for week in weeks {
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
            // ONE query for the block (finding F5): eight rungs used to mean
            // eight HealthKit round trips on Home's first load.
            let metresByWeek = await HealthKitBridge.distanceMeters(
                activity: activity, windows: windows(weeks))
            for (week, metres) in zip(weeks, metresByWeek) {
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
            // TWO queries for the block, not two per rung (finding F5). An
            // eight-week Recovery block used to cost sixteen HealthKit round
            // trips, which is the part of this file that did not honour its own
            // "only what this metric needs is fetched" header.
            let minutesByWeek = await HealthKitBridge.lissMinutes(windows: windows(weeks))
            let tags = await HealthKitBridge.workoutTags(windows: windows(weeks))
            for (week, healthMinutes) in zip(weeks, minutesByWeek) {
                let inWeek = logs.filter { $0.loggedAt >= week.start && $0.loggedAt < week.end }
                let weekSessions = sessions.filter { session in
                    guard let completed = session.completedAt else { return false }
                    return completed >= week.start && completed < week.end
                }
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

    /// The rungs' windows, in the shape `HealthKitBridge`'s batch reads take.
    private func windows(_ weeks: [(key: String, start: Date, end: Date)])
        -> [(start: Date, end: Date)] {
        weeks.map { (start: $0.start, end: $0.end) }
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

    /// One exercise's logs inside the block's own window.
    ///
    /// PENALTY EXCLUDED AND FAILED KEPT, for the reason `setLogs` above gives in
    /// full: a failed triple completed two reps and credits a full set, so
    /// filtering `is_failed` server-side would silently undercount. The limit is
    /// a ceiling on one lift's logs across one block, which no real athlete
    /// approaches — it is there so the read cannot silently truncate on
    /// PostgREST's default max-rows.
    private func exerciseLogs(userID: UUID, exerciseID: UUID,
                              since: Date, until: Date) async -> [SetLog] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .gte("logged_at", value: formatter.string(from: since))
                .lt("logged_at", value: formatter.string(from: until))
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: true)
                .limit(2000)
                .execute().value
            return rows
        } catch {
            AppLogger.db.error("block goal exercise set_logs read failed: \(error.localizedDescription, privacy: .public)")
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

// MARK: - A13: blocks that predate goals (spec §5.4)

/// What A13 did for one week: the goal that now drives the block, and the
/// `weekly_goals` row its ladder materialised for that week.
///
/// `week` is nil when nothing was written — offline, no rung for this week, or
/// (the one that matters) the athlete's own row stood and
/// `WeeklyGoalWriteRule` left it alone. The caller then falls back to whatever
/// was already there rather than to a row this never wrote.
struct DetectedBlockWeek: Sendable {
    let goal: BlockGoal
    let week: WeeklyGoal?
}

extension LiveBlockGoalRepository: LadderWeekSource {

    /// **PLAN ITEM 6'S SEAM** (controller ruling, 2026-09-07; final review F1).
    ///
    /// Home's first load of a week calls `WeeklyGoalRepository.detectIfMissing`,
    /// which asks this before it detects anything of its own: an athlete with an
    /// active block gets that block's rung, re-laddered from actuals, and only
    /// an athlete without one falls through to plain detection.
    ///
    /// nil is the answer for "this athlete has no block goal to answer with",
    /// which is every account until they build one — and it is what makes plain
    /// detection the untouched path it was before this existed.
    func ladderWeek(weekStart: String) async -> WeeklyGoal? {
        guard let enrollment = try? await ProgramRepository.active() else { return nil }
        return await detectGoalIfMissing(enrollment: enrollment,
                                         weekStart: weekStart)?.week
    }
}

extension LiveBlockGoalRepository {

    /// Derive and persist a goal for a block that predates goals — and, for a
    /// block that already HAS one, bring its ladder up to date.
    ///
    /// Mirrors `LiveWeeklyGoalRepository.detectIfMissing` exactly: the read
    /// happens, the rule decides, ONE attempt is made and the caller moves on,
    /// so an offline launch renders the block without a ladder and retries next
    /// refresh rather than looping.
    ///
    /// **PLAN ITEM 6, THE CONTROLLER'S RULING, IS THE FIRST BRANCH.** A block
    /// that already carries a goal is NOT re-derived — the milestone belongs to
    /// the athlete and Coach may not restate it. What Coach does instead is what
    /// it is allowed to do: re-ladder the remaining rungs from actuals, and
    /// materialise this week's rung into `weekly_goals` (which itself defers to
    /// `WeeklyGoalWriteRule` and leaves the athlete's own week alone).
    ///
    /// `source = .coach` on a fresh derivation, which is what makes the
    /// athlete's later edit on the ladder page an override Coach must respect
    /// (owner decision 8).
    ///
    /// The ladder is derived and persisted IMMEDIATELY after the goal, so a
    /// migrated block has rungs on its first Home load rather than an empty page.
    ///
    /// **IT HANDS BACK THE WEEK'S ROW, not just the goal** (final review F1).
    /// The caller is `LiveWeeklyGoalRepository.detectIfMissing`, which owes
    /// Home a `WeeklyGoal`; returning only the `BlockGoal` would have made it
    /// re-read the row this just wrote.
    @discardableResult
    func detectGoalIfMissing(enrollment: ProgramEnrollment,
                             weekStart: String? = nil) async -> DetectedBlockWeek? {
        let calendar = Calendar.current
        let now = Date()
        let currentWeek = weekStart ?? WeekMath.weekStartString(now, calendar: calendar)

        if let existing = await goal(enrollmentID: enrollment.id) {
            // The re-laddered ladder is handed straight to materialisation
            // rather than being dropped and re-read (finding F5).
            guard let fresh = await reLadder(goalID: existing.id) else {
                return DetectedBlockWeek(goal: existing, week: nil)
            }
            let week = await materialiseRung(goal: existing, ladder: fresh,
                                             weekStart: currentWeek)
            return DetectedBlockWeek(goal: existing, week: week)
        }

        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        let unit = await MainActor.run { ThemeStore.shared.weightUnit }
        let volumeTargets = (try? await VolumeTargetRepository.all()) ?? []
        let weeklyGoal = await effectiveWeeklyGoal(userID: userID)
        // Only fetched for a muscle-focused block: everything else answers from
        // the enrollment alone, and this is three round trips.
        let prescribed = enrollment.focus.muscleGroup == nil
            ? [:]
            : await prescribedMuscleSets(userID: userID, calendar: calendar)

        let draft = LadderMath.detectedGoal(
            enrollment: enrollment, volumeTargets: volumeTargets,
            effectiveWeeklyGoal: weeklyGoal, prescribedMuscleSets: prescribed,
            unit: unit, now: now, calendar: calendar)
        let goal = BlockGoal(draft: draft, userID: userID,
                             enrollmentID: enrollment.id, now: now)
        guard await saveDetected(goal) else { return nil }

        guard let derived = await deriveLadder(goal: goal, enrollment: enrollment,
                                               unit: unit, calendar: calendar, now: now)
        else { return DetectedBlockWeek(goal: goal, week: nil) }
        let week = await materialiseRung(goal: goal, ladder: derived,
                                         weekStart: currentWeek)
        return DetectedBlockWeek(goal: goal, week: week)
    }

    /// The first ladder for a block that had none.
    ///
    /// A strength goal reads its rungs off the block's OWN template weeks
    /// (`LadderReadout.strengthRungs(template:…)`, snapped to the athlete's own
    /// plate grid by the same helper the build-time door uses).
    /// Everything else ramps. Either way the rungs land `ahead` except the week
    /// the athlete is in, which `LadderMath.statuses` marks `current` by the
    /// same law that marks it on every later refresh.
    @discardableResult
    private func deriveLadder(goal: BlockGoal, enrollment: ProgramEnrollment,
                              unit: WeightUnit, calendar: Calendar,
                              now: Date) async -> Ladder? {
        let weekKeys = LadderMath.weekStartStrings(from: enrollment.startedOn,
                                                   count: max(1, enrollment.weeks),
                                                   calendar: calendar)
        guard !weekKeys.isEmpty else { return nil }
        let template = enrollment.template
        var targets: [GoalTarget] = []

        if goal.metric == .liftOneRepMax, let exerciseID = goal.target.exerciseID,
           let baseline = enrollment.baselineValue(for: exerciseID),
           let readOut = LadderReadout.strengthRungs(template: template,
                                                     exerciseID: exerciseID,
                                                     baselineE1RMLbs: baseline,
                                                     unit: unit),
           readOut.count == weekKeys.count {
            targets = readOut
        } else {
            targets = LadderRules.rule(for: goal.metric).rungs(
                current: GoalTarget(), target: goal.target, weeks: weekKeys.count,
                constraints: LadderReadout.constraints(template: template, unit: unit))
        }
        guard targets.count == weekKeys.count else { return nil }

        let raw = zip(weekKeys.enumerated(), targets).map { pair, target in
            LadderRung(weekIndex: pair.offset, weekStartString: pair.element,
                       target: target, status: .ahead)
        }
        let rungs = LadderMath.statuses(
            rungs: raw, metric: goal.metric, measuredByWeek: [:],
            currentWeekStart: WeekMath.weekStartString(now, calendar: calendar))
        let ladder = Ladder(goalID: goal.id, rungs: rungs, derivedAt: now)
        guard await saveLadder(ladder) else { return nil }
        return ladder
    }

    /// The BLOCK'S own prescribed sets per group, when the titration has
    /// nothing to say.
    ///
    /// THE WEEK'S ROUTINES, not the whole library — `routinesForWeek` is what
    /// narrows it, for the reason `LiveWeeklyGoalRepository.detect` records: a
    /// five-routine library summed into a week's targets is a target nobody
    /// prescribed. The arithmetic is `WeeklyGoalDetector.routineTargets`, the
    /// same six-group credit progress is measured with.
    private func prescribedMuscleSets(userID: UUID,
                                      calendar: Calendar) async -> [String: Int] {
        let library = (try? await RoutineRepository.fetchAll(ownerID: userID)) ?? []
        let sessions = (try? await SessionRepository.upcoming(limit: 50)) ?? []
        let history = (try? await SessionRepository.history(userID: userID,
                                                            limit: 50)) ?? []
        let weekRoutines = WeeklyGoalDetector.routinesForWeek(
            library: library, sessions: sessions + history,
            now: Date(), calendar: calendar)
        guard !weekRoutines.isEmpty else { return [:] }
        let rows = (try? await RoutineRepository
            .exercisesForRoutines(ids: weekRoutines.map(\.id))) ?? []
        let catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        let byID = Dictionary(catalog.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        let byGroup = WeeklyGoalDetector.routineTargets(
            weekRoutines: weekRoutines,
            routineExercises: Dictionary(grouping: rows, by: \.routineID),
            catalog: byID)
        return Dictionary(uniqueKeysWithValues: byGroup.map { ($0.key.rawValue, $0.value) })
    }

    /// The anti-goalpost weekly days number, with the app's own default when
    /// there is no profile to read — the same 3 `LiveWeeklyGoalRepository` and
    /// `HomeView.weeklyGoalWidget` both fall back to.
    private func effectiveWeeklyGoal(userID: UUID) async -> Int {
        let profile = try? await ProfileRepository.fetch(userID: userID)
        return profile?.effectiveWeeklyGoal ?? 3
    }
}
