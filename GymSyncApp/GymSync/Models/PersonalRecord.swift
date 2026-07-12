import Foundation
import Supabase

struct PersonalRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let exerciseID: UUID
    let weight: Decimal
    let reps: Int
    let previousBest: Decimal
    let sessionID: UUID?
    let achievedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case exerciseID = "exercise_id"
        case weight
        case reps
        case previousBest = "previous_best"
        case sessionID = "session_id"
        case achievedAt = "achieved_at"
    }
}

enum PersonalRecordRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Best-effort PR log — called from both detection sites (solo + group live) after
    /// a `weight > priorMax` comparison. Callers should wrap with `try?`; a failed insert
    /// must never block or delay set logging.
    static func record(
        exerciseID: UUID,
        weight: Decimal,
        reps: Int,
        previousBest: Decimal,
        sessionID: UUID?
    ) async throws -> PersonalRecord {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            var row: [String: String] = [
                "id": UUID().uuidString,
                "user_id": userID.uuidString,
                "exercise_id": exerciseID.uuidString,
                "weight": "\(weight)",
                "reps": "\(reps)",
                "previous_best": "\(previousBest)"
            ]
            if let sessionID {
                row["session_id"] = sessionID.uuidString
            }
            let inserted: PersonalRecord = try await client
                .from("personal_records")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            return inserted
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Most recent PRs for a user, descending by `achieved_at`.
    static func recent(userID: UUID, limit: Int) async throws -> [PersonalRecord] {
        do {
            let rows: [PersonalRecord] = try await client
                .from("personal_records")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("achieved_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// PRs achieved within a specific session — backs the session recap's
    /// aggregate PR count, per-lifter PR badges, and "your PR" callout.
    static func bySession(sessionID: UUID) async throws -> [PersonalRecord] {
        do {
            let rows: [PersonalRecord] = try await client
                .from("personal_records")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Count of PRs achieved on/after `date` — backs the "PRs this month" stat tile.
    static func countSince(userID: UUID, date: Date) async throws -> Int {
        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            struct IDRow: Decodable { let id: UUID }
            let rows: [IDRow] = try await client
                .from("personal_records")
                .select("id")
                .eq("user_id", value: userID.uuidString)
                .gte("achieved_at", value: isoFmt.string(from: date))
                .execute()
                .value
            return rows.count
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
