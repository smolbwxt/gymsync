import Foundation

// MARK: - BlockGoalMetricMath
//
// Spec §2.2's registry, read side. "Where am I now" for the metrics phase 1
// adds. The five shipped metrics already have readers in
// `WeeklyGoalProgressMath` (liftProgress, muscleSetsProgress, distanceProgress,
// distinctTrainingDays, sessionsOfTypeProgress) and are NOT duplicated here —
// two readers for one metric is exactly the drift the agreement law forbids.
//
// PURE. No network, no `Date.now`, no HealthKit store. The HealthKit-backed
// reader (A6) takes samples as a parameter for the same reason, which is also
// global constraint 5: a unit test must never raise a permission sheet.
enum BlockGoalMetricMath {

    /// `bodyWeight` — the most recent logged body weight, in CANONICAL POUNDS.
    ///
    /// The app's OWN log is the source (`BodyWeightLogRepository.recent`,
    /// `Models/BodyWeightLog.swift:37`), which stores pounds with `unit = "lbs"`
    /// whatever the athlete typed (`BodyWeightLogSheet.swift:94-96`). A row
    /// whose `unit` is anything else is a row this app did not write; it is
    /// skipped rather than converted on a guess.
    ///
    /// nil when there is no log at all — which the ladder renders as "log a
    /// weight", never as 0 lb.
    static func currentBodyWeightPounds(logs: [BodyWeightLog]) -> Decimal? {
        logs.filter { $0.unit.lowercased() == "lbs" && $0.weight > 0 }
            .max { $0.loggedAt < $1.loggedAt }?
            .weight
    }

    /// `cumulativeVolume` — pounds moved across `logs`, the same arithmetic the
    /// plate milestone catalog counts.
    ///
    /// `completedReps`, never raw `reps`, and penalties excluded: the failure
    /// doctrine `WeeklyGoalProgressMath.muscleSetCredit` states in full. A
    /// failed triple moved two reps' worth of iron and counts them; a failed
    /// single moved none.
    static func volumePounds(logs: [SetLog]) -> Double {
        logs.reduce(0.0) { total, log in
            guard !log.isPenalty,
                  let reps = log.completedReps, reps > 0,
                  let weight = log.weight, weight > 0 else { return total }
            return total + NSDecimalNumber(decimal: weight).doubleValue * Double(reps)
        }
    }

    /// `benchmarkTime` — the fastest completed run of one named routine, in
    /// seconds, or nil when it has never been finished.
    ///
    /// FASTEST, not most recent: a benchmark is a record of the best you have
    /// done, the same reading `StatMath.estimatedOneRepMax`'s consumers take of
    /// a lift. A session with no `startedAt` is skipped rather than measured
    /// from its `completedAt` alone.
    static func bestBenchmarkSeconds(sessions: [WorkoutSession],
                                     routineID: UUID) -> Int? {
        sessions
            .compactMap { session -> Int? in
                guard session.routineID == routineID,
                      let started = session.startedAt,
                      let completed = session.completedAt,
                      completed > started else { return nil }
                return Int(completed.timeIntervalSince(started).rounded())
            }
            .min()
    }

    /// `liftRepsAtLoad` — the most reps completed in a single set at or above
    /// `loadLbs`, for one exercise.
    ///
    /// AT OR ABOVE, because "10 at 225" is satisfied by ten at 235. A set below
    /// the load says nothing about the goal and is not scaled into it — that
    /// would be an e1RM, which is a different metric with its own reader.
    static func bestRepsAtLoad(logs: [SetLog], exerciseID: UUID,
                               loadLbs: Decimal) -> Int? {
        logs
            .filter { $0.exerciseID == exerciseID && !$0.isPenalty }
            .compactMap { log -> Int? in
                guard let weight = log.weight, weight >= loadLbs,
                      let reps = log.completedReps, reps > 0 else { return nil }
                return reps
            }
            .max()
    }
}
