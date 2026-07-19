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
    /// Phase W Task 5 (watch-hr design §4) — the live `user_settings
    /// .share_heart_rate` value, mirrored here for the SAME reason
    /// `paletteID` is: this class is already the app's one cross-view
    /// `@Observable` cache of the current `user_settings` row, updated by
    /// both `load()` (below) and `noteExternalSettingsWrite(_:)`
    /// (`YouTabView.setShareHeartRate`'s own success-path call, already
    /// existing since Task 4). `GroupSessionLiveView.pushWatchSessionState()`
    /// reads this DIRECTLY instead of caching its own copy once at
    /// `openAndSubscribe()` time — the fix for the carried-in T4 review
    /// finding ("shareHeartRate is cached once... a mid-session toggle flip
    /// never reaches the Watch"). Defaults `false`, matching `UserSettings
    /// .defaults`' own safe opt-out default.
    public private(set) var shareHeartRate: Bool = false

    /// Cached most-recent settings row — kept so `select(_:)` can persist the
    /// new palette without clobbering `defaultRestSeconds` (mutates a copy of
    /// the whole row, same convention as `RestTimerSettingView.select(_:)`,
    /// rather than upserting a bare `UserSettings.defaults` that would reset
    /// the rest timer back to 120s on every palette change).
    private var lastKnownSettings: UserSettings?

    /// The in-flight persist `Task` spawned by the most recent `select(_:)`
    /// call, if any. Tracked so rapid palette taps can't race each other: a
    /// second tap cancels the first tap's still-running upsert instead of
    /// letting both run unordered, where a slower first-tap upsert completing
    /// *after* the second could let a stale palette value win the DB row (and
    /// `lastKnownSettings`), reverting to it on next launch.
    ///
    /// Fix round B1 (final review blocker): this is `nil`ed out by the task
    /// itself once it finishes (success, failure, or cancellation) — see the
    /// `defer` in `select(_:)` — so elsewhere (`noteExternalSettingsWrite`)
    /// its non-nil-ness can be trusted as a live "a palette persist is
    /// currently in flight" signal, not just "one was ever started." A
    /// `persistGeneration` counter guards that reset so an older, superseded
    /// task's delayed cleanup can't stomp on a newer task that's still
    /// genuinely running.
    private var persistTask: Task<Void, Never>?
    private var persistGeneration = 0

    /// Best-effort load from `user_settings` — silently keeps the seeded
    /// `.midnight` default on any failure (unauthenticated, network, missing
    /// row), the same absence-means-default convention as every other
    /// Settings Hub read (`UserSettingsRepository.get()` itself already
    /// falls back to `.defaults` when no row exists; this additionally
    /// tolerates the call throwing, e.g. pre-sign-in).
    public func load() async {
        guard let settings = try? await UserSettingsRepository.get() else { return }
        lastKnownSettings = settings
        shareHeartRate = settings.shareHeartRate
        apply(paletteID: settings.palette)
    }

    /// Updates the live theme immediately — the whole app re-renders via the
    /// `\.gsTheme` environment key RootView injects from `current` — then
    /// persists in the background. Persistence is best-effort (matches the
    /// brief's "persists via upsert (best-effort; UI updates regardless)"):
    /// the picker row's checkmark already reflects the tap before the network
    /// call even starts, and a failed upsert doesn't roll the UI back (unlike
    /// `RestTimerSettingView`, which does revert on error) — a palette is
    /// cosmetic, so keeping the user's chosen look for the session even if
    /// persistence fails is preferable to silently snapping back to the old
    /// one under their thumb.
    ///
    /// Race guard (fix round 1, task-5 review): rapid taps cancel the
    /// previous tap's still-in-flight persist `Task` before starting a new
    /// one, and the task itself re-checks `Task.isCancelled` both right
    /// before the upsert and right after it (before touching
    /// `lastKnownSettings`) — so a cancelled tap can neither write its stale
    /// palette to the DB nor clobber `lastKnownSettings` with it, even if the
    /// cancellation lands mid-await. UI behavior is unchanged: `apply(
    /// paletteID:)` below still runs synchronously on every call, before any
    /// cancellation logic.
    public func select(_ paletteID: String) {
        apply(paletteID: paletteID)
        persistTask?.cancel()
        persistGeneration += 1
        let generation = persistGeneration
        persistTask = Task {
            defer {
                // Only the still-current generation clears the slot — an
                // older, cancelled task finishing its cleanup late must not
                // nil out a newer task that's still in flight.
                if generation == persistGeneration {
                    persistTask = nil
                }
            }
            guard let userID = await SupabaseService.shared.currentUserID() else { return }
            var updated = lastKnownSettings ?? UserSettings.defaults(userID: userID)
            updated.palette = paletteID

            guard !Task.isCancelled else { return }
            let succeeded = (try? await UserSettingsRepository.upsert(updated)) != nil

            guard !Task.isCancelled, succeeded else { return }
            lastKnownSettings = updated
        }
    }

    /// Called by `RestTimerSettingView`'s save path right after it persists a
    /// new `defaultRestSeconds` value, so `ThemeStore`'s own cached row
    /// doesn't go stale and clobber the rest-timer value the next time
    /// `select(_:)` upserts a palette change. Closes the "rest-then-palette"
    /// direction of the full-row-upsert race (see `YouTabView
    /// .effectiveUserSettings` for the "palette-then-rest" direction, which
    /// this method's `settings` argument already benefits from — it always
    /// carries the live `paletteID` by the time it reaches here).
    ///
    /// Delegates to `mergeExternalSettingsWrite(cached:incoming:persistInFlight:)`
    /// — see that function's doc comment for the merge semantics.
    ///
    /// Not `public` (unlike `load()`/`select(_:)`): its parameter is
    /// `UserSettings`, which is an internal (module-default-access) type —
    /// a `public` method can't expose an internal type in its signature.
    /// `RestTimerSettingView` is in the same module, so internal access is
    /// sufficient for its one call site.
    func noteExternalSettingsWrite(_ settings: UserSettings) {
        lastKnownSettings = Self.mergeExternalSettingsWrite(
            cached: lastKnownSettings,
            incoming: settings,
            persistInFlight: persistTask != nil
        )
        // `shareHeartRate` always adopts the merged result — `select(_:)`'s
        // in-flight task only ever owns `.palette` (see the merge rule's
        // own doc comment below), so `shareHeartRate` is never the field
        // being protected from clobber; it always wins from whichever
        // write reported it, same as `defaultRestSeconds`.
        shareHeartRate = lastKnownSettings?.shareHeartRate ?? false
    }

    /// Pure merge rule behind `noteExternalSettingsWrite` — extracted (and
    /// kept `nonisolated`, since it only touches its value-type parameters)
    /// so it's unit-testable without a `ThemeStore` instance, `@MainActor`,
    /// or network. Decision table:
    ///   - no cached row yet -> adopt `incoming` wholesale (nothing to
    ///     protect).
    ///   - no persist in flight -> adopt `incoming` wholesale (`cached` isn't
    ///     fresher than `incoming` in this case, so there's nothing at risk).
    ///   - persist in flight -> a `select(_:)` task is still working toward
    ///     landing its own palette value in the DB and in `lastKnownSettings`;
    ///     it — not this call — owns `.palette` in the cache until it
    ///     finishes. So: keep `cached.palette`, and adopt only
    ///     `incoming.defaultRestSeconds` (the field this call actually has
    ///     authority over).
    ///
    /// This is a field-level ("don't touch a field someone else is actively
    /// writing"), not value-level, merge rule — it doesn't try to determine
    /// whether `incoming.palette` happens to already match the in-flight
    /// task's target value; it always defers regardless, which is simplest
    /// and safe in every case. Residual risk (documented, not fixable from
    /// the cache alone): if the in-flight `select(_:)` task already read
    /// `lastKnownSettings` into its own local snapshot *before* this call
    /// runs, its eventual upsert will still write using that earlier
    /// snapshot's `defaultRestSeconds` — no cache reconciliation after the
    /// fact can correct an already-captured local variable. That narrow
    /// interleaving window is a network-timing race, not a cache-merge bug;
    /// device QA is the backstop for it.
    ///
    /// Task 4 (watch-hr design §4) extension: `shareHeartRate` joins
    /// `defaultRestSeconds` on the "adopt from incoming" side of the rule,
    /// not the "protect from clobber" side — `select(_:)`'s in-flight task
    /// only ever owns `.palette` (it's the only field that task writes), so
    /// every OTHER field an external caller reports (`YouTabView
    /// .setShareHeartRate`'s own `noteExternalSettingsWrite` call, mirroring
    /// `RestTimerSettingView.select(_:)`'s identical call) should win over
    /// whatever `cached` was holding, exactly like `defaultRestSeconds`
    /// already does. A future 4th `user_settings` field added the same way
    /// should extend this same line, not the guard above it.
    nonisolated static func mergeExternalSettingsWrite(
        cached: UserSettings?,
        incoming: UserSettings,
        persistInFlight: Bool
    ) -> UserSettings {
        guard persistInFlight, var merged = cached else {
            return incoming
        }
        merged.defaultRestSeconds = incoming.defaultRestSeconds
        merged.shareHeartRate = incoming.shareHeartRate
        return merged
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
