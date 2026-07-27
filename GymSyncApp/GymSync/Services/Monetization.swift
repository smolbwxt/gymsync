import Foundation

// MARK: - Monetization (freemium Pro — SHIPPED DORMANT)
//
// Direction (2026-07-27): social layer free forever (groups, sessions,
// voice, logging, PRs, streaks — network features die behind paywalls);
// Pro gates the PERSONAL-DEPTH layer, "gating features we know will be
// useful" with the least frustration. No ads at launch (revenue math +
// privacy posture; the recap interstitial HOOK exists so that decision
// stays reversible without rework).
//
// DORMANT: `paywallEnabled` is false. Every gate below returns "allowed"
// until it flips, so V1 launches fully free while the entitlement column,
// guard trigger, gates and paywall all ship in place — retrofitting this
// under live users is far worse than shipping it off.
//
// LAUNCH GRANDFATHERING (write this down now so flipping the flag is a
// decision, not a scramble): when the flag flips, everyone who signed up
// before that date gets `pro_until = flip_date + 1 year` via one
// service-role UPDATE. Early users become evangelists, not hostages.
enum Monetization {

    /// The master switch. Flipping this is a PRODUCT decision — see the
    /// grandfathering note above before doing it.
    static let paywallEnabled = false

    /// The features Pro gates. Deliberately the personal-depth layer only.
    enum Feature {
        /// Training-program enrollment (the "self-assigned personal
        /// trainer" — the clearest willingness-to-pay match).
        case programs
        /// Per-exercise history + trends beyond the free window.
        case deepHistory
        /// More than `freeRoutineLimit` owned routines.
        case unlimitedRoutines
        /// CSV / health export (when built).
        case export
    }

    /// Free-tier allowances, in one place so the paywall copy and the
    /// gates can never disagree.
    static let freeRoutineLimit = 5
    static let freeHistoryDays = 90

    /// The single entitlement question. `profile` nil (signed out / still
    /// loading) fails OPEN while dormant and CLOSED once live — a loading
    /// hiccup must never flash the paywall today, and must never leak Pro
    /// later.
    static func isPro(_ profile: Profile?) -> Bool {
        guard let until = profile?.proUntil else { return false }
        return until > .now
    }

    /// "May this user use `feature` right now?" — the one call sites use.
    /// While dormant: always yes. Once live: Pro users yes, free users no
    /// (the caller shows PaywallView).
    static func allows(_ feature: Feature, profile: Profile?) -> Bool {
        guard paywallEnabled else { return true }
        return isPro(profile)
    }
}
