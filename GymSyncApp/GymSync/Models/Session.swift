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
    // Phase 3b additions (chess clock / turn rotation)
    var currentTurnUserID: UUID?
    var currentTurnStartedAt: Date?
    // Phase 3b: duration editing audit fields (columns added in 3a migration)
    var durationWasEdited: Bool
    var editedBy: UUID?

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
        case currentTurnUserID = "current_turn_user_id"
        case currentTurnStartedAt = "current_turn_started_at"
        case durationWasEdited = "duration_was_edited"
        case editedBy = "edited_by"
    }

    // Safe decode: duration_was_edited has DB DEFAULT false so older rows always carry it;
    // edited_by is nullable. Custom init guards against any schema-lag during migration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,    forKey: .id)
        routineID            = try c.decodeIfPresent(UUID.self,   forKey: .routineID)
        organizerID          = try c.decode(UUID.self,    forKey: .organizerID)
        state                = try c.decode(String.self,  forKey: .state)
        startedAt            = try c.decodeIfPresent(Date.self,   forKey: .startedAt)
        completedAt          = try c.decodeIfPresent(Date.self,   forKey: .completedAt)
        createdAt            = try c.decode(Date.self,    forKey: .createdAt)
        groupID              = try c.decodeIfPresent(UUID.self,   forKey: .groupID)
        roomCode             = try c.decodeIfPresent(String.self, forKey: .roomCode)
        scheduledFor         = try c.decodeIfPresent(Date.self,   forKey: .scheduledFor)
        seriesID             = try c.decodeIfPresent(UUID.self,   forKey: .seriesID)
        currentTurnUserID    = try c.decodeIfPresent(UUID.self,   forKey: .currentTurnUserID)
        currentTurnStartedAt = try c.decodeIfPresent(Date.self,   forKey: .currentTurnStartedAt)
        durationWasEdited    = (try? c.decodeIfPresent(Bool.self, forKey: .durationWasEdited)) ?? false
        editedBy             = try? c.decodeIfPresent(UUID.self,  forKey: .editedBy)
    }

    // Memberwise init used by startSolo and other repository callers.
    init(
        id: UUID,
        routineID: UUID?,
        organizerID: UUID,
        state: String,
        startedAt: Date?,
        completedAt: Date?,
        createdAt: Date,
        groupID: UUID?,
        roomCode: String?,
        scheduledFor: Date?,
        seriesID: UUID?,
        currentTurnUserID: UUID?,
        currentTurnStartedAt: Date?,
        durationWasEdited: Bool = false,
        editedBy: UUID? = nil
    ) {
        self.id                   = id
        self.routineID            = routineID
        self.organizerID          = organizerID
        self.state                = state
        self.startedAt            = startedAt
        self.completedAt          = completedAt
        self.createdAt            = createdAt
        self.groupID              = groupID
        self.roomCode             = roomCode
        self.scheduledFor         = scheduledFor
        self.seriesID             = seriesID
        self.currentTurnUserID    = currentTurnUserID
        self.currentTurnStartedAt = currentTurnStartedAt
        self.durationWasEdited    = durationWasEdited
        self.editedBy             = editedBy
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
