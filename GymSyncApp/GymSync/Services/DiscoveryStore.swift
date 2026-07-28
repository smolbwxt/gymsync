import Foundation

// MARK: - Discovery highlights ("you haven't pressed this yet")
//
// Design: docs/superpowers/specs/2026-07-25-first-run-guidance-design.md,
// mechanism 1 — refined by the user (2026-07-25) from a colored dot to a
// subtle 3D/depth treatment on the control itself.
//
// WHY DEPTH AND NOT COLOR, twice over:
//  1. The app already uses accent-filled indicators to mean "something is
//     waiting for you" (unread messages, pending friend requests). A
//     discovery dot in that same language teaches people to ignore dots,
//     and they start missing real friend requests.
//  2. Proven the hard way on 2026-07-26: a low-opacity accent over the Onyx
//     near-black ground doesn't tint, it muddies — and its hue swings with
//     whichever accent the user picked. Any highlight built from color
//     opacity is unreliable on this ground BY CONSTRUCTION. Elevation and
//     edge-light aren't.
//
// The dot survives in exactly one place — the tab bar — because at 21pt an
// icon has no room to read as "raised". Tab dot = wayfinding ("something
// under here"); raised control = the thing itself.

/// One never-pressed control worth pointing at. Deliberately a small,
/// curated list: highlighting everything highlights nothing.
enum DiscoveryTarget: String, CaseIterable, Identifiable {
    case homeSchedule     = "disc.home.schedule.v1"
    case libraryDiscover  = "disc.library.discover.v1"
    case libraryCampaigns = "disc.library.campaigns.v1"
    case socialLocal      = "disc.social.local.v1"
    case socialFeed       = "disc.social.feed.v1"
    case youAppearance    = "disc.you.appearance.v1"

    var id: String { rawValue }

    /// Which tab's icon carries the rollup dot for this control.
    var tab: AppState.Tab {
        switch self {
        case .homeSchedule:                       return .home
        case .libraryDiscover, .libraryCampaigns: return .library
        case .socialLocal, .socialFeed:           return .social
        case .youAppearance:                      return .you
        }
    }

    /// Short name for the QA tools row.
    var label: String {
        switch self {
        case .homeSchedule:     return "Schedule widget (new)"
        case .libraryDiscover:  return "Discover tab (new)"
        case .libraryCampaigns: return "Campaigns tab (new)"
        case .socialLocal:      return "Local hubs (new)"
        case .socialFeed:       return "Pump check feed (new)"
        case .youAppearance:    return "Appearance (new)"
        }
    }
}

/// Observable so a tab-bar dot disappears the instant its control is
/// pressed — a plain `UserDefaults` read wouldn't re-render the dock, and a
/// dot that outlives its reason is worse than no dot.
@Observable
final class DiscoveryStore {
    static let shared = DiscoveryStore()

    /// Observable MIRROR of the persisted state. Truth lives in
    /// `UserDefaults` under each target's own raw value as its key — one
    /// bool per target, NOT a single array — because `OneShotFlags` requires
    /// every registered flag's id to BE its storage key. An array under one
    /// key would make the QA reset clear something the registry reports on
    /// separately, which is precisely the silent-drift failure the registry
    /// exists to prevent.
    private(set) var pressed: Set<String>

    private init() {
        pressed = Set(DiscoveryTarget.allCases
            .filter { UserDefaults.standard.bool(forKey: $0.rawValue) }
            .map(\.rawValue))
    }

    /// Reads the observable mirror, so SwiftUI re-renders on change.
    func isNew(_ target: DiscoveryTarget) -> Bool { !pressed.contains(target.rawValue) }

    /// Cleared on FIRST PRESS — the contract is literally "you haven't
    /// pressed this yet", so seeing it is not enough.
    func markPressed(_ target: DiscoveryTarget) {
        guard !pressed.contains(target.rawValue) else { return }
        UserDefaults.standard.set(true, forKey: target.rawValue)
        pressed.insert(target.rawValue)
    }

    func unmark(_ target: DiscoveryTarget) {
        UserDefaults.standard.removeObject(forKey: target.rawValue)
        pressed.remove(target.rawValue)
    }

    /// Rebuilds the mirror from storage — needed after anything writes the
    /// keys directly (tests, and `OneShotFlags.resetAll` if its per-flag
    /// resets are ever routed around this type).
    func syncFromDefaults() {
        pressed = Set(DiscoveryTarget.allCases
            .filter { UserDefaults.standard.bool(forKey: $0.rawValue) }
            .map(\.rawValue))
    }

    /// Does any control under `tab` still need discovering? Backs the tab
    /// icon's rollup dot.
    func hasNew(in tab: AppState.Tab) -> Bool {
        DiscoveryTarget.allCases.contains { $0.tab == tab && isNew($0) }
    }
}
