import Foundation
import Supabase

/// Create-or-update path for a user's primary gym. The `gyms` table schema
/// (Dossier §B.9) already exists with a unique partial index enforcing at
/// most one `is_primary = true` row per user — a second INSERT with
/// `is_primary = true` for the same user would violate that index, so this
/// repository must UPDATE the existing primary row in place rather than
/// inserting a duplicate.
enum GymRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// If the caller already has a primary gym, updates it (name/lat/lng/radius)
    /// and returns the same row. Otherwise inserts a new row with
    /// `is_primary = true`. Relies on `CheckInService.primaryGym()` to detect
    /// the existing-row case.
    static func upsertPrimary(
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int
    ) async throws -> Gym {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            if let existing = try await CheckInService.primaryGym() {
                struct GymUpdate: Encodable {
                    let name: String
                    let latitude: Double
                    let longitude: Double
                    let radius_meters: Int
                }
                let updated: Gym = try await client
                    .from("gyms")
                    .update(GymUpdate(
                        name: name,
                        latitude: latitude,
                        longitude: longitude,
                        radius_meters: radiusMeters
                    ))
                    .eq("id", value: existing.id.uuidString)
                    .select()
                    .single()
                    .execute()
                    .value
                return updated
            } else {
                struct GymInsert: Encodable {
                    let id: String
                    let user_id: String
                    let name: String
                    let latitude: Double
                    let longitude: Double
                    let radius_meters: Int
                    let is_primary: Bool
                }
                let inserted: Gym = try await client
                    .from("gyms")
                    .insert(GymInsert(
                        id: UUID().uuidString,
                        user_id: userID.uuidString,
                        name: name,
                        latitude: latitude,
                        longitude: longitude,
                        radius_meters: radiusMeters,
                        is_primary: true
                    ))
                    .select()
                    .single()
                    .execute()
                    .value
                return inserted
            }
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
