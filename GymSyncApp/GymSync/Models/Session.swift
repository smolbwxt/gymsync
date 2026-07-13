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

// MARK: - Burpee Ledger DTO (Canvas Completion Task 3)
//
// One `session_participants` row, joined server-side with just the
// `sessions` fields the ledger needs. Fetched via a single PostgREST embed
// query (`SessionRepository.myBurpeeLedgerRows(groupID:)`) — `sessions!inner
// (...)` filtered by `sessions.group_id` AND `user_id = auth.uid()`, the
// mirror image of `upcoming()`'s `sessions` embedding
// `session_participants!inner(...)`. No per-session ID fan-out into the URL.
//
// Fix round 1 (task-3-report.md): this DTO used to also back the group-wide
// crew debts list, on the assumption that "every group-scheduled session
// invites the full group roster, so any CURRENT group member is a
// participant of every group session" — true only for members who were
// ALREADY in the group when a session was scheduled. A member who joins
// later has no `session_participants` row for earlier sessions at all, so
// RLS's "participants readable by other participants" policy silently
// dropped those sessions from their fetch, undercounting every crew
// member's total (not just their own). The crew-wide aggregate now comes
// from the `group_burpee_ledger` SECURITY DEFINER RPC (membership-gated,
// see `GroupBurpeeLedgerAggregate` below) instead. This DTO is scoped to
// self-only rows now, which sidesteps the gap entirely: "user_id =
// auth.uid()" makes a user's own rows unconditionally RLS-visible,
// regardless of when they joined the group.
struct BurpeeLedgerRow: Decodable, Sendable {
    let userID: UUID
    let checkInState: String?
    let lateMinutes: Int
    let burpeesOwed: Int
    let session: SessionInfo

    struct SessionInfo: Decodable, Sendable {
        let id: UUID
        let state: String
        let scheduledFor: Date?
        let startedAt: Date?
        let latePenalty: LatePenalty?

        struct LatePenalty: Decodable, Sendable {
            let perMinute: Int?
            enum CodingKeys: String, CodingKey { case perMinute = "per_minute" }
        }

        enum CodingKeys: String, CodingKey {
            case id, state
            case scheduledFor = "scheduled_for"
            case startedAt = "started_at"
            case latePenalty = "late_penalty"
        }

        /// The date the ledger sorts/displays by — when this session happened
        /// (or is scheduled to). Ad-hoc sessions have no `scheduled_for`.
        var effectiveDate: Date? { scheduledFor ?? startedAt }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case checkInState = "check_in_state"
        case lateMinutes = "late_minutes"
        case burpeesOwed = "burpees_owed"
        case session = "sessions"
    }
}

// MARK: - Burpee Ledger RPC row (Fix round 1 — task-3-report.md)
//
// One row of `group_burpee_ledger(p_group)`'s SECURITY DEFINER aggregate.
// Replaces the client-side `BurpeeLedgerRow` summation for crew debts: the
// old direct `session_participants` query undercounted every crew member's
// total for any caller who joined the group after some of the group's
// sessions had already run (they were never invited to those sessions, so
// `session_participants`' "readable by other participants" RLS policy hid
// those rows from THEIR fetch entirely — not just their own debt, everyone
// else's too). The RPC is gated on current group membership instead of
// session participation, so it sums across every session the group has run
// regardless of who was invited to which one.
struct GroupBurpeeLedgerAggregate: Decodable, Sendable {
    let userID: UUID
    let totalOwed: Int
    let lateCount: Int
    let noShowCount: Int
    let lastLateAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case totalOwed = "total_owed"
        case lateCount = "late_count"
        case noShowCount = "no_show_count"
        case lastLateAt = "last_late_at"
    }
}
