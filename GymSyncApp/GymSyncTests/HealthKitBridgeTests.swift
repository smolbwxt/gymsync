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

    // MARK: - estimatedCalories (Phase H — recap Apple Health card)

    func testEstimatedCaloriesFormula() {
        // Flat 7.5 kcal/min, rounded to nearest int (see the function's doc comment).
        XCTAssertEqual(HealthKitBridge.estimatedCalories(minutes: 40), 300)
        XCTAssertEqual(HealthKitBridge.estimatedCalories(minutes: 42), 315)
        // The canvas fixture ("42 min · 318 kcal", dc.html "SOLO RECAP") is a
        // hand-authored proof value, not literally 42.0 minutes — 42.4 min
        // is the duration that actually rounds to 318 kcal under this formula.
        XCTAssertEqual(HealthKitBridge.estimatedCalories(minutes: 42.4), 318)
    }

    func testEstimatedCaloriesClampsNegativeMinutesToZero() {
        XCTAssertEqual(HealthKitBridge.estimatedCalories(minutes: -10), 0)
        XCTAssertEqual(HealthKitBridge.estimatedCalories(minutes: 0), 0)
    }

    // MARK: - Duration-edit re-export (Phase H — metadata-stamping pure logic)

    func testExportMetadataStampsSessionID() {
        let sessionID = UUID()
        let metadata = HealthKitBridge.exportMetadata(sessionID: sessionID)
        XCTAssertEqual(metadata[HKMetadataKeyExternalUUID] as? String, sessionID.uuidString)
        XCTAssertEqual(metadata.count, 1, "exportMetadata should stamp exactly the external-UUID key")
    }

    func testExportPredicateIsKeyedPerSession() {
        // Pure NSPredicate construction — no HKHealthStore access, hermetic.
        // Two different sessions must produce predicates over different
        // allowed values; predicateFormat is the safe way to assert this
        // (NSPredicate equality semantics for HK's internal predicate
        // subclasses aren't a contract this test should lean on).
        let sessionA = UUID()
        let sessionB = UUID()
        let predicateA = HealthKitBridge.exportPredicate(sessionID: sessionA)
        let predicateB = HealthKitBridge.exportPredicate(sessionID: sessionB)
        XCTAssertNotEqual(predicateA.predicateFormat, predicateB.predicateFormat)
        XCTAssertTrue(predicateA.predicateFormat.contains(sessionA.uuidString))
    }

    // MARK: - Weekly goal distance read (Stream A task A7 — pure mapping)

    func testActivityTypeMapsTheGoalEditorsFourActivities() {
        XCTAssertEqual(HealthKitBridge.activityType(for: "run"), .running)
        XCTAssertEqual(HealthKitBridge.activityType(for: "bike"), .cycling)
        XCTAssertEqual(HealthKitBridge.activityType(for: "row"), .rowing)
        XCTAssertEqual(HealthKitBridge.activityType(for: "walk"), .walking)
    }

    func testActivityTypeIsCaseInsensitive() {
        XCTAssertEqual(HealthKitBridge.activityType(for: "RUN"), .running)
        XCTAssertEqual(HealthKitBridge.activityType(for: "Bike"), .cycling)
    }

    func testUnknownActivityMapsToNilRatherThanMatchingEverything() {
        XCTAssertNil(HealthKitBridge.activityType(for: "swim"))
        XCTAssertNil(HealthKitBridge.activityType(for: ""))
    }
}
