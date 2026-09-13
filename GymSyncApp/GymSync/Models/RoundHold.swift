import Foundation

// MARK: - RoundHold
//
// Every number the crew is held by, in ONE place (spec §9a, owner decision
// 11; plan task S1).
//
// A round closes when the last lifter logs. When one lifter is still resting
// well past their own normal rest, the round wait offers the crew a quiet
// line — never a dialog, never an automatic advance (plan task S7). These
// four constants decide when that line appears, and the reason they live here
// rather than at the call site is that a threshold inlined in a view is a
// threshold that can be 90 s on one screen and 120 s on another; the crew
// experiences that difference as the app being wrong about who is late.
//
// The input is `RestMeasure.medians(from:since:)` (`SessionStations.swift`) —
// the lifter's own measured rest in this session, not a prescription.
enum RoundHold {

    /// No crew is offered a skip before a minute and a half, however fast
    /// the lifter usually is.
    static let floorSeconds: TimeInterval = 90

    /// "Still resting" means half again the lifter's own normal rest.
    static let multiplier: Double = 1.5

    /// Three minutes is the most a crew waits on one person.
    static let capSeconds: TimeInterval = 180

    /// The re-mix law's one number (spec §3.3, plan task S3): while the
    /// crew's measured rests are within 45 s of each other they are close
    /// enough to rotate freely; past that, pairing the long resters together
    /// stops the fast lifters waiting behind them. It lives beside the hold's
    /// constants because it is the same question — how far apart is too far
    /// apart — asked about the crew instead of about one lifter.
    static let remixSpreadSeconds: TimeInterval = 45

    /// What "I need a minute" buys the held lifter — once per exercise
    /// (plan task S7 owns the once-per-exercise state; see
    /// `threshold(medianRestSeconds:extensionsTaken:)` below for why the
    /// arithmetic itself also refuses to stack).
    static let extensionSeconds: TimeInterval = 60

    /// `min(max(90, 1.5 x median), 180)`.
    static func threshold(medianRestSeconds: TimeInterval) -> TimeInterval {
        min(max(floorSeconds, multiplier * medianRestSeconds), capSeconds)
    }

    /// The same threshold with the held lifter's own extension applied.
    ///
    /// A minute is a minute, not a minute per tap: any count above one
    /// answers the same as one. The cap on the crew's patience is
    /// `capSeconds + extensionSeconds`, and nothing a client does can raise
    /// it further.
    static func threshold(medianRestSeconds: TimeInterval, extensionsTaken: Int) -> TimeInterval {
        let base = threshold(medianRestSeconds: medianRestSeconds)
        return extensionsTaken > 0 ? base + extensionSeconds : base
    }
}
