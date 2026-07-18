import Foundation
import Supabase

// MARK: - BodyWeightLog (Phase H Task 3)
//
// One `body_weight_logs` row (20260724000001_body_weight_logs.sql). RLS:
// owner-only in both directions (single `FOR ALL` policy, `user_id =
// auth.uid()`) — same idiom as `UserStreak`'s single-owner tables, except
// this one IS client-writable (no SECURITY DEFINER trigger gate). Master
// spec schema (docs/superpowers/specs/2026-06-28-gymsync-design.md:395-401)
// is verbatim: id/user_id/weight/unit/logged_at, no other columns.
struct BodyWeightLog: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    let weight: Decimal
    let unit: String
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case weight
        case unit
        case loggedAt = "logged_at"
    }
}

enum BodyWeightLogRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// This user's log rows, most-recent-first — backs the Stats "Body
    /// Weight" trend chart. `limit` defaults to a generous window (twice-
    /// weekly logging for 3 years is still under 400 rows); `TrendChartView`
    /// filters the fetched set down to the selected 8w/6m/1y range
    /// client-side, same idiom `ExerciseHistoryView.chartData` already uses
    /// for the Est. 1RM trend.
    static func recent(userID: UUID, limit: Int = 400) async throws -> [BodyWeightLog] {
        do {
            let rows: [BodyWeightLog] = try await client
                .from("body_weight_logs")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Logs a new weight entry as the current user, timestamped `now()` by
    /// the column default (omitted here, same "absence means default"
    /// idiom `user_settings`'s repository-less insert relies on for
    /// `default_rest_seconds`/`palette`). `unit` defaults to `"lbs"` — no
    /// unit-preference setting exists anywhere in `profiles`/
    /// `user_settings` today (grepped both before writing this; confirmed
    /// absent), so this is the task brief's documented default, not a read
    /// of a per-user setting. Dictionary-insert + `"\(weight)"` string
    /// coercion mirrors `PersonalRecordRepository.record`'s exact idiom for
    /// a `numeric` column (Models/PersonalRecord.swift:58-64).
    @discardableResult
    static func log(weight: Decimal, unit: String = "lbs") async throws -> BodyWeightLog {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let inserted: BodyWeightLog = try await client
                .from("body_weight_logs")
                .insert([
                    "user_id": userID.uuidString,
                    "weight": "\(weight)",
                    "unit": unit,
                ])
                .select()
                .single()
                .execute()
                .value
            return inserted
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
