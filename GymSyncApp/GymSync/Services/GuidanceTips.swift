import Foundation

// MARK: - GuidanceTip
//
// Design: docs/superpowers/specs/2026-07-25-first-run-guidance-design.md
// (mechanism 2, "just-in-time spotlights"). One case per screen that earns
// a first-visit explanation. Each tip fires ONCE, the first time you land
// on that screen — never in a blast at launch, and never again after.
//
// Copy lives here rather than at the call sites so the whole app's teaching
// voice can be read in one place (and reviewed as a set), and so the QA
// "replay first-run tips" row can label each flag without duplicating
// strings.
//
// Keys are versioned (`.v1`): rewriting a tip's copy meaningfully means
// bumping its key so users who saw the OLD wording get shown the new one,
// rather than silently never seeing the rewrite.
enum GuidanceTip: String, CaseIterable, Identifiable {
    case home     = "tip.home.v1"
    case library  = "tip.library.v1"
    case builder  = "tip.builder.v1"
    case workout  = "tip.workout.v1"
    case stats    = "tip.stats.v1"
    case social   = "tip.social.v1"

    var id: String { rawValue }

    /// Short name for the QA tools row.
    var label: String {
        switch self {
        case .home:    return "Home tip"
        case .library: return "Library tip"
        case .builder: return "Routine builder tip"
        case .workout: return "Live workout tip"
        case .stats:   return "Stats tip"
        case .social:  return "Social tip"
        }
    }

    var title: String {
        switch self {
        case .home:    return "Start here"
        case .library: return "Your routines live here"
        case .builder: return "Build the routine"
        case .workout: return "Log as you lift"
        case .stats:   return "Everything you lift lands here"
        case .social:  return "Train with people"
        }
    }

    var message: String {
        switch self {
        case .home:
            return "Start a workout any time — or schedule one and check in when you arrive."
        case .library:
            return "Build a routine from scratch, or open Discover for a ready-made one you can add in a tap."
        case .builder:
            return "Add exercises, then set targets and rest. Save it and it's yours to run any time."
        case .workout:
            return "Log each set as you go. Beat your best on a lift and we'll call out the PR."
        case .stats:
            return "Volume, PRs and per-exercise history — it fills in as you train."
        case .social:
            return "Start a group to train with friends: shared sessions, live turns, and a crew leaderboard."
        }
    }

    var hasBeenSeen: Bool { UserDefaults.standard.bool(forKey: rawValue) }
    func markSeen() { UserDefaults.standard.set(true, forKey: rawValue) }
    func reset() { UserDefaults.standard.removeObject(forKey: rawValue) }

    /// Global off switch, surfaced in You ▸ Settings. Device-local for the
    /// same reason the seen flags are (see OneShotFlags).
    static let tipsEnabledKey = "guidanceTipsEnabled"
    static var tipsEnabled: Bool {
        UserDefaults.standard.object(forKey: tipsEnabledKey) as? Bool ?? true
    }
}
