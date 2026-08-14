import Foundation

// MARK: - OneShotFlags
//
// The single registry of every "show this exactly once, ever" flag in the
// app — first-run walkthrough, coach marks, safety advisories, and (as they
// land) the first-run guidance system's per-screen spotlight keys.
//
// WHY A REGISTRY AND NOT A LOOSE PILE OF UserDefaults KEYS: the QA reset
// below has to clear ALL of them. If each new tip only remembers to set its
// own key, the reset button silently stops covering the newest tip — it
// keeps "working" while testing less and less, which is the worst kind of
// broken. Registering here is the one step that keeps the button honest, so
// EVERY new one-shot flag belongs in `all` below.
//
// Storage is deliberately device-local (`UserDefaults`), matching the
// existing `VoiceCoachMarkStore` / `hasSeenWalkthroughV1` precedent: this is
// per-device UI state, not user data worth syncing.
enum OneShotFlags {

    /// One resettable flag: how to read it, and how to clear it. Reads and
    /// resets are delegated to whoever OWNS the key wherever one exists
    /// (`VoiceCoachMarkStore`), rather than this file duplicating key
    /// strings that would drift.
    struct Flag: Identifiable {
        let id: String
        let label: String
        let isSet: () -> Bool
        let reset: () -> Void
    }

    /// Raw `@AppStorage` keys — these have no owning store type, so the
    /// literals live here (their single source of truth) and the views read
    /// them through `@AppStorage` with the same string.
    static let walkthroughKey = "hasSeenWalkthroughV1"
    static let venueAdvisoryKey = "hasSeenVenueAdvisory"

    static var all: [Flag] {
        // Guidance spotlights register themselves off GuidanceTip.allCases —
        // adding a case to that enum automatically joins the QA reset, which
        // is the whole point of the registry (a tip that had to remember to
        // register here would eventually forget).
        GuidanceTip.allCases.map { tip in
            Flag(id: tip.rawValue,
                 label: tip.label,
                 isSet: { tip.hasBeenSeen },
                 reset: { tip.reset() })
        } + DiscoveryTarget.allCases.map { target in
            // Discovery highlights join the same replay, off allCases for
            // the same reason: a target that had to remember to register
            // would eventually forget.
            // isSet reads STORAGE (not the store's observable mirror) so the
            // registry's contract — id is the defaults key — holds under
            // direct writes; reset goes through the store so the live UI
            // drops its highlights immediately.
            Flag(id: target.rawValue,
                 label: target.label,
                 isSet: { UserDefaults.standard.bool(forKey: target.rawValue) },
                 reset: { DiscoveryStore.shared.unmark(target) })
        } + GuidanceTours.all.map { tour in
            // Tours join the same registry off GuidanceTours.all — same
            // never-forgets rationale as the tip/discovery registrations.
            Flag(id: tour.id,
                 label: "Tour: \(tour.id)",
                 isSet: { tour.hasBeenSeen },
                 reset: { tour.reset() })
        } + [
            Flag(id: walkthroughKey,
                 label: "First-run walkthrough",
                 isSet: { UserDefaults.standard.bool(forKey: walkthroughKey) },
                 reset: { UserDefaults.standard.removeObject(forKey: walkthroughKey) }),
            Flag(id: venueAdvisoryKey,
                 label: "Local hub safety advisory",
                 isSet: { UserDefaults.standard.bool(forKey: venueAdvisoryKey) },
                 reset: { UserDefaults.standard.removeObject(forKey: venueAdvisoryKey) }),
            // `id` is the REAL defaults key (not a friendly alias) so the
            // registry's id and the storage it clears can never diverge.
            Flag(id: VoiceCoachMarkStore.defaultsKey,
                 label: "Push-to-talk coach mark",
                 isSet: { VoiceCoachMarkStore.hasBeenShown },
                 reset: { VoiceCoachMarkStore.reset() }),
            Flag(id: HeartRatePrimeStore.defaultsKey,
                 label: "Heart rate first-session prompt",
                 isSet: { HeartRatePrimeStore.hasBeenAsked },
                 reset: { HeartRatePrimeStore.reset() }),
        ]
    }

    /// Number of flags currently marked seen — the QA row's subtitle.
    static var seenCount: Int { all.filter { $0.isSet() }.count }

    /// Clears every registered flag so the whole first-run experience
    /// replays. Screens that read their flag through `@AppStorage` pick the
    /// change up immediately (it observes `UserDefaults`); anything that
    /// captured its value at presentation time replays on the next launch.
    static func resetAll() {
        all.forEach { $0.reset() }
    }
}
