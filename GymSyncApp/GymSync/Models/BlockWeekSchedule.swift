import Foundation
import Supabase

// MARK: - BlockWeekSchedule
//
// One week of a block carrying its own training days (owner 2026-08-25:
// "each week can carry its own schedule"). A block's default rhythm
// still lives in its SessionSeries; this is the per-week OVERRIDE, so a
// block that never varies stores nothing and behaves exactly as before.
//
// `weekdays` uses Calendar's own convention — 1 = Sunday … 7 = Saturday
// — so a value read here can be compared directly against
// `Calendar.component(.weekday:)` with no ±1 translation anywhere.
struct BlockWeekSchedule: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let enrollmentID: UUID
    let weekNumber: Int
    var weekdays: [Int]
    var hour: Int
    var minute: Int

    enum CodingKeys: String, CodingKey {
        case id
        case enrollmentID = "enrollment_id"
        case weekNumber = "week_number"
        case weekdays, hour, minute
    }

    /// "MON · WED · FRI · 6:00 PM" — the sheet's and the calendar's
    /// shared readback, so the two can never describe a week differently.
    var summary: String {
        guard !weekdays.isEmpty else { return "No days set" }
        let names = ["", "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        let days = weekdays.sorted()
            .compactMap { names.indices.contains($0) ? names[$0] : nil }
            .joined(separator: " · ")
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let time = Calendar.current.date(from: components).map { formatter.string(from: $0) } ?? ""
        return time.isEmpty ? days : "\(days) · \(time)"
    }
}

enum BlockWeekScheduleRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Every per-week override for a block, keyed by week number.
    static func forEnrollment(_ enrollmentID: UUID) async -> [Int: BlockWeekSchedule] {
        let rows: [BlockWeekSchedule]? = try? await client
            .from("block_week_schedules")
            .select("id, enrollment_id, week_number, weekdays, hour, minute")
            .eq("enrollment_id", value: enrollmentID.uuidString)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: (rows ?? []).map { ($0.weekNumber, $0) })
    }

    /// Upsert one week's days. The (enrollment, week) unique constraint
    /// makes this idempotent, so the sheet can save on every toggle.
    @discardableResult
    static func save(enrollmentID: UUID, weekNumber: Int,
                     weekdays: [Int], hour: Int, minute: Int) async -> BlockWeekSchedule? {
        guard let me = await SupabaseService.shared.currentUserID() else { return nil }
        struct Upsert: Encodable {
            let user_id: String
            let enrollment_id: String
            let week_number: Int
            let weekdays: [Int]
            let hour: Int
            let minute: Int
        }
        return try? await client
            .from("block_week_schedules")
            .upsert(Upsert(user_id: me.uuidString,
                           enrollment_id: enrollmentID.uuidString,
                           week_number: weekNumber,
                           weekdays: weekdays.sorted(),
                           hour: hour, minute: minute),
                    onConflict: "enrollment_id,week_number")
            .select("id, enrollment_id, week_number, weekdays, hour, minute")
            .single()
            .execute()
            .value
    }

    /// Drop a week's override so it falls back to the block's default
    /// rhythm — "same as the rest of the block" is a real answer, and it
    /// should not be stored as an empty day list.
    static func clear(enrollmentID: UUID, weekNumber: Int) async {
        _ = try? await client
            .from("block_week_schedules")
            .delete()
            .eq("enrollment_id", value: enrollmentID.uuidString)
            .eq("week_number", value: weekNumber)
            .execute()
    }
}
