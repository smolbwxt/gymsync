import Foundation

// MARK: - VolumeTitration
//
// Finding each athlete's own volume, per muscle, by moving it and reading
// what comes back.
//
// Owner 2026-08-26: "Everyone responds to volume stimulus differently.
// Let's prescribe middle of the road, and perturb the volume every couple
// of weeks to see how performance improves. The data or the client will
// tell us how it feels."
//
// WHY A SEARCH RATHER THAN A NUMBER
//
// The corpus's own spread is the argument. Damas (n=19) found 32% of
// lifters grew better on high volume, 32% better on low, and 36% about the
// same. Scarpelli (2020, within-subject, n=16) gave one leg the athlete's
// habitual volume +20% and the other a fixed 22 sets/week: the
// individualised leg grew 9.9% CSA against 6.2%, and for eight of sixteen
// subjects the "standard" target was a 30-120% jump on what they had been
// doing. A single prescribed number is wrong for most people in one
// direction or the other, and no amount of tuning the number fixes that.
//
// WHAT IS BEING MEASURED, WHICH IS NOT WHAT IT SOUNDS LIKE
//
// Not "did you grow" — that is unreadable on this timescale. The corpus's
// median study runs ~10 weeks and short windows are dominated by neural
// adaptation, so a fortnight cannot answer it. What a fortnight CAN answer
// is whether the athlete is recovering from the dose and still performing,
// which is the definition of maximum recoverable volume and the thing
// worth searching for anyway.
//
// So the loop reads two things:
//   PERFORMANCE — did they hit the prescribed reps, and is that holding or
//                 declining across sessions. Objective, already in SetLog.
//   RECOVERY    — how long the muscle took to come back, from the recovery
//                 probe. Duration, not presence: coming back for the next
//                 session still carrying the last one is the signal.
//
// TWO CORRECTIONS FROM THE OWNER, both of which changed this design
//
// 1. Effort is NOT a fatigue signal. The corpus's deload trigger reads
//    "most muscles at 0-1 RIR WITH broadly declining performance", and an
//    early draft of this treated the 0-1 RIR half as a warning. It is not:
//    an athlete who chose EffortAppetite.toFailure is PRESCRIBED 0-1 RIR
//    and is training exactly as intended. Owner, verbatim: "I wouldn't say
//    that having most exercises be 0-1 RIR is a bad thing. I deliberately
//    train for that exact thing to happen." Declining performance is the
//    signal. Effort level never is, on its own.
//
// 2. A logged RPE of 7 is not noise. The dial defaults to 7.0, so an
//    untouched 7 and a meant 7 are indistinguishable — but people
//    genuinely do train at 7, and discarding every 7 throws away real
//    answers to keep out defaults. So RPE is used only where a DEFAULT
//    would not change the conclusion: a 9 or 10 is information (nobody
//    drags the dial up by accident), a 7 is treated as unremarkable rather
//    than as absent.
enum VolumeTitration {

    /// Where the search may go. Owner's call: floor 12, ceiling 25.
    ///
    /// The floor is the one number in the corpus with a demonstrated
    /// penalty behind it — a systematic review binning weekly per-muscle
    /// volume as low (<12), moderate (12-20) and high (>20) found moderate
    /// clearly superior to low for every muscle measured. The ceiling is
    /// where the evidence thins rather than where it stops: the 35-study
    /// meta-analysis models growth still rising past 20, with later sets
    /// worth roughly a third of early ones and credible intervals widening
    /// sharply above 25.
    static let floorWeeklySets = 12
    static let ceilingWeeklySets = 25

    /// A deload may go under the floor. A working prescription may not.
    static let deloadFloorWeeklySets = 6

    /// What the athlete said about a muscle when asked.
    enum RecoveryState: String, Codable, CaseIterable, Sendable {
        case fresh, tender, sore, wrecked

        /// Whether this counts as recovered for the purpose of closing a
        /// probe. `tender` closes it: mild residual soreness is a normal
        /// part of training and waiting for a perfectly fresh muscle would
        /// never close a probe for anyone training hard.
        var isRecovered: Bool {
            switch self {
            case .fresh, .tender: return true
            case .sore, .wrecked: return false
            }
        }
    }

    /// One closed observation: a muscle was trained, and came back.
    struct RecoveryObservation: Equatable, Sendable {
        let muscle: String
        let trainedAt: Date
        let recoveredAt: Date?
        let lastState: RecoveryState?

        /// Days to recover, or nil while still open.
        func days(calendar: Calendar = .current) -> Int? {
            guard let recoveredAt else { return nil }
            return calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: trainedAt),
                                           to: calendar.startOfDay(for: recoveredAt)).day
        }
    }

    /// One session's performance for a muscle: did the prescription land.
    struct SessionOutcome: Equatable, Sendable {
        let date: Date
        /// Prescribed reps actually completed across the muscle's working
        /// sets, as a fraction. 1.0 means every rep was hit.
        let repCompletion: Double
        /// Best estimated 1RM for the muscle's lead lift that session, when
        /// there is one. Used only to corroborate a decline.
        let bestE1RM: Decimal?
        /// Any working set flagged as failed.
        let anyFailure: Bool
    }

    /// What the search decided, and why — the `why` is not decoration. A
    /// volume change the athlete cannot see a reason for reads as the app
    /// being erratic.
    enum Move: Equatable, Sendable {
        case add(sets: Int, reason: String)
        case hold(reason: String)
        case cut(sets: Int, reason: String)
        /// Performance is declining and recovery is not completing. The
        /// corpus's response is not a trim: "cut that muscle group's
        /// volume by half or take a recovery week."
        case deload(reason: String)

        var delta: Int {
            switch self {
            case .add(let s, _): return s
            case .cut(let s, _): return -s
            case .hold, .deload: return 0
            }
        }

        /// The sentence explaining the move, written for the athlete.
        /// Persisted with the target so the schedule page can say WHY a
        /// muscle's prescription moved, not just that it did.
        var reason: String {
            switch self {
            case .add(_, let r), .hold(let r), .cut(_, let r), .deload(let r):
                return r
            }
        }
    }

    /// The decision for ONE muscle.
    ///
    /// `sessionGapDays` is how often this athlete's split trains this
    /// muscle — the yardstick recovery duration is measured against. Six
    /// days to recover is fine on a once-weekly split and a crisis on a
    /// three-times-weekly one, which is why an absolute soreness threshold
    /// would be the wrong instrument.
    static func decide(muscle: String,
                       current: Int,
                       outcomes: [SessionOutcome],
                       recovery: [RecoveryObservation],
                       sessionGapDays: Int,
                       calendar: Calendar = .current) -> Move {
        let recent = outcomes.sorted { $0.date > $1.date }

        // Not enough to read yet. Holding is the honest answer — the
        // alternative is moving someone's prescription on one session,
        // where a bad night's sleep is indistinguishable from a dose that
        // is too big.
        guard recent.count >= 2 else {
            return .hold(reason: "Still watching — I need a couple of sessions before I move anything.")
        }

        let latest = recent[0], previous = recent[1]

        // MRV, the corpus's own rule: "distinct performance decline across
        // two consecutive sessions for a muscle group signals it has hit
        // maximum recoverable volume." Note what is NOT here: how hard
        // they were working. Someone training at 0-1 RIR on purpose is
        // not thereby over-reaching.
        let declining = latest.repCompletion < previous.repCompletion
            && previous.repCompletion < 1.0
        let stillCarrying = openTooLong(recovery, gap: sessionGapDays, calendar: calendar)

        if declining && stillCarrying {
            return .deload(reason: "\(muscle.capitalized) is going backwards two sessions running and hasn't been recovering between them. That's the sign the dose is past what you can absorb — not a reason to push harder.")
        }
        if declining {
            return .cut(sets: 2, reason: "Reps slipped on \(muscle) two sessions running. Taking a couple of sets back off it.")
        }
        if stillCarrying {
            return .hold(reason: "Holding \(muscle) — you're hitting the reps, but you're still carrying the last session when the next one comes round.")
        }

        // NEVER CLIMB ON REPS ALONE (owner 2026-08-26: "let's hold the
        // volume until the probe has data").
        //
        // Note the ASYMMETRY, which is deliberate. The two directions are
        // not the same bet. Adding volume on reps alone is a guess that
        // the athlete is recovering, made without asking them - and the
        // whole point of the search is that recovery is the thing being
        // measured. Cutting, above, does NOT wait: a lifter whose reps are
        // going backwards two sessions running is the corpus's own MRV
        // signal, and making them wait for a probe to confirm what their
        // performance is already saying would be the wrong direction to be
        // cautious in.
        //
        // So: silence blocks the climb, never the retreat.
        guard hasRecoveryEvidence(recovery) else {
            return .hold(reason: "Holding \(muscle) where it is until I know how you're recovering. Tell me how the last session left you and I'll start moving it.")
        }

        // Room to add: the reps are landing AND the muscle is back before
        // the next session for it.
        if latest.repCompletion >= 1.0 && !latest.anyFailure {
            guard current < ceilingWeeklySets else {
                return .hold(reason: "\(muscle.capitalized) is at the top of the range I'll take it to without you asking. It's working — hold here.")
            }
            return .add(sets: 1, reason: "You're finishing every rep on \(muscle) and recovering in time. Adding a set to see if there's more there.")
        }
        return .hold(reason: "Holding \(muscle) — close, but not clean enough yet to add.")
    }

    /// Whether the probe has said enough to justify moving volume UP.
    ///
    /// Two closed observations, the same bar `openTooLong` uses, so the
    /// evidence needed to add is the same evidence needed to hold back.
    /// An open probe does not count: "still recovering" is not an answer
    /// about how long recovery took.
    static func hasRecoveryEvidence(_ recovery: [RecoveryObservation]) -> Bool {
        recovery.filter { $0.recoveredAt != nil }.count >= 2
    }

    /// Whether recovery is running into the next session for this muscle.
    ///
    /// Reads the two most recent CLOSED observations, and treats an
    /// observation that is still open past the gap as carrying too. One
    /// long recovery is a hard week; two in a row is a dose.
    static func openTooLong(_ recovery: [RecoveryObservation],
                            gap: Int,
                            calendar: Calendar = .current,
                            now: Date = .now) -> Bool {
        let sorted = recovery.sorted { $0.trainedAt > $1.trainedAt }.prefix(2)
        guard sorted.count == 2 else { return false }
        return sorted.allSatisfy { observation in
            if let days = observation.days(calendar: calendar) { return days >= gap }
            // Still open: has it already run past the gap?
            let elapsed = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: observation.trainedAt),
                to: calendar.startOfDay(for: now)).day ?? 0
            return elapsed >= gap
        }
    }

    /// Apply a move, keeping the result inside the search bounds.
    static func apply(_ move: Move, to current: Int) -> Int {
        switch move {
        case .deload:
            // "Cut that muscle group's volume by half" — and a deload is
            // the one time a working prescription may sit under the floor,
            // because that is what a deload is for.
            return max(deloadFloorWeeklySets, current / 2)
        default:
            let moved = current + move.delta
            return min(ceilingWeeklySets, max(floorWeeklySets, moved))
        }
    }

    /// The starting point for a muscle with no history: the middle of the
    /// band the athlete's goal prescribes. Owner: "prescribe middle of the
    /// road" and let the search do the rest.
    static func startingPoint(low: Int, high: Int) -> Int {
        min(ceilingWeeklySets, max(floorWeeklySets, (low + high) / 2))
    }
}
