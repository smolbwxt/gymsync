import XCTest
@testable import GymSync

/// `SessionStations` and `StationSplit` — plan task S1 (the shape and the
/// count); plan task S3 extends this file with `assign`'s laws.
///
/// The station assignment crosses the wire as `sessions.stations`, a jsonb
/// column written ONLY by `public.set_session_stations`
/// (`20260913000102_session_round_engine.sql`, plan task D3). Swift decodes
/// what Postgres validates, so the two must agree about every key — which is
/// what the literal below is for.
final class SessionStationsTests: XCTestCase {

    // MARK: - The contract
    //
    // `sessions.stations`' own COMMENT ON COLUMN (plan task D1) states the
    // shape as:
    //
    //   {"exercise_position": int, "stations": [{"name": text,
    //    "lifter_ids": [uuid], "turn_order": [uuid]}]}
    //
    // THIS LITERAL IS THE CONTRACT (plan ruling R-B5). It is that comment
    // with concrete values substituted for the type names and nothing else
    // changed — no added key, no renamed key, no reordering. If D3's
    // validation and this decoder ever disagree, this test is what says so.
    private let contractJSON = """
    {"exercise_position": 2, "stations": [{"name": "RACK A", \
    "lifter_ids": ["3f1e0d5c-0000-4000-8000-00000000a001", \
    "3f1e0d5c-0000-4000-8000-00000000a002"], \
    "turn_order": ["3f1e0d5c-0000-4000-8000-00000000a001", \
    "3f1e0d5c-0000-4000-8000-00000000a002"]}, \
    {"name": "RACK B", \
    "lifter_ids": ["3f1e0d5c-0000-4000-8000-00000000a003"], \
    "turn_order": ["3f1e0d5c-0000-4000-8000-00000000a003"]}]}
    """

    private let sam  = UUID(uuidString: "3F1E0D5C-0000-4000-8000-00000000A001")!
    private let dana = UUID(uuidString: "3F1E0D5C-0000-4000-8000-00000000A002")!
    private let lee  = UUID(uuidString: "3F1E0D5C-0000-4000-8000-00000000A003")!

    private func decodeContract() throws -> SessionStations {
        try JSONDecoder().decode(SessionStations.self, from: Data(contractJSON.utf8))
    }

    func testTheColumnsShapeDecodes() throws {
        let stations = try decodeContract()
        XCTAssertEqual(stations.exercisePosition, 2)
        XCTAssertEqual(stations.stations.count, 2)
        XCTAssertEqual(stations.stations[0].name, "RACK A")
        XCTAssertEqual(stations.stations[0].lifterIDs, [sam, dana])
        XCTAssertEqual(stations.stations[0].turnOrder, [sam, dana])
        XCTAssertEqual(stations.stations[1].name, "RACK B")
        XCTAssertEqual(stations.stations[1].lifterIDs, [lee])
        XCTAssertEqual(stations.stations[1].turnOrder, [lee])
    }

    /// Postgres writes uuids lower-cased; Swift's `UUID` prints them upper.
    /// The decoder must not care, because the column will only ever hand us
    /// the lower-cased form.
    func testLowerCasedUuidsFromPostgresDecode() throws {
        let stations = try decodeContract()
        XCTAssertEqual(stations.stations[0].lifterIDs.first, sam)
    }

    /// The keys we WRITE must be the keys D3 validates. An encoder that
    /// emitted `lifterIDs` would be rejected by `set_session_stations`'
    /// shape check at runtime and by nothing at compile time.
    func testTheEncodedKeysAreTheColumnsKeys() throws {
        let contract = try decodeContract()
        let encoded = try JSONEncoder().encode(contract)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["exercise_position", "stations"])

        let rows = try XCTUnwrap(object["stations"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(Set(row.keys), ["name", "lifter_ids", "turn_order"])
        }
    }

    func testTheShapeRoundTrips() throws {
        let original = try decodeContract()
        let reread = try JSONDecoder().decode(
            SessionStations.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(reread, original)
    }

    /// A crew of one is one station of one — the shape has no special case
    /// for a solo lifter and must not need one.
    func testASingleStationEncodesAndDecodes() throws {
        let one = SessionStations(
            exercisePosition: 0,
            stations: [SessionStations.Station(name: "RACK A", lifterIDs: [sam], turnOrder: [sam])]
        )
        let reread = try JSONDecoder().decode(
            SessionStations.self, from: JSONEncoder().encode(one)
        )
        XCTAssertEqual(reread, one)
    }

    // MARK: - StationSplit.count (the five data decisions, decision 3)
    //
    // max(1, min(ceil(crew / 3), equipmentCap ?? Int.max)). The cap is a
    // real parameter with real tests; B1 passes `nil` at every call site
    // because no session -> venue link and no rack COUNT exist (venues.
    // equipment is a text[] of equipment CLASSES). Inventing a rack count
    // from that list is what this signature refuses to do.

    func testTheCountIsCeilOfAThirdOfTheCrew() {
        XCTAssertEqual(StationSplit.count(crew: 1, equipmentCap: nil), 1)
        XCTAssertEqual(StationSplit.count(crew: 3, equipmentCap: nil), 1)
        XCTAssertEqual(StationSplit.count(crew: 4, equipmentCap: nil), 2)
        XCTAssertEqual(StationSplit.count(crew: 5, equipmentCap: nil), 2)
        XCTAssertEqual(StationSplit.count(crew: 6, equipmentCap: nil), 2)
        XCTAssertEqual(StationSplit.count(crew: 7, equipmentCap: nil), 3)
    }

    func testACapOfOneCollapsesEveryCrewToOneStation() {
        for crew in 1...12 {
            XCTAssertEqual(StationSplit.count(crew: crew, equipmentCap: 1), 1,
                           "crew of \(crew) with one rack")
        }
    }

    func testACapOfTwoBindsOnlyOnceTheCrewOutgrowsIt() {
        XCTAssertEqual(StationSplit.count(crew: 1, equipmentCap: 2), 1)
        XCTAssertEqual(StationSplit.count(crew: 3, equipmentCap: 2), 1)
        XCTAssertEqual(StationSplit.count(crew: 4, equipmentCap: 2), 2)
        XCTAssertEqual(StationSplit.count(crew: 5, equipmentCap: 2), 2)
        XCTAssertEqual(StationSplit.count(crew: 6, equipmentCap: 2), 2)
        XCTAssertEqual(StationSplit.count(crew: 7, equipmentCap: 2), 2)
    }

    /// There is always at least one station: an empty room, a nonsense cap
    /// and a negative crew all answer 1 rather than 0. A zero would divide
    /// the crew into nothing.
    func testThereIsAlwaysAtLeastOneStation() {
        XCTAssertEqual(StationSplit.count(crew: 0, equipmentCap: nil), 1)
        XCTAssertEqual(StationSplit.count(crew: 0, equipmentCap: 0), 1)
        XCTAssertEqual(StationSplit.count(crew: 9, equipmentCap: 0), 1)
        XCTAssertEqual(StationSplit.count(crew: -3, equipmentCap: nil), 1)
    }

    /// No station is ever deeper than three when the cap is absent — the
    /// count is what makes `assign`'s depth law (plan task S3) reachable.
    func testAnUncappedCountAlwaysAdmitsADepthOfThree() {
        for crew in 1...12 {
            let stations = StationSplit.count(crew: crew, equipmentCap: nil)
            XCTAssertGreaterThanOrEqual(stations * 3, crew, "crew of \(crew)")
        }
    }
}
