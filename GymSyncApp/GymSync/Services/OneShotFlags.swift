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

    /// O3 (2026-08-28): the walkthrough is per-ACCOUNT - a second account
    /// on the same phone gets its own first run. A PERSISTED device-wide
    /// `hasSeenWalkthroughV1` is deliberately not honored: an existing
    /// user sees the (skippable) walkthrough once more, which is cheaper
    /// than a new account silently getting none.
    ///
    /// The one override is the LAUNCH-ARGUMENT domain — `-hasSeenWalkthroughV1 YES`
    /// on the command line, which nothing ever persists. That is the UI-test /
    /// QA escape hatch `ScreenshotTests.launchApp()` depends on; without it the
    /// walkthrough's `fullScreenCover` sits over every signed-in capture.
    static func walkthroughSeen(userID: UUID) -> Bool {
        walkthroughSeen(userID: userID,
                        launchArguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))
    }

    /// Testable seam: `launchArguments` is the argument-domain dictionary. See the doc comment on
    /// the zero-argument overload for why only the argument domain (never the persisted legacy key)
    /// counts as an override.
    ///
    /// Injected rather than read here so tests never have to mutate the process-wide argument
    /// domain — `setVolatileDomain(_:forName:)` is documented to raise NSInvalidArgumentException
    /// when the named domain already exists, and NSArgumentDomain always does.
    static func walkthroughSeen(userID: UUID, launchArguments: [String: Any]) -> Bool {
        if launchArgumentSkipsWalkthrough(launchArguments) { return true }
        return UserDefaults.standard.bool(forKey: "\(walkthroughKey).\(userID.uuidString)")
    }

    /// UI-test / QA override: `-hasSeenWalkthroughV1 YES` on the launch line. Reads the ARGUMENT
    /// domain only — the persisted legacy device-wide key is deliberately not honored
    /// (O3, 2026-08-28: an existing user sees the skippable walkthrough once more, which is
    /// cheaper than a second account on the same phone silently getting none).
    /// `ScreenshotTests.launchApp()` relies on this.
    private static func launchArgumentSkipsWalkthrough(_ args: [String: Any]) -> Bool {
        guard let raw = args[walkthroughKey] else { return false }
        if let flag = raw as? Bool { return flag }
        if let number = raw as? NSNumber { return number.boolValue }
        if let text = raw as? String { return ["YES", "yes", "TRUE", "true", "1"].contains(text) }
        return false
    }

    static func setWalkthroughSeen(userID: UUID) {
        UserDefaults.standard.set(true, forKey: "\(walkthroughKey).\(userID.uuidString)")
    }
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
                 // Per-user keys share the prefix; the QA reset must clear
                 // every one of them or it silently tests less and less
                 // (this registry's founding rule).
                 isSet: { UserDefaults.standard.dictionaryRepresentation().keys
                     .contains { $0.hasPrefix(walkthroughKey)
                         && UserDefaults.standard.bool(forKey: $0) } },
                 reset: { UserDefaults.standard.dictionaryRepresentation().keys
                     .filter { $0.hasPrefix(walkthroughKey) }
                     .forEach { UserDefaults.standard.removeObject(forKey: $0) } }),
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
