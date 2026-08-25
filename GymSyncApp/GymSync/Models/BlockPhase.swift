import Foundation

// MARK: - BlockPhase
//
// The phase taxonomy, derived — never labelled by hand.
//
// The 2026-08-25 periodization pass (27 videos, 170 findings, corpus
// area 'periodization') settled two things the UI had been guessing at:
//
//  1. Accumulation → intensification → realization/peaking is REAL for
//     performance goals. Multiple strong findings describe them as three
//     macrocycle-level phases each carrying a distinct volume/intensity
//     manipulation, not merely names for "early / middle / late".
//
//  2. It does NOT transfer to hypertrophy. Classic periodization exists
//     to peak a performance on a date; hypertrophy is a continuous
//     structural adaptation with no peak to aim at, and what looks like
//     periodization there is reactive block-to-block management rather
//     than planned phases. Showing a PEAK label on a hypertrophy block
//     would assert something the field explicitly denies.
//
// So the taxonomy is GOAL-CONDITIONAL, and the block's own data already
// says which kind it is: `ProgramWeek.percentOfBaseline` is populated for
// percentage-driven (performance) weeks and nil for volume-driven ones.
// A block with no percentages gets no phase strip — it gets its
// mesocycle structure instead, which the evidence treats as universal
// (3-5 overload weeks closing in a deload).
enum BlockPhase: String, Equatable, Sendable {
    case accumulation = "ACCUMULATION"
    case intensification = "INTENSIFICATION"
    case peak = "PEAK"
    case deload = "DELOAD"

    /// One line an athlete can act on, not a definition.
    var blurb: String {
        switch self {
        case .accumulation: return "Volume leads. Build the work capacity the heavy weeks spend."
        case .intensification: return "Load leads. Volume holds or eases while the bar gets heavier."
        case .peak: return "Volume drops so the strength shows up. Least work, heaviest bar."
        case .deload: return "The week that makes the next block work. Same movements, less of them."
        }
    }
}

enum BlockPhaseMap {

    /// The phase of every week, or nil when this block carries no phase
    /// taxonomy at all (volume-driven / hypertrophy — see the type note).
    ///
    /// Derivation for percentage blocks: deload weeks are deload. The
    /// remaining weeks are ranked by their own prescribed percentage and
    /// split into thirds — bottom third accumulates, middle intensifies,
    /// top third peaks. Every input is a number the block already
    /// carries, so nothing here is invented.
    static func phases(for weeks: [ProgramWeek]) -> [BlockPhase]? {
        // Deload percentages are excluded from the range on purpose: a
        // deload is the block's lightest week BY DESIGN, and letting it
        // define the floor would push every real overload week upward
        // and read week 2 as an intensification.
        let percents = weeks.filter { !$0.isDeload }.compactMap(\.percentOfBaseline)
        // A block needs real percentage variation before an
        // accumulation/intensification/peak reading means anything. A
        // flat-percentage block is a repeated week, not an arc.
        guard percents.count >= 3, let low = percents.min(), let high = percents.max(),
              high - low >= 5 else { return nil }

        let span = high - low
        return weeks.map { week in
            guard !week.isDeload else { return .deload }
            guard let percent = week.percentOfBaseline else {
                // A volume/test week inside a percentage block: it is not
                // adding load, so it reads as accumulation.
                return .accumulation
            }
            let position = (percent - low) / span
            if position >= 0.67 { return .peak }
            if position >= 0.34 { return .intensification }
            return .accumulation
        }
    }

    /// Mesocycle index per week — universal, and what a hypertrophy block
    /// shows in place of a phase strip. A mesocycle is an overload run
    /// that CLOSES on its deload week, so the deload belongs to the
    /// mesocycle it ends, and the next week opens the next one.
    static func mesocycles(for weeks: [ProgramWeek]) -> [Int] {
        var index = 1
        var out: [Int] = []
        for week in weeks {
            out.append(index)
            if week.isDeload { index += 1 }
        }
        return out
    }

    /// "MESO 2 · WK 3" — the readback for a block with no phase arc.
    static func mesocycleLabel(for weeks: [ProgramWeek], week number: Int) -> String? {
        guard weeks.indices.contains(number - 1) else { return nil }
        let map = mesocycles(for: weeks)
        let meso = map[number - 1]
        let weekInMeso = map[..<(number - 1)].filter { $0 == meso }.count + 1
        let total = Set(map).count
        return total > 1 ? "MESO \(meso) OF \(total) · WK \(weekInMeso)" : "WK \(weekInMeso)"
    }
}
