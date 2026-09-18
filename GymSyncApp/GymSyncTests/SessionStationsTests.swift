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

    // MARK: - StationSplit.assign (spec §3.3, owner decisions 2 and 6) — S3

    /// Twelve stable lifters. `id(0)` is `a`, `id(1)` is `b`, and so on, so a
    /// failing assertion prints a readable order.
    private func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000000%02d", index))!
    }
    private var a: UUID { id(0) }
    private var b: UUID { id(1) }
    private var c: UUID { id(2) }
    private var d: UUID { id(3) }
    private var e: UUID { id(4) }
    private var g: UUID { id(5) }
    private var h: UUID { id(6) }

    private func crew(_ n: Int) -> [UUID] { (0..<n).map(id) }

    private func stations(_ groups: [[UUID]], at position: Int = 0) -> SessionStations {
        SessionStations(
            exercisePosition: position,
            stations: groups.enumerated().map { index, members in
                SessionStations.Station(name: "RACK \(index)",
                                        lifterIDs: members,
                                        turnOrder: members)
            }
        )
    }

    // --- the two laws that hold for every input -----------------------------

    /// Owner decision 2. `set_session_stations` rejects a deeper station
    /// outright, so a split that produced one would fail the write entirely.
    func testNoStationIsEverDeeperThanThree() {
        for size in 1...12 {
            let split = StationSplit.assign(
                lifters: crew(size),
                count: StationSplit.count(crew: size, equipmentCap: nil),
                restMedians: [:],
                previous: nil
            )
            for station in split {
                XCTAssertLessThanOrEqual(station.count, 3, "crew of \(size): \(split)")
            }
        }
    }

    /// Asserted as a SET, not a count: two stations that each hold the same
    /// lifter also add up to the right total.
    func testEveryLifterAppearsExactlyOnce() {
        for size in 1...12 {
            let lifters = crew(size)
            let flat = StationSplit.assign(
                lifters: lifters,
                count: StationSplit.count(crew: size, equipmentCap: nil),
                restMedians: [:],
                previous: nil
            ).flatMap { $0 }
            XCTAssertEqual(Set(flat), Set(lifters), "crew of \(size)")
            XCTAssertEqual(flat.count, lifters.count, "crew of \(size) — a duplicate")
        }
    }

    /// No rack carries two more lifters than another: a station of three
    /// beside a station of one is a queue, not a split.
    func testTheStationsAreBalanced() {
        for size in 1...12 {
            let split = StationSplit.assign(
                lifters: crew(size),
                count: StationSplit.count(crew: size, equipmentCap: nil),
                restMedians: [:],
                previous: nil
            )
            let sizes = split.map(\.count)
            XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1,
                                     "crew of \(size): \(sizes)")
        }
    }

    /// THE DEPTH LAW WINS OVER THE COUNT. A one-rack cap cannot put seven
    /// lifters on one rack — the server would reject the write, so the split
    /// raises the count instead of obeying the cap.
    func testACountThatWouldBreakTheDepthLawIsRaised() {
        let split = StationSplit.assign(lifters: crew(7), count: 1,
                                        restMedians: [:], previous: nil)
        XCTAssertEqual(split.count, 3)
        XCTAssertEqual(split, [[a, b, c], [d, e], [g, h]])
    }

    // --- the empty previous, and a crew that cannot split -------------------

    /// Nothing to shift: the crew is dealt in the turn order the caller
    /// handed over.
    func testAnEmptyPreviousDealsInTheGivenOrder() {
        let split = StationSplit.assign(lifters: [a, b, c, d, e], count: 2,
                                        restMedians: [:], previous: nil)
        XCTAssertEqual(split, [[a, b, c], [d, e]])
    }

    /// A crew of three IS one station. There is no re-mix to make: whoever
    /// the order puts first, the three of them rest together either way.
    /// (The live body does not even call this below four — the assertion is
    /// that the function stays sane if something does.)
    func testACrewOfThreeIsOneStationWhoeverElseHasLifted() {
        let split = StationSplit.assign(lifters: [a, b, c], count: 1,
                                        restMedians: [a: 40, b: 200, c: 90],
                                        previous: stations([[a, b, c]]))
        XCTAssertEqual(split.count, 1)
        XCTAssertEqual(Set(split[0]), Set([a, b, c]))
    }

    func testAnEmptyCrewIsNoStations() {
        XCTAssertEqual(StationSplit.assign(lifters: [], count: 2,
                                           restMedians: [:], previous: nil).count, 0)
    }

    // --- branch 1: close rests rotate ---------------------------------------

    /// Spec §3.3's "re-mixes only while averages are close". The previous
    /// order shifts by exactly one, so the pairs change at every exercise.
    func testCloseRestsRotateTheOrderByExactlyOneStep() {
        let split = StationSplit.assign(
            lifters: [a, b, c, d, e],
            count: 2,
            restMedians: [a: 60, b: 70, c: 65, d: 80, e: 62],   // spread 20
            previous: stations([[a, b, c], [d, e]])
        )
        XCTAssertEqual(split, [[b, c, d], [e, a]])
    }

    /// The point of the rotation, stated as the thing the crew experiences:
    /// nobody keeps the same rest partners.
    func testTheRotationChangesWhoRestsTogether() {
        let previous = stations([[a, b, c], [d, e]])
        let split = StationSplit.assign(lifters: [a, b, c, d, e], count: 2,
                                        restMedians: [:], previous: previous)
        let before = previous.stations.map { Set($0.lifterIDs) }
        let after = split.map { Set($0) }
        XCTAssertNotEqual(before, after)
        XCTAssertTrue(after.contains { $0.contains(a) && $0.contains(e) },
                      "the two ends of the old order now share a rack: \(split)")
    }

    /// A lifter who left the previous assignment is dropped; one who arrived
    /// since is dealt in behind the crew that was already standing there.
    func testTheOrderFollowsWhoIsActuallyHere() {
        let split = StationSplit.assign(
            lifters: [b, c, d, e, g],                         // a left, g arrived
            count: 2,
            restMedians: [:],
            previous: stations([[a, b, c], [d, e]])
        )
        XCTAssertEqual(split, [[c, d, e], [g, b]])
    }

    // --- branch 2: a wide spread pairs by rest ------------------------------

    /// Spread 130 s. The long resters wait together and the short resters are
    /// not held up behind them — and the input order does not matter.
    func testAWideSpreadPairsByMeasuredRest() {
        let split = StationSplit.assign(
            lifters: [d, a, e, b, c],
            count: 2,
            restMedians: [a: 30, b: 35, c: 40, d: 150, e: 160],
            previous: stations([[a, b, c], [d, e]])
        )
        XCTAssertEqual(split, [[a, b, c], [d, e]])
    }

    /// An unknown is not a claim of being fast, and not a claim of being slow:
    /// a lifter with no measured rest sorts to the middle of the range.
    func testAnUnmeasuredLifterSortsToTheMiddle() {
        let split = StationSplit.assign(
            lifters: [a, b, c, d, g, h],
            count: 2,
            restMedians: [a: 20, b: 25, g: 200, h: 210],   // c and d unmeasured
            previous: nil
        )
        XCTAssertEqual(split, [[a, b, c], [d, g, h]])
    }

    // --- the threshold itself -----------------------------------------------

    /// 45 s is `RoundHold.remixSpreadSeconds` and appears nowhere else. At
    /// exactly 45 the crew is still close, so it rotates; one second wider
    /// and it pairs.
    func testFortyFiveIsTheBoundaryAndLivesInRoundHold() {
        XCTAssertEqual(RoundHold.remixSpreadSeconds, 45)

        let previous = stations([[a, b, c], [d, e]])
        let onTheLine = StationSplit.assign(
            lifters: [a, b, c, d, e], count: 2,
            restMedians: [a: 60, b: 105, c: 60, d: 105, e: 60],   // spread 45
            previous: previous)
        XCTAssertEqual(onTheLine, [[b, c, d], [e, a]], "45 s apart still rotates")

        let overTheLine = StationSplit.assign(
            lifters: [a, b, c, d, e], count: 2,
            restMedians: [a: 60, b: 106, c: 60, d: 106, e: 60],   // spread 46
            previous: previous)
        XCTAssertEqual(overTheLine, [[a, c, e], [b, d]], "46 s apart pairs by rest")
    }

    // --- the rows that cross the wire ---------------------------------------

    /// THE CLIENT-SIDE INVARIANT (D4): `set_session_stations` validates the
    /// jsonb shape and the roster — every present lifter in exactly one
    /// station, depth <= 3 — but it does NOT validate `turn_order`'s contents.
    /// So "each station's turn order is a permutation of its lifters" has
    /// nothing server-side to catch a violation, and this is what catches it.
    func testEveryStationsTurnOrderIsAPermutationOfItsLifters() {
        for size in 1...12 {
            let rows = StationSplit.rows(from: StationSplit.assign(
                lifters: crew(size),
                count: StationSplit.count(crew: size, equipmentCap: nil),
                restMedians: [:],
                previous: nil
            ))
            for station in rows {
                XCTAssertEqual(Set(station.turnOrder), Set(station.lifterIDs),
                               "crew of \(size), \(station.name): same set")
                XCTAssertEqual(station.turnOrder.count, station.lifterIDs.count,
                               "crew of \(size), \(station.name): same count")
                XCTAssertEqual(Set(station.turnOrder).count, station.turnOrder.count,
                               "crew of \(size), \(station.name): no duplicate")
                XCTAssertFalse(station.turnOrder.isEmpty,
                               "crew of \(size), \(station.name): a rack with nobody on it")
            }
        }
    }

    /// The invariant survives the branch that reorders the crew, not only the
    /// one that deals it in the order it arrived.
    func testThePermutationHoldsAfterAWideSpreadPairsByRest() {
        let rows = StationSplit.rows(from: StationSplit.assign(
            lifters: [d, a, e, b, c, g],
            count: 2,
            restMedians: [a: 30, b: 35, d: 150, e: 160],   // c and g unmeasured
            previous: stations([[a, b, c], [d, e]])
        ))
        XCTAssertEqual(rows.count, 2)
        for station in rows {
            XCTAssertEqual(Set(station.turnOrder), Set(station.lifterIDs))
            XCTAssertEqual(station.turnOrder, station.lifterIDs)
        }
        XCTAssertEqual(Set(rows.flatMap(\.lifterIDs)), Set([a, b, c, d, e, g]))
    }

    /// RACK A, RACK B — the kicker `StationCard` prints (plan task S6).
    func testTheStationsAreNamedForTheirRacks() {
        XCTAssertEqual(StationSplit.name(0), "RACK A")
        XCTAssertEqual(StationSplit.name(1), "RACK B")
        XCTAssertEqual(StationSplit.name(7), "RACK H")
        XCTAssertEqual(StationSplit.name(8), "RACK 9")   // past the alphabet, still legible

        let rows = StationSplit.rows(from: [[a, b], [c, d]])
        XCTAssertEqual(rows.map(\.name), ["RACK A", "RACK B"])
    }

    /// One measured rest is not a spread, it is an absence. There is nothing
    /// to pair by, so the crew rotates.
    func testASingleMeasuredRestIsNotASpread() {
        let split = StationSplit.assign(
            lifters: [a, b, c, d, e], count: 2,
            restMedians: [a: 300],
            previous: stations([[a, b, c], [d, e]]))
        XCTAssertEqual(split, [[b, c, d], [e, a]])
    }
}
