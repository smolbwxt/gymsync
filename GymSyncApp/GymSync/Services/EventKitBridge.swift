import EventKit
import Foundation

/// Syncs the CURRENT USER's ORGANIZED scheduled sessions to their iOS
/// Calendar (master spec §2's `EventKitBridge`, "iOS Calendar sync for
/// scheduled sessions" — `docs/superpowers/specs/2026-06-28-gymsync-
/// design.md:39,137`; Phase H v1 scope per `docs/superpowers/specs/2026-07-
/// 18-health-calendar-design.md`'s Component 2: ONE-WAY, ORGANIZER-only.
/// Participant-side sync and two-way sync are both out of scope for v1).
///
/// Mirrors `HealthKitBridge.swift`'s shape: a static-namespace enum wrapping
/// the platform store, pure/testable helpers split out from the
/// EKEventStore-touching async calls, best-effort posture (every write here
/// logs and swallows its own failures — see each function's doc comment for
/// exactly which callers that protects), `AppLogger.calendar` for every
/// outcome.
///
/// Gating: every write path below assumes its caller already checked
/// `CalendarSyncPrefsStore.isEnabled()` (the You-tab toggle — see
/// `YouTabView.calendarSyncRow`) — this file does NOT re-check the
/// preference itself, only the live system authorization, so it stays a
/// thin EventKit wrapper rather than owning app-level policy. No function
/// here is ever called from anywhere except: the toggle's own enable/disable
/// actions, the schedule/reschedule/cancel call sites that gate on the
/// preference first (`ScheduleSessionView.schedule()`,
/// `LobbyView.applyReschedule()/cancelOccurrence()/cancelSeriesForward()`,
/// `SeriesEditorView.save()`), and `RootView`'s app-foreground hook into
/// `reconcile()` (see that function's own doc comment below).
///
/// FORMER KNOWN LIMITATION (v1, controller-accepted — Phase O Task 2
/// closed this): the only state transitions that used to remove a mapped
/// event were the client-initiated ones above. A session the server-side
/// cron moves to `abandoned` with no client involvement —
/// `enqueue_scheduled_pushes()`'s "Abandon at 6 hours" step (`supabase/
/// migrations/20260716000004_reminder_window_fix.sql:107-124`, superseding
/// `20260716000003_push_cron.sql`) — never had `removeEvent` called for
/// it. `reconcile()` (below) now catches this on the next app foreground,
/// alongside the toggle-race/stale-reschedule/just-past-backfill findings
/// it also absorbs — see its doc comment for the full list.
enum EventKitBridge {
    static let store = EKEventStore()

    // MARK: - Permission

    /// iOS 17+ full-access API. `GymSyncApp/project.yml` pins
    /// `options.deploymentTarget.iOS: "17.0"` (no earlier target to support),
    /// so this uses ONLY `requestFullAccessToEvents()` — no
    /// `requestAccess(to:)` legacy fallback, no availability check needed.
    /// Full access (not write-only) is required: `removeEvent` and
    /// `syncEvent`'s update-in-place path both need `event(withIdentifier:)`,
    /// which needs read access — `EKEventStore`'s write-only grant can add
    /// events but cannot look any back up, even ones this app created.
    static func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    static func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Pure helpers (no EKEventStore access — hermetically testable)

    /// "Gym Sync: {routine}" mirrors the Google Calendar Flow 10 title shape
    /// exactly (master spec `:936`, `"Gym Sync: {routine name}"`) for
    /// consistency between the two calendar surfaces, even though Flow 10
    /// itself is a separate (unbuilt, server-side) sync — falls back to a
    /// routine-less title for ad-hoc sessions (`ScheduleSessionView`'s
    /// Routine picker allows "None").
    static func eventTitle(routineName: String?) -> String {
        guard let routineName, !routineName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Gym Sync Session"
        }
        return "Gym Sync: \(routineName)"
    }

    /// Estimated event duration from a routine's exercise count, via the
    /// SAME shared heuristic Home/Library/RoutineBuilder already use for a
    /// routine's "~X min" meta suffix (`Models/StatMath.swift:124`,
    /// `StatMath.estimatedMinutes(exerciseCount:)` — ~12 min/exercise, the
    /// prescription formula at its defaults)
    /// — one estimate, reused rather than re-derived for the calendar
    /// event's end time. Floors at 30 min so a 1-2 exercise routine doesn't
    /// produce a near-zero-length event. `nil` exerciseCount (no routine
    /// selected, or its exercise count hasn't resolved yet) falls back to
    /// the master spec's OWN Flow 10 default ("estimated end (default 60
    /// min, configurable per routine)", `:937`) — the spec's
    /// "configurable per routine" duration field does not exist anywhere on
    /// this codebase's `Routine` model (`Models/Routine.swift`), so 60 min
    /// here is the honest spec-default floor, not a stand-in for a
    /// configuration value that was never built.
    static func estimatedDuration(exerciseCount: Int?) -> TimeInterval {
        let minutes: Int
        if let exerciseCount {
            minutes = max(30, StatMath.estimatedMinutes(exerciseCount: exerciseCount))
        } else {
            minutes = 60
        }
        return TimeInterval(minutes * 60)
    }

    /// `reconcile()`'s stale-detection rule (Phase O Task 2, fix wave 1 —
    /// reviewer Finding 3), extracted as a pure helper: no `EKEventStore` or
    /// network access, just a dictionary lookup over already-fetched data,
    /// so it's hermetically testable without a live `SessionRepository`
    /// fetch. A mapped session id is stale when either:
    ///   - it's ABSENT from `liveStates` — `reconcile()`'s own doc comment
    ///     already establishes why "cancelled" and "nonexistent" collapse
    ///     into this one "missing" signal: `sessions.state`'s CHECK
    ///     constraint has no `'cancelled'` value at all (cancel hard-DELETEs
    ///     the row), so a cancelled session's id simply never comes back
    ///     from the batch fetch — indistinguishable, by design, from an id
    ///     that never existed or that RLS no longer lets this user see; or
    ///   - its live state IS present but equals `"abandoned"` (the
    ///     cron-driven "Abandon at 6 hours" transition — see `reconcile()`'s
    ///     doc comment for the migration citation).
    /// `"completed"` and every other live state (`scheduled`, `lobby_open`,
    /// `editing`, `voting`, `locked`, `in_progress`) are deliberately kept —
    /// a session that already happened, or is still in some active
    /// pre-workout state, keeps its calendar footprint.
    static func staleSessionIDs(mappedIDs: [UUID], liveStates: [UUID: String]) -> [UUID] {
        mappedIDs.filter { id in
            guard let state = liveStates[id] else { return true } // cancelled/nonexistent
            return state == "abandoned"
        }
    }

    // MARK: - Writes (best-effort — log, never throw into a caller's
    // server-mutation flow; every caller's own write must already have
    // succeeded before it reaches here)

    /// Creates the calendar event for a newly-scheduled organized session,
    /// or — if a mapping already exists for this session id (a reschedule
    /// re-sync) — updates that SAME event in place rather than leaking a
    /// duplicate. No-ops quietly (returns `nil`) when the session has no
    /// `scheduledFor` or the app doesn't currently hold full Calendar
    /// access; the internal authorization re-check is defense-in-depth
    /// alongside the caller's own `CalendarSyncPrefsStore.isEnabled()` gate
    /// (mirrors `HealthKitBridge.exportWorkout`'s own internal
    /// `HKHealthStore.isHealthDataAvailable()` guard on top of its callers'
    /// checks).
    ///
    /// HONEST FAILURE MODE (Phase O Task 2, fix wave 1 — reviewer Finding
    /// 2; corrects an overstated "re-toggle recovers this" claim that used
    /// to live in the call sites' own comments, see `ScheduleSessionView.
    /// schedule()`/`SeriesEditorView.save()`): `store.save(event, span:)`
    /// below and `SessionCalendarSyncStore.setEventIdentifier(...)` are two
    /// separate statements, and a process kill lands between them the event
    /// exists in the user's calendar but was never mapped. Verified this
    /// window is already as narrow as it can be — the only thing between
    /// them is the `guard let identifier = event.eventIdentifier` extraction
    /// (required; `setEventIdentifier` needs that value), a synchronous,
    /// non-throwing, no-I/O property read with no `await` in it, so there's
    /// nothing left to remove — the two calls are adjacent. That narrow
    /// window is still a REAL, permanent failure mode, not a false alarm: no
    /// recovery path in this file (`reconcile()`, `removeEvent`'s callers,
    /// `YouTabView.backfillCalendarSync`) ever looks at anything but MAPPED
    /// session ids, so an unmapped-but-saved event is invisible to all of
    /// them forever, AND the next backfill (finding no mapping) creates a
    /// SECOND event for the same session rather than recovering the first —
    /// re-toggling calendar sync duplicates this case, it does not fix it.
    /// Building an orphan-detection subsystem (e.g. reverse-scanning
    /// `EKEventStore` by title/notes against the mapping) would close this
    /// gap but is out of scope for v1 — noted here as a possible future item,
    /// not built.
    @discardableResult
    static func syncEvent(session: WorkoutSession, routineName: String?, exerciseCount: Int?) async -> String? {
        guard let start = session.scheduledFor else { return nil }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        let event: EKEvent
        if let existingID = SessionCalendarSyncStore.eventIdentifier(for: session.id),
           let existing = store.event(withIdentifier: existingID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }

        event.title = eventTitle(routineName: routineName)
        event.notes = "Scheduled via Gym Sync."
        event.startDate = start
        event.endDate = start.addingTimeInterval(estimatedDuration(exerciseCount: exerciseCount))

        do {
            try store.save(event, span: .thisEvent)
            guard let identifier = event.eventIdentifier else {
                AppLogger.calendar.error("syncEvent: save succeeded but no eventIdentifier for session \(session.id, privacy: .public)")
                return nil
            }
            SessionCalendarSyncStore.setEventIdentifier(identifier, for: session.id)
            AppLogger.calendar.info("Synced calendar event for session \(session.id, privacy: .public)")
            return identifier
        } catch {
            AppLogger.calendar.error("syncEvent failed for session \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Best-effort removal of a session's mapped event — cancel/cancel-
    /// series call sites, and the You-tab toggle's disable-path teardown.
    /// Quietly no-ops (not an error) when there's no mapping, or the mapped
    /// event is already gone (e.g. the user deleted it by hand in
    /// Calendar.app) — both mean "this session has no calendar footprint,"
    /// which is exactly the postcondition this function exists to guarantee.
    ///
    /// The mapping is cleared ONLY on those two confirmed-gone outcomes
    /// (already-missing event, or a successful `store.remove`) — a
    /// transient `store.remove` failure (e.g. EventKit db momentarily
    /// locked) logs and KEEPS the mapping, so a later retry of this same
    /// call can still find the event via `SessionCalendarSyncStore.
    /// eventIdentifier(for:)` instead of orphaning it forever.
    static func removeEvent(sessionID: UUID) async {
        guard let identifier = SessionCalendarSyncStore.eventIdentifier(for: sessionID) else { return }
        guard let event = store.event(withIdentifier: identifier) else {
            SessionCalendarSyncStore.removeMapping(for: sessionID)
            return
        }
        do {
            try store.remove(event, span: .thisEvent)
            SessionCalendarSyncStore.removeMapping(for: sessionID)
            AppLogger.calendar.info("Removed calendar event for session \(sessionID, privacy: .public)")
        } catch {
            AppLogger.calendar.error("removeEvent failed for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reconciliation sweep (Phase O Task 2)

    /// Guards against two overlapping sweeps (e.g. a quick background→
    /// foreground→background→foreground flap firing `.onChange(of:
    /// scenePhase)` twice before the first pass's network fetch returns).
    /// Same "static flag, not call-site discipline" shape as
    /// `LiveKitRoomConnection.didDisableAutomaticAudioConfiguration`
    /// (`Services/LiveKitRoomConnection.swift:38`) — this file has no actor
    /// isolation of its own (matches `syncEvent`/`removeEvent` above, which
    /// already mutate `SessionCalendarSyncStore` from whatever context calls
    /// them), so this is a best-effort de-dupe, not a hard mutual-exclusion
    /// guarantee — acceptable here because a redundant sweep is merely
    /// wasted work, never incorrect (each pass independently re-derives
    /// "stale" from a fresh server fetch).
    private static var isReconciling = false

    /// App-foreground reconciliation sweep. Absorbs three Phase H gate-
    /// review findings that all reduce to the same root cause — a mapped
    /// session whose SERVER state moved on without any client call site
    /// ever invoking `removeEvent` for it:
    ///   - **N-2** (rapid toggle-off/on race): disabling sync removes every
    ///     mapped event, but a session cancelled in the gap before the next
    ///     enable's backfill re-adds a now-stale event for it.
    ///   - **N-3** (stale reschedule sync after a failed refetch): a
    ///     `LobbyView.applyReschedule()` whose post-write `reload()` fails
    ///     leaves `effectiveSession` (and therefore the synced event) on
    ///     the pre-reschedule time, with no later retry.
    ///   - **N-5** (just-past sessions backfilled): a session that crosses
    ///     `scheduledFor <= now` between `YouTabView.backfillCalendarSync`'s
    ///     fetch and its per-session sync still gets an event for a time
    ///     that's already passed.
    /// Plus this file's own KNOWN LIMITATION (type doc comment above): the
    /// cron-driven `abandoned` transition has no client call site at all;
    /// and sessions cancelled/gone while Calendar permission was denied
    /// (so no client `removeEvent` could have fired even if the state
    /// change WAS client-driven).
    ///
    /// Rather than patching each call site's individual race window, this
    /// sweep is the single downstream safety net: enumerate every locally-
    /// mapped session, batch-fetch what the server currently says each
    /// one's state is, and remove the calendar footprint for anything
    /// that's gone or `abandoned`. "Cancelled" and "nonexistent" collapse
    /// into ONE signal here — `SeriesRepository.cancelOccurrence`/
    /// `cancelSeriesForward` (`SessionSeries.swift:350-358`, `:361-379`)
    /// hard-DELETE the row (there is no `'cancelled'` value in `sessions.
    /// state`'s check constraint — `supabase/migrations/20260709000006_
    /// create_sessions.sql:6-7` enumerates exactly `scheduled, lobby_open,
    /// editing, voting, locked, in_progress, completed, abandoned`), so a
    /// cancelled session's id simply never comes back from `SessionRepository.
    /// sessions(ids:)`'s `.in("id", values:)` fetch — same as an id that
    /// never existed or that RLS no longer lets this user see. `completed`
    /// sessions are deliberately left alone: an event for a session that
    /// actually happened is a legitimate calendar record, not stale state.
    ///
    /// Caller contract (mirrors every other function in this file, see the
    /// type doc comment's "Gating" paragraph): the caller checks
    /// `CalendarSyncPrefsStore.isEnabled()` before calling; this function
    /// only re-checks live system authorization as its own defense-in-depth
    /// guard, same as `syncEvent`. Best-effort: any failure (the batch
    /// fetch itself, or an individual `removeEvent`) is logged and the
    /// sweep simply ends for this pass — every mapping stays intact for
    /// the NEXT foreground pass to retry, this never throws into or blocks
    /// the caller.
    static func reconcile() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let ids = SessionCalendarSyncStore.allSessionIDs()
        guard !ids.isEmpty else { return }

        do {
            let liveSessions = try await SessionRepository.sessions(ids: ids)
            let liveStates = Dictionary(uniqueKeysWithValues: liveSessions.map { ($0.id, $0.state) })
            let staleIDs = staleSessionIDs(mappedIDs: ids, liveStates: liveStates)
            guard !staleIDs.isEmpty else {
                AppLogger.calendar.info("reconcile: \(ids.count, privacy: .public) mapped session(s), 0 stale")
                return
            }
            for staleID in staleIDs {
                await removeEvent(sessionID: staleID)
            }
            AppLogger.calendar.info("reconcile: removed \(staleIDs.count, privacy: .public) of \(ids.count, privacy: .public) mapped session(s) (cancelled/abandoned/nonexistent)")
        } catch {
            AppLogger.calendar.error("reconcile: batch fetch failed, sweep aborted this pass: \(error.localizedDescription, privacy: .public)")
        }
    }
}
