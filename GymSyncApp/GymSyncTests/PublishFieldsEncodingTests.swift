import XCTest
@testable import GymSync

// Pure `JSONEncoder` round-trips for `RoutineRepository.PublishFieldsUpdate`
// — no network/simulator dependency. Mirrors BurpeeLedgerMathTests' shape
// (pure-function coverage, no live-DB setUp), itself following
// StatDerivationTests' established pattern for this test target.
//
// `PublishFieldsUpdate` is the codebase's first explicit-null-clearing
// `Encodable` (`encode(to:)` calls `container.encode(_:forKey:)`, not the
// synthesized `encodeIfPresent`, so a `nil` field serializes as JSON `null`
// instead of being omitted — see that type's doc comment in Routine.swift
// for why PostgREST's PATCH needs the explicit null). These tests verify
// that behavior directly against the encoder, independent of the network
// round-trip `updatePublishFields` wraps it in.
final class PublishFieldsEncodingTests: XCTestCase {

    private func encodeToDict(_ value: RoutineRepository.PublishFieldsUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try XCTUnwrap(obj as? [String: Any])
    }

    // MARK: - All fields set

    func testEncode_allFieldsSet_containsAllThreeKeysWithValues() throws {
        let topSetID = UUID()
        let update = RoutineRepository.PublishFieldsUpdate(
            defaultSort: "time",
            scoringMetrics: ["time", "volume", "top_set"],
            scoringTopSetExerciseID: topSetID
        )
        let dict = try encodeToDict(update)

        XCTAssertEqual(dict["default_sort"] as? String, "time")
        XCTAssertEqual(dict["scoring_metrics"] as? [String], ["time", "volume", "top_set"])
        XCTAssertEqual(dict["scoring_top_set_exercise_id"] as? String, topSetID.uuidString)
    }

    // MARK: - All fields nil

    func testEncode_allFieldsNil_serializesExplicitNullsNotMissingKeys() throws {
        let update = RoutineRepository.PublishFieldsUpdate(
            defaultSort: nil,
            scoringMetrics: nil,
            scoringTopSetExerciseID: nil
        )
        let data = try JSONEncoder().encode(update)
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let dict = try XCTUnwrap(obj as? [String: Any])

        // All 3 keys must be PRESENT (not omitted) and hold NSNull — this is
        // the whole point of the explicit `encode(to:)`: a synthesized
        // `encodeIfPresent` would drop these keys entirely, and PostgREST's
        // PATCH leaves the previously-set column value stuck instead of
        // clearing it.
        XCTAssertEqual(dict.count, 3)
        XCTAssertTrue(dict.keys.contains("default_sort"))
        XCTAssertTrue(dict.keys.contains("scoring_metrics"))
        XCTAssertTrue(dict.keys.contains("scoring_top_set_exercise_id"))
        XCTAssertTrue(dict["default_sort"] is NSNull)
        XCTAssertTrue(dict["scoring_metrics"] is NSNull)
        XCTAssertTrue(dict["scoring_top_set_exercise_id"] is NSNull)

        // Also assert against the raw serialized string, independent of
        // JSONSerialization's own null handling: the "null" token must
        // literally appear for each key.
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"default_sort\":null"))
        XCTAssertTrue(json.contains("\"scoring_metrics\":null"))
        XCTAssertTrue(json.contains("\"scoring_top_set_exercise_id\":null"))
    }

    // MARK: - Mixed

    func testEncode_mixedFields_setFieldsHaveValuesNilFieldsAreExplicitNull() throws {
        // The exact shape a curator un-picking ONLY "Top Set" produces:
        // defaultSort/scoringMetrics still set, the top-set id cleared.
        let update = RoutineRepository.PublishFieldsUpdate(
            defaultSort: "volume",
            scoringMetrics: ["volume"],
            scoringTopSetExerciseID: nil
        )
        let dict = try encodeToDict(update)

        XCTAssertEqual(dict.count, 3)
        XCTAssertEqual(dict["default_sort"] as? String, "volume")
        XCTAssertEqual(dict["scoring_metrics"] as? [String], ["volume"])
        XCTAssertTrue(dict.keys.contains("scoring_top_set_exercise_id"))
        XCTAssertTrue(dict["scoring_top_set_exercise_id"] is NSNull)
    }
}
