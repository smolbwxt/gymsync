import CoreLocation
import XCTest
@testable import GymSync

/// Pure coverage for `VenueMath` — no network. The distance cases are the
/// load-bearing ones: the client's haversine must agree with the SQL
/// `private.venue_distance_meters` the server gates check-in on, or a user
/// standing inside the radius gets a friendly "you're here" and then a
/// server rejection (or worse, the reverse).
final class VenueMathTests: XCTestCase {

    private func coord(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Distance

    func testDistanceZeroForSamePoint() {
        XCTAssertEqual(VenueMath.distanceMeters(from: coord(34, -118), to: coord(34, -118)),
                       0, accuracy: 0.001)
    }

    /// 0.01° of latitude ≈ 1.11 km anywhere on the globe — the exact case
    /// the pgTAP suite uses for its out-of-geofence rejection, so both
    /// sides are pinned to the same number.
    func testDistanceOneHundredthDegreeLatitude() {
        let meters = VenueMath.distanceMeters(from: coord(34.00, -118.00), to: coord(34.01, -118.00))
        XCTAssertEqual(meters, 1111.9, accuracy: 1.0)
    }

    /// Longitude degrees shrink with latitude — at 34°N, 0.01° of longitude
    /// is ~921 m, not 1112. A flat-earth (equirectangular) approximation
    /// would miss this; the server's haversine does not.
    func testDistanceLongitudeShrinksWithLatitude() {
        let meters = VenueMath.distanceMeters(from: coord(34.00, -118.00), to: coord(34.00, -118.01))
        XCTAssertEqual(meters, 921.8, accuracy: 2.0)
    }

    func testDistanceIsSymmetric() {
        let a = coord(40.7128, -74.0060)
        let b = coord(34.0522, -118.2437)
        XCTAssertEqual(VenueMath.distanceMeters(from: a, to: b),
                       VenueMath.distanceMeters(from: b, to: a),
                       accuracy: 0.001)
    }

    /// A default 200 m radius must accept a point ~110 m out and reject one
    /// ~330 m out (0.001° and 0.003° latitude).
    func testDistanceAgainstDefaultRadius() {
        let venue = coord(34.0, -118.0)
        XCTAssertLessThan(VenueMath.distanceMeters(from: coord(34.001, -118.0), to: venue), 200)
        XCTAssertGreaterThan(VenueMath.distanceMeters(from: coord(34.003, -118.0), to: venue), 200)
    }

    // MARK: - Presence

    private func member(visible: Bool, seenMinutesAgo: Double?) -> VenueMember {
        VenueMember(
            venueID: UUID(),
            userID: UUID(),
            isVisibleOnHub: visible,
            lastSeenAt: seenMinutesAgo.map { Date.now.addingTimeInterval(-$0 * 60) }
        )
    }

    func testPresenceRequiresOptInAndRecency() {
        XCTAssertTrue(VenueMath.isPresent(member(visible: true, seenMinutesAgo: 30)))
        // Opted in but stale — the window is 4h.
        XCTAssertFalse(VenueMath.isPresent(member(visible: true, seenMinutesAgo: 60 * 5)))
        // Recent but opted out — never present.
        XCTAssertFalse(VenueMath.isPresent(member(visible: false, seenMinutesAgo: 1)))
        // Never checked in.
        XCTAssertFalse(VenueMath.isPresent(member(visible: true, seenMinutesAgo: nil)))
    }

    func testPresenceWindowBoundary() {
        let justInside = member(visible: true, seenMinutesAgo: 239)
        let justOutside = member(visible: true, seenMinutesAgo: 241)
        XCTAssertTrue(VenueMath.isPresent(justInside))
        XCTAssertFalse(VenueMath.isPresent(justOutside))
    }

    // MARK: - Copy

    func testDistanceText() {
        XCTAssertEqual(VenueMath.distanceText(220), "220 m away")
        XCTAssertEqual(VenueMath.distanceText(999), "999 m away")
        XCTAssertEqual(VenueMath.distanceText(1400), "1.4 km away")
    }
}
