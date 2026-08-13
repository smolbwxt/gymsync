import Foundation

// MARK: - RestRecoveryMath
//
// Recovery-adaptive rest (owner 2026-08-12: "if you are recovering poorly,
// then the next set suffers horribly — rest should increase or decrease
// appropriately"). Pure judgment math over RecoveryBuffer's peak-to-now
// drop; the session view supplies the inputs and owns every action.
//
// SELF-REFERENCED by design: the baseline is the lifter's own median
// end-of-rest drop from THIS session — no population numbers, no age
// formulas, no cross-session state (fatigue, caffeine, and sleep make
// yesterday's drops a lie today).
//
// Honesty flag (science audit 2026-08): set-to-set HR-guided rest for
// lifting is coaching heuristic, not RCT-proven. This module only ever
// SUGGESTS — the timer runs unchanged unless the lifter taps — and it
// stays silent (nil) without an HR source, without a baseline (2+
// completed rests), or in the ambiguous middle of the window.
enum RestRecoveryMath {

    enum Verdict: Equatable {
        /// Drop already at baseline before the window's halfway point —
        /// offer an early start.
        case ready
        /// Drop well short of baseline late in the window — offer +30s.
        case lagging
    }

    /// Median of this session's prior end-of-rest drops; nil until two
    /// rests have completed (one data point is an anecdote).
    static func baseline(priorDrops: [Int]) -> Double? {
        guard priorDrops.count >= 2 else { return nil }
        let sorted = priorDrops.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? Double(sorted[mid - 1] + sorted[mid]) / 2
            : Double(sorted[mid])
    }

    /// The judgment at `progress` (0…1 through the rest window):
    /// - `.ready` — current drop ≥ baseline before 50% of the window
    /// - `.lagging` — current drop < 60% of baseline at ≥ 80% of the window
    /// - nil — anything else, including missing inputs
    static func verdict(currentDrop: Int?, baseline: Double?, progress: Double) -> Verdict? {
        guard let currentDrop, let baseline, baseline > 0 else { return nil }
        if progress < 0.5, Double(currentDrop) >= baseline { return .ready }
        if progress >= 0.8, Double(currentDrop) < baseline * 0.6 { return .lagging }
        return nil
    }
}