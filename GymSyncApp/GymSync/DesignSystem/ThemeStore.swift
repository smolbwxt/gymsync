import SwiftUI

/// Live palette state — Canvas Completion Task 5. Singleton (matches
/// `AppState.shared`/`AuthService.shared`'s convention) so both `RootView`
/// (which injects `\.gsTheme` + `.preferredColorScheme` from `current`) and
/// any Settings Hub row/picker can observe and mutate the same instance.
///
/// Seeded to `.midnight` (matches `UserSettings.defaults`' own "midnight"
/// column default) so the app renders correctly before `load()` resolves —
/// same "seed with the default, refine once the network read lands"
/// convention as `YouTabView`'s other `.task`-loaded state.
@Observable
@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()
    private init() {}

    public private(set) var paletteID: String = "midnight"
    public private(set) var current: GSTheme = .midnight

    /// Cached most-recent settings row — kept so `select(_:)` can persist the
    /// new palette without clobbering `defaultRestSeconds` (mutates a copy of
    /// the whole row, same convention as `RestTimerSettingView.select(_:)`,
    /// rather than upserting a bare `UserSettings.defaults` that would reset
    /// the rest timer back to 120s on every palette change).
    private var lastKnownSettings: UserSettings?

    /// Best-effort load from `user_settings` — silently keeps the seeded
    /// `.midnight` default on any failure (unauthenticated, network, missing
    /// row), the same absence-means-default convention as every other
    /// Settings Hub read (`UserSettingsRepository.get()` itself already
    /// falls back to `.defaults` when no row exists; this additionally
    /// tolerates the call throwing, e.g. pre-sign-in).
    public func load() async {
        guard let settings = try? await UserSettingsRepository.get() else { return }
        lastKnownSettings = settings
        apply(paletteID: settings.palette)
    }

    /// Updates the live theme immediately — the whole app re-renders via the
    /// `\.gsTheme` environment key RootView injects from `current` — then
    /// persists in the background. Persistence is fire-and-forget/best-effort
    /// (matches the brief's "persists via upsert (best-effort; UI updates
    /// regardless)"): the picker row's checkmark already reflects the tap
    /// before the network call even starts, and a failed upsert doesn't roll
    /// the UI back (unlike `RestTimerSettingView`, which does revert on
    /// error) — a palette is cosmetic, so keeping the user's chosen look for
    /// the session even if persistence fails is preferable to silently
    /// snapping back to the old one under their thumb.
    public func select(_ paletteID: String) {
        apply(paletteID: paletteID)
        Task {
            guard let userID = await SupabaseService.shared.currentUserID() else { return }
            var updated = lastKnownSettings ?? UserSettings.defaults(userID: userID)
            updated.palette = paletteID
            if (try? await UserSettingsRepository.upsert(updated)) != nil {
                lastKnownSettings = updated
            }
        }
    }

    private func apply(paletteID: String) {
        self.paletteID = paletteID
        self.current = GSPalettes.theme(for: paletteID)
        // Re-stamps the UIKit tab bar / navigation bar appearance proxies so
        // chrome created after this point (newly pushed nav bars, etc.)
        // matches the new palette. Already-mounted bars may not repaint
        // until next presented — a documented UIAppearance-proxy limitation,
        // not something SwiftUI's environment propagation can reach around.
        GSAppearance.apply(theme: current)
    }
}
