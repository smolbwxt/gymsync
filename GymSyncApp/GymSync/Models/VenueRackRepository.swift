import Foundation
import Supabase

// MARK: - VenueRackRepository
//
// THE RACK COUNT BELONGS TO THE BUILDING (decision 1, 2026-09-18, answering
// R-B3's "who maintains rack counts"). A venue that hosts four squat racks
// hosts them for every crew that trains there, on every day — so the number
// lives on `venues.rack_counts jsonb`, keyed by the equipment classes
// `venues.equipment` already lists, and NOT on a session, a profile or a
// per-crew answer re-asked every time.
//
// ANY LIFTER CHECKED IN THERE MAY SET OR CORRECT IT. The gate is
// `venue_checkins` — a server-verified geofenced presence, which is exactly
// the claim "I can see the racks from here" — and not `venue_users`, which
// only records that somebody joined a hub in March. That table is RLS-enabled
// with NO policies at all, so only a SECURITY DEFINER function can read it,
// which is why the gate lives inside the RPC and cannot live here.
//
// AN ABSENT KEY IS NOT A ZERO. "No racks of this class here" is the class
// missing from `venues.equipment`; an unknown count is the key being absent
// from `rack_counts`, which is why `set_venue_rack_count` rejects 0 rather
// than storing it and why this type answers with a dictionary that simply
// does not carry the key.
enum VenueRackRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct RackCountsRow: Decodable {
        let rackCounts: [String: Int]
        enum CodingKeys: String, CodingKey { case rackCounts = "rack_counts" }
    }

    /// Every rack count this venue has, class → count.
    ///
    /// `venues` is globally readable (the same RLS `VenueRepository.all()`
    /// relies on), so this needs no membership and no check-in. An empty
    /// dictionary is the ordinary answer for a venue nobody has counted yet.
    static func counts(venueID: UUID) async throws -> [String: Int] {
        do {
            let rows: [RackCountsRow] = try await client
                .from("venues")
                .select("rack_counts")
                .eq("id", value: venueID)
                .limit(1)
                .execute()
                .value
            return rows.first?.rackCounts ?? [:]
        } catch { throw ErrorMapping.map(error) }
    }

    private struct SetRackCountParams: Encodable {
        let venueID: UUID
        let equipmentClass: String
        let count: Int
        enum CodingKeys: String, CodingKey {
            case venueID = "p_venue_id"
            case equipmentClass = "p_equipment_class"
            case count = "p_count"
        }
    }

    /// Set (or correct) one class's count. Last write wins, and
    /// `rack_counts_updated_by` / `_at` record who and when, so a wrong
    /// number has an author.
    ///
    /// THE FUNCTION VALIDATES RATHER THAN TRUSTS: `p_equipment_class` must be
    /// one of the five classes, `p_count` is 1-99, and the caller must hold a
    /// `venue_checkins` row at this venue within 12 hours — otherwise it
    /// raises `P0001`. `jsonb_set` on a single key, so two lifters correcting
    /// two different classes cannot clobber each other.
    ///
    /// Every caller shows the raised message where the question was asked and
    /// leaves the stepper standing: a rack count is never on the path of
    /// anything the lifter is waiting for.
    static func set(venueID: UUID, equipmentClass: String, count: Int) async throws {
        do {
            _ = try await client
                .rpc("set_venue_rack_count",
                     params: SetRackCountParams(venueID: venueID,
                                                equipmentClass: equipmentClass,
                                                count: count))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
