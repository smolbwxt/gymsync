import Foundation

struct RoutineExercise: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let routineID: UUID
    let exerciseID: UUID
    var position: Int
    var targetSets: Int?
    var targetReps: String?
    var targetWeight: String?
    var restSeconds: Int?
    var notes: String?
    // Set structures (20260814000003) — trailing defaults keep every
    // construction site compiling. setType: straight | drop | burnout.
    var setType: String = "straight"
    var supersetGroup: Int? = nil
    var dropSteps: Int? = nil
    var dropPercent: Decimal? = nil
    /// Final set prescribed TO FAILURE — renders in place of a rep target;
    /// per the failure doctrine a prescribed failure is the assignment
    /// fulfilled, never a stall signal.
    var targetFailure: Bool = false
    /// Rep RANGES (generator schema 20260814000009) — the double-
    /// progression primitive. Legacy targetReps (text) stays for display;
    /// generated prescriptions fill all three.
    var targetRepsLow: Int? = nil
    var targetRepsHigh: Int? = nil
    /// Cardio prescriptions (generator): zone + MINUTES — the session UI
    /// branches on their presence instead of sets × reps.
    var cardioZone: Int? = nil
    var cardioMinutes: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case routineID = "routine_id"
        case exerciseID = "exercise_id"
        case position
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetWeight = "target_weight"
        case restSeconds = "rest_seconds"
        case notes
        case setType = "set_type"
        case supersetGroup = "superset_group"
        case dropSteps = "drop_steps"
        case dropPercent = "drop_percent"
        case targetFailure = "target_failure"
        case targetRepsLow = "target_reps_low"
        case targetRepsHigh = "target_reps_high"
        case cardioZone = "cardio_zone"
        case cardioMinutes = "cardio_minutes"
    }
}
