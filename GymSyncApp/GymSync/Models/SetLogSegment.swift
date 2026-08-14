import Foundation
import Supabase

/// One rung of a drop set's ladder (set structures phase B, owner
/// decision: NESTED sub-rows). The parent `set_logs` row carries the TOP
/// bell — PRs, e1RM, and suggestions read it unchanged — and segments
/// carry the drops: "225→180→145" is one parent (225) plus two segments.
/// Volume: the server trigger (20260814000004) adds each segment's
/// reps × weight to lifetime volume on insert.
struct SetLogSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let setLogID: UUID
    let segmentIndex: Int
    var weight: Decimal?
    var reps: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case setLogID = "set_log_id"
        case segmentIndex = "segment_index"
        case weight, reps
    }
}

enum SetLogSegmentRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Batch-insert a drop ladder's segments. Best-effort at call sites —
    /// a failed ladder write must never block or roll back the parent
    /// set (which already logged through the normal path).
    static func log(_ segments: [SetLogSegment]) async throws {
        guard !segments.isEmpty else { return }
        do {
            try await client
                .from("set_log_segments")
                .insert(segments)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
