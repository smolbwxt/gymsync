import Foundation

// MARK: - PlateDelta
//
// "STRIP 25 · ADD 45 + 5" — the per-side plate changes between what's on
// the bar now (the current lifter's weight) and what YOUR next set needs.
// The spectator prep card's collapsed face (composite v5) leads with this
// answer. Pure wrapper over PlateMath so it's unit-testable; all weights
// in the DISPLAY unit, the same domain as every other `PlateMath.stack`
// call site (GSBarLoader, BarLoaderWidget).
enum PlateDelta {
    struct Change: Equatable {
        let plate: Decimal
        let count: Int
    }

    /// Changes ordered by the caller's `plates` array (descending size,
    /// by convention everywhere in this app).
    struct Delta: Equatable {
        let strip: [Change]
        let add: [Change]
        var isNoChange: Bool { strip.isEmpty && add.isEmpty }
    }

    static func delta(
        fromWeight: Decimal,
        toWeight: Decimal,
        barWeight: Decimal = PlateMath.defaultBarWeight,
        plates: [Decimal] = PlateMath.standardPlates
    ) -> Delta {
        let fromStack = PlateMath.stack(for: fromWeight, barWeight: barWeight, plates: plates)
        let toStack = PlateMath.stack(for: toWeight, barWeight: barWeight, plates: plates)
        var strip: [Change] = []
        var add: [Change] = []
        for (i, plate) in plates.enumerated() {
            let diff = toStack.platesPerSide[i] - fromStack.platesPerSide[i]
            let n = NSDecimalNumber(decimal: abs(diff)).intValue
            guard n > 0 else { continue }
            if diff < 0 {
                strip.append(Change(plate: plate, count: n))
            } else {
                add.append(Change(plate: plate, count: n))
            }
        }
        return Delta(strip: strip, add: add)
    }

    /// "STRIP 35 · ADD 45 + 5" / "ADD 2×45" / "BAR MATCHES".
    static func headline(_ d: Delta) -> String {
        func part(_ label: String, _ changes: [Change]) -> String? {
            guard !changes.isEmpty else { return nil }
            let bits = changes.map { c in
                c.count == 1
                    ? GSBarLoader.plateLabel(c.plate)
                    : "\(c.count)×\(GSBarLoader.plateLabel(c.plate))"
            }
            return "\(label) \(bits.joined(separator: " + "))"
        }
        let parts = [part("STRIP", d.strip), part("ADD", d.add)].compactMap { $0 }
        return parts.isEmpty ? "BAR MATCHES" : parts.joined(separator: " · ")
    }
}
