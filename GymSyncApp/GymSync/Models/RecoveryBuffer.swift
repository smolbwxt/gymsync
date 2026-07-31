import Foundation

// MARK: - RecoveryBuffer
//
// Session-local heart-rate history behind the spectator page's YOUR
// RECOVERY card (composite v5). Pure and clock-agnostic — callers pass
// timestamps — so the HRR math is unit-testable; the view feeds it from
// whatever HR source is live (BLE strap or the session broadcast).
//
// `drop` is the fall from the WINDOW's peak to the newest sample — the
// honest live proxy for heart-rate recovery while resting. It never
// compares across more than `window` seconds, so a spike from three sets
// ago can't inflate the number.
struct RecoveryBuffer: Equatable {
    struct Sample: Equatable {
        let t: TimeInterval
        let bpm: Int
    }

    let window: TimeInterval
    private(set) var samples: [Sample] = []

    init(window: TimeInterval = 90) {
        self.window = window
    }

    /// Append a reading. Non-positive bpm is ignored; a timestamp at or
    /// before the newest sample is ignored (monotonic clock contract);
    /// samples older than `window` are trimmed from the front.
    mutating func append(bpm: Int, at t: TimeInterval) {
        guard bpm > 0 else { return }
        if let last = samples.last, t <= last.t { return }
        samples.append(Sample(t: t, bpm: bpm))
        let cutoff = t - window
        samples.removeAll { $0.t < cutoff }
    }

    var current: Int? { samples.last?.bpm }
    var peak: Int? { samples.map(\.bpm).max() }

    /// Peak-to-now fall within the window; nil until two samples exist
    /// (a single reading has nothing to recover FROM).
    var drop: Int? {
        guard samples.count >= 2, let peak, let current else { return nil }
        return peak - current
    }

    /// `barCount` bucket means, normalized 0…1 against the window's bpm
    /// range. A flat series maps to 0.5 everywhere — the sparkline never
    /// invents variance that isn't there. Empty buckets carry the previous
    /// bucket's value so the line has no holes. Empty until two samples.
    func sparkline(barCount: Int) -> [Double] {
        guard barCount > 0, samples.count >= 2,
              let first = samples.first, let last = samples.last else { return [] }
        let lo = Double(samples.map(\.bpm).min() ?? 0)
        let hi = Double(peak ?? 0)
        let t0 = first.t
        let dt = max(last.t - t0, 0.001) / Double(barCount)
        var buckets: [[Int]] = Array(repeating: [], count: barCount)
        for s in samples {
            let idx = min(barCount - 1, Int((s.t - t0) / dt))
            buckets[idx].append(s.bpm)
        }
        var out: [Double] = []
        var prev = 0.5
        for b in buckets {
            if b.isEmpty {
                out.append(prev)
                continue
            }
            let mean = Double(b.reduce(0, +)) / Double(b.count)
            let v = hi == lo ? 0.5 : (mean - lo) / (hi - lo)
            out.append(v)
            prev = v
        }
        return out
    }

    mutating func reset() { samples.removeAll() }
}
