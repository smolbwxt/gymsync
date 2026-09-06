import Foundation
import HealthKit

enum HealthKitBridge {
    static let store = HKHealthStore()

    static func requestPermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        // Read scope added for the HR backfill (2026-07-27): heart-rate
        // samples written by ANY device's companion app (Garmin, Polar,
        // Fitbit, Whoop all sync into Health) become recap data for every
        // watch brand — the non-live half of "everyone has the option to
        // have live HR".
        // Dietary reads added 2026-08-24: MyFitnessPal, MyNetDiary,
        // Cronometer, and Lose It all sync these into Apple Health, so
        // reading Health integrates every tracker at once — no partner
        // APIs. Coach's nutrition tool consumes the summary.
        try await store.requestAuthorization(
            toShare: [workoutType],
            read: [HKQuantityType(.heartRate),
                   HKQuantityType(.dietaryEnergyConsumed),
                   HKQuantityType(.dietaryProtein),
                   HKQuantityType(.dietaryCarbohydrates),
                   HKQuantityType(.dietaryFatTotal)]
        )
    }

    // MARK: - Weekly goal: workouts + distance (Stream A task A7)

    /// The three read types the weekly goal's `distance` and
    /// `sessionsOfType` kinds need, behind their OWN authorization request.
    ///
    /// A SEPARATE REQUEST ON PURPOSE (controller ruling, 2026-09-06), not an
    /// addition to `requestPermission()`'s read set: this is asked only when
    /// the athlete actually sets a `distance` or `sessionsOfType` goal, never
    /// at launch. A permission sheet naming workouts and distance to someone
    /// who has not asked for a miles goal is a prompt with no answer in it —
    /// and the more types the launch prompt lists, the more likely the whole
    /// sheet is dismissed, taking heart rate and nutrition down with it.
    ///
    /// `toShare` is empty: the workout WRITE scope is already held by
    /// `requestPermission()` and re-requesting it here would re-prompt.
    ///
    /// HealthKit never reveals a DENIAL for read types (by design — that
    /// would itself leak health information), so this returning without
    /// throwing means the sheet was answered, not that access was granted.
    /// Every reader below therefore treats "no samples" and "denied" as the
    /// same thing, which is also what makes them safe to call unconditionally.
    static func requestWorkoutAndDistancePermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: weeklyGoalReadTypes)
    }

    /// The three read types the weekly goal needs, in one place so the
    /// request and the status check cannot ask about different sets.
    private static var weeklyGoalReadTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(),
         HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.distanceCycling)]
    }

    /// Has the athlete never been ASKED for the weekly goal's Health reads?
    ///
    /// This is what stops `0 mi` from meaning two different things: a
    /// `distance` goal whose permission was never requested reads a perfect,
    /// silent zero, indistinguishable from a week with no runs in it. While
    /// this returns true the strip says `CONNECT HEALTH` instead of a number
    /// (`WeeklyGoalProgressMath.connectHealthRead`).
    ///
    /// `getRequestStatusForAuthorization` is the ONLY signal Apple offers
    /// here, and it answers "would a request show a sheet", not "did they say
    /// yes". That is deliberate on Apple's part: `authorizationStatus(for:)`
    /// reports the SHARING side only, because disclosing read permission
    /// would itself leak health information. **So a DENIAL is
    /// indistinguishable from no data** once the ask has happened, and a
    /// lifter who declined sees `0 / 15 mi`. Stated at
    /// `distanceProgress` too, and the honest limit of this whole mechanism.
    ///
    /// `true` when Health is unavailable on the device, because "connect
    /// Health" is then permanently the truthful read rather than `0 mi`.
    static func weeklyGoalHealthNeedsConnecting() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return true }
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: [], read: weeklyGoalReadTypes)
            return status == .shouldRequest
        } catch {
            AppLogger.health.error("weekly goal health status failed: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }

    /// The goal editor's four activities, mapped to HealthKit's own types.
    /// Pure, so the mapping is testable without a store. An activity string
    /// this app has never heard of maps to nil and counts nothing, rather
    /// than silently matching every workout.
    static func activityType(for activity: String) -> HKWorkoutActivityType? {
        switch activity.lowercased() {
        case "run":  return .running
        case "bike": return .cycling
        case "row":  return .rowing
        case "walk": return .walking
        default:     return nil
        }
    }

    /// Every workout in the window, from ANY source in Apple Health — the
    /// same reasoning `heartRateStats` gives for reading rather than only
    /// writing: a Garmin/Polar/Whoop run syncs into Health, and a weekly
    /// mileage goal that ignored it would be wrong for most runners.
    ///
    /// Best-effort: `[]` on no availability, no permission, or any error.
    static func workouts(from start: Date, to end: Date) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    /// The raw distance samples for one activity's distance type, in the
    /// window. `[]` for an unknown activity, and for every failure path.
    ///
    /// Kept alongside `distanceMeters` below because the two answer
    /// different questions: this one is every distance sample the phone or
    /// watch recorded, which is what a future "you walked 3 mi outside your
    /// workouts" read would want; `distanceMeters` is the goal's own number.
    static func distances(activity: String, from start: Date,
                          to end: Date) async -> [HKQuantitySample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let identifier: HKQuantityTypeIdentifier
        switch activityType(for: activity) {
        case .cycling: identifier = .distanceCycling
        case .running, .walking: identifier = .distanceWalkingRunning
        default: return []   // rowing has no distance type in this read set
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(identifier),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Metres covered in workouts of one activity during the window — the
    /// number behind a `distance` goal.
    ///
    /// Summed from the WORKOUTS' own `totalDistance` rather than from raw
    /// distance samples, because a workout's total is the figure its
    /// recording app stands behind; summing samples would double-count a
    /// run that a watch recorded alongside the phone. `totalDistance` is
    /// only populated when the distance read types are authorized, which is
    /// why `requestWorkoutAndDistancePermission` asks for all three.
    ///
    /// 0 when nothing matched, when the activity is unknown, and when
    /// permission was never granted — never nil, so the strip renders
    /// `0 / 15 mi` rather than an error.
    static func distanceMeters(activity: String, from start: Date,
                               to end: Date) async -> Double {
        guard let type = activityType(for: activity) else { return 0 }
        return await workouts(from: start, to: end)
            .filter { $0.workoutActivityType == type }
            .reduce(0.0) { $0 + ($1.totalDistance?.doubleValue(for: .meter()) ?? 0) }
    }

    /// The tags `WeeklyGoalProgressMath.sessionCounts` reads to let a real
    /// HealthKit workout outrank a routine-name guess (task A6), each
    /// carrying its OWN WINDOW.
    ///
    /// Windows, not days. Keyed by calendar day this promoted every app
    /// session that day — an outdoor run plus two lifting sessions on a
    /// Saturday credited two toward a `cardio` goal, neither of them the run
    /// — so the match now has to overlap the session it is corroborating
    /// (`HealthWorkoutTag.matches(type:sessionStart:sessionEnd:)`).
    ///
    /// Only the two HealthKit activity families that map cleanly onto this
    /// app's type vocabulary are tagged. `hiit` and `class` are deliberately
    /// absent even though `.highIntensityIntervalTraining` exists, because
    /// this app's `hiit` means "a routine the athlete calls HIIT", and
    /// equating the two would make a Peloton class satisfy a goal about
    /// their own programming.
    static func workoutTags(from start: Date, to end: Date) async -> [HealthWorkoutTag] {
        await workouts(from: start, to: end).compactMap { workout in
            let tag: String
            switch workout.workoutActivityType {
            case .running, .cycling, .rowing, .walking, .elliptical, .stairClimbing:
                tag = "cardio"
            case .yoga, .flexibility, .mindAndBody, .preparationAndRecovery:
                tag = "mobility"
            default:
                return nil
            }
            return HealthWorkoutTag(type: tag, start: workout.startDate,
                                    end: workout.endDate)
        }
    }

    static func duration(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    /// Rough resistance-training calorie estimate for the recap's Apple
    /// Health card — no per-user bodyweight is stored anywhere in the app,
    /// so this uses a flat ~7.5 kcal/min (moderate-intensity weight training,
    /// average adult) rather than a full MET × bodyweight × duration formula.
    /// Consumed by `SoloRecapView`'s "Synced to Apple Health" card (Phase H —
    /// dormancy ends here; see `WorkoutSessionView.recapHealthSummary`).
    static func estimatedCalories(minutes: Double) -> Int {
        Int((max(0, minutes) * 7.5).rounded())
    }

    static func totalVolume(from logs: [SetLog]) -> Double {
        logs.reduce(0.0) { acc, log in
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps,
                  let weight = log.weight else { return acc }
            return acc + Double(reps) * NSDecimalNumber(decimal: weight).doubleValue
        }
    }

    /// The metadata stamped on every exported `HKWorkout`. Split out as a
    /// pure function (no `HKHealthStore` access) so it's directly unit-
    /// testable — see `HealthKitBridgeTests.testExportMetadataStampsSessionID`.
    ///
    /// `HKMetadataKeyExternalUUID` is HealthKit's documented metadata key for
    /// exactly this "tag a sample with an external app-side record id" use
    /// case (Phase H gap: `replaceWorkout` below needs a way to find a
    /// session's prior export in order to delete it before re-exporting).
    /// Fix-forward only — workouts exported before this change carry no
    /// stamp and can't be matched; see `replaceWorkout`'s doc comment for
    /// the resulting honest limitation.
    static func exportMetadata(sessionID: UUID) -> [String: Any] {
        [HKMetadataKeyExternalUUID: sessionID.uuidString]
    }

    /// The predicate that finds a session's previously-exported `HKWorkout`
    /// by its stamped `HKMetadataKeyExternalUUID` (see `exportMetadata`
    /// above). Split out from `replaceWorkout` so the predicate construction
    /// itself is directly unit-testable without touching `HKHealthStore`.
    static func exportPredicate(sessionID: UUID) -> NSPredicate {
        HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [sessionID.uuidString]
        )
    }

    /// Average + max heart rate over a window, from ANY source in Apple
    /// Health — this is what makes recap HR work for Garmin/Polar/Fitbit/
    /// Whoop users whose companion apps sync after the workout. Best-effort:
    /// nil on no data, no permission, or any error (a recap must never
    /// block on Health).
    static func heartRateStats(start: Date, end: Date) async -> (avg: Int, max: Int)? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                guard let stats,
                      let avg = stats.averageQuantity()?.doubleValue(for: unit),
                      let max = stats.maximumQuantity()?.doubleValue(for: unit) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (Int(avg.rounded()), Int(max.rounded())))
            }
            store.execute(query)
        }
    }

    // MARK: - Nutrition (owner 2026-08-24: MFP/MyNetDiary via Health)

    /// Per-day totals for one dietary type over a window; only days that
    /// actually have data count (a tracker skipped on Sunday must not
    /// drag the average down). Best-effort: empty on no permission, no
    /// data, or any error — Coach must never block on Health.
    private static func dailyTotals(_ id: HKQuantityTypeIdentifier,
                                    unit: HKUnit,
                                    start: Date, end: Date) async -> [Double] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let type = HKQuantityType(id)
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: anchor,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var totals: [Double] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                        totals.append(sum)
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    /// The computed nutrition sentence for Coach's tool belt — averages
    /// over the last 7 logged days from Apple Health (which every major
    /// diet tracker syncs into). The model narrates this arithmetic; it
    /// never computes its own.
    static func nutritionSummaryLine() async -> String {
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: end) else {
            return "No nutrition data available."
        }
        let kcal = await dailyTotals(.dietaryEnergyConsumed, unit: .kilocalorie(),
                                     start: start, end: end)
        guard !kcal.isEmpty else {
            return "No nutrition data synced to Apple Health in the last 7 days. If the athlete tracks with MyFitnessPal, MyNetDiary, Cronometer, or Lose It, turning on Apple Health sync in that app brings their diet into this conversation."
        }
        let protein = await dailyTotals(.dietaryProtein, unit: .gram(),
                                        start: start, end: end)
        let carbs = await dailyTotals(.dietaryCarbohydrates, unit: .gram(),
                                      start: start, end: end)
        let fat = await dailyTotals(.dietaryFatTotal, unit: .gram(),
                                    start: start, end: end)
        func avg(_ xs: [Double]) -> Int? {
            xs.isEmpty ? nil : Int((xs.reduce(0, +) / Double(xs.count)).rounded())
        }
        var parts = ["NUTRITION (Apple Health, \(kcal.count) logged day\(kcal.count == 1 ? "" : "s") of the last 7): ~\(avg(kcal) ?? 0) kcal/day"]
        if let p = avg(protein) { parts.append("protein ~\(p) g/day") }
        if let c = avg(carbs) { parts.append("carbs ~\(c) g/day") }
        if let f = avg(fat) { parts.append("fat ~\(f) g/day") }
        return parts.joined(separator: ", ") + "."
    }

    static func exportWorkout(session: WorkoutSession, setLogs: [SetLog]) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = session.startedAt,
              let end = session.completedAt else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        // Stamp the session id (Phase H) so a later duration edit can find
        // and delete this exact sample before re-exporting — see
        // `replaceWorkout` below. Must happen before `finishWorkout()`
        // finalizes the sample.
        try await builder.addMetadata(exportMetadata(sessionID: session.id))
        _ = try await builder.finishWorkout()
        AppLogger.health.info("Exported workout \(session.id, privacy: .public) duration=\(duration(from: start, to: end))")
    }

    /// Re-writes a session's `HKWorkout` after its duration was edited
    /// (`SessionRepository.editDuration`, called from
    /// `CompletedSessionView.DurationEditSheet.save()`): deletes the prior
    /// export — matched by the `HKMetadataKeyExternalUUID` stamp `exportWorkout`
    /// writes above — then re-exports with the corrected start/end.
    ///
    /// Best-effort by design: never throws. Every failure is logged; the
    /// caller (the duration edit itself) must never be blocked or failed by
    /// a HealthKit problem.
    ///
    /// HONEST LIMITATION: a workout exported before this Phase H change has
    /// no metadata stamp to match on, so the delete step finds nothing for
    /// it — the edit still re-exports, which means such a session ends up
    /// with two HK samples (the old, un-deletable-without-a-key one, plus
    /// the freshly stamped one). Logged, not silently swallowed; this is the
    /// same "may create a second Health entry" tradeoff
    /// `CompletedSessionView` already accepted pre-Phase-H, now narrowed to
    /// only pre-stamp exports instead of every edit.
    static func replaceWorkout(session: WorkoutSession, setLogs: [SetLog]) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        do {
            let deletedCount = try await store.deleteObjects(
                of: HKObjectType.workoutType(),
                predicate: exportPredicate(sessionID: session.id)
            )
            // Phase O Task 2: disambiguate 0-deleted from N-deleted — a bare
            // "deleted 0" line read as ambiguous (Task 1's ledgered Minor:
            // could mean "this session's export predates the metadata
            // stamp" OR "something is broken"). It's neither by default —
            // see the HONEST LIMITATION doc comment above: any export from
            // before this Phase H change has no `HKMetadataKeyExternalUUID`
            // stamp to match on, so 0-deleted is the EXPECTED outcome for
            // those, not a failure signal.
            if deletedCount == 0 {
                AppLogger.health.info("replaceWorkout: 0 prior export(s) matched for session \(session.id, privacy: .public) (pre-stamp export or none existed — expected for old exports)")
            } else {
                AppLogger.health.info("replaceWorkout: deleted \(deletedCount, privacy: .public) prior export(s) for session \(session.id, privacy: .public)")
            }
        } catch {
            AppLogger.health.error("replaceWorkout: delete failed for session \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Fall through and re-export anyway — worst case a delete
            // failure (as opposed to a genuine "nothing matched") leaves a
            // duplicate sample rather than a missing one.
        }

        do {
            try await exportWorkout(session: session, setLogs: setLogs)
        } catch {
            AppLogger.health.error("replaceWorkout: re-export failed for session \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
