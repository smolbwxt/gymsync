import Foundation

struct WorkoutSession: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID?
    let organizerID: UUID
    var state: String
    var startedAt: Date?
    var completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case routineID = "routine_id"
        case organizerID = "organizer_id"
        case state
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}
