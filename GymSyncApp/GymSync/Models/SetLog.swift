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
    /// Owner items 6+7 (20260813000003): the lifter's body weight in
    /// CANONICAL POUNDS, stamped at log time for bodyweight-equipment
    /// exercises — a snapshot on purpose (last month's pull-ups were done
    /// at last month's body weight). nil for loaded lifts and for lifters
    /// with no body-weight log. Trailing default keeps every construction
    /// site compiling.
    var bodyWeightLbs: Decimal? = nil

    /// reps × this = honest tonnage: added load plus the body weight the
    /// set actually moved. nil when neither component exists (the set
    /// contributes no volume rather than a guessed one).
    var effectiveWeightPounds: Decimal? {
        if weight == nil && bodyWeightLbs == nil { return nil }
        return (weight ?? 0) + (bodyWeightLbs ?? 0)
    }

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
        case bodyWeightLbs = "body_weight_lbs"
    }
}
