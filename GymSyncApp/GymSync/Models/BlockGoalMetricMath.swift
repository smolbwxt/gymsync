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

    // MARK: - Recovery's two readers (task A6)
    //
    // Recovery is the one preset with two metrics, and it is still ONE goal
    // (spec §2.3): the primary is `stretchingExercisesPerWeek` — what the block
    // schedules — and `lissMinutesPerWeek` is its companion read on the same
    // rung.

    /// `lissMinutesPerWeek` — Health's minutes plus the app's own cardio-only
    /// sessions, de-duplicated by overlap.
    ///
    /// An athlete with no Health connected still has a reading: a session whose
    /// routine is cardio-only is LISS by prescription. An athlete WITH Health
    /// gets both, and a session the watch also recorded must not count twice —
    /// `HealthWorkoutTag.matches(type:sessionStart:sessionEnd:)` is the same
    /// interval-overlap test `sessionCounts` uses, and the same 15-minute
    /// tolerance, so the two readings cannot disagree about what one piece of
    /// training was.
    ///
    /// `routines` is taken and not read, deliberately: every other reader on
    /// this seam is handed the same four collections, and A11 fetches the
    /// library anyway for the benchmark's routine name. Widening the signature
    /// later would touch every call site; the parameter is the seam's shape.
    static func lissMinutes(healthMinutes: Int,
                            sessions: [WorkoutSession],
                            routines: [UUID: Routine],
                            routineExercises: [UUID: [RoutineExercise]],
                            catalog: [UUID: Exercise],
                            healthWorkouts: [HealthWorkoutTag]) -> Int {
        var appMinutes = 0
        for session in sessions {
            guard let completed = session.completedAt,
                  let routineID = session.routineID,
                  isCardioOnly(routineID: routineID,
                               routineExercises: routineExercises,
                               catalog: catalog) else { continue }
            let started = session.startedAt ?? completed
            // Already counted on the Health side — the watch closed its own
            // workout around this session.
            if healthWorkouts.contains(where: { $0.matches(type: "cardio",
                                                           sessionStart: started,
                                                           sessionEnd: completed) }) {
                continue
            }
            appMinutes += Int((completed.timeIntervalSince(started) / 60).rounded())
        }
        return max(0, healthMinutes) + appMinutes
    }

    /// Every exercise in the routine is `cardio`. Not "half or more" — that is
    /// `sessionCounts`' threshold for "was this a cardio session", and this is
    /// a stricter question: LISS is the whole session being easy work, and a
    /// lifting day with a finisher on the bike is not it.
    static func isCardioOnly(routineID: UUID,
                             routineExercises: [UUID: [RoutineExercise]],
                             catalog: [UUID: Exercise]) -> Bool {
        let categories = (routineExercises[routineID] ?? [])
            .compactMap { catalog[$0.exerciseID]?.category.lowercased() }
        guard !categories.isEmpty else { return false }
        return categories.allSatisfy { $0 == "cardio" }
    }

    /// `stretchingExercisesPerWeek` — completed mobility exercises this week.
    ///
    /// Counted by DISTINCT EXERCISE per session, not by set: "six stretching
    /// exercises" is six movements, and three sets of a hamstring stretch is
    /// one of them. A penalty log is not training, for the same reason it
    /// credits no muscle sets.
    static func stretchingExerciseCount(logs: [SetLog],
                                        catalog: [UUID: Exercise]) -> Int {
        var seen: Set<String> = []
        for log in logs {
            guard !log.isPenalty, log.completedReps != nil,
                  let exercise = catalog[log.exerciseID],
                  exercise.category.lowercased() == "mobility" else { continue }
            seen.insert("\(log.sessionID.uuidString)-\(log.exerciseID.uuidString)")
        }
        return seen.count
    }
}
