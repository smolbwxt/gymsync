import Foundation

// MARK: - Units
//
// Design: docs/superpowers/specs/2026-07-26-lifting-quality-design.md.
//
// STORED WEIGHTS ARE ALWAYS POUNDS. This type is the only place that
// converts, and it converts at exactly two edges: formatting a stored value
// for display, and parsing a typed value back to storage. Nothing in the
// database is ever kg, so there is no migration, no mixed-unit dataset, and
// every existing aggregate (leaderboards, group stats, campaign volume)
// keeps summing one unit and needs no changes.

enum WeightUnit: String, CaseIterable, Sendable {
    case lbs
    case kg

    var label: String { rawValue }

    /// Pounds in one unit.
    var poundsPerUnit: Decimal {
        switch self {
        case .lbs: return 1
        case .kg:  return Decimal(2.2046226218)
        }
    }

    /// Smallest increment that can actually be LOADED, for the standard
    /// plate set: PLATES GO ON IN PAIRS, so the step is twice the smallest
    /// plate — 5 lb (a pair of 2.5s), 2.5 kg (a pair of 1.25s). Using the
    /// plate value itself would print 227.5 lb, which needs a 1.25 lb pair
    /// no gym stocks.
    ///
    /// Only a fallback: `Units.loadableIncrement(plates:)` derives this
    /// from the user's OWN inventory whenever one is configured.
    var displayIncrement: Decimal { standardPlates.last.map { $0 * 2 } ?? 5 }

    /// Plate denominations a typical gym stocks, in THIS unit, descending.
    var standardPlates: [Decimal] {
        switch self {
        case .lbs: return [45, 35, 25, 10, 5, 2.5]
        case .kg:  return [25, 20, 15, 10, 5, 2.5, 1.25]
        }
    }

    /// The bar most gyms mean by "the bar", in this unit — 45 lb / 20 kg.
    var defaultBar: Decimal {
        switch self {
        case .lbs: return 45
        case .kg:  return 20
        }
    }
}

enum Units {

    // MARK: - Conversion

    /// Canonical pounds -> the user's unit.
    static func fromPounds(_ pounds: Decimal, to unit: WeightUnit) -> Decimal {
        unit == .lbs ? pounds : pounds / unit.poundsPerUnit
    }

    /// The user's unit -> canonical pounds, for storage.
    static func toPounds(_ value: Decimal, from unit: WeightUnit) -> Decimal {
        unit == .lbs ? value : value * unit.poundsPerUnit
    }

    // MARK: - Rounding

    /// Smallest loadable step for a given plate inventory — twice the
    /// smallest plate, because plates go on in pairs. A gym with no 2.5s
    /// genuinely moves in 10 lb steps, and pretending otherwise produces
    /// numbers that user cannot assemble.
    static func loadableIncrement(plates: [Decimal], unit: WeightUnit) -> Decimal {
        let usable = plates.filter { $0 > 0 }
        guard let smallest = usable.min() else { return unit.displayIncrement }
        return smallest * 2
    }

    /// Rounds to the nearest loadable increment for `unit` (standard set).
    static func roundToIncrement(_ value: Decimal, unit: WeightUnit) -> Decimal {
        roundToIncrement(value, step: unit.displayIncrement)
    }

    static func roundToIncrement(_ value: Decimal, step: Decimal) -> Decimal {
        guard step > 0 else { return value }
        let quotient = NSDecimalNumber(decimal: value / step).doubleValue
        return Decimal(quotient.rounded()) * step
    }

    /// The nearest weight the user can ACTUALLY BUILD, given their bar and
    /// plates — the honest answer for a converted number.
    ///
    /// Rounding to an increment is necessary but not sufficient: a weird
    /// inventory (only 45s, say) makes most multiples of the nominal step
    /// unbuildable. So this proposes a candidate and then asks `PlateMath`
    /// — the single source of truth for what can be racked — to confirm it,
    /// checking one step below and one above and keeping whichever is
    /// closer to the target.
    ///
    /// Everything happens in `unit`, not in pounds: 225 lb is 102.058 kg,
    /// and a ladder computed in pounds yields rungs a kg lifter can't load.
    static func nearestLoadable(_ target: Decimal,
                                barWeight: Decimal,
                                plates: [Decimal],
                                unit: WeightUnit) -> Decimal {
        guard target > barWeight else { return barWeight }
        let step = loadableIncrement(plates: plates, unit: unit)

        // At-or-below is exactly what PlateMath already guarantees.
        let below = PlateMath.stack(for: target, barWeight: barWeight, plates: plates).achievedWeight
        if below == target { return target }

        // The next rung up is only a candidate until PlateMath confirms it
        // is actually rackable with THESE plates.
        let candidate = below + step
        let above = PlateMath.stack(for: candidate, barWeight: barWeight, plates: plates).achievedWeight
        guard above > below else { return below }

        return (target - below) <= (above - target) ? below : above
    }

    // MARK: - Display

    /// "225 lbs" / "102.5 kg". Trims a trailing ".0" (the app already does
    /// this for body weight and est-1RM, so a new format here would read as
    /// inconsistent).
    static func format(pounds: Decimal, unit: WeightUnit,
                       rounded: Bool = true, includeUnit: Bool = true) -> String {
        let converted = fromPounds(pounds, to: unit)
        let value = rounded ? roundToIncrement(converted, unit: unit) : converted
        return "\(trimmed(value))\(includeUnit ? " \(unit.label)" : "")"
    }

    /// Formats a BARBELL weight snapped to what the user can actually
    /// build. Use this wherever a converted number is shown for a barbell
    /// lift — an unloadable weight is worse than a rounded one, because the
    /// lifter stands at the rack trying to make it.
    static func formatLoadable(pounds: Decimal,
                               unit: WeightUnit,
                               barPounds: Decimal,
                               plates: [Decimal]) -> String {
        // Snap in the USER'S unit against THEIR plates, then label.
        let targetInUnit = fromPounds(pounds, to: unit)
        let barInUnit = fromPounds(barPounds, to: unit)
        let snapped = nearestLoadable(targetInUnit, barWeight: barInUnit,
                                      plates: plates, unit: unit)
        return "\(trimmed(snapped)) \(unit.label)"
    }

    /// Body weight keeps one decimal in both units — 1.25 kg granularity is
    /// a plate concept, not a bodyweight one, and rounding a person to the
    /// nearest 2.5 lb loses a real trend.
    static func formatBodyWeight(pounds: Decimal, unit: WeightUnit) -> String {
        let converted = fromPounds(pounds, to: unit)
        var value = converted
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 1, .plain)
        return "\(trimmed(rounded)) \(unit.label)"
    }

    /// Parses user entry in `unit` and returns canonical pounds. Accepts a
    /// comma decimal separator — a kg-using locale very often types "102,5"
    /// and silently dropping that entry is a bad first impression.
    static func parseToPounds(_ text: String, unit: WeightUnit) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Decimal(string: normalized), value >= 0 else {
            return nil
        }
        return toPounds(value, from: unit)
    }

    private static func trimmed(_ value: Decimal) -> String {
        var input = value
        var whole = Decimal()
        NSDecimalRound(&whole, &input, 0, .plain)
        return whole == value ? "\(whole)" : "\(value)"
    }
}
