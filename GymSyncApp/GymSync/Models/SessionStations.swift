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

    // MARK: - The split, and the re-mix (spec §3.3, owner decisions 2 and 6)

    /// Deal the crew into stations, in turn order.
    ///
    /// Each returned array is one station's lifters IN THE ORDER THEY GO. Turn
    /// order is fixed within an exercise (owner decision 6): the caller writes
    /// this once per exercise position and never again, and
    /// `set_session_stations`' idempotency on that position is what enforces
    /// it server-side when two clients re-mix at the same moment.
    ///
    /// THE RE-MIX LAW, whole. Take the spread of the crew's measured rests —
    /// `max(median) − min(median)` over the lifters who have one:
    ///
    ///   * `spread <= RoundHold.remixSpreadSeconds` — ROTATE. Shift the order
    ///     the crew last stood in by one, so different people rest together at
    ///     every exercise change. This is the case the feature exists for.
    ///   * `spread > RoundHold.remixSpreadSeconds` — PAIR BY REST. Sort by
    ///     measured rest and deal in blocks, so the long resters wait together
    ///     and the short resters are not held up behind them.
    ///
    /// Deterministic in both branches: the caller's own order is the tie-break,
    /// so two clients computing the same re-mix compute the same answer.
    static func assign(
        lifters: [UUID],
        count: Int,
        restMedians: [UUID: TimeInterval],
        previous: SessionStations?
    ) -> [[UUID]] {
        guard !lifters.isEmpty else { return [] }

        // THE DEPTH LAW WINS OVER THE COUNT. `set_session_stations` rejects a
        // station deeper than three outright, so a count that would force a
        // fourth lifter onto one rack — an equipment cap, or a caller's
        // mistake — is raised instead of obeyed. Losing a rack costs the crew
        // one station; breaking the law costs them the whole write.
        let stations = max(1, max(count, (lifters.count + 2) / 3))

        return deal(orderedForSplit(lifters: lifters,
                                    restMedians: restMedians,
                                    previous: previous),
                    into: stations)
    }

    /// RACK A, RACK B, RACK C — the crew's own word for a station, and the
    /// kicker `StationCard` prints (plan task S6).
    static func name(_ index: Int) -> String {
        let letters = Array("ABCDEFGH")
        return index < letters.count ? "RACK \(letters[index])" : "RACK \(index + 1)"
    }

    /// Turn a split into the rows `set_session_stations` stores.
    ///
    /// THE ONE PLACE `lifterIDs` AND `turnOrder` ARE PAIRED. D4 established
    /// that `set_session_stations` validates the jsonb shape and the roster —
    /// every present lifter in exactly one station, depth <= 3 — but NOT
    /// `turn_order`'s contents. So "each station's turn order is a permutation
    /// of its lifters" is a CLIENT-SIDE invariant with nothing server-side to
    /// catch a violation, and a call site that built the two arrays separately
    /// could drift them apart silently. Here they are the same array, and
    /// `SessionStationsTests` asserts it for every crew from one to twelve.
    static func rows(from split: [[UUID]]) -> [SessionStations.Station] {
        var built: [SessionStations.Station] = []
        for (index, members) in split.enumerated() {
            built.append(SessionStations.Station(name: name(index),
                                                 lifterIDs: members,
                                                 turnOrder: members))
        }
        return built
    }

    /// The order the crew is dealt in — the re-mix law's two branches.
    private static func orderedForSplit(lifters: [UUID],
                                        restMedians: [UUID: TimeInterval],
                                        previous: SessionStations?) -> [UUID] {
        let measured = lifters.compactMap { restMedians[$0] }
        // Fewer than two measured rests is not a spread, it is an absence.
        // Nothing to pair by, so the crew rotates.
        guard measured.count >= 2, let low = measured.min(), let high = measured.max(),
              high - low > RoundHold.remixSpreadSeconds else {
            return rotated(lifters: lifters, previous: previous)
        }
        return pairedByRest(lifters: lifters, restMedians: restMedians)
    }

    /// Close rests: shift the previous order by one. With no previous
    /// assignment there is no order to shift, and the crew is dealt as the
    /// caller handed it over — the rotation's own turn order.
    private static func rotated(lifters: [UUID], previous: SessionStations?) -> [UUID] {
        guard let previous else { return lifters }

        let live = Set(lifters)
        var order: [UUID] = []
        var seen = Set<UUID>()
        // Whoever is still here, in the order they last stood in.
        for id in previous.stations.flatMap(\.turnOrder) where live.contains(id) && !seen.contains(id) {
            order.append(id)
            seen.insert(id)
        }
        // Whoever arrived since, in the order the caller gave them.
        for id in lifters where !seen.contains(id) {
            order.append(id)
            seen.insert(id)
        }

        guard order.count > 1 else { return order }
        return Array(order.dropFirst()) + [order[0]]
    }

    /// Wide spread: sort by measured rest and let `deal` cut it into blocks.
    ///
    /// A lifter with no measured rest yet sorts to the MIDDLE of the range —
    /// an unknown is not a claim of being fast, and it is not a claim of being
    /// slow either.
    private static func pairedByRest(lifters: [UUID],
                                     restMedians: [UUID: TimeInterval]) -> [UUID] {
        let measured = lifters.compactMap { restMedians[$0] }
        let middle = ((measured.max() ?? 0) + (measured.min() ?? 0)) / 2
        return lifters.enumerated()
            .sorted { lhs, rhs in
                let l = restMedians[lhs.element] ?? middle
                let r = restMedians[rhs.element] ?? middle
                if l != r { return l < r }
                return lhs.offset < rhs.offset   // the caller's order breaks ties
            }
            .map(\.element)
    }

    /// Balanced blocks: the first `n % stations` stations take one extra, so
    /// no station is ever two deeper than another. A station nobody lands on
    /// is not returned — a rack with no lifter is not a station.
    private static func deal(_ ordered: [UUID], into stations: Int) -> [[UUID]] {
        guard stations > 0, !ordered.isEmpty else { return [] }
        let base = ordered.count / stations
        let extra = ordered.count % stations
        var result: [[UUID]] = []
        var index = 0
        for station in 0..<stations {
            let size = base + (station < extra ? 1 : 0)
            guard size > 0 else { continue }
            result.append(Array(ordered[index..<(index + size)]))
            index += size
        }
        return result
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
