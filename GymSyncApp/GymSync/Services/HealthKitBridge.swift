import Foundation
import HealthKit

enum HealthKitBridge {
    static let store = HKHealthStore()

    static func requestPermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [workoutType], read: [])
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
