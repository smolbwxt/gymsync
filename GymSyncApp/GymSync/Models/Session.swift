import Foundation

struct WorkoutSession: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID?
    let organizerID: UUID
    var state: String
    var startedAt: Date?
    var completedAt: Date?
    let createdAt: Date
    // Phase 3a additions
    let groupID: UUID?
    let roomCode: String?
    let scheduledFor: Date?
    // Phase 4 additions (recurring series)
    let seriesID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case routineID = "routine_id"
        case organizerID = "organizer_id"
        case state
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case groupID = "group_id"
        case roomCode = "room_code"
        case scheduledFor = "scheduled_for"
        case seriesID = "series_id"
    }
}

struct SessionParticipant: Codable, Sendable {
    let sessionID: UUID
    let userID: UUID
    let turnOrder: Int?
    let checkInState: String?
    let checkInAt: Date?
    let checkInMethod: String?
    let lateMinutes: Int
    let burpeesOwed: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case turnOrder = "turn_order"
        case checkInState = "check_in_state"
        case checkInAt = "check_in_at"
        case checkInMethod = "check_in_method"
        case lateMinutes = "late_minutes"
        case burpeesOwed = "burpees_owed"
    }
}
