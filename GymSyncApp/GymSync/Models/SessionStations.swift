import Foundation

// MARK: - SessionStations
//
// The CURRENT exercise's station assignment (spec §3.3, owner decision 2;
// plan task S1).
//
// This is `sessions.stations`, a jsonb column
// (`20260913000101_session_style_stations_round.sql`, plan task D1) written
// ONLY by `public.set_session_stations` (plan task D3) — transient by design,
// which is why spec §6 says "a separate table is not needed": the assignment
// for the exercise the crew is on now is the only assignment anybody needs.
//
// The coding keys are the column comment's keys, exactly. `SessionStationsTests`
// decodes a literal copied from that comment (plan ruling R-B5); if this
// decoder and D3's validation ever disagree, that test is what says so.
struct SessionStations: Codable, Equatable, Sendable {
    /// Which exercise this assignment belongs to. `set_session_stations` is
    /// idempotent on it: two clients re-mixing at the same exercise change
    /// cannot disagree, because the second call reads the first one back
    /// unchanged.
    var exercisePosition: Int
    var stations: [Station]

    struct Station: Codable, Equatable, Sendable {
        /// What the crew calls the rack — "RACK A", "RACK B".
        var name: String
        /// Who is on it. Never more than three (owner decision 2, enforced
        /// server-side by `set_session_stations`).
        var lifterIDs: [UUID]
        /// The order they go in, fixed for the whole exercise (owner
        /// decision 6). Written once per exercise position and never again.
        var turnOrder: [UUID]

        enum CodingKeys: String, CodingKey {
            case name
            case lifterIDs = "lifter_ids"
            case turnOrder = "turn_order"
        }
    }

    enum CodingKeys: String, CodingKey {
        case exercisePosition = "exercise_position"
        case stations
    }
}

// MARK: - StationSplit
//
// How many stations a crew splits into (the plan's data decision 3).
//
// The owner's 2026-09-12 refinement was `min(ceil(n/3), racks at the venue)`.
// NEITHER half of the second term exists: `venues.equipment`
// (`20260814000010_venue_equipment.sql:9`) is a text[] of equipment CLASSES,
// not counts, and no session -> venue link exists at all. So the cap is a
// real parameter with real tests, and every caller in Phase B1 passes `nil`.
// What this signature refuses to do is invent a rack count from a list of
// equipment classes.
enum StationSplit {

    /// `max(1, min(ceil(crew / 3), equipmentCap ?? .max))`.
    ///
    /// There is always at least one station — a zero would divide the crew
    /// into nothing — and a crew of four is two stations, not one of four.
    static func count(crew: Int, equipmentCap: Int?) -> Int {
        let lifters = max(0, crew)
        let byDepth = (lifters + 2) / 3   // ceil(lifters / 3), in integers
        guard let cap = equipmentCap else { return max(1, byDepth) }
        return max(1, min(byDepth, cap))
    }
}

// MARK: - RestMeasure
//
// Per-lifter rest, measured from what the crew actually did (plan task S1).
//
// Two things read this and nothing else may invent its own: the hold
// threshold (`RoundHold.threshold(medianRestSeconds:)`, spec §9a) and the
// re-mix law (`StationSplit.assign`, plan task S3). Self-referenced on
// purpose, in `RestRecoveryMath`'s own idiom — no population numbers, no
// prescribed rest, just the gaps this crew is leaving between their own sets
// in this session.
//
// The caller decides what goes in. The live body passes `allSessionSets` —
// the uncapped, `logged_at ASC` array it already holds — so nothing here
// filters by exercise or by penalty; a burpee is a log like any other to a
// stopwatch.
enum RestMeasure {

    /// Per-lifter median of the gaps between consecutive logs at or after
    /// `since`.
    ///
    /// A lifter with fewer than two logs in the window has NO median and is
    /// absent from the result — one log is one moment, and a moment has no
    /// duration. Reporting 0 instead would put the hold threshold's floor on
    /// a lifter nobody has measured yet.
    static func medians(from logs: [SetLog], since: Date) -> [UUID: TimeInterval] {
        var byLifter: [UUID: [Date]] = [:]
        for log in logs where log.loggedAt >= since {
            byLifter[log.userID, default: []].append(log.loggedAt)
        }

        var result: [UUID: TimeInterval] = [:]
        for (lifter, stamps) in byLifter {
            let ordered = stamps.sorted()
            guard ordered.count >= 2 else { continue }
            let gaps = zip(ordered, ordered.dropFirst()).map { $1.timeIntervalSince($0) }
            result[lifter] = median(of: gaps)
        }
        return result
    }

    /// Even counts average the middle two — `RestRecoveryMath.baseline`'s
    /// own convention, kept identical so two medians in one session cannot
    /// mean two different things.
    private static func median(of values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
