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

    /// Defaults to ON (a first-run system that defaults off teaches nobody),
    /// so presence has to be checked separately from value.
    ///
    /// `object(forKey:) as? Bool` is WRONG here and cost a CI round: a value
    /// supplied through the launch-argument domain (`-guidanceTipsEnabled
    /// NO`, how ScreenshotTests suppresses spotlights) arrives as an NSString,
    /// so the cast fails, the `?? true` default wins, and tips stay enabled —
    /// silently, with the only symptom being unhittable controls behind a
    /// scrim in the capture suite. `bool(forKey:)` parses "NO"/"0"/"false"
    /// as well as a real Bool, so it handles both the argument domain and
    /// the @AppStorage toggle.
    static var tipsEnabled: Bool {
        guard UserDefaults.standard.object(forKey: tipsEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: tipsEnabledKey)
    }
}

// MARK: - Tours (owner 2026-08-14: "develop the flow after the start solo
// workout widget"). Each tour steps through targets on ONE screen — see
// GSSpotlight.swift's tour section for the architectural rule that keeps
// these safe. Home replaces the old single .home tip; a lifter who saw
// that tip still gets the tour once (three of its four steps are new).
enum GuidanceTours {
    /// **v2** — Home v3 (production plan task B2). The id is BUMPED rather
    /// than edited in place: `hasBeenSeen` is keyed on it, so a changed step
    /// list under the old id would leave every lifter who already walked v1
    /// on a tour that points at a widget which no longer exists.
    ///
    /// `tour.home.schedule` is deleted with `scheduleWidget` — that job
    /// moved to the calendar card's `+` and the calendar page. The freed
    /// step goes to the weekly goal strip, the one genuinely new thing on
    /// the page. The walk is now: the button, the goal, the calendar, the
    /// streak.
    static let home = GuidanceTour(id: "tour.home.v2", steps: [
        .init(anchorKey: GuidanceTip.home.rawValue,
              title: "Start here",
              message: "Start a workout any time — run one of your routines or go freeform."),
        .init(anchorKey: "tour.home.goal",
              title: "Your goal this week",
              message: "Coach sets a goal each week — muscle sets, miles, sessions or days. Tap the strip to change it."),
        .init(anchorKey: "tour.home.calendar",
              title: "Your training calendar",
              message: "Everything on the books lands here — tap it to open the calendar, where you schedule and move sessions."),
        .init(anchorKey: "tour.home.streak",
              title: "Defend the streak",
              message: "Train each week and the streak grows. Check in when you arrive so your gym time counts."),
    ])

    static let crews = GuidanceTour(id: "tour.crews.v1", steps: [
        .init(anchorKey: GuidanceTip.social.rawValue,
              title: "Train with people",
              message: "Start a crew to lift together: shared live sessions, turns on the bar, chat, and a streak you defend as a team."),
        .init(anchorKey: "tour.crews.outside",
              title: "Outside the box",
              message: "Friends and requests, pump checks from your people, and who's at your gym right now."),
    ])

    static let you = GuidanceTour(id: "tour.you.v1", steps: [
        .init(anchorKey: "tour.you.stats",
              title: "Everything you lift lands here",
              message: "Lifetime volume up top — tap through for weekly volume, PRs, body weight, and per-exercise history."),
        .init(anchorKey: "tour.you.routines",
              title: "Your routines, your Coach",
              message: "Five slots to build in, Discover for ready-made plans, and Coach — your generated program — coming soon."),
        .init(anchorKey: "tour.you.rack",
              title: "The Shop",
              message: "Pro, the Rack — your live-session soundboard — and coaching all live here."),
    ])

    /// QA reset rides along with the tips reset.
    static let all: [GuidanceTour] = [home, crews, you]
}
