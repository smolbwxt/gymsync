import Foundation

/// Lightweight local cache of the Home stat-tile row's last successfully
/// loaded values, used to render the OFFLINE·STALE-CACHE state (canvas frame
/// 41) when `ConnectivityMonitor.shared.isOnline` is false.
///
/// Backed by `UserDefaults` directly. No existing UserDefaults-based idiom
/// was found anywhere in the app (`UserSettings.swift` and
/// `NotificationPrefsRepository` persist small client-state values, but both
/// are Supabase-table-backed, not local) — this mirrors `UserSettings`'s
/// plain-Codable shape without the network round-trip. Per the Phase U plan's
/// Global Constraints, this is explicitly NOT SwiftData.
///
/// Each field is independently optional — `HomeView.refresh()`'s three
/// underlying fetches (`fetchHistory`, `fetchProfile`,
/// `fetchPRCountThisMonth`) already fail independently (each wrapped in its
/// own `try?`), so a field here only updates when THAT fetch succeeds. A
/// field that has never once successfully loaded renders as the frame's
/// em-dash "—" (see `StatTilesRow.staleValue(_:)`).
struct StatTilesSnapshot: Codable, Equatable {
    var workoutsThisWeek: Int?
    var lifetimeLbs: Decimal?
    var prsThisMonth: Int?

    static let empty = StatTilesSnapshot()

    /// True once at least one field has ever been cached. Gates whether
    /// OFFLINE·STALE-CACHE has anything to show at all — an offline cold
    /// start with no prior successful load has nothing "stale" to render, so
    /// `HomeView.statTilesRowState` falls through to FIRST-SESSION·ZERO (or
    /// LOADED-with-zeros, if history is non-empty) instead.
    var hasAnyValue: Bool {
        workoutsThisWeek != nil || lifetimeLbs != nil || prsThisMonth != nil
    }
}

/// UserDefaults-backed persistence for `StatTilesSnapshot`.
enum StatTilesSnapshotStore {
    private static let defaultsKey = "stat_tiles_snapshot_v1"

    static func load() -> StatTilesSnapshot {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(StatTilesSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Merges whichever fields succeeded THIS pass into whatever's already
    /// cached — a `nil` argument means that field's fetch failed (or was
    /// skipped, e.g. signed out) this time and leaves the previously cached
    /// value untouched rather than clobbering it with nil. No-ops entirely
    /// when nothing succeeded (e.g. fully signed-out refresh), so a
    /// never-signed-in device never writes an all-nil snapshot.
    ///
    /// Call after every `HomeView.refresh()` — "saved after every successful
    /// stats load" per the Phase U plan.
    static func save(workoutsThisWeek: Int?, lifetimeLbs: Decimal?, prsThisMonth: Int?) {
        guard workoutsThisWeek != nil || lifetimeLbs != nil || prsThisMonth != nil else { return }
        var snapshot = load()
        if let workoutsThisWeek { snapshot.workoutsThisWeek = workoutsThisWeek }
        if let lifetimeLbs { snapshot.lifetimeLbs = lifetimeLbs }
        if let prsThisMonth { snapshot.prsThisMonth = prsThisMonth }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
