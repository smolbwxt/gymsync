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
