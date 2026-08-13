import CoreLocation
import Foundation
import Supabase

// MARK: - Venue Hubs H1: models, math, repository
//
// Design: docs/superpowers/specs/2026-07-25-venue-hubs-design.md
// Backend: supabase/migrations/20260729000002_venue_hubs.sql
//
// SCOPING NOTE (carried from the design doc so it is visible at the call
// site): SMS phone verification is NOT part of H1 — the user benched
// Twilio. `profiles.phone_verified_at` exists server-side as the switch-on
// point. The age gate, opt-in-only visibility, mutual block exclusion, and
// the 3/hour rate limit ARE enforced (the last three server-side).

/// A row of `venues`. `qr_code_token` is deliberately NOT decoded: H1 has
/// no scan path, and a token the client never needs is a token the client
/// should never hold.
struct Venue: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    /// nil = community-owned (the creator relinquished — 20260814000002).
    let createdBy: UUID?
    let isVerified: Bool
    let bannerURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case radiusMeters = "radius_meters"
        case createdBy = "created_by"
        case isVerified = "is_verified"
        case bannerURL = "banner_url"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A row of `venue_users` — the caller's own membership, or a co-member
/// who has opted in (RLS decides which rows are even visible).
struct VenueMember: Decodable, Identifiable, Sendable {
    let venueID: UUID
    let userID: UUID
    let isVisibleOnHub: Bool
    let lastSeenAt: Date?
    var id: String { "\(venueID)-\(userID)" }

    enum CodingKeys: String, CodingKey {
        case venueID = "venue_id"
        case userID = "user_id"
        case isVisibleOnHub = "is_visible_on_hub"
        case lastSeenAt = "last_seen_at"
    }
}

/// A `venue_month_leaderboard` row.
struct VenueLeaderboardRow: Decodable, Identifiable, Sendable {
    let userID: UUID
    let username: String
    let volume: Decimal
    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case volume
    }
}

// MARK: - VenueMath (pure — see VenueMathTests)

enum VenueMath {
    /// Presence window: a member shows on the hub only if seen within this
    /// interval. A gym session's realistic outer bound — it also means
    /// forgetting to toggle off decays by itself rather than leaving a
    /// stale "here" forever.
    static let presenceWindow: TimeInterval = 4 * 60 * 60

    /// Great-circle metres — the SAME haversine the server's
    /// `private.venue_distance_meters` computes. Client and server must
    /// agree by FORMULA (the client's number only drives the friendly
    /// pre-check; the server's is authoritative), which is exactly why
    /// neither side uses a library the other lacks.
    static func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let a = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
        return earthRadius * 2 * asin(min(1, sqrt(a)))
    }

    /// True when `member` should render in "Who's here" — opted in AND
    /// seen inside the presence window. Mirrors the server's visibility
    /// gate plus the client-side recency rule.
    static func isPresent(_ member: VenueMember, now: Date = .now) -> Bool {
        guard member.isVisibleOnHub, let seen = member.lastSeenAt else { return false }
        return now.timeIntervalSince(seen) <= presenceWindow
    }

    /// "220 m away" / "1.4 km away" — hub list copy.
    static func distanceText(_ meters: Double) -> String {
        meters < 1000
            ? "\(Int(meters.rounded())) m away"
            : String(format: "%.1f km away", meters / 1000)
    }
}

// MARK: - Repository

enum VenueRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Every venue (globally readable by RLS). The client sorts by distance
    /// — v1's venue list is small, and a server-side distance sort would
    /// mean sending the user's coordinates on every browse, which the
    /// design's location-privacy rule avoids.
    static func all() async throws -> [Venue] {
        do {
            let rows: [Venue] = try await client
                .from("venues")
                .select("id, name, latitude, longitude, radius_meters, created_by, is_verified, banner_url")
                .order("name", ascending: true)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    private struct VenueInsert: Encodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Int
        let createdBy: UUID
        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude
            case radiusMeters = "radius_meters"
            case createdBy = "created_by"
        }
    }

    /// Claims a new venue. `is_verified` is never sent — the RLS policy
    /// rejects any insert that sets it (partnership flag is admin-only).
    static func claim(name: String, coordinate: CLLocationCoordinate2D,
                      radiusMeters: Int = 200) async throws -> Venue {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: Venue = try await client
                .from("venues")
                .insert(VenueInsert(
                    name: name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radiusMeters: radiusMeters,
                    createdBy: userID
                ))
                .select("id, name, latitude, longitude, radius_meters, created_by, is_verified, banner_url")
                .single()
                .execute()
                .value
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    /// Rename an owned, unverified venue — rides the creator-edit RLS
    /// policy (a verified venue's row is admin-only, and RLS silently
    /// no-ops the update for non-creators).
    static func rename(venueID: UUID, name: String) async throws {
        do {
            try await client
                .from("venues")
                .update(["name": name])
                .eq("id", value: venueID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct VenueIDParam: Encodable {
        let venueID: UUID
        enum CodingKeys: String, CodingKey { case venueID = "p_venue_id" }
    }

    /// Hand an owned venue to the community (created_by → NULL). The hub,
    /// its members, and their history all survive — only edit rights end.
    static func relinquish(venueID: UUID) async throws {
        do {
            try await client
                .rpc("relinquish_venue", params: VenueIDParam(venueID: venueID))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Delete an owned, unverified venue. Returns false when other members
    /// exist (shared context — the caller should offer relinquish instead).
    static func deleteOwn(venueID: UUID) async throws -> Bool {
        do {
            return try await client
                .rpc("delete_own_venue", params: VenueIDParam(venueID: venueID))
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Members of a venue the caller is allowed to see: their own row plus
    /// opted-in, non-blocked co-members (all decided by RLS — this is a
    /// plain select).
    static func members(venueID: UUID) async throws -> [VenueMember] {
        do {
            let rows: [VenueMember] = try await client
                .from("venue_users")
                .select()
                .eq("venue_id", value: venueID)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    private struct CheckInParams: Encodable {
        let venueID: UUID
        let lat: Double
        let lng: Double
        enum CodingKeys: String, CodingKey {
            case venueID = "p_venue_id"
            case lat = "p_lat"
            case lng = "p_lng"
        }
    }

    /// The authoritative check-in. Server enforces age gate, 3/hour rate
    /// limit, and the geofence — its P0001 messages are user-facing copy
    /// and surface verbatim (same contract as the session check-in window
    /// trigger).
    static func checkIn(venueID: UUID, coordinate: CLLocationCoordinate2D) async throws {
        do {
            _ = try await client
                .rpc("check_in_to_venue", params: CheckInParams(
                    venueID: venueID,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude
                ))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct VisibilityUpdate: Encodable {
        let isVisibleOnHub: Bool
        enum CodingKeys: String, CodingKey { case isVisibleOnHub = "is_visible_on_hub" }
    }

    /// "I'm here — show me on the hub." Owner-scoped UPDATE; the RPC never
    /// touches this column, so the toggle is always the user's own act.
    static func setVisible(venueID: UUID, visible: Bool) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("venue_users")
                .update(VisibilityUpdate(isVisibleOnHub: visible))
                .eq("venue_id", value: venueID)
                .eq("user_id", value: userID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct LeaderboardParams: Encodable {
        let venueID: UUID
        enum CodingKeys: String, CodingKey { case venueID = "p_venue_id" }
    }

    static func leaderboard(venueID: UUID) async throws -> [VenueLeaderboardRow] {
        do {
            let rows: [VenueLeaderboardRow] = try await client
                .rpc("venue_month_leaderboard", params: LeaderboardParams(venueID: venueID))
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}

// MARK: - Age gate

enum AgeGateRepository {
    /// Self-attested 18+ (spec §6.7: honor-system, not ID-verified). The
    /// client stamping this IS the intended mechanism — `check_in_to_venue`
    /// refuses to run without it.
    static func attest18Plus() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        struct AgeUpdate: Encodable {
            let ageVerified: Date
            enum CodingKeys: String, CodingKey { case ageVerified = "age_verified_18plus_at" }
        }
        do {
            _ = try await SupabaseService.shared.client
                .from("profiles")
                .update(AgeUpdate(ageVerified: .now))
                .eq("id", value: userID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Whether the signed-in user has already attested.
    static func hasAttested() async -> Bool {
        guard let userID = await SupabaseService.shared.currentUserID() else { return false }
        struct AgeRow: Decodable {
            let ageVerified: Date?
            enum CodingKeys: String, CodingKey { case ageVerified = "age_verified_18plus_at" }
        }
        let row: AgeRow? = try? await SupabaseService.shared.client
            .from("profiles")
            .select("age_verified_18plus_at")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        return row?.ageVerified != nil
    }
}
