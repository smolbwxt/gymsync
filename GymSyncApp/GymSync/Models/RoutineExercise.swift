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
    }
}
