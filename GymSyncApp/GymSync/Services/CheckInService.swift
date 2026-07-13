import CoreLocation
import Foundation
import Supabase

// MARK: - Gym model

struct Gym: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case latitude
        case longitude
        case radiusMeters = "radius_meters"
        case isPrimary = "is_primary"
    }
}

// MARK: - CheckInService

enum CheckInService {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: Primary gym query

    /// Returns the user's primary gym, or nil if none is set.
    static func primaryGym() async throws -> Gym? {
        do {
            let gym: Gym = try await client
                .from("gyms")
                .select()
                .eq("is_primary", value: true)
                .single()
                .execute()
                .value
            return gym
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            AppLogger.db.error("primaryGym fetch failed: \(error.localizedDescription, privacy: .public)")
            throw ErrorMapping.map(error)
        }
    }

    // MARK: Geofence check (pure)

    /// Returns true if `location` is within the gym's geofence radius.
    static func distanceCheck(gym: Gym, location: CLLocation) -> Bool {
        let gymLocation = CLLocation(latitude: gym.latitude, longitude: gym.longitude)
        return location.distance(from: gymLocation) <= Double(gym.radiusMeters)
    }

    // MARK: One-shot location

    /// Requests a one-shot current location. Asks for when-in-use auth if not yet determined.
    /// Throws `GymSyncError.validation("Location unavailable")` on denial or failure, or
    /// `GymSyncError.validation("Location timed out")` if no CLLocationManager callback
    /// fires within the hard timeout (see `LocationOneShotHelper.fetchLocation()`).
    @MainActor
    static func requestLocation() async throws -> CLLocation {
        try await LocationOneShotHelper().fetchLocation()
    }
}

// MARK: - LocationOneShotHelper

/// Retained for the duration of the async call; holds the CLLocationManager + delegate.
///
/// `@MainActor`-isolated so `CLLocationManager` is always constructed and driven from the
/// main run loop — a non-isolated `async` context can otherwise run on a Swift Concurrency
/// cooperative-pool thread with no actively-pumped run loop, which is a well-known failure
/// mode where CLLocationManager silently never delivers delegate callbacks (see Bug 2 in
/// the device-QA diagnosis).
@MainActor
private final class LocationOneShotHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Hard timeout for the one-shot location fetch. Covers Location Services off
    /// system-wide, an unanswered `.notDetermined` prompt, an indoor GPS fix that never
    /// resolves, or any other path where no CLLocationManager delegate callback ever fires.
    private static let timeout: Duration = .seconds(10)

    func fetchLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // Auth delegate will call requestLocation() after grant.
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                resume(throwing: GymSyncError.validation("Location unavailable"))
            @unknown default:
                resume(throwing: GymSyncError.validation("Location unavailable"))
            }

            // Race the delegate callback against a hard timeout. Whichever fires first
            // wins — `resume(throwing:)`/`resume(returning:)` are guarded by the
            // `continuation = nil` check below, so this is safe to call even after a
            // delegate callback (or a prior timeout) already resumed.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.timeout)
                self?.resume(throwing: GymSyncError.validation("Location timed out"))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(throwing: GymSyncError.validation("Location unavailable"))
        case .notDetermined:
            break  // still waiting
        @unknown default:
            resume(throwing: GymSyncError.validation("Location unavailable"))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            resume(returning: location)
        } else {
            resume(throwing: GymSyncError.validation("Location unavailable"))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(throwing: GymSyncError.validation("Location unavailable"))
    }

    // MARK: - Safe single-resume

    private func resume(returning location: CLLocation) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: location)
    }

    private func resume(throwing error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(throwing: error)
    }
}
