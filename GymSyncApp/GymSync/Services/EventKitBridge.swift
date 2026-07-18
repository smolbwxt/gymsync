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
/// actions, and the schedule/reschedule/cancel call sites that gate on the
/// preference first (`ScheduleSessionView.schedule()`,
/// `LobbyView.applyReschedule()/cancelOccurrence()/cancelSeriesForward()`).
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
    /// `StatMath.estimatedMinutes(exerciseCount:)` — flat ~15 min/exercise)
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
    static func removeEvent(sessionID: UUID) async {
        guard let identifier = SessionCalendarSyncStore.eventIdentifier(for: sessionID) else { return }
        defer { SessionCalendarSyncStore.removeMapping(for: sessionID) }
        guard let event = store.event(withIdentifier: identifier) else { return }
        do {
            try store.remove(event, span: .thisEvent)
            AppLogger.calendar.info("Removed calendar event for session \(sessionID, privacy: .public)")
        } catch {
            AppLogger.calendar.error("removeEvent failed for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
