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
    /// Currently unreferenced — the recap's Apple Health card (Phase H) consumes this again.
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

    static func exportWorkout(session: WorkoutSession, setLogs: [SetLog]) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = session.startedAt,
              let end = session.completedAt else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
        AppLogger.health.info("Exported workout \(session.id, privacy: .public) duration=\(duration(from: start, to: end))")
    }
}
