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

    /// Smallest increment that can actually be LOADED on a bar: a pair of
    /// the smallest common plate. Displaying 102.0583 kg for a 225 lb
    /// squat is technically right and practically useless — nobody can
    /// load it, so nothing should print it.
    var displayIncrement: Decimal {
        switch self {
        case .lbs: return 2.5
        case .kg:  return 1.25
        }
    }

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

    /// Rounds to the nearest loadable increment for `unit` (2.5 lb / 1.25
    /// kg). Used for every displayed WORKING weight.
    static func roundToIncrement(_ value: Decimal, unit: WeightUnit) -> Decimal {
        let step = unit.displayIncrement
        guard step > 0 else { return value }
        let quotient = NSDecimalNumber(decimal: value / step).doubleValue
        return Decimal(quotient.rounded()) * step
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
