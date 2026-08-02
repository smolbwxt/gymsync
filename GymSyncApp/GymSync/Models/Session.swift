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
    /// Monotonic rotation counter (20260801000001). A client that queues a
    /// set while offline records the version it saw, and passes it back when
    /// the queued advance replays — if the rotation already moved on, the
    /// RPC no-ops instead of double-advancing. Defaults to 0 so a row
    /// decoded before the column existed is still safe to compare.
    var turnVersion: Int
    /// Warm-up phase (20260803000004): organizer-set minutes between
    /// session start and lifting. 0 = no warm-up window — pre-feature
    /// sessions (and rows decoded before the column existed) behave
    /// exactly as before, so the warm-up page can never appear for them.
    var warmupMinutes: Int
    /// When lifting actually began: the last present participant's
    /// unanimous warm-up vote, or the organizer's force-start. NULL while
    /// warming up. Effective lifting start = `liftingStartedAt` if set,
    /// else `startedAt + warmupMinutes`.
    var liftingStartedAt: Date?

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
        case turnVersion = "turn_version"
        case warmupMinutes = "warmup_minutes"
        case liftingStartedAt = "lifting_started_at"
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
        turnVersion          = (try? c.decodeIfPresent(Int.self,  forKey: .turnVersion)) ?? 0
        warmupMinutes        = (try? c.decodeIfPresent(Int.self,  forKey: .warmupMinutes)) ?? 0
        liftingStartedAt     = try? c.decodeIfPresent(Date.self,  forKey: .liftingStartedAt)
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
        editedBy: UUID? = nil,
        turnVersion: Int = 0,
        warmupMinutes: Int = 0,
        liftingStartedAt: Date? = nil
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
        self.turnVersion          = turnVersion
        self.warmupMinutes        = warmupMinutes
        self.liftingStartedAt     = liftingStartedAt
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
    /// "I'm warm" vote (20260803000004). When every PRESENT participant
    /// (advance_turn's online/ready/late trio) has voted, lifting begins.
    let warmupReady: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case turnOrder = "turn_order"
        case checkInState = "check_in_state"
        case checkInAt = "check_in_at"
        case checkInMethod = "check_in_method"
        case lateMinutes = "late_minutes"
        case burpeesOwed = "burpees_owed"
        case warmupReady = "warmup_ready"
    }

    // Safe decode: warmup_ready has DB DEFAULT false so full-row selects
    // always carry it; the guard covers schema-lag / projected selects,
    // mirroring WorkoutSession's own custom-decode idiom above. (No
    // memberwise construction sites exist for this type — rows are only
    // ever decoded — so replacing the synthesized init is safe.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID     = try c.decode(UUID.self,   forKey: .sessionID)
        userID        = try c.decode(UUID.self,   forKey: .userID)
        turnOrder     = try c.decodeIfPresent(Int.self,    forKey: .turnOrder)
        checkInState  = try c.decodeIfPresent(String.self, forKey: .checkInState)
        checkInAt     = try c.decodeIfPresent(Date.self,   forKey: .checkInAt)
        checkInMethod = try c.decodeIfPresent(String.self, forKey: .checkInMethod)
        lateMinutes   = try c.decode(Int.self,    forKey: .lateMinutes)
        burpeesOwed   = try c.decode(Int.self,    forKey: .burpeesOwed)
        warmupReady   = (try? c.decodeIfPresent(Bool.self, forKey: .warmupReady)) ?? false
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

// MARK: - Burpee Ledger RPC row (Fix round 1 — task-3-report.md; paid/settled
// added Phase S Task 5)
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
//
// `paid`/`settled` (20260719000005_burpee_ledger_paid.sql, RPC v2): settled
// burpees are DERIVED, not stored — `paid` sums that user's `is_penalty =
// true` set_logs reps across the group's sessions (no exercise-identity
// filter; see that migration's "Burpee-identification finding" for why),
// and `settled = paid >= total_owed`. `totalOwed` here still reports the
// RAW lifetime sum (never decremented) — `BurpeeLedgerMath.CrewDebt.
// outstanding` is what nets `paid` against it for display.
struct GroupBurpeeLedgerAggregate: Decodable, Sendable {
    let userID: UUID
    let totalOwed: Int
    let paid: Int
    let settled: Bool
    let lateCount: Int
    let noShowCount: Int
    let lastLateAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case totalOwed = "total_owed"
        case paid
        case settled
        case lateCount = "late_count"
        case noShowCount = "no_show_count"
        case lastLateAt = "last_late_at"
    }
}

// MARK: - Activity Feed RPC row (Canvas frame 45, Task 3)
//
// One row of `activity_feed(p_limit)`'s SECURITY DEFINER aggregate
// (`20260719000002_activity_feed_rpc.sql`) — same Decodable-only,
// snake_case-CodingKeys idiom as `GroupBurpeeLedgerAggregate` above (this
// is a read-only RPC projection, never re-encoded, so `Decodable` rather
// than `Codable`).
//
// `startedAt` is decoded optionally even though the RPC only ever returns
// `state = 'completed'` sessions (which `SessionRepository.complete()`
// always pairs with a `completed_at` write — see that function): a defensive
// nil here just blanks the duration in the feed row rather than throwing
// away the ENTIRE array decode over one unexpected null, matching
// `WorkoutSession.startedAt`'s own optionality for the same column elsewhere.
struct ActivityFeedRow: Decodable, Identifiable, Sendable {
    let sessionID: UUID
    let startedAt: Date?
    let completedAt: Date
    let isGroup: Bool
    let displayName: String
    let setCount: Int
    let volume: Decimal
    let prCount: Int

    var id: UUID { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case isGroup = "is_group"
        case displayName = "display_name"
        case setCount = "set_count"
        case volume
        case prCount = "pr_count"
    }
}
