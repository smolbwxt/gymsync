import Foundation

/// LOCAL (on-device) `session_id` → `EKEvent.eventIdentifier` mapping for the
/// iOS Calendar sync (`EventKitBridge`, Phase H Task 2). UserDefaults-backed,
/// mirroring `StatTilesSnapshotStore`'s precedent (`StatTilesSnapshot.swift`)
/// — no existing UserDefaults-based idiom in this codebase touches Supabase,
/// so this file follows that one's plain-Codable-over-UserDefaults shape
/// rather than inventing a new pattern.
///
/// DECISION: this mapping is intentionally NOT the master spec's
/// `session_calendar_syncs` table (`docs/superpowers/specs/2026-06-28-
/// gymsync-design.md:633-639`). That table exists for Google Calendar's
/// SERVER-side sync (Flow 10, `:927-946`): a Supabase Edge Function reacts to
/// `sessions` INSERT/UPDATE/DELETE and needs a durable, server-visible
/// mapping — keyed `(session_id, provider)` — to find the right Google event
/// to update or delete later, because the writer (the Edge Function) and the
/// eventual reader (the same Edge Function, possibly on a different
/// invocation) are different processes that only share the database.
///
/// The iOS EventKit sync has no such split: the only writer is this device's
/// `EventKitBridge`, driven directly by this device's own UI actions
/// (schedule/reschedule/cancel — see call sites in `ScheduleSessionView` and
/// `LobbyView`), and the only reader is that same code the next time it needs
/// to update or remove that same event — on the same device, in the same
/// process family. A server table would just be a second, unsynchronized copy
/// of state `EKEventStore` and this dictionary already agree on, with no
/// process boundary it would actually bridge. `EKEvent.eventIdentifier`
/// values are themselves local-store-specific and meaningless off-device, so
/// nothing here can help a hypothetical multi-device iOS sync either — that's
/// out of scope for v1 same as it is for HealthKit (also on-device only).
enum SessionCalendarSyncStore {
    private static let defaultsKey = "session_calendar_sync_map_v1"

    /// Serializes every access below (Phase O Task 2, fix wave 1 — reviewer
    /// Finding 1). `EventKitBridge.reconcile()`'s app-foreground sweep and
    /// `YouTabView.disableCalendarSync()`'s toggle-off teardown both walk
    /// `allSessionIDs()` and call `removeMapping`/`setEventIdentifier` from
    /// their own independent `Task`s, with no actor or queue of their own
    /// serializing them against each other — two such calls can genuinely
    /// overlap (e.g. a reconcile sweep still running when the user flips the
    /// toggle off). Each individual `UserDefaults` get/set is already
    /// thread-safe, but the load-mutate-save SEQUENCE below is not: two
    /// interleaved sequences can each read the same starting dictionary,
    /// mutate their own copy, and save it back — the second save silently
    /// overwrites (loses) the first's update, which can resurrect a mapping
    /// whose `EKEvent` was already deleted by the other caller.
    ///
    /// Fix: one plain `NSLock` around every function's ENTIRE body (not just
    /// `removeMapping`, which is where the race was first spotted — every
    /// method here does its own load-mutate-save or load-only sequence and
    /// needs the same guarantee). No API change — every call site
    /// (`EventKitBridge`, `YouTabView`, `AuthService.signOut()`, and the
    /// existing `SessionCalendarSyncStoreTests`) keeps calling these as
    /// plain synchronous static functions. Judged against converting this to
    /// an `actor`: an actor would force `await` onto every one of those call
    /// sites (several of which are themselves already deep in `Task { }`
    /// closures started after a UI dismiss — see `EventKitBridge.swift`'s
    /// Item 2 history) for no benefit this store's callers need, since
    /// nothing here ever awaits WHILE holding the lock (pure in-memory dict
    /// work + synchronous `UserDefaults` calls) — a lock can never be held
    /// across a suspension point here, so there's no actor-reentrancy
    /// concern a lock would introduce that an actor wouldn't also have.
    /// `NSLock` (not a `DispatchQueue`) because there's no async dispatch
    /// need, just mutual exclusion around synchronous work — the lightest
    /// idiom that fits.
    private static let lock = NSLock()

    /// Raw load with NO locking of its own — only ever called from inside a
    /// block that already holds `lock`, so every public entry point below
    /// can compose a multi-step load-mutate-save sequence under ONE lock
    /// acquisition without `NSLock`'s non-reentrant self-deadlock risk.
    private static func loadLocked(defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    /// Raw save, same "caller already holds `lock`" contract as
    /// `loadLocked` above.
    private static func saveLocked(_ map: [String: String], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func eventIdentifier(for sessionID: UUID, defaults: UserDefaults = .standard) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(defaults: defaults)[sessionID.uuidString]
    }

    static func setEventIdentifier(_ identifier: String, for sessionID: UUID, defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        var map = loadLocked(defaults: defaults)
        map[sessionID.uuidString] = identifier
        saveLocked(map, defaults: defaults)
    }

    /// Removes the mapping for one session, returning the identifier that
    /// was removed (if any) — the caller (`EventKitBridge.removeEvent`)
    /// doesn't currently need the return value but it keeps this symmetric
    /// with `Dictionary.removeValue(forKey:)`'s own signature.
    @discardableResult
    static func removeMapping(for sessionID: UUID, defaults: UserDefaults = .standard) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var map = loadLocked(defaults: defaults)
        let removed = map.removeValue(forKey: sessionID.uuidString)
        saveLocked(map, defaults: defaults)
        return removed
    }

    /// Every currently-mapped session id — backs the You-tab toggle's
    /// disable path ("best-effort remove mapped events"), which needs to
    /// walk every session this device has ever synced without the caller
    /// tracking that list separately.
    static func allSessionIDs(defaults: UserDefaults = .standard) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(defaults: defaults).keys.compactMap(UUID.init)
    }

    /// Wipes the mapping. Call on sign-out (`AuthService.signOut()`) — same
    /// "a second user on a shared device must not inherit the first user's
    /// local state" reasoning as `StatTilesSnapshotStore.clear()`. Doesn't
    /// touch the calendar itself (removing every EKEvent on sign-out would
    /// be a surprising side effect for a device the NEXT user might not even
    /// be the same person on) — just forgets the mapping, matching how
    /// `StatTilesSnapshotStore.clear()` forgets cached numbers without
    /// un-doing anything server-side.
    static func clear(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// LOCAL on/off state for the You-tab's "Add my sessions to Calendar" toggle
/// (`YouTabView.calendarSyncRow`). UserDefaults-backed for the same reason as
/// `SessionCalendarSyncStore` above, and kept in this file alongside it since
/// both are small pieces of local state for the same feature (matches
/// `StatTilesSnapshot.swift`'s precedent of a model/store pair sharing one
/// file rather than splitting trivially-small pieces across files).
///
/// DECISION: also local-only, not a `user_settings` column. Unlike most
/// per-user preferences (`user_settings.palette`, `default_rest_seconds`,
/// etc. — legitimately worth syncing across a user's devices), this toggle
/// gates a permission this SPECIFIC device must independently hold from iOS
/// (`EKEventStore` authorization is granted per-device, not per-account) —
/// syncing the boolean to a second device wouldn't let that device skip its
/// own permission prompt, so a server round-trip would add a network
/// dependency to a read this feature needs on every schedule/reschedule/
/// cancel, for no actual cross-device benefit.
enum CalendarSyncPrefsStore {
    private static let defaultsKey = "calendar_sync_enabled_v1"

    /// `UserDefaults.bool(forKey:)` returns `false` when the key has never
    /// been set — this alone satisfies "default off" with no explicit
    /// bootstrap write needed (mirrors `NotificationPreferencesView`'s
    /// "absence means enabled" default, just inverted).
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
