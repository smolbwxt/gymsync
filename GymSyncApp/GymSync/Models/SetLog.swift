import Foundation

struct SetLog: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let sessionID: UUID
    let exerciseID: UUID
    let setIndex: Int
    var reps: Int?
    var weight: Decimal?
    var rpe: Decimal?
    var isFailed: Bool
    var isPenalty: Bool
    var note: String?
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case setIndex = "set_index"
        case reps
        case weight
        case rpe
        case isFailed = "is_failed"
        case isPenalty = "is_penalty"
        case note
        case loggedAt = "logged_at"
    }
}
