import XCTest
import HealthKit
@testable import GymSync

final class HealthKitBridgeTests: XCTestCase {
    func testDurationCalculation() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 3700)  // +45 min
        XCTAssertEqual(HealthKitBridge.duration(from: start, to: end), 2700)
    }

    func testTotalVolumeFromSets() {
        let logs: [SetLog] = [
            SetLog(id: UUID(), userID: UUID(), sessionID: UUID(),
                   exerciseID: UUID(), setIndex: 1,
                   reps: 5, weight: 185, rpe: nil,
                   isFailed: false, isPenalty: false, note: nil, loggedAt: .now),
            SetLog(id: UUID(), userID: UUID(), sessionID: UUID(),
                   exerciseID: UUID(), setIndex: 2,
                   reps: 5, weight: 185, rpe: nil,
                   isFailed: false, isPenalty: false, note: nil, loggedAt: .now),
        ]
        XCTAssertEqual(HealthKitBridge.totalVolume(from: logs), 1850)
    }
}
