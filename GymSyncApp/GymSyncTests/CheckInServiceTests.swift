import CoreLocation
import XCTest
@testable import GymSync

final class CheckInServiceTests: XCTestCase {
    // Fixed gym at a well-known coordinate (lat/lon near San Francisco Ferry Building)
    private let gymLat = 37.7955
    private let gymLon = -122.3937
    private let gymRadius = 200  // metres

    private func makeGym() -> Gym {
        Gym(
            id: UUID(),
            userID: UUID(),
            name: "Test Gym",
            latitude: gymLat,
            longitude: gymLon,
            radiusMeters: gymRadius,
            isPrimary: true
        )
    }

    // MARK: - distanceCheck: inside radius

    /// A location ~150 m north of the gym (0.00135° latitude ≈ 150 m).
    func testDistanceCheckInsideRadius() {
        let gym = makeGym()
        let nearbyLocation = CLLocation(latitude: gymLat + 0.00135, longitude: gymLon)
        XCTAssertTrue(
            CheckInService.distanceCheck(gym: gym, location: nearbyLocation),
            "A point ~150 m from the gym centre should be inside the 200 m radius"
        )
    }

    // MARK: - distanceCheck: outside radius

    /// A location ~500 m north of the gym (0.0045° latitude ≈ 500 m).
    func testDistanceCheckOutsideRadius() {
        let gym = makeGym()
        let farLocation = CLLocation(latitude: gymLat + 0.0045, longitude: gymLon)
        XCTAssertFalse(
            CheckInService.distanceCheck(gym: gym, location: farLocation),
            "A point ~500 m from the gym centre should be outside the 200 m radius"
        )
    }

    // MARK: - distanceCheck: exactly at gym centre

    func testDistanceCheckAtGymCentre() {
        let gym = makeGym()
        let exactLocation = CLLocation(latitude: gymLat, longitude: gymLon)
        XCTAssertTrue(
            CheckInService.distanceCheck(gym: gym, location: exactLocation),
            "The gym centre itself should pass the geofence check"
        )
    }
}
