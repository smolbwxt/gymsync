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

    /// Failure doctrine (owner 2026-08-13): a failed set is CALIBRATION,
    /// not noise. Logging n reps with FAIL means the nth rep was attempted
    /// and missed — n − 1 reps were COMPLETED with nothing left in the
    /// tank (true RIR 0), which is the exact domain 1RM formulas were fit
    /// on and better data than any RPE guess. The one failure that carries
    /// no strength information is the missed single (n ≤ 1): zero reps
    /// completed proves nothing was lifted → nil. Clean sets pass reps
    /// through unchanged. Every PR judgment, e1RM estimate, and suggestion
    /// path reads THIS, never raw `reps`, so the two can't drift.
    var completedReps: Int? {
        guard let reps, reps > 0 else { return nil }
        guard isFailed else { return reps }
        return reps > 1 ? reps - 1 : nil
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
