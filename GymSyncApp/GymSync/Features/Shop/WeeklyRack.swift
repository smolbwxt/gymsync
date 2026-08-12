import Foundation

/// Deterministic weekly selection for "THIS WEEK'S RACK" (redesign Phase 2,
/// 2026-08; re-homed into MyRackView + the You-tab THE RACK widget when the
/// Shop tab dissolved, 2026-08-12). Pure date math plus a seeded shuffle —
/// no networking, no state; callers fetch the catalog and hand it here.
///
/// Determinism contract: the seed derives from the ISO-8601 week
/// (`yearForWeekOfYear * 100 + weekOfYear`) evaluated in UTC, so every
/// device shows the SAME four sounds for the same catalog during the same
/// ISO week, and the rack flips at the same instant worldwide (start of
/// the next ISO week — Monday 00:00 UTC), the fixed-reset convention
/// weekly-rotation shops use.
enum WeeklyRack {

    /// One week's rack: slot 1 is the loaner (the free-to-rack highlight),
    /// slots 2–4 are the browse-only shelf.
    struct Selection {
        let loaner: SoundboardSound
        /// Slots 2–4 (fewer when the catalog holds under 4 sounds).
        let others: [SoundboardSound]
    }

    /// SplitMix64 (Steele/Lea/Flood 2014) as a `RandomNumberGenerator` —
    /// implemented locally because the system generator is deliberately
    /// unseedable, and the whole point here is replaying the SAME shuffle
    /// from the same week seed on every device.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// ISO-8601 calendar pinned to UTC — see the determinism contract above.
    /// (The UTC identifier always resolves; `.current` is an unreachable
    /// belt-and-braces fallback, never a silent behavior change.)
    private static var isoCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    /// Seed formula: `yearForWeekOfYear * 100 + weekOfYear`
    /// (e.g. 2026-W31 → 202631).
    static func weekSeed(for date: Date = Date()) -> UInt64 {
        let comps = isoCalendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 2026
        let week = comps.weekOfYear ?? 1
        return UInt64(year * 100 + week)
    }

    /// Start of the next ISO week (Monday 00:00 UTC) — drives the header
    /// countdown. Falls back to now + 7 days if the interval math ever
    /// returns nil (it can't for `.weekOfYear` on a valid date).
    static func nextRotation(after date: Date = Date()) -> Date {
        isoCalendar.dateInterval(of: .weekOfYear, for: date)?.end
            ?? date.addingTimeInterval(7 * 24 * 3600)
    }

    /// Deterministically pick this week's four:
    ///   1. Sort by slug (defensive — `fetchCatalog()` already orders by
    ///      slug, but the shuffle's replayability must not depend on
    ///      server-side ordering).
    ///   2. Shuffle with the week-seeded generator.
    ///   3. Slot 1 = the first `isCurated` sound in shuffled order (the
    ///      loaner); falls back to the first sound when nothing is curated.
    ///   4. Slots 2–4 = the next three OTHER sounds in shuffled order.
    /// Returns nil only for an empty catalog.
    static func select(from catalog: [SoundboardSound],
                       on date: Date = Date()) -> Selection? {
        guard !catalog.isEmpty else { return nil }
        var rng = SplitMix64(seed: weekSeed(for: date))
        let shuffled = catalog
            .sorted { $0.slug < $1.slug }
            .shuffled(using: &rng)
        let loaner = shuffled.first(where: { $0.isCurated }) ?? shuffled[0]
        let others = shuffled.filter { $0.slug != loaner.slug }.prefix(3)
        return Selection(loaner: loaner, others: Array(others))
    }
}
