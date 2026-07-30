import Foundation

// MARK: - HeartRatePrimeStore
//
// "Have we ever asked this user about heart rate?" — one persisted answer,
// mirroring `VoiceCoachMarkStore`'s shape (key owned here, registered with
// `OneShotFlags` under its REAL key so a QA reset can't drift from it).
//
// WHY A LOCAL FLAG RATHER THAN ASKING HEALTHKIT (user direction 2026-07-30):
// HealthKit deliberately refuses to report READ authorization. For read
// types `authorizationStatus(for:)` returns `.notDetermined` even AFTER the
// user grants — Apple's privacy design, since "denied" would itself leak
// health information (an app could infer a condition from which types you
// withhold). So "have we asked" is unanswerable from the system and must be
// our own record.
//
// This drives the three-state vitals widget:
//   • never asked      → "—" (nothing decided yet); starting a session
//                        raises the prime sheet exactly once
//   • asked, no signal → session elapsed time (useful, and never nags again
//                        — the ♥ card stays a manual route to pairing)
//   • signal           → live bpm
//
// A dash therefore means UNDECIDED, not "off". Conflating the two is what
// made the original screen feel broken: it showed nothing, forever, with no
// path forward and no explanation.
enum HeartRatePrimeStore {
    /// Internal (not private) so `OneShotFlags` registers this flag under the
    /// key it actually clears.
    static let defaultsKey = "heartRate.prime.asked.v1"

    /// True once the prime sheet has been presented — regardless of what the
    /// user chose. "Not now" is a decision, and re-asking every session is
    /// exactly the nagging this flag exists to prevent.
    static var hasBeenAsked: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    /// QA replay (`OneShotFlags`).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
