import SwiftUI

// MARK: - GSBarLoader
//
// "What do I actually put on the bar." A drawn barbell with the plates for
// ONE SIDE stacked out from the collar, sized by denomination and coloured
// like real plates, plus the per-side count and the arithmetic spelled out.
//
// Reference (user-supplied, 2026-07-26): a dedicated plate-calculator app.
// Taken from it: the horizontal bar with proportional labelled plates, the
// loading-order numbers, the per-side count table, and a plain-language
// "quick maths" line. Deliberately NOT taken: its simultaneous dual-unit
// readout (this app has a unit preference, so showing both is clutter) and
// its saturated single-hue plates (colour here carries DENOMINATION, which
// is information, rather than branding).
//
// Colour is by plate weight, following the competition convention lifters
// already read at a glance — 25 kg red, 20 blue, 15 yellow, 10 green; 45 lb
// blue, 35 yellow, 25 green. These are FIXED, not accent-derived: they mean
// "this is a 25", the same way the check-in gold means "act now", and
// re-tinting them per user accent would destroy the only reason they're
// coloured.

struct GSBarLoader: View {
    @Environment(\.gsTheme) private var theme

    /// Target in the DISPLAY unit (already converted by the caller).
    let target: Decimal
    let barWeight: Decimal
    let plates: [Decimal]
    let unit: WeightUnit

    private var stack: PlateMath.Stack {
        PlateMath.stack(for: target, barWeight: barWeight, plates: plates)
    }

    /// Denominations actually needed, outermost-last, paired with counts.
    private var loaded: [(plate: Decimal, count: Int)] {
        zip(plates, stack.platesPerSide)
            .compactMap { plate, count in
                let n = NSDecimalNumber(decimal: count).intValue
                return n > 0 ? (plate, n) : nil
            }
    }

    private var isExact: Bool { stack.achievedWeight == target }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            barGraphic
            countRow
            mathsLine
        }
    }

    // MARK: Bar

    private var barGraphic: some View {
        HStack(spacing: 2) {
            // Collar end — the fixed point plates load against.
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.neutral500)
                .frame(width: 10, height: 26)

            // Plates, heaviest first (how they actually go on).
            ForEach(Array(loaded.enumerated()), id: \.offset) { _, item in
                ForEach(0..<item.count, id: \.self) { _ in
                    plateView(item.plate)
                }
            }

            // The sleeve running off to the right.
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.neutral500.opacity(0.55))
                .frame(height: 10)

            Spacer(minLength: 0)
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plateView(_ plate: Decimal) -> some View {
        let color = Self.plateColor(plate, unit: unit)
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: Self.plateWidth(plate, unit: unit),
                   height: Self.plateHeight(plate, unit: unit))
            .overlay {
                Text(Self.plateLabel(plate))
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .foregroundStyle(Self.plateInk(plate, unit: unit))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
    }

    // MARK: Counts + maths

    private var countRow: some View {
        HStack(spacing: 6) {
            Text("PER SIDE")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
            if loaded.isEmpty {
                Text("empty bar")
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                ForEach(Array(loaded.enumerated()), id: \.offset) { _, item in
                    Text("\(item.count)×\(Self.plateLabel(item.plate))")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.surface)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The arithmetic, spelled out — the same transparency the programs
    /// feature uses for its targets ("82.5% of your 225 → 185 lb"). If the
    /// exact target can't be built with these plates, say so plainly rather
    /// than drawing a stack that silently isn't what was asked for.
    private var mathsLine: some View {
        // Loads (bar, total, target) follow the app-wide one-decimal rule
        // via Units.displayWeight; the per-side SUM keeps plateLabel — it's
        // exact plate arithmetic (3×1.25 = 3.75) and rounding it would make
        // the spelled-out equation visibly not add up.
        let perSide = loaded.reduce(Decimal(0)) { $0 + $1.plate * Decimal($1.count) }
        let sum = "\(Units.displayWeight(barWeight)) + 2×\(Self.plateLabel(perSide))"
        return VStack(alignment: .leading, spacing: 2) {
            if loaded.isEmpty {
                // No plates at all — "45 + 2×0 = 45" is technically true but
                // reads like a bug; say what it is.
                Text("Empty bar — \(Units.displayWeight(stack.achievedWeight)) \(unit.label)")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                Text("\(sum) = \(Units.displayWeight(stack.achievedWeight)) \(unit.label)")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            if !isExact {
                Text("closest loadable to \(Units.displayWeight(target)) with your plates")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral700)
            }
        }
    }

    // MARK: Plate rendering rules

    /// Taller and wider for heavier plates — a 45 should look like a 45 next
    /// to a 2.5, the way it does on the rack. sqrt of the weight ratio (a
    /// plate's diameter doesn't scale linearly with its mass) with a LOW
    /// floor: the first cut floored at 0.18 linear, which drew the 1.25 kg
    /// at half the height of the 25 — screenshot review 2026-07-26 flagged
    /// the smalls as far too large.
    private static func plateHeight(_ plate: Decimal, unit: WeightUnit) -> CGFloat {
        let heaviest = unit.standardPlates.first ?? 45
        let ratio = NSDecimalNumber(decimal: plate / heaviest).doubleValue
        let scaled = ratio.squareRoot()
        return 18 + CGFloat(min(1, max(0.10, scaled))) * 74
    }

    private static func plateWidth(_ plate: Decimal, unit: WeightUnit) -> CGFloat {
        let heaviest = unit.standardPlates.first ?? 45
        let ratio = NSDecimalNumber(decimal: plate / heaviest).doubleValue
        return 13 + CGFloat(min(1, max(0.25, ratio))) * 7
    }

    /// Competition plate colours by denomination — what lifters already read
    /// at a glance. Anything unrecognised falls back to iron grey, which is
    /// what a non-standard plate looks like anyway.
    static func plateColor(_ plate: Decimal, unit: WeightUnit) -> Color {
        let value = NSDecimalNumber(decimal: plate).doubleValue
        switch unit {
        case .kg:
            switch value {
            case 25:   return Color.gsHex(0xE23B2E)
            case 20:   return Color.gsHex(0x2F6FD0)
            case 15:   return Color.gsHex(0xE8C33A)
            case 10:   return Color.gsHex(0x2FA45C)
            case 5:    return Color.gsHex(0xE8E8E8)
            case 2.5:  return Color.gsHex(0x8A8F98)
            case 1.25: return Color.gsHex(0xB8BDC6)
            default:   return Color.gsHex(0x53585F)
            }
        case .lbs:
            switch value {
            case 55:   return Color.gsHex(0xE23B2E)
            case 45:   return Color.gsHex(0x2F6FD0)
            case 35:   return Color.gsHex(0xE8C33A)
            case 25:   return Color.gsHex(0x2FA45C)
            case 10:   return Color.gsHex(0xE8E8E8)
            case 5:    return Color.gsHex(0x8A8F98)
            case 2.5:  return Color.gsHex(0xB8BDC6)
            default:   return Color.gsHex(0x53585F)
            }
        }
    }

    /// Dark ink on the pale plates (white, silver, yellow), light on the
    /// saturated ones. Keyed off the DENOMINATION rather than comparing
    /// `Color` values — SwiftUI `Color` equality is not a reliable way to
    /// ask "is this the pale one" once a color has been through the
    /// environment.
    private static func plateInk(_ plate: Decimal, unit: WeightUnit) -> Color {
        let value = NSDecimalNumber(decimal: plate).doubleValue
        let paleKg: Set<Double> = [15, 5, 2.5, 1.25]
        let paleLbs: Set<Double> = [35, 10, 5, 2.5]
        let isPale = unit == .kg ? paleKg.contains(value) : paleLbs.contains(value)
        return isPale ? Color.gsHex(0x14161A) : .white
    }

    /// "45", "2.5", "1.25" — trims the trailing zero so plates read like
    /// plates. DENOMINATIONS ONLY: this stays exact (a 1.25 kg chip must
    /// not become "1.3"). For a LOAD — a rung, a target, a total — use
    /// `Units.displayWeight`, which enforces the one-decimal rule and
    /// swallows Decimal conversion noise.
    static func plateLabel(_ value: Decimal) -> String {
        var input = value
        var whole = Decimal()
        NSDecimalRound(&whole, &input, 0, .plain)
        return whole == value ? "\(whole)" : "\(value)"
    }
}

// MARK: - GSBarLoaderMini

/// Compact, label-free rendering of a loaded bar — the collapsed "Load the
/// bar" card's at-a-glance preview (user request 2026-07-27). Same
/// PlateMath stack and fixed competition colours as the full loader at
/// roughly one-third scale; no labels, no counts, no maths line — the full
/// widget one tap away carries all of that.
struct GSBarLoaderMini: View {
    @Environment(\.gsTheme) private var theme

    /// Target in the DISPLAY unit (already converted by the caller).
    let target: Decimal
    let barWeight: Decimal
    let plates: [Decimal]
    let unit: WeightUnit

    private var loaded: [(plate: Decimal, count: Int)] {
        let stack = PlateMath.stack(for: target, barWeight: barWeight, plates: plates)
        return zip(plates, stack.platesPerSide).compactMap { plate, count in
            let n = NSDecimalNumber(decimal: count).intValue
            return n > 0 ? (plate, n) : nil
        }
    }

    var body: some View {
        HStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.neutral500)
                .frame(width: 4, height: 12)
            ForEach(Array(loaded.enumerated()), id: \.offset) { _, item in
                ForEach(0..<item.count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(GSBarLoader.plateColor(item.plate, unit: unit))
                        .frame(width: Self.miniWidth(item.plate, unit: unit),
                               height: Self.miniHeight(item.plate, unit: unit))
                }
            }
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.neutral500.opacity(0.55))
                .frame(width: 18, height: 4)
        }
        .frame(height: 40)
    }

    // Same sqrt-of-mass-ratio proportions as the full loader, scaled down.
    private static func miniHeight(_ plate: Decimal, unit: WeightUnit) -> CGFloat {
        let heaviest = unit.standardPlates.first ?? 45
        let ratio = NSDecimalNumber(decimal: plate / heaviest).doubleValue
        return 8 + CGFloat(min(1, max(0.10, ratio.squareRoot()))) * 28
    }

    private static func miniWidth(_ plate: Decimal, unit: WeightUnit) -> CGFloat {
        let heaviest = unit.standardPlates.first ?? 45
        let ratio = NSDecimalNumber(decimal: plate / heaviest).doubleValue
        return 5 + CGFloat(min(1, max(0.25, ratio))) * 3
    }
}
